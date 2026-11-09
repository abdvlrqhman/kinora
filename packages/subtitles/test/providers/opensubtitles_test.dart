import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:subtitles/subtitles.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  final query = SubtitleQuery(
    type: MediaType.episode,
    imdbId: 'tt0903747',
    season: 1,
    episode: 1,
    languages: [
      Language.of('ar'),
      Language.of('en'),
      Language.of('pt-BR'),
      Language.of('zh-Hant'),
    ],
    fileHash: '8E245D9679D31E12',
    fileSize: 12909756,
  );

  test('search builds a sorted, lowercase, redirect-free query', () async {
    final seen = <Seen>[];
    final p = OpenSubtitlesProvider(
      apiKey: 'test-key',
      userAgent: 'Kinora v1.2.3',
      client: recordingClient(
        seen,
        (_) async => jsonResponse(
          fixtureJson('providers/opensubtitles_search_bb_s01e01.json'),
        ),
      ),
      sleep: noSleep,
    );
    final results = await p.search(query);
    final req = seen.single;
    expect(req.url.path, '/api/v1/subtitles');
    expect(
      req.url.query,
      'episode_number=1&languages=ar%2Cen%2Cpt-br%2Czh-tw&moviehash=8e245d9679d31e12'
      '&parent_imdb_id=903747&season_number=1&type=episode',
    );
    expect(req.headers['Api-Key'], 'test-key');
    expect(req.headers['User-Agent'], 'Kinora v1.2.3');
    expect(req.headers.containsKey('Authorization'), isFalse);

    expect(results, hasLength(5));
    final first = results.first;
    expect(first.providerId, 'opensubtitles');
    expect(first.id, '3165201');
    expect(first.language.code, 'ar');
    expect(first.releaseNames, ['Breaking.Bad.S01E01.720p.BluRay.x264-DEMAND']);
    expect(
      first.fileName,
      'Breaking.Bad.S01E01.720p.BluRay.x264-DEMAND.ar.srt',
    );
    expect(first.matchedByHash, isTrue);
    expect(first.matchedHash, '8e245d9679d31e12');
    expect(first.fps, 23.976);
    expect(first.rating, 8.5);
    expect(first.downloads, 52000);
    expect(first.uploadDate, DateTime.utc(2019, 6, 25, 7, 2, 57));
    expect(first.season, 1);
    expect(first.episodeFrom, 1);
    expect(first.payload, {'file_id': 3227001});
    expect(results[1].hearingImpaired, isTrue);
    expect(results[1].matchedByHash, isFalse);
    expect(results[2].language.code, 'pt-BR');
    expect(results[3].machineTranslated, isTrue, reason: 'ai_translated');
    expect(results[4].language.code, 'zh-Hant');
  });

  test('movie search uses imdb_id without tt and leading zeros', () async {
    final seen = <Seen>[];
    final p = OpenSubtitlesProvider(
      apiKey: 'k',
      client: recordingClient(
        seen,
        (_) async => jsonResponse({'total_pages': 1, 'data': <Object?>[]}),
      ),
    );
    await p.search(
      SubtitleQuery(
        type: MediaType.movie,
        imdbId: 'tt0133093',
        languages: [Language.of('en')],
      ),
    );
    expect(seen.single.url.queryParameters, {
      'imdb_id': '133093',
      'languages': 'en',
      'type': 'movie',
    });
  });

  test('languages OpenSubtitles lacks are not requested', () async {
    final seen = <Seen>[];
    final p = OpenSubtitlesProvider(
      apiKey: 'k',
      client: recordingClient(seen, (_) async => jsonResponse({})),
    );
    expect(
      await p.search(
        SubtitleQuery(
          type: MediaType.movie,
          imdbId: 'tt1',
          languages: [Language.of('gaa')],
        ),
      ),
      isEmpty,
    );
    expect(seen, isEmpty);
  });

  test('login, then download with Bearer token on base_url host', () async {
    final seen = <Seen>[];
    final p = OpenSubtitlesProvider(
      apiKey: 'k',
      username: 'user',
      password: 'pass',
      client: recordingClient(seen, (r) async {
        if (r.url.path.endsWith('/login'))
          return jsonResponse(
            fixtureJson('providers/opensubtitles_login.json'),
          );
        if (r.url.path.endsWith('/download'))
          return jsonResponse(
            fixtureJson('providers/opensubtitles_download.json'),
          );
        return http.Response.bytes(
          utf8.encode('1\r\n00:00:01,000 --> 00:00:02,000\r\nمرحبا\r\n'),
          200,
          headers: {'content-disposition': 'attachment; filename="bb.ar.srt"'},
        );
      }),
    );
    final result = SubtitleResult(
      providerId: 'opensubtitles',
      id: '1',
      language: Language.of('ar'),
      payload: const {'file_id': 3227001},
    );
    final d = await p.download(result);
    expect(d.fileName, 'bb.ar.srt');
    expect(d.format, SubtitleFormat.srt);
    expect(seen.map((s) => '${s.method} ${s.url.host}${s.url.path}'), [
      'POST api.opensubtitles.com/api/v1/login',
      'POST vip-api.opensubtitles.com/api/v1/download',
      'GET www.opensubtitles.com/download/ABCDEF/subfile/Breaking.Bad.S01E01.720p.BluRay.x264-DEMAND.ar.srt',
    ]);
    expect(seen[0].body, '{"username":"user","password":"pass"}');
    expect(seen[1].headers['Authorization'], startsWith('Bearer eyJ'));
    expect(seen[1].body, '{"file_id":3227001}');
    expect(
      seen[2].headers.containsKey('Api-Key'),
      isFalse,
      reason: 'no key sent to the file host',
    );
    // Token is reused.
    await p.download(result);
    expect(seen.where((s) => s.url.path.endsWith('/login')), hasLength(1));
  });

  test('quota exhausted -> SubtitleQuotaException with reset time', () async {
    final p = OpenSubtitlesProvider(
      apiKey: 'k',
      client: recordingClient(
        [],
        (_) async => jsonResponse(
          fixtureJson('providers/opensubtitles_quota.json'),
          status: 406,
        ),
      ),
    );
    await expectLater(
      p.download(
        SubtitleResult(
          providerId: 'opensubtitles',
          id: '1',
          language: Language.of('en'),
          payload: const {'file_id': 1},
        ),
      ),
      throwsA(
        isA<SubtitleQuotaException>()
            .having(
              (e) => e.resetAt,
              'resetAt',
              DateTime.utc(2026, 11, 10, 6, 0, 53),
            )
            .having((e) => e.message, 'message', contains('allowed 20')),
      ),
    );
  });

  test('bad credentials -> SubtitleAuthException', () async {
    final p = OpenSubtitlesProvider(
      apiKey: 'k',
      username: 'u',
      password: 'wrong',
      client: recordingClient(
        [],
        (_) async => jsonResponse({
          'message': 'Error, invalid username/password',
          'status': 401,
        }, status: 401),
      ),
    );
    await expectLater(
      p.search(const SubtitleQuery(type: MediaType.movie, imdbId: 'tt1')),
      throwsA(isA<SubtitleAuthException>()),
    );
  });

  test('metadata', () {
    final p = OpenSubtitlesProvider(apiKey: 'k');
    expect(p.id, 'opensubtitles');
    expect(p.requiresKey, isTrue);
    expect(p.capabilities, contains(ProviderCapability.hashSearch));
  });
}
