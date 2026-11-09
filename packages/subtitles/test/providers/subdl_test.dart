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
    languages: [Language.of('ar'), Language.of('en')],
  );

  test('search request and parsing of a recorded response', () async {
    final seen = <Seen>[];
    final p = SubdlProvider(
      apiKey: 'test-key',
      maxPages: 1,
      client: recordingClient(
        seen,
        (_) async =>
            jsonResponse(fixtureJson('providers/subdl_bb_s01e01.json')),
      ),
    );
    final results = await p.search(query);
    expect(seen.single.url.queryParameters, {
      'api_key': 'test-key',
      'imdb_id': 'tt0903747',
      'type': 'tv',
      'season_number': '1',
      'episode_number': '1',
      'languages': 'AR,EN',
      'subs_per_page': '30',
      'releases': '1',
      'comment': '1',
    });
    expect(results, hasLength(30));
    expect(results.map((r) => r.language.code).toSet(), {'ar', 'en'});
    final ai = results.first;
    expect(ai.id, '3743681-8665511');
    expect(ai.releaseNames, ['Breaking.Bad.S01E01.720p.BluRay.Sujaidr.Arabic']);
    expect(ai.fileName, 'Breaking.Bad.S01E01.720p.BluRay.Sujaidr.ar.srt');
    expect(ai.machineTranslated, isTrue, reason: 'author SUBDL AI');
    expect(ai.fps, 24.0);
    expect(ai.season, 1);
    expect(ai.episodeFrom, 1);
    expect(ai.episodeTo, 1);
    // The key SubDL echoes in URLs never reaches results.
    for (final r in results) {
      expect(r.payload.toString(), isNot(contains('api_key')));
      expect(r.payload['path'], startsWith('/subtitle/'));
    }
    final pack = results.firstWhere((r) => r.isSeasonPack);
    expect(
      pack.releaseNames.first,
      'Breaking Bad, SEASON 1 1080p x265 [23.976 FPS]',
    );
    expect(pack.fps, 23.976);
    expect(pack.episodeFrom, isNull);
  });

  test('pages until totalPages', () async {
    final seen = <Seen>[];
    final page =
        fixtureJson('providers/subdl_inception.json')! as Map<String, Object?>;
    final p = SubdlProvider(
      apiKey: 'k',
      maxPages: 2,
      client: recordingClient(seen, (_) async => jsonResponse(page)),
    );
    final results = await p.search(
      SubtitleQuery(
        type: MediaType.movie,
        imdbId: 'tt1375666',
        year: 2010,
        languages: [Language.of('en'), Language.of('ar')],
      ),
    );
    expect(seen.map((s) => s.url.queryParameters['page']), [null, '2']);
    expect(results, hasLength(60));
    expect(seen.first.url.queryParameters['type'], 'movie');
    expect(seen.first.url.queryParameters['year'], '2010');
  });

  test('no results and errors', () async {
    final none = SubdlProvider(
      apiKey: 'k',
      client: recordingClient(
        [],
        (_) async =>
            jsonResponse({'status': false, 'error': "can't find movie or tv"}),
      ),
    );
    expect(await none.search(query), isEmpty);
    final bad = SubdlProvider(
      apiKey: 'k',
      client: recordingClient(
        [],
        (_) async => jsonResponse({
          'status': false,
          'error': 'Invalid API key',
        }, status: 403),
      ),
    );
    await expectLater(bad.search(query), throwsA(isA<SubtitleAuthException>()));
  });

  test('download adds the key only for dl.subdl.com', () async {
    final seen = <Seen>[];
    final p = SubdlProvider(
      apiKey: 'test-key',
      client: recordingClient(
        seen,
        (_) async => http.Response.bytes(
          fixtureBytes('archive/season_pack.zip'),
          200,
          headers: {
            'content-disposition':
                "attachment; filename*=UTF-8''Breaking%20Bad%20S01E01.zip",
          },
        ),
      ),
    );
    final d = await p.download(
      SubtitleResult(
        providerId: 'subdl',
        id: '1-2',
        language: Language.of('ar'),
        payload: const {'path': '/subtitle/1-2.zip'},
      ),
    );
    expect(
      seen.single.url.toString(),
      'https://dl.subdl.com/subtitle/1-2.zip?api_key=test-key',
    );
    expect(d.fileName, 'Breaking Bad S01E01.zip');
    expect(archiveKind(d.bytes), 'zip');
  });
}
