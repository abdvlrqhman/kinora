// Hits the real providers. Excluded by default; run with
//   dart test -P live
// Keys come from the environment (never from files in the repo):
//   SUBDL_API_KEY, SUBSOURCE_API_KEY, WYZIE_API_KEY, OPENSUBTITLES_API_KEY
//   (+ OPENSUBTITLES_USERNAME / OPENSUBTITLES_PASSWORD), JIMAKU_API_KEY.
// A provider whose key is missing is skipped.
@Tags(['live'])
library;

import 'dart:io';

import 'package:subtitles/subtitles.dart';
import 'package:test/test.dart';

final ar = Language.of('ar');
final en = Language.of('en');

final breakingBad = SubtitleQuery(
  type: MediaType.episode,
  imdbId: 'tt0903747',
  tmdbId: 1396,
  title: 'Breaking Bad',
  year: 2008,
  season: 1,
  episode: 1,
  languages: [ar, en],
  releaseNames: const ['Breaking.Bad.S01E01.720p.BluRay.x264-DEMAND'],
);

final inception = SubtitleQuery(
  type: MediaType.movie,
  imdbId: 'tt1375666',
  tmdbId: 27205,
  title: 'Inception',
  year: 2010,
  languages: [en],
  releaseNames: const ['Inception.2010.1080p.BluRay.x264-SPARKS'],
);

String? env(String name) {
  final v = Platform.environment[name];
  return v == null || v.trim().isEmpty ? null : v.trim();
}

/// Searches, checks results are sane, then downloads + parses the best one.
Future<void> exercise(SubtitleProvider provider, SubtitleQuery query) async {
  final search = SubtitleSearch(providers: [provider]);
  final update = await search.searchAll(query);
  final status = update.providers[provider.id]!;
  expect(status.state, ProviderState.done, reason: '${status.error}');
  expect(status.count, greaterThan(0), reason: 'no results');
  final ranked = [for (final list in update.byLanguage.values) ...list];
  expect(ranked, isNotEmpty, reason: 'everything was rejected');
  expect(
    update.byLanguage.keys.every(query.languages.contains),
    isTrue,
    reason: 'unexpected languages ${update.counts}',
  );
  // Most answers should be for the right episode/movie.
  expect(update.rejected, lessThan(status.count));

  final best = update.best[query.languages.first] ?? ranked.first;
  final loaded = await search.load(best.result, query: query);
  expect(loaded.document.cues.length, greaterThan(50), reason: '$loaded');
  // ignore: avoid_print
  print(
    '${provider.id} ${query.title}: ${status.count} results, '
    '${update.counts.map((l, n) => MapEntry(l.code, n))}, '
    'rejected ${update.rejected}; best "${best.result.releaseNames.firstOrNull}" '
    '(${best.fit.toStringAsFixed(2)} ${best.tier.name}) -> '
    '${loaded.fileName} ${loaded.encoding} ${loaded.document.cues.length} cues',
  );
}

void main() {
  group('SubDL', () {
    final key = env('SUBDL_API_KEY');
    test(
      'Breaking Bad S01E01',
      () => exercise(SubdlProvider(apiKey: key!, maxPages: 1), breakingBad),
      skip: key == null ? 'SUBDL_API_KEY not set' : false,
    );
    test(
      'Inception',
      () => exercise(SubdlProvider(apiKey: key!, maxPages: 1), inception),
      skip: key == null ? 'SUBDL_API_KEY not set' : false,
    );
  });

  group('SubSource', () {
    final key = env('SUBSOURCE_API_KEY');
    test(
      'Breaking Bad S01E01',
      () => exercise(SubSourceProvider(apiKey: key!, maxPages: 1), breakingBad),
      skip: key == null ? 'SUBSOURCE_API_KEY not set' : false,
    );
    test(
      'Inception',
      () => exercise(SubSourceProvider(apiKey: key!, maxPages: 1), inception),
      skip: key == null ? 'SUBSOURCE_API_KEY not set' : false,
    );
  });

  group('Wyzie', () {
    final key = env('WYZIE_API_KEY');
    test(
      'Breaking Bad S01E01',
      () => exercise(WyzieProvider(apiKey: key!), breakingBad),
      skip: key == null ? 'WYZIE_API_KEY not set' : false,
    );
    test(
      'Inception',
      () => exercise(WyzieProvider(apiKey: key!), inception),
      skip: key == null ? 'WYZIE_API_KEY not set' : false,
    );
  });

  group('OpenSubtitles.com', () {
    final key = env('OPENSUBTITLES_API_KEY');
    OpenSubtitlesProvider make() => OpenSubtitlesProvider(
      apiKey: key!,
      username: env('OPENSUBTITLES_USERNAME'),
      password: env('OPENSUBTITLES_PASSWORD'),
    );
    test(
      'Breaking Bad S01E01',
      () => exercise(make(), breakingBad),
      skip: key == null ? 'OPENSUBTITLES_API_KEY not set' : false,
    );
    test(
      'Inception',
      () => exercise(make(), inception),
      skip: key == null ? 'OPENSUBTITLES_API_KEY not set' : false,
    );
  });

  group('Jimaku', () {
    final key = env('JIMAKU_API_KEY');
    final frieren = SubtitleQuery(
      type: MediaType.episode,
      tmdbId: 209867,
      title: 'Frieren',
      season: 1,
      episode: 1,
      languages: [Language.of('ja')],
    );
    test(
      'Frieren E01',
      () => exercise(JimakuProvider(apiKey: key!), frieren),
      skip: key == null ? 'JIMAKU_API_KEY not set' : false,
    );
  });

  group('Stremio OpenSubtitles v3 addon (no key)', () {
    StremioSubtitlesProvider make() => StremioSubtitlesProvider(
      url: Uri.parse('https://opensubtitles-v3.strem.io/manifest.json'),
    );
    test('Breaking Bad S01E01', () => exercise(make(), breakingBad));
    test('Inception', () => exercise(make(), inception));
  });

  group('Podnapisi (no key)', () {
    late bool online;
    setUpAll(() async {
      try {
        online = (await InternetAddress.lookup('www.podnapisi.net')).isNotEmpty;
      } on SocketException {
        online = false;
      }
    });
    test('Breaking Bad S01E01', () async {
      if (!online)
        markTestSkipped('www.podnapisi.net does not resolve (site offline)');
      if (online) await exercise(PodnapisiProvider(), breakingBad);
    });
  });
}
