import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinora/core/db/database.dart';
import 'package:kinora/data/repositories.dart';

void main() {
  test('one download per video is enforced', () async {
    final db = AppDatabase.forExecutor(NativeDatabase.memory());
    addTearDown(db.close);
    DownloadsCompanion row(String id) => DownloadsCompanion.insert(
      id: id,
      mediaId: 'tt1',
      videoId: 'tt1:1:1',
      type: 'series',
      title: 'Show',
      releaseName: 'x',
      kind: 'torrent',
      directory: '/tmp',
      state: 'queued',
    );
    await db.into(db.downloads).insert(row('a'));
    await expectLater(
      db.into(db.downloads).insert(row('b')),
      throwsA(isA<SqliteException>()),
    );
  });

  test(
    'dismissing hides from Continue watching but keeps watched marks',
    () async {
      final db = AppDatabase.forExecutor(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = ProgressRepository(db);
      Future<void> save(String id, int pos) => repo.save(
        videoId: id,
        mediaId: 'tt1',
        type: 'series',
        name: 'Show',
        position: Duration(minutes: pos),
        duration: const Duration(minutes: 40),
      );
      await save('tt1:1:1', 40); // watched
      await save('tt1:1:2', 10); // in progress
      expect(await repo.watchContinue().first, hasLength(1));
      await repo.dismiss('tt1');
      expect(await repo.watchContinue().first, isEmpty);
      expect((await repo.get('tt1:1:1'))!.completed, isTrue);
      await save('tt1:1:2', 12); // watching again
      expect(await repo.watchContinue().first, hasLength(1));
    },
  );
}
