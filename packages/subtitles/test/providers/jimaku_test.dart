import 'package:http/http.dart' as http;
import 'package:subtitles/subtitles.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  test(
    'search by TMDB id, files for the episode, language from names',
    () async {
      final seen = <Seen>[];
      final p = JimakuProvider(
        apiKey: 'test-key',
        client: recordingClient(
          seen,
          (r) async => jsonResponse(
            fixtureJson(
              r.url.path.endsWith('/files')
                  ? 'providers/jimaku_files.json'
                  : 'providers/jimaku_entries.json',
            ),
          ),
        ),
      );
      final results = await p.search(
        SubtitleQuery(
          type: MediaType.episode,
          tmdbId: 209867,
          season: 1,
          episode: 5,
          languages: [Language.of('ja'), Language.of('en')],
        ),
      );
      expect(seen[0].url.path, '/api/entries/search');
      expect(seen[0].url.queryParameters, {'tmdb_id': 'tv:209867'});
      expect(seen[0].headers['Authorization'], 'test-key');
      expect(seen[1].url.path, '/api/entries/2210/files');
      expect(seen[1].url.queryParameters, {'episode': '5'});
      expect(results.map((r) => r.language.code), ['ja', 'en', 'ja']);
      expect(
        results.first.fileName,
        '[SubsPlease] Sousou no Frieren - 05 (1080p).ja.srt',
      );
      expect(results.first.format, SubtitleFormat.srt);
      expect(results.last.isSeasonPack, isTrue);
    },
  );

  test('only requested languages; text search without TMDB id', () async {
    final seen = <Seen>[];
    final p = JimakuProvider(
      apiKey: 'k',
      client: recordingClient(
        seen,
        (r) async => jsonResponse(
          fixtureJson(
            r.url.path.endsWith('/files')
                ? 'providers/jimaku_files.json'
                : 'providers/jimaku_entries.json',
          ),
        ),
      ),
    );
    final en = await p.search(
      SubtitleQuery(
        type: MediaType.episode,
        title: 'Frieren',
        season: 1,
        episode: 5,
        languages: [Language.of('en')],
      ),
    );
    expect(seen.first.url.queryParameters, {'query': 'Frieren'});
    expect(en.map((r) => r.fileName), ['Frieren.S01E05.WEBRip.Netflix.en.srt']);
  });

  test('download sends the key only to jimaku.cc', () async {
    final seen = <Seen>[];
    final p = JimakuProvider(
      apiKey: 'test-key',
      client: recordingClient(seen, (_) async => http.Response('x', 200)),
    );
    SubtitleResult r(String url) => SubtitleResult(
      providerId: 'jimaku',
      id: '1',
      language: Language.of('ja'),
      fileName: 'a.srt',
      payload: {'url': url},
    );
    await p.download(r('https://jimaku.cc/entry/1/download/a.srt'));
    await p.download(r('https://cdn.example.test/a.srt'));
    expect(seen[0].headers['Authorization'], 'test-key');
    expect(seen[1].headers.containsKey('Authorization'), isFalse);
  });
}
