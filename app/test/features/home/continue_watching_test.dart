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
}
