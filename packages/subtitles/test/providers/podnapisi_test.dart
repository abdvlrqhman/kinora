import 'package:http/http.dart' as http;
import 'package:subtitles/subtitles.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  test(
    'search per language, parses flags, drops movies for episodes',
    () async {
      final seen = <Seen>[];
      final p = PodnapisiProvider(
        client: recordingClient(
          seen,
          (_) async => jsonResponse(
            fixtureJson('providers/podnapisi_search_bbt_s07e05.json'),
          ),
        ),
      );
      final results = await p.search(
        SubtitleQuery(
          type: MediaType.episode,
          title: 'The Big Bang Theory',
          year: 2007,
          season: 7,
          episode: 5,
          languages: [Language.of('en')],
        ),
      );
      final q = seen.single.url.queryParametersAll;
      expect(seen.single.url.path, '/subtitles/search/advanced');
      expect(q['keywords'], ['The Big Bang Theory']);
      expect(q['seasons'], ['7']);
      expect(q['episodes'], ['5']);
      expect(q['language'], ['en']);
      expect(q['movie_type'], ['tv-series', 'mini-series']);
      expect(seen.single.headers['Accept'], 'application/json');
      expect(results.map((r) => r.id), ['2581', 'GMso']);
      expect(results.first.hearingImpaired, isTrue);
      expect(results.first.releaseNames, [
        'the.big.bang.theory.s07e05.1080p.bluray.x264-rovers',
      ]);
      expect(results.first.downloads, 33406);
      expect(results.first.season, 7);
      expect(results.first.episodeFrom, 5);
      expect(results[1].fps, 23.976);
      expect(results[1].releaseNames, hasLength(2));
    },
  );

  test('download uses the zip container', () async {
    final seen = <Seen>[];
    final p = PodnapisiProvider(
      client: recordingClient(
        seen,
        (_) async =>
            http.Response.bytes(fixtureBytes('archive/nested.zip'), 200),
      ),
    );
    final d = await p.download(
      SubtitleResult(
        providerId: 'podnapisi',
        id: 'GMso',
        language: Language.of('en'),
      ),
    );
    expect(
      seen.single.url.toString(),
      'https://www.podnapisi.net/subtitles/GMso/download?container=zip',
    );
    expect(d.fileName, 'GMso.zip');
  });

  test('site offline surfaces as a network error', () async {
    final p = PodnapisiProvider(
      sleep: noSleep,
      client: recordingClient(
        [],
        (_) async =>
            throw http.ClientException('Failed host lookup: www.podnapisi.net'),
      ),
    );
    await expectLater(
      p.search(
        SubtitleQuery(
          type: MediaType.movie,
          title: 'Inception',
          languages: [Language.of('en')],
        ),
      ),
      throwsA(isA<SubtitleNetworkException>()),
    );
  });
}
