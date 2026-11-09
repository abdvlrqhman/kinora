import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinora/app/providers.dart';
import 'package:kinora/core/db/database.dart';
import 'package:kinora/features/home/home_feed.dart';
import 'package:kinora/services/sources.dart';

import '../harness.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer c;
  setUp(() {
    db = testDb();
    c = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        metaProvider.overrideWith((ref, key) async => seriesMeta()),
      ],
    );
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });

  Future<List<WatchProgressData>> items() async {
    final sub = c.listen(continueItemsProvider, (_, _) {});
    addTearDown(sub.close);
    return c.read(continueItemsProvider.future);
  }

  Future<void> episode(int s, int e, int day, {bool done = false}) =>
      saveProgress(
        db,
        videoId: 'tt200:$s:$e',
        mediaId: 'tt200',
        season: s,
        episode: e,
        positionMs: done ? 3000000 : 1500000,
        completed: done,
        at: DateTime(2026, 11, day),
      );

  test(
    'after a finished episode comes the next, not an older half-watched one',
    () async {
      await episode(1, 1, 1);
      await episode(1, 2, 2, done: true);
      final list = await items();
      expect(list, hasLength(1));
      expect(list.single.videoId, 'tt200:1:3');
      expect(list.single.episodeTitle, 'Salt and Iron');
      expect(list.single.positionMs, 0, reason: 'from the start');
    },
  );

  test('the newest half-watched episode resumes', () async {
    await episode(1, 2, 1, done: true);
    await episode(1, 3, 2);
    final list = await items();
    expect(list.single.videoId, 'tt200:1:3');
    expect(list.single.positionMs, 1500000);
  });

  test('nothing after the last episode, nor after a finished movie', () async {
    await episode(3, 2, 1, done: true);
    await saveProgress(
      db,
      videoId: 'tt100',
      mediaId: 'tt100',
      type: 'movie',
      name: 'The Long Light',
      positionMs: 3000000,
      completed: true,
      at: DateTime(2026, 11, 2),
    );
    expect(await items(), isEmpty);
  });

  test(
    'after a finished special comes the first episode not watched',
    () async {
      await episode(1, 1, 1, done: true);
      await episode(1, 2, 2, done: true);
      await episode(0, 1, 3, done: true);
      expect((await items()).single.videoId, 'tt200:1:3');
    },
  );

  test(
    'a finished episode without a season still counts as an episode',
    () async {
      await saveProgress(
        db,
        videoId: 'tt200:1:2',
        mediaId: 'tt200',
        positionMs: 3000000,
        completed: true,
        at: DateTime(2026, 11, 2),
      );
      expect((await items()).single.videoId, 'tt200:1:3');
    },
  );

  test('shows watched to the end don’t crowd out a half-watched one', () async {
    for (var i = 0; i < 25; i++) {
      await saveProgress(
        db,
        videoId: 'tt9$i:3:2',
        mediaId: 'tt9$i',
        season: 3,
        episode: 2,
        positionMs: 3000000,
        completed: true,
        at: DateTime(2026, 11, 2, 0, i),
      );
    }
    await episode(1, 1, 1);
    expect((await items()).single.videoId, 'tt200:1:1');
  });

  test('offline: the next episode downloaded on the phone', () async {
    final offline = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        metaProvider.overrideWith(
          (ref, key) async => throw Exception('offline'),
        ),
      ],
    );
    addTearDown(offline.dispose);
    await episode(1, 2, 2, done: true);
    for (final e in [4, 3]) {
      await db
          .into(db.downloads)
          .insert(
            DownloadsCompanion.insert(
              id: 'd$e',
              mediaId: 'tt200',
              videoId: 'tt200:1:$e',
              type: 'series',
              title: 'Harbor Lights',
              season: const Value(1),
              episode: Value(e),
              releaseName: 'Harbor.Lights.S01E0$e',
              kind: 'torrent',
              directory: '/tmp/k',
              state: 'completed',
            ),
          );
    }
    final sub = offline.listen(continueItemsProvider, (_, _) {});
    addTearDown(sub.close);
    final list = await offline.read(continueItemsProvider.future);
    expect(list.single.videoId, 'tt200:1:3');
  });
}
