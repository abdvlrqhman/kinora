import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kinora/app/providers.dart';
import 'package:kinora/core/db/database.dart';
import 'package:kinora/core/secure_keys.dart';
import 'package:kinora/features/trakt/history_screen.dart';
import 'package:kinora/features/trakt/lists_screen.dart';
import 'package:kinora/services/sources.dart';
import 'package:kinora/services/trakt.dart';
import 'package:stremio/stremio.dart';

import '../../services/fake_trakt.dart';

import 'package:kinora/ui/widgets/sheet.dart';

import '../harness.dart';
import '../settings/settings_harness.dart' show FakeSecureStorage;

const dark = MetaPreview(id: 'tt5753856', type: 'series', name: 'Dark');

void main() {
  late FakeTrakt trakt;
  late AppDatabase db;

  List<Override> signedIn() => [
    httpClientProvider.overrideWithValue(trakt.client),
    secureKeysProvider.overrideWithValue(SecureKeys(FakeSecureStorage())),
    traktConfigProvider.overrideWithValue(
      const TraktConfig(clientId: 'kinora', api: 'https://trakt.test'),
    ),
    metaProvider.overrideWith((ref, key) async => throw StateError('off')),
  ];

  /// Signs the screen's own Trakt in (through the fake), then settles.
  Future<void> signIn(WidgetTester tester) async {
    final element = tester.element(find.byType(Scaffold).first);
    final sync = ProviderScope.containerOf(element).read(traktSyncProvider);
    await tester.runAsync(() async {
      await sync.finishSignIn(await sync.startSignIn());
    });
    await tester.pumpAndSettle();
  }

  setUp(() {
    trakt = FakeTrakt()..pendingPolls = 0;
    db = testDb();
  });

  testScreen('your lists: rows, and a new one made from the sheet', (
    tester,
  ) async {
    trakt.lists[1] = (
      name: 'Anime',
      privacy: 'private',
      items: [('show', 'tt5753856'), ('movie', 'tt0113277')],
    );
    await pumpScreen(
      tester,
      const ListsScreen(),
      db: db,
      overrides: signedIn(),
    );
    await signIn(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ListsScreen)),
    );
    container.invalidate(myListsProvider);
    await tester.runAsync(() => container.read(myListsProvider.future));
    await tester.pumpAndSettle();
    expect(find.text('Anime'), findsOneWidget);
    expect(find.text('2 titles, Only you'), findsOneWidget);

    await tester.tap(find.text('New list'));
    await tester.pumpAndSettle();
    // Nameless: says what's missing.
    await tester.tap(find.text('Make list'));
    await tester.pumpAndSettle();
    expect(find.text('Give the list a name.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Weekend');
    await tester.tap(find.text('Everyone'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Make list'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.runAsync(() => container.read(myListsProvider.future));
    await tester.pumpAndSettle();
    expect(trakt.lists.values.map((l) => (l.name, l.privacy)), [
      ('Anime', 'private'),
      ('Weekend', 'public'),
    ]);
    expect(find.text('0 titles, Everyone'), findsOneWidget);
  });

  testScreen('a list: its titles, and deleting it asks first, by name', (
    tester,
  ) async {
    trakt.lists[7] = (
      name: 'Heists',
      privacy: 'friends',
      items: [('movie', 'tt0113277')],
    );
    final nav = await pumpScreen(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => context.push('/lists/7?name=Heists'),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      db: db,
      overrides: signedIn(),
      routes: [
        GoRoute(
          path: '/lists/:id',
          builder: (_, s) => ListScreen(
            id: int.parse(s.pathParameters['id']!),
            name: s.uri.queryParameters['name']!,
          ),
        ),
      ],
    );
    await signIn(tester);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Heists'), findsWidgets);
    expect(find.text('T tt0113277'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete “Heists”?'), findsOneWidget);
    expect(find.textContaining('and its 1 title'), findsOneWidget);
    await tester.tap(find.text('Delete list'));
    await tester.pumpAndSettle();
    expect(trakt.lists, isEmpty);
    expect(nav.router.state.uri.path, '/');
    expect(find.text('Deleted “Heists”'), findsOneWidget);
  });

  testScreen('Lists on a title: ticks the lists it\'s on, and adds', (
    tester,
  ) async {
    trakt
      ..lists[1] = (name: 'Mind-benders', privacy: 'private', items: [])
      ..lists[2] = (
        name: 'German',
        privacy: 'private',
        items: [('show', 'tt5753856')],
      );
    await pumpScreen(
      tester,
      const Scaffold(
        body: Center(child: ListsAction(meta: dark)),
      ),
      db: db,
      overrides: signedIn(),
    );
    await signIn(tester);
    await tester.tap(find.byIcon(Icons.playlist_add_rounded));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    bool ticked(String name) => tester
        .widget<SheetAction>(find.widgetWithText(SheetAction, name))
        .selected;
    expect(ticked('German'), isTrue);
    expect(ticked('Mind-benders'), isFalse);

    await tester.runAsync(() async {
      await tester.tap(find.text('Mind-benders'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(ticked('Mind-benders'), isTrue);
    expect(trakt.lists[1]!.items, [('show', 'tt5753856')]);
  });

  testScreen('Watched: by day, and marking one unwatched asks first', (
    tester,
  ) async {
    final now = DateTime.now();
    for (final (id, s, e, at) in [
      ('tt5753856:1:3', 1, 3, now),
      ('tt5753856:1:2', 1, 2, now.subtract(const Duration(days: 1))),
    ]) {
      await db
          .into(db.watchProgress)
          .insert(
            WatchProgressCompanion.insert(
              videoId: id,
              mediaId: 'tt5753856',
              type: 'series',
              name: 'Dark',
              season: Value(s),
              episode: Value(e),
              positionMs: 100,
              durationMs: 100,
              completed: const Value(true),
              updatedAt: Value(at),
            ),
          );
    }
    await pumpScreen(tester, const HistoryScreen(), db: db);
    await tester.pumpAndSettle();
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    // Signed out: no Trakt numbers, history all the same.
    expect(find.textContaining('hours'), findsNothing);

    await tester.tap(find.byTooltip('More for Dark, S1 E3'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark as unwatched'));
    await tester.pumpAndSettle();
    expect(find.text('Mark Dark, S1 E3 as unwatched?'), findsOneWidget);
    await tester.tap(find.text('Mark as unwatched'));
    await tester.pumpAndSettle();
    expect(find.text('Today'), findsNothing);
    expect(find.text('Marked Dark, S1 E3 as unwatched'), findsOneWidget);
    final left = await tester.runAsync(() => db.select(db.watchProgress).get());
    expect(left!.map((r) => r.videoId), ['tt5753856:1:2']);
  });

  testScreen('Watched, signed in: this year\'s hours, top show, genres', (
    tester,
  ) async {
    trakt
      ..stats = {
        'movies': {'watched': 4, 'minutes': 480},
        'episodes': {'watched': 60, 'minutes': 2700},
        'shows': {'watched': 3},
      }
      ..history = [
        for (var i = 0; i < 6; i++)
          {
            'id': i,
            'type': 'episode',
            'episode': {'runtime': 60},
            'show': {
              'title': 'Dark',
              'genres': ['science-fiction'],
              'ids': {'imdb': 'tt5753856'},
            },
          },
      ];
    await pumpScreen(
      tester,
      const HistoryScreen(),
      db: db,
      overrides: signedIn(),
    );
    await signIn(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HistoryScreen)),
    );
    await tester.runAsync(() => container.read(traktStatsProvider.future));
    await tester.pumpAndSettle();
    expect(find.text('6 hours'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('6 episodes'), findsOneWidget);
    expect(find.text('Science fiction'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(find.textContaining('In all: 53 hours'), findsOneWidget);
  });
}
