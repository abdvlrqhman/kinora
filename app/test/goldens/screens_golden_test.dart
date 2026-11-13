// Visual review screenshots; excluded from CI comparisons (pixels differ
// between machines). Update with: flutter test --update-goldens --tags golden
@Tags(['golden'])
library;

import 'package:dlna/dlna.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinora/app/app.dart';
import 'package:kinora/app/intro.dart';
import 'package:kinora/app/providers.dart';
import 'package:kinora/core/db/database.dart';
import 'package:kinora/core/settings.dart';
import 'package:kinora/features/cast/cast_picker.dart';
import 'package:kinora/features/home/home_feed.dart';
import 'package:kinora/features/search/search_screen.dart';
import 'package:kinora/features/title/title_screen.dart';
import 'package:kinora/features/trakt/trakt_ui.dart';
import 'package:kinora/services/cast_service.dart';
import 'package:kinora/services/sources.dart';
import 'package:kinora/services/tmdb.dart';
import 'package:kinora/services/trakt.dart';
import 'package:stremio/stremio.dart';

import '../features/harness.dart';
import 'golden_helper.dart';

// Regenerate with: flutter test --update-goldens test/goldens
void main() {
  setUpAll(loadAppFonts);

  final day = DateTime(2026, 10);

  MetaDetail series() => seriesMeta(
    background: art('harbor_backdrop'),
    poster: art('harbor_poster'),
    still: (s, e) => art('still_${(s * 3 + e) % 6 + 1}'),
  );

  Future<void> seedSeries(AppDatabase db) async {
    for (final e in [1, 2]) {
      await saveProgress(
        db,
        videoId: 'tt200:1:$e',
        mediaId: 'tt200',
        season: 1,
        episode: e,
        positionMs: 3000000,
        completed: true,
        at: day.add(Duration(days: e)),
      );
    }
    await saveProgress(
      db,
      videoId: 'tt200:1:3',
      mediaId: 'tt200',
      season: 1,
      episode: 3,
      positionMs: 1150000,
      at: day.add(const Duration(days: 3)),
    );
    for (final (id, state, done) in [
      ('tt200:1:2', 'completed', 100),
      ('tt200:1:4', 'downloading', 38),
    ]) {
      await db
          .into(db.downloads)
          .insert(
            DownloadsCompanion.insert(
              id: id,
              mediaId: 'tt200',
              videoId: id,
              type: 'series',
              title: 'Harbor Lights',
              releaseName: 'x',
              kind: 'torrent',
              directory: '/tmp',
              state: state,
              totalBytes: const Value(100),
              doneBytes: Value(done),
            ),
          );
    }
  }

  Future<Nav> pumpTitle(WidgetTester tester) async {
    final db = testDb();
    await seedSeries(db);
    await warmUp(tester);
    final nav = await pumpScreen(
      tester,
      const TitleScreen(type: 'series', id: 'tt200'),
      db: db,
      overrides: [
        ...withSource(),
        metaProvider.overrideWith((ref, key) async => series()),
        resolveWith(fakeReleases),
      ],
    );
    phoneInsets(tester);
    await settleImages(tester);
    return nav;
  }

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(390, 844) * 3
      ..devicePixelRatio = 3;
    phoneInsets(tester);
    addTearDown(tester.view.reset);

    final db = testDb();
    await saveProgress(
      db,
      videoId: 'tt200:1:3',
      mediaId: 'tt200',
      season: 1,
      episode: 3,
      episodeTitle: 'Salt and Iron',
      positionMs: 1150000,
      still: art('still_3'),
      at: day.add(const Duration(days: 3)),
    );
    await saveProgress(
      db,
      videoId: 'tt101',
      mediaId: 'tt101',
      type: 'movie',
      name: 'Glass Harbor',
      positionMs: 4100000,
      durationMs: 6600000,
      at: day.add(const Duration(days: 2)),
    );
    await saveProgress(
      db,
      videoId: 'tt201:2:1',
      mediaId: 'tt201',
      name: 'North Wind',
      season: 2,
      episode: 1,
      positionMs: 600000,
      still: art('still_4'),
      at: day.add(const Duration(days: 1)),
    );
    for (final (id, name, poster) in [
      ('tt103', 'Glacier', 'glacier_poster'),
      ('tt104', 'Bloom', 'bloom_poster'),
    ]) {
      await db
          .into(db.libraryItems)
          .insert(
            LibraryItemsCompanion.insert(
              mediaId: id,
              type: 'movie',
              name: name,
              poster: Value(art(poster)),
            ),
          );
    }

    final movies = catalogRow('Popular movies', [
      preview(
        'tt100',
        'The Long Light',
        poster: art('dune_poster'),
        background: art('dune_backdrop'),
      ),
      preview('tt101', 'Glass Harbor', poster: art('harbor_poster')),
      preview('tt102', 'Ember', poster: art('ember_poster')),
      preview('tt103', 'Glacier', poster: art('glacier_poster')),
    ]);
    final shows = catalogRow('Popular shows', [
      preview(
        'tt200',
        'Harbor Lights',
        type: 'series',
        poster: art('tide_poster'),
      ),
      preview(
        'tt201',
        'North Wind',
        type: 'series',
        poster: art('forest_poster'),
      ),
      preview(
        'tt202',
        'Neon Coast',
        type: 'series',
        poster: art('neon_poster'),
      ),
    ]);

    await warmUp(tester);
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          initialSettingsProvider.overrideWithValue(
            const AppSettings(onboarded: true),
          ),
          databaseProvider.overrideWithValue(db),
          ...withSource(),
          homeRowsProvider.overrideWith(
            (ref) => Stream.value(HomeRows([movies, shows])),
          ),
          onlineProvider.overrideWith((ref) => Stream.value(true)),
          castSearchProvider.overrideWithValue(() async {}),
          traktConfigProvider.overrideWithValue(
            const TraktConfig(clientId: 'kinora'),
          ),
          resolveWith(fakeReleases),
          metaProvider.overrideWith(
            (ref, key) async => switch (key.id) {
              'tt100' => movieMeta(
                background: art('dune_backdrop'),
                poster: art('dune_poster'),
              ),
              'tt101' => MetaDetail(
                id: 'tt101',
                type: 'movie',
                name: 'Glass Harbor',
                background: art('harbor_backdrop'),
              ),
              _ => throw StateError('No details'),
            },
          ),
        ],
        child: const KinoraApp(showIntro: false),
      ),
    );
    await settleImages(tester);
  }

  // At rest: Continue watching clears the tab bar.
  // Launch: the mark switching on, then the hold with Powered by Spacie.
  testScreen('intro', (tester) async {
    tester.view
      ..physicalSize = const Size(390, 844) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    IntroOverlay.debugReset();
    await tester.pumpWidget(
      const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: IntroOverlay(
          child: Scaffold(body: Center(child: Text('app'))),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await expectLater(
      find.byType(IntroOverlay),
      matchesGoldenFile('screens/intro_lighting.png'),
    );
    await tester.pump(const Duration(milliseconds: 900));
    await expectLater(
      find.byType(IntroOverlay),
      matchesGoldenFile('screens/intro.png'),
    );
    await tester.pumpAndSettle();
  });

  testScreen('home', (tester) async {
    await pumpHome(tester);
    await expectLater(
      find.byType(KinoraApp),
      matchesGoldenFile('screens/home.png'),
    );
  });

  // Trakt from Home: the avatar beside Cast opens the account sheet.
  testScreen('home, Trakt signed in', (tester) async {
    await pumpHome(tester);
    ProviderScope.containerOf(tester.element(find.byType(KinoraApp)))
        .read(traktSyncProvider)
        .debugSignedIn(
          'abdvlrqhman',
          at: DateTime.now().subtract(const Duration(minutes: 3)),
          brought: (watched: 120, resume: 3, listed: 12),
        );
    await tester.pump();
    await tester.tap(find.byType(TraktAvatar));
    await settleImages(tester);
    await expectLater(
      find.byType(KinoraApp),
      matchesGoldenFile('screens/home_trakt.png'),
    );
  });

  // Scrolled: rows passing under the tab bar dim behind its scrim.
  testScreen('home, scrolled under the tab bar', (tester) async {
    await pumpHome(tester);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -260));
    await settleImages(tester);
    await expectLater(
      find.byType(KinoraApp),
      matchesGoldenFile('screens/home_scrolled.png'),
    );
  });

  testScreen('title, series', (tester) async {
    await pumpTitle(tester);
    await expectLater(
      find.byType(TitleScreen),
      matchesGoldenFile('screens/title_series.png'),
    );
  });

  // With a TMDB key: tagline, age rating, cast photos, More like this.
  testScreen('title, series with TMDB', (tester) async {
    tester.view
      ..physicalSize = const Size(390, 1700) * 3
      ..devicePixelRatio = 3;
    final db = testDb();
    await seedSeries(db);
    await warmUp(tester);
    await pumpScreen(
      tester,
      const TitleScreen(type: 'series', id: 'tt200'),
      db: db,
      size: const Size(390, 1700),
      overrides: [
        ...withSource(),
        metaProvider.overrideWith((ref, key) async => series()),
        resolveWith(fakeReleases),
        tmdbTitleProvider.overrideWith(
          (ref, key) async => TmdbTitle(
            id: 1,
            series: true,
            tagline: 'Every light hides a harbor.',
            certification: 'TV-MA',
            cast: [
              (name: 'Ines Duarte', role: 'Mara Lind', photo: art('still_3')),
              (name: 'Kai Morrow', role: 'Teo Vass', photo: art('still_4')),
              (name: 'Sela Voss', role: 'The Pilot', photo: null),
              (name: 'Arno Pike', role: null, photo: art('harbor_poster')),
            ],
            similar: [
              for (final n in ['tide', 'ember', 'glacier', 'neon'])
                (
                  id: n.length,
                  type: 'series',
                  name: n,
                  poster: art('${n}_poster'),
                  year: '2024',
                ),
            ],
          ),
        ),
      ],
    );
    phoneInsets(tester);
    await settleImages(tester);
    await expectLater(
      find.byType(TitleScreen),
      matchesGoldenFile('screens/title_tmdb.png'),
    );
  });

  testScreen('title, series episodes', (tester) async {
    await pumpTitle(tester);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -620));
    await settleImages(tester);
    await expectLater(
      find.byType(TitleScreen),
      matchesGoldenFile('screens/title_series_episodes.png'),
    );
  });

  testScreen('title, header strip once scrolled', (tester) async {
    await pumpTitle(tester);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -420));
    await settleImages(tester);
    await expectLater(
      find.byType(TitleScreen),
      matchesGoldenFile('screens/title_header_strip.png'),
    );
  });

  testScreen('cast picker', (tester) async {
    await pumpTitle(tester);
    ProviderScope.containerOf(tester.element(find.byType(TitleScreen)))
        .read(castServiceProvider)
        .devices = [
      DlnaDevice(
        udn: 'uuid:tv-2',
        friendlyName: 'Bedroom TV',
        modelName: 'LG webOS TV',
        location: Uri.parse('http://192.168.1.31:1527/'),
        avTransportControlUrl: Uri.parse('http://192.168.1.31:1527/av'),
      ),
      DlnaDevice(
        udn: 'uuid:tv-1',
        friendlyName: 'Living Room TV',
        modelName: 'Samsung 5 Series',
        location: Uri.parse('http://192.168.1.20:9197/dmr'),
        avTransportControlUrl: Uri.parse('http://192.168.1.20:9197/av'),
      ),
    ];
    await tester.tap(find.bySemanticsLabel('Cast to a TV'));
    await settleImages(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('screens/cast_picker.png'),
    );
  });

  testScreen('version sheet', (tester) async {
    await pumpTitle(tester);
    await tester.tap(find.bySemanticsLabel('Choose another version'));
    await settleImages(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('screens/version_sheet.png'),
    );
  });

  testScreen('search results', (tester) async {
    final results = [
      preview(
        'tt101',
        'Glass Harbor',
        poster: art('harbor_poster'),
        year: '2019',
      ),
      preview(
        'tt105',
        'Harbor at Dusk',
        poster: art('dune_poster'),
        year: '2022',
      ),
      preview(
        'tt200',
        'Harbor Lights',
        type: 'series',
        poster: art('tide_poster'),
        year: '2023–',
      ),
      preview(
        'tt203',
        'Harbor Patrol',
        type: 'series',
        poster: art('glacier_poster'),
        year: '2011–2015',
      ),
      preview(
        'tt204',
        'The Harbormaster',
        type: 'series',
        poster: art('ember_poster'),
        year: '2020',
      ),
      preview(
        'kitsu:9',
        'Harbor Spirits',
        type: 'anime',
        poster: art('bloom_poster'),
        year: '2018',
      ),
    ];
    await warmUp(tester);
    await pumpScreen(
      tester,
      const SearchScreen(),
      db: testDb(),
      overrides: [
        ...withSource(),
        searchProvider.overrideWith((ref, q) async => results),
      ],
    );
    phoneInsets(tester);
    await tester.enterText(find.byType(TextField), 'harbor');
    await tester.pump(SearchScreen.debounce);
    FocusManager.instance.primaryFocus?.unfocus();
    await settleImages(tester);
    await expectLater(
      find.byType(SearchScreen),
      matchesGoldenFile('screens/search_results.png'),
    );
  });
}
