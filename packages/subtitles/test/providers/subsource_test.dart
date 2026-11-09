import 'package:http/http.dart' as http;
import 'package:subtitles/subtitles.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  test(
    'episode: finds the season title, lists subs in wanted languages',
    () async {
      final seen = <Seen>[];
      final p = SubSourceProvider(
        apiKey: 'test-key',
        client: recordingClient(
          seen,
          (r) async => jsonResponse(
            fixtureJson(
              r.url.path.endsWith('/movies/search')
                  ? 'providers/subsource_search_bb.json'
                  : 'providers/subsource_subs_bb.json',
            ),
          ),
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
      expect(seen[0].url.path, '/api/v1/movies/search');
      expect(seen[0].url.queryParameters, {
        'searchType': 'imdb',
        'imdb': 'tt0903747',
        'type': 'series',
        'season': '1',
      });
      expect(seen[0].headers['X-API-Key'], 'test-key');
      expect(seen[1].url.queryParameters, {
        'movieId': '26604',
        'language': 'arabic,english',
        'limit': '100',
      });
      expect(results, hasLength(30));
      final first = results.first;
      expect(first.id, '10065902');
      expect(first.language.code, 'ar');
      expect(first.releaseNames, [
        'Breaking Bad Season 1 (2160p x265 10bit Joy)',
      ]);
      expect(first.downloads, 317);
      expect(first.rating, 10);
      expect(first.season, 1);
      expect(first.uploadDate, DateTime.utc(2024, 12, 13, 10, 51, 12, 768));
      expect(results.where((r) => r.forced), isEmpty);
    },
  );

  test('movie search and download', () async {
    final seen = <Seen>[];
    final p = SubSourceProvider(
      apiKey: 'test-key',
      client: recordingClient(seen, (r) async {
        if (r.url.path.endsWith('/download')) {
          return http.Response.bytes(
            fixtureBytes('archive/multi_language.zip'),
            200,
            headers: {
              'content-type': 'application/zip',
              'content-disposition': 'attachment; filename="inception-2010_english_10215904-[SubSource].zip"',
            },
          );
        }
        return jsonResponse(
          fixtureJson(
            r.url.path.endsWith('/movies/search')
                ? 'providers/subsource_search_inception.json'
                : 'providers/subsource_subs_inception.json',
          ),
        );
      }),
    );
    final results = await p.search(
      SubtitleQuery(
        type: MediaType.movie,
        imdbId: 'tt1375666',
        languages: [Language.of('en')],
      ),
    );
    expect(results, hasLength(20));
    expect(results.first.fps, 23.976);
    expect(results.first.comments, contains('corrections'));
    final d = await p.download(results.first);
    expect(seen.last.url.path, '/api/v1/subtitles/10215904/download');
    expect(seen.last.headers['X-API-Key'], 'test-key');
    expect(d.fileName, 'inception-2010_english_10215904-[SubSource].zip');
  });

  test('falls back to text search; no title -> no results', () async {
    final seen = <Seen>[];
    final p = SubSourceProvider(
      apiKey: 'k',
      client: recordingClient(
        seen,
        (_) async => jsonResponse({'success': true, 'data': <Object?>[]}),
      ),
    );
    final r = await p.search(
      SubtitleQuery(
        type: MediaType.movie,
        imdbId: 'tt9999999',
        title: 'Obscure Film',
        year: 2001,
        languages: [Language.of('en')],
      ),
    );
    expect(r, isEmpty);
    expect(seen.map((s) => s.url.queryParameters['searchType']), [
      'imdb',
      'text',
    ]);
    expect(seen.last.url.queryParameters['q'], 'Obscure Film');
  });

  test('rate limit with retryAfter body is retried', () async {
    var calls = 0;
    final sleeps = <Duration>[];
    final p = SubSourceProvider(
      apiKey: 'k',
      sleep: (d) async => sleeps.add(d),
      client: recordingClient(
        [],
        (_) async => ++calls == 1
            ? jsonResponse({
                'error': 'Rate limit exceeded',
                'retryAfter': 2,
              }, status: 429)
            : jsonResponse({'success': true, 'data': <Object?>[]}),
      ),
    );
    await p.search(const SubtitleQuery(type: MediaType.movie, imdbId: 'tt1'));
    expect(sleeps, [const Duration(seconds: 2)]);
  });
}
