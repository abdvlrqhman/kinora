import 'package:http/http.dart' as http;
import 'package:subtitles/subtitles.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  test('episode request with extras; filters languages client-side', () async {
    final seen = <Seen>[];
    final p = StremioSubtitlesProvider(
      url: Uri.parse('https://opensubtitles-v3.strem.io/manifest.json'),
      name: 'OpenSubtitles v3',
      client: recordingClient(
        seen,
        (_) async =>
            jsonResponse(fixtureJson('providers/stremio_bb_s01e01.json')),
      ),
    );
    expect(p.id, 'stremio:opensubtitles-v3.strem.io');
    expect(p.displayName, 'OpenSubtitles v3');
    final results = await p.search(
      SubtitleQuery(
        type: MediaType.episode,
        imdbId: 'tt0903747',
        season: 1,
        episode: 1,
        languages: [Language.of('ar'), Language.of('pt-BR'), Language.of('fa')],
        fileHash: '8e245d9679d31e12',
        fileSize: 12909756,
        releaseNames: const ['Breaking Bad S01E01 720p.mkv'],
      ),
    );
    expect(
      seen.single.url.toString(),
      'https://opensubtitles-v3.strem.io/subtitles/series/tt0903747%3A1%3A1/'
      'videoHash=8e245d9679d31e12&videoSize=12909756&filename=Breaking%20Bad%20S01E01%20720p.mkv.json',
    );
    expect(results.map((r) => r.language.code).toSet(), {'ar', 'pt-BR', 'fa'});
    final pob = results.firstWhere((r) => r.language.code == 'pt-BR');
    expect(pob.fps, isNotNull);
    expect(pob.season, 1);
    expect(pob.episodeFrom, 1);
    expect(pob.payload['url'], startsWith('https://subs5.strem.io/'));
    expect(results.every((r) => r.matchedByHash == false), isTrue);
  });

  test('movie without extras, all languages when none requested', () async {
    final seen = <Seen>[];
    final p = StremioSubtitlesProvider(
      url: Uri.parse('https://addon.example.test/cfg123/'),
      client: recordingClient(
        seen,
        (_) async =>
            jsonResponse(fixtureJson('providers/stremio_inception.json')),
      ),
    );
    final results = await p.search(
      const SubtitleQuery(type: MediaType.movie, imdbId: 'tt1375666'),
    );
    expect(
      seen.single.url.toString(),
      'https://addon.example.test/cfg123/subtitles/movie/tt1375666.json',
    );
    expect(results.length, greaterThan(50));
    expect(results.first.releaseNames, isNotEmpty);
  });

  test('kitsu ids and download', () async {
    final seen = <Seen>[];
    final p = StremioSubtitlesProvider(
      url: Uri.parse('https://addon.example.test'),
      client: recordingClient(
        seen,
        (r) async => r.url.path.endsWith('.json')
            ? jsonResponse({
                'subtitles': [
                  {
                    'id': 'a',
                    'url': 'https://subs.example.test/a.srt',
                    'lang': 'eng',
                  },
                ],
              })
            : http.Response('1\n00:00:01,000 --> 00:00:02,000\nHi\n', 200),
      ),
    );
    final r = await p.search(
      SubtitleQuery(
        type: MediaType.episode,
        kitsuId: 46474,
        season: 1,
        episode: 3,
        languages: [Language.of('en')],
      ),
    );
    expect(seen.first.url.path, '/subtitles/series/kitsu%3A46474%3A3.json');
    final d = await p.download(r.single);
    expect(d.fileName, 'a.srt');
    expect(d.format, SubtitleFormat.srt);
  });
}
