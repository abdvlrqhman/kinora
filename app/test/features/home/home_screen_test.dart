import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinora/core/db/database.dart';
import 'package:kinora/features/home/home_feed.dart';
import 'package:kinora/features/home/home_screen.dart';
import 'package:kinora/features/title/title_model.dart';
import 'package:kinora/ui/glass.dart';
import 'package:kinora/ui/widgets/states.dart';
import 'package:kinora/services/sources.dart';

import '../harness.dart';

void main() {
  final rows = [
    catalogRow('Popular movies', [
      preview('tt100', 'The Long Light'),
      preview('tt101', 'Glass Harbor'),
      preview('tt102', 'Ember'),
    ]),
    catalogRow('Popular shows', [
      preview('tt200', 'Harbor Lights', type: 'series'),
      preview('tt201', 'North Wind', type: 'series'),
    ]),
  ];

  Future<void> seedLibrary(AppDatabase db) async {
    await saveProgress(
      db,
      videoId: 'tt200:1:3',
      mediaId: 'tt200',
      season: 1,
      episode: 3,
      episodeTitle: 'Salt and Iron',
      positionMs: 1200000,
      at: DateTime(2026, 11),
    );
    await db
        .into(db.libraryItems)
        .insert(
          LibraryItemsCompanion.insert(
            mediaId: 'tt201',
            type: 'series',
            name: 'North Wind',
          ),
        );
  }

  testScreen('shows the billboard, Continue watching, My list and rows', (
    tester,
  ) async {
    final db = testDb();
    await seedLibrary(db);
    var loads = 0;
    final nav = await pumpScreen(
      tester,
      const HomeScreen(),
      db: db,
      size: const Size(390, 1600),
      overrides: [
        ...withSource(),
        homeRowsProvider.overrideWith((ref) {
          loads++;
          return Stream.value(HomeRows(rows));
        }),
        metaProvider.overrideWith(
          (ref, key) async =>
              key.id == 'tt100' ? movieMeta() : throw StateError('No details'),
        ),
      ],
    );
    await tester.pumpAndSettle();

    // Billboard: first title, facts from its details, Play + My list.
    expect(find.text('The Long Light'), findsWidgets); // billboard + poster
    expect(find.text('2h 10m'), findsOneWidget);
    expect(find.text('Drama, Mystery'), findsOneWidget);
    expect(find.text('Continue watching'), findsOneWidget);
    expect(find.text('S1 E3  30m left'), findsOneWidget);
    expect(find.text('My list'), findsNWidgets(2)); // row title + button
    expect(find.text('Popular movies'), findsOneWidget);
    expect(find.text('Popular shows'), findsOneWidget);

    // Play starts a movie directly.
    await tester.tap(find.bySemanticsLabel('Play The Long Light'));
    await tester.pumpAndSettle();
    expect(nav.played.last.videoId, 'tt100');
    expect(nav.played.last.type, 'movie');
    await nav.back(tester);

    // A poster opens its title page.
    await tester.tap(find.bySemanticsLabel('Glass Harbor'));
    await tester.pumpAndSettle();
    expect(nav.locations.last, '/title/movie/tt101');
    await nav.back(tester);

    // Continue watching resumes where it stopped.
    await tester.tap(find.bySemanticsLabel(RegExp('^Resume Harbor Lights')));
    await tester.pumpAndSettle();
    expect(nav.played.last.videoId, 'tt200:1:3');
    expect(nav.played.last.startAt, const Duration(minutes: 20));
    await nav.back(tester);

    // Pull to refresh reloads the catalogs.
    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, 500),
      1000,
    );
    await tester.pumpAndSettle();
    expect(loads, 2);
  });

  testScreen('long-press on Continue watching offers row actions', (
    tester,
  ) async {
    final db = testDb();
    await seedLibrary(db);
    final nav = await pumpScreen(
      tester,
      const HomeScreen(),
      db: db,
      size: const Size(390, 1600),
      overrides: [
        ...withSource(),
        homeRowsProvider.overrideWith((ref) => Stream.value(HomeRows(rows))),
        metaProvider.overrideWith((ref, key) async => movieMeta()),
      ],
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.bySemanticsLabel(RegExp('^Resume Harbor')));
    await tester.pumpAndSettle();
    expect(find.text('Go to title'), findsOneWidget);
    expect(find.text('Mark as watched'), findsOneWidget);
    await tester.tap(find.text('Go to title'));
    await tester.pumpAndSettle();
    expect(nav.locations.last, '/title/series/tt200');
    await nav.back(tester);

    await tester.longPress(find.bySemanticsLabel(RegExp('^Resume Harbor')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove from row'));
    await tester.pumpAndSettle();
    // Hidden from the row; progress and watched marks are kept.
    final kept = await db.select(db.watchProgress).get();
    expect(kept, isNotEmpty);
    expect(kept.every((r) => r.dismissed), isTrue);
    expect(find.text('Continue watching'), findsNothing);
  });

  testScreen('invites adding a source when none is installed', (tester) async {
    final db = testDb();
    final nav = await pumpScreen(
      tester,
      const HomeScreen(),
      db: db,
      overrides: [enabledAddonsProvider.overrideWith((ref) async => [])],
    );
    await tester.pumpAndSettle();
    expect(find.text('Add a source to see movies and shows.'), findsOneWidget);
    await tester.tap(find.text('Add a source'));
    await tester.pumpAndSettle();
    expect(nav.locations.last, '/settings/sources');
  });

  testScreen('says what went wrong and retries', (tester) async {
    final db = testDb();
    var calls = 0;
    await pumpScreen(
      tester,
      const HomeScreen(),
      db: db,
      overrides: [
        ...withSource(),
        homeRowsProvider.overrideWith((ref) {
          calls++;
          return Stream.error(
            Exception('SocketException: Network is unreachable'),
          );
        }),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.text('Check your connection, then try again.'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(calls, 2);
  });

  testScreen('fits at 1.5x text size', (tester) async {
    final db = testDb();
    await seedLibrary(db);
    await pumpScreen(
      tester,
      const HomeScreen(),
      db: db,
      textScale: 1.5,
      overrides: [
        ...withSource(),
        homeRowsProvider.overrideWith((ref) => Stream.value(HomeRows(rows))),
        metaProvider.overrideWith((ref, key) async => movieMeta()),
      ],
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testScreen(
    'a show\'s billboard resumes it in one tap and names the version',
    (tester) async {
      final db = testDb();
      await seedLibrary(db);
      final nav = await pumpScreen(
        tester,
        const HomeScreen(),
        db: db,
        size: const Size(390, 1600),
        overrides: [
          ...withSource(),
          homeRowsProvider.overrideWith(
            (ref) => Stream.value(
              HomeRows([
                catalogRow('Popular shows', [
                  preview('tt200', 'Harbor Lights', type: 'series'),
                ]),
              ]),
            ),
          ),
          metaProvider.overrideWith(
            (ref, key) async => key.id == 'tt200'
                ? seriesMeta()
                : throw StateError('No details'),
          ),
          resolveWith(fakeReleases),
        ],
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<GlassButton>(find.byKey(const ValueKey('billboard-play')))
            .label,
        'Resume S1 E3',
      );
      expect(find.textContaining('1080p WEB-DL, 214 seeds'), findsOneWidget);
      expect(find.textContaining('30m left'), findsWidgets);
      expect(find.bySemanticsLabel('Details'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('billboard-play')));
      await tester.pumpAndSettle();
      expect(nav.played.last.videoId, 'tt200:1:3');
      expect(nav.played.last.startAt, const Duration(minutes: 20));
    },
  );

  testScreen('rows appear as each source answers; offline says so', (
    tester,
  ) async {
    final feed = StreamController<HomeRows>();
    addTearDown(feed.close);
    await pumpScreen(
      tester,
      const HomeScreen(),
      db: testDb(),
      size: const Size(390, 1600),
      overrides: [
        ...withSource(),
        homeRowsProvider.overrideWith((ref) => feed.stream),
        metaProvider.overrideWith((ref, key) async => movieMeta()),
      ],
    );
    feed.add(HomeRows([rows.first], complete: false));
    await tester.pumpAndSettle();
    expect(find.text('Popular movies'), findsOneWidget);
    expect(find.byType(LoadingBlock), findsWidgets); // the slow one

    feed.add(const HomeRows([], failed: true, offline: true));
    await tester.pumpAndSettle();
    expect(find.text('You’re offline'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  test('the billboard rotates daily and prefers shows with new episodes', () {
    final pool = [
      for (var i = 0; i < 12; i++)
        preview('tt$i', 'Film $i', background: 'b$i'),
    ];
    final row = [catalogRow('Popular', pool)];
    final days = {
      for (var d = 1; d <= 20; d++)
        pickFeatured(row, const [], DateTime(2026, 11, d))!.id,
    };
    // Ten titles with backdrops take turns, a different one each day.
    expect(days.length, 10);
    expect(
      pickFeatured(row, const [], DateTime(2026, 11, 3, 9))!.id,
      pickFeatured(row, const [], DateTime(2026, 11, 3, 23))!.id,
    );
    final show = TitleModel(seriesMeta(background: 'harbor'));
    final fresh = [NewEpisodes(show, show.order.take(1).toList())];
    expect(pickFeatured(row, fresh, DateTime(2026, 11, 3))!.id, 'tt200');
  });
}
