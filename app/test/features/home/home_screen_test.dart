import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinora/core/db/database.dart';
import 'package:kinora/features/home/home_screen.dart';
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
        homeCatalogsProvider.overrideWith((ref) async {
          loads++;
          return rows;
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
        homeCatalogsProvider.overrideWith((ref) async => rows),
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
    expect(await db.select(db.watchProgress).get(), isEmpty);
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
        homeCatalogsProvider.overrideWith((ref) async {
          calls++;
          throw Exception('SocketException: Network is unreachable');
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
        homeCatalogsProvider.overrideWith((ref) async => rows),
        metaProvider.overrideWith((ref, key) async => movieMeta()),
      ],
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
