import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kinora/app/providers.dart';
import 'package:kinora/core/db/database.dart';
import 'package:kinora/services/play_request.dart';
import 'package:kinora/services/resolver.dart';
import 'package:kinora/services/sources.dart';
import 'package:kinora/ui/theme.dart';
import 'package:stremio/stremio.dart';

/// Records where a screen navigated to.
final class Nav {
  final played = <PlayRequest>[];
  final locations = <String>[];
  late final GoRouter router;

  /// Pops the stub page the screen pushed.
  Future<void> back(WidgetTester tester) async {
    router.pop();
    await tester.pumpAndSettle();
  }
}

/// Pumps [screen] at `/` inside a router with stub title, player and
/// settings routes, an in-memory database and the given overrides.
Future<Nav> pumpScreen(
  WidgetTester tester,
  Widget screen, {
  required AppDatabase db,
  List<Override> overrides = const [],
  double textScale = 1,
  Size size = const Size(390, 844),
}) async {
  tester.view
    ..physicalSize = size * 3
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final nav = Nav();
  Widget stub(String text) => Scaffold(body: Center(child: Text(text)));
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => screen),
      GoRoute(
        path: '/title/:type/:id',
        builder: (_, s) {
          nav.locations.add(s.uri.toString());
          return stub('title page');
        },
      ),
      GoRoute(
        path: '/player',
        builder: (_, s) {
          nav.played.add(s.extra! as PlayRequest);
          return stub('player');
        },
      ),
      GoRoute(
        path: '/settings/sources',
        builder: (_, s) {
          nav.locations.add(s.uri.toString());
          return stub('sources');
        },
      ),
    ],
  );
  addTearDown(router.dispose);
  nav.router = router;
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [databaseProvider.overrideWithValue(db), ...overrides],
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: kinoraTheme(),
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    ),
  );
  return nav;
}

/// [testWidgets] that unmounts at the end (pass or fail), so drift's
/// zero-length close timers run before the pending-timer check.
void testScreen(String description, WidgetTesterCallback body) =>
    testWidgets(description, (tester) async {
      try {
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
      }
    });

/// A fresh in-memory database. Not closed: closing while a failed test's
/// tree still listens can hang, and memory is freed with the test isolate.
AppDatabase testDb() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase.forExecutor(NativeDatabase.memory());
}

final testAddon = Addon(
  transportUrl: Uri.parse('https://addon.test/manifest.json'),
  manifest: AddonManifest.fromJson({
    'id': 'test.addon',
    'name': 'Test source',
    'resources': ['catalog', 'meta'],
    'types': ['movie', 'series'],
  }),
);

/// Overrides for "one source is installed".
List<Override> withSource() => [
  enabledAddonsProvider.overrideWith((ref) async => [testAddon]),
];

CatalogRow catalogRow(String title, List<MetaPreview> items) => CatalogRow(
  title: title,
  type: items.first.type,
  items: items,
  addon: testAddon,
  catalog: ManifestCatalog(type: items.first.type, id: title),
);

MetaPreview preview(
  String id,
  String name, {
  String type = 'movie',
  String? poster,
  String? background,
  String? year = '2024',
}) => MetaPreview(
  id: id,
  type: type,
  name: name,
  poster: poster,
  background: background,
  releaseInfo: year,
);

/// A movie with full details.
MetaDetail movieMeta({String? background, String? poster}) => MetaDetail(
  id: 'tt100',
  type: 'movie',
  name: 'The Long Light',
  poster: poster,
  background: background,
  releaseInfo: '2024',
  runtime: '2h 10min',
  imdbRating: '8.1',
  genres: const ['Drama', 'Mystery'],
  description:
      'A lighthouse keeper on a far northern island starts receiving '
      'letters from a ship that sank forty years ago.',
  cast: const ['Ana Reyes', 'Tomas Berg', 'Lia Okafor'],
  director: const ['Mira Sand'],
);

/// Fixed "today" for series fixtures: S2 E3 airs after it.
final fixtureNow = DateTime.now();

