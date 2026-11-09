import 'package:http/http.dart' as http;
import 'package:subtitles/subtitles.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  test('search: params, AI rows, formats', () async {
    final seen = <Seen>[];
    final p = WyzieProvider(
      apiKey: 'test-key',
      client: recordingClient(
        seen,
        (_) async =>
            jsonResponse(fixtureJson('providers/wyzie_bb_s01e01.json')),
      ),
    );
    final results = await p.search(
      SubtitleQuery(
        type: MediaType.episode,
        imdbId: 'tt0903747',
        season: 1,
        episode: 1,
        languages: [Language.of('ar'), Language.of('en')],
      ),
    );
    expect(seen.single.url.queryParameters, {
      'id': 'tt0903747',
      'season': '1',
      'episode': '1',
      'language': 'ar,en',
      'key': 'test-key',
    });
    expect(results, hasLength(38));
    final first = results.first;
    expect(first.id, '1952400548');
    expect(first.language.code, 'ar');
    expect(first.releaseNames, ['S1E01 - Pilot']);
    expect(first.fileName, 'S1E01 - Pilot.srt');
    expect(first.downloads, 482959);
    expect(first.format, SubtitleFormat.srt);
    expect(results.where((r) => r.machineTranslated), isNotEmpty);
    expect(results.where((r) => r.format == SubtitleFormat.ssa), isNotEmpty);
    // en-US etc. normalize to en.
    expect(results.map((r) => r.language.code).toSet(), {'ar', 'en'});
  });

  test('404 = no subtitles; 401 = auth error', () async {
    final none = WyzieProvider(
      apiKey: 'k',
      client: recordingClient(
        [],
        (_) async => jsonResponse({
          'code': 404,
          'message': 'No subtitles found',
        }, status: 404),
      ),
    );
    expect(
      await none.search(
        const SubtitleQuery(type: MediaType.movie, imdbId: 'tt1'),
      ),
      isEmpty,
    );
    final bad = WyzieProvider(
      apiKey: 'k',
      client: recordingClient(
        [],
        (_) async => jsonResponse({
          'code': 401,
          'message': 'API key required',
        }, status: 401),
      ),
    );
    await expectLater(
      bad.search(const SubtitleQuery(type: MediaType.movie, imdbId: 'tt1')),
      throwsA(isA<SubtitleAuthException>()),
    );
  });

  test('download fetches the signed URL as-is', () async {
    final seen = <Seen>[];
    final p = WyzieProvider(
      apiKey: 'k',
      client: recordingClient(
        seen,
        (_) async => http.Response(
          '1\n00:00:01,000 --> 00:00:02,000\nHi\n',
          200,
          headers: {'content-disposition': 'inline; filename="subtitle.srt"'},
        ),
      ),
    );
    final d = await p.download(
      SubtitleResult(
        providerId: 'wyzie',
        id: '1',
        language: Language.of('en'),
        format: SubtitleFormat.srt,
        payload: const {
          'url': 'https://sub.wyzie.io/c/abc/id/1?format=srt&tok=t',
        },
      ),
    );
    expect(
      seen.single.url.toString(),
      'https://sub.wyzie.io/c/abc/id/1?format=srt&tok=t',
    );
    expect(d.format, SubtitleFormat.srt);
  });
}
