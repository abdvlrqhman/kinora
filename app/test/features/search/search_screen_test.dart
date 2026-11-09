import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinora/core/db/database.dart';
import 'package:kinora/features/search/search_model.dart';
import 'package:kinora/features/search/search_screen.dart';
import 'package:kinora/services/sources.dart';

import '../harness.dart';

void main() {
  final results = [
    preview('tt100', 'Harbor', year: '2019'),
    preview('tt200', 'Harbor Lights', type: 'series', year: '2023–'),
    preview('tt201', 'Harbor Patrol', type: 'series', year: '2011'),
    preview('kitsu:9', 'Harbor Spirits', type: 'anime', year: '2020'),
  ];

  group('parsePlayLink', () {
    test('reads the magnet name', () {
      final link = parsePlayLink(
        'magnet:?xt=urn:btih:0123456789abcdef&dn=Big+Buck+Bunny%20(2008)'
        '&tr=udp://tracker.test:80',
      );
      expect(link?.name, 'Big Buck Bunny (2008)');
    });

    test('names a magnet without dn plainly', () {
      expect(parsePlayLink('magnet:?xt=urn:btih:abc')?.name, 'Magnet link');
    });

    test('uses the URL file name', () {
      final link = parsePlayLink(
        ' https://cdn.example.com/films/Night%20Train.mkv?token=1 ',
      );
      expect(link?.name, 'Night Train.mkv');
      expect(
        link?.url,
        'https://cdn.example.com/films/Night%20Train.mkv?token=1',
      );
      expect(parsePlayLink('http://example.com')?.name, 'example.com');
    });

    test('leaves search text alone', () {
      expect(parsePlayLink('harbor lights'), isNull);
      expect(parsePlayLink('magnet'), isNull);
      expect(parsePlayLink('ftp://example.com/a.mkv'), isNull);
      expect(parsePlayLink('https://'), isNull);
    });
  });

  test('groups results as Movies, Shows, Anime', () {
    final groups = groupResults(results);
    expect(
      [for (final g in groups) (g.label, g.items.length)],
      [('Movies', 1), ('Shows', 2), ('Anime', 1)],
    );
  });

  testScreen('focuses the field and searches after a 350 ms pause', (
    tester,
  ) async {
    final queries = <String>[];
    final nav = await pumpScreen(
      tester,
      const SearchScreen(),
      db: testDb(),
      overrides: [
        ...withSource(),
        searchProvider.overrideWith((ref, q) async {
          queries.add(q);
          return results;
        }),
      ],
    );
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.focusNode!.hasFocus, isTrue);

    await tester.enterText(find.byType(TextField), 'har');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(find.byType(TextField), 'harbor');
    await tester.pump(const Duration(milliseconds: 300));
    expect(queries, isEmpty);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pumpAndSettle();
    expect(queries, ['harbor']);

    expect(find.bySemanticsLabel('Movies, 1 results'), findsOneWidget);
    expect(find.bySemanticsLabel('Shows, 2 results'), findsOneWidget);
    expect(find.bySemanticsLabel('Anime, 1 results'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Harbor Lights, 2023–'));
    await tester.pumpAndSettle();
    expect(nav.locations.last, '/title/series/tt200');
  });

  testScreen('remembers, reuses and removes recent searches', (tester) async {
    final db = testDb();
    await db
        .into(db.searchHistory)
        .insert(
          SearchHistoryCompanion.insert(
            query: 'dune',
            at: Value(DateTime(2026)),
          ),
        );
    await db
        .into(db.searchHistory)
        .insert(
          SearchHistoryCompanion.insert(
            query: 'arrival',
            at: Value(DateTime(2026, 2)),
          ),
        );
    await pumpScreen(
      tester,
      const SearchScreen(),
      db: db,
      overrides: [
        ...withSource(),
        searchProvider.overrideWith((ref, q) async => results),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.text('Recent searches'), findsOneWidget);
    expect(find.text('arrival'), findsOneWidget);
    expect(find.text('dune'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Remove dune from recent searches'));
    await tester.pumpAndSettle();
    expect(find.text('dune'), findsNothing);

    // Submitting saves the search; clearing shows it first in recents.
    await tester.enterText(find.byType(TextField), 'harbor');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Shows, 2 results'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Clear search'));
    await tester.pumpAndSettle();
    final recents = await db.select(db.searchHistory).get();
    expect(recents.map((r) => r.query), containsAll(['harbor', 'arrival']));
    expect(find.text('harbor'), findsOneWidget);

    // Tapping a recent search runs it.
    await tester.tap(find.bySemanticsLabel('Search for arrival'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Movies, 1 results'), findsOneWidget);
  });

  testScreen('offers to play a pasted magnet link', (tester) async {
    var searched = false;
    final nav = await pumpScreen(
      tester,
      const SearchScreen(),
      db: testDb(),
      overrides: [
        ...withSource(),
        searchProvider.overrideWith((ref, q) async {
          searched = true;
          return results;
        }),
      ],
    );
    const magnet = 'magnet:?xt=urn:btih:0123456789abcdef&dn=Night+Train';
    await tester.enterText(find.byType(TextField), magnet);
    await tester.pump(SearchScreen.debounce);
    await tester.pumpAndSettle();
    expect(find.text('Play this link'), findsOneWidget);
    expect(find.text('Night Train'), findsOneWidget);
    expect(searched, isFalse);

    await tester.tap(find.text('Play this link'));
    await tester.pumpAndSettle();
    final played = nav.played.last;
    expect(played.type, 'movie');
    expect(played.videoId, magnet);
    expect(played.mediaId, magnet);
    expect(played.title, 'Night Train');
  });

  testScreen('says when nothing matches', (tester) async {
    await pumpScreen(
      tester,
      const SearchScreen(),
      db: testDb(),
      overrides: [
        ...withSource(),
        searchProvider.overrideWith((ref, q) async => []),
      ],
    );
    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pump(SearchScreen.debounce);
    await tester.pumpAndSettle();
    expect(find.text('No matches'), findsOneWidget);
    expect(find.textContaining('“zzzz”'), findsOneWidget);
  });

  testScreen('invites adding a source before searching', (tester) async {
    final nav = await pumpScreen(
      tester,
      const SearchScreen(),
      db: testDb(),
      overrides: [enabledAddonsProvider.overrideWith((ref) async => [])],
    );
    await tester.enterText(find.byType(TextField), 'harbor');
    await tester.pump(SearchScreen.debounce);
    await tester.pumpAndSettle();
    expect(
      find.text('Add a source to search movies and shows.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Add a source'));
    await tester.pumpAndSettle();
    expect(nav.locations.last, '/settings/sources');
  });

  testScreen('fits at 1.5x text size', (tester) async {
    await pumpScreen(
      tester,
      const SearchScreen(),
      db: testDb(),
      textScale: 1.5,
      overrides: [
        ...withSource(),
        searchProvider.overrideWith((ref, q) async => results),
      ],
    );
    await tester.enterText(find.byType(TextField), 'harbor');
    await tester.pump(SearchScreen.debounce);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