/// Three seasons plus specials; S2 E3 hasn't aired.
MetaDetail seriesMeta({
  String? background,
  String? poster,
  String? Function(int season, int episode)? still,
}) {
  final titles = {
    1: ['Low Tide', 'The Keeper', 'Salt and Iron', 'Harbor Lights'],
    2: ['North Wind', 'The Long Night', 'Open Water'],
    3: ['Return', 'Beacons'],
  };
  final past = fixtureNow.subtract(const Duration(days: 400));
  return MetaDetail(
    id: 'tt200',
    type: 'series',
    name: 'Harbor Lights',
    poster: poster,
    background: background,
    releaseInfo: '2023–',
    runtime: '52 min',
    imdbRating: '8.6',
    genres: const ['Drama', 'Crime', 'Thriller'],
    description:
        'When a container ship runs aground off a quiet fishing town, a '
        'harbor pilot uncovers a smuggling ring that reaches her own family.',
    cast: const ['Ines Duarte', 'Kai Morrow', 'Sela Voss', 'Arno Pike'],
    director: const ['Jon Halvorsen'],
    videos: [
      for (final MapEntry(key: s, value: names) in titles.entries)
        for (var e = 1; e <= names.length; e++)
          Episode(
            id: 'tt200:$s:$e',
            title: names[e - 1],
            season: s,
            episode: e,
            released: s == 2 && e == 3
                ? fixtureNow.add(const Duration(days: 30))
                : past.add(Duration(days: s * 100 + e * 7)),
            thumbnail: still?.call(s, e),
            overview:
                'The pilot follows a ledger to the old cannery, where '
                'someone has kept the lights on for years.',
          ),
      Episode(
        id: 'tt200:0:1',
        title: 'Behind the lights',
        season: 0,
        episode: 1,
        released: past,
      ),
    ],
  );
}

/// Saves a progress row.
Future<void> saveProgress(
  AppDatabase db, {
  required String videoId,
  required String mediaId,
  String type = 'series',
  String name = 'Harbor Lights',
  int? season,
  int? episode,
  required int positionMs,
  int durationMs = 3000000,
  bool completed = false,
  required DateTime at,
  String? still,
  String? episodeTitle,
}) => db
    .into(db.watchProgress)
    .insertOnConflictUpdate(
      WatchProgressCompanion.insert(
        videoId: videoId,
        mediaId: mediaId,
        type: type,
        name: name,
        season: Value(season),
        episode: Value(episode),
        episodeTitle: Value(episodeTitle),
        positionMs: positionMs,
        durationMs: durationMs,
        completed: Value(completed),
        still: Value(still),
        updatedAt: Value(at),
      ),
    );

/// Fake releases, best first.
const fakeReleases = [
  ResolvedRelease(
    candidateId: 'c1',
    releaseName: 'Harbor.Lights.S01E03.1080p.WEB-DL.DDP5.1-NTb',
    headline: '1080p WEB-DL, 214 seeds',
    reasons: ['Arabic subtitles match', 'Plays on TV'],
    warnings: [],
    score: 0.94,
    sizeBytes: 2147483648,
    seeders: 214,
    resolution: '1080p',
    source: 'WEB-DL',
    addonName: 'Torrentio',
  ),
  ResolvedRelease(
    candidateId: 'c2',
    releaseName: 'Harbor.Lights.S01E03.2160p.WEB.DV.HDR.H265-FLUX',
    headline: '4K Dolby Vision WEB, cached',
    reasons: ['Starts instantly'],
    warnings: ['Dolby Vision may look dim on this phone'],
    score: 0.88,
    sizeBytes: 9019431321,
    instant: true,
    resolution: '4K',
    source: 'WEB',
    addonName: 'Real-Debrid',
  ),
  ResolvedRelease(
    candidateId: 'c3',
    releaseName: 'Harbor.Lights.S01E03.720p.HDTV.x264-SYNCOPY',
    headline: '720p HDTV, 41 seeds',
    reasons: ['Small download'],
    warnings: ['Few seeds', 'No Arabic subtitles'],
    score: 0.61,
    sizeBytes: 734003200,
    seeders: 41,
    resolution: '720p',
    source: 'HDTV',
    addonName: 'Torrentio',
  ),
];

Override resolveWith(List<ResolvedRelease> releases, {String? message}) =>
    resolveProvider.overrideWith(
      (ref, video) async => ResolveResult(releases: releases, message: message),
    );
