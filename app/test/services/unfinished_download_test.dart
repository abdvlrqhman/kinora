import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:kinora/core/db/database.dart';
import 'package:kinora/services/downloads.dart';

import '../features/harness.dart';

void main() {
  final hash = 'ab' * 20;
  test('an episode still downloading is found by its torrent', () async {
    final db = testDb();
    addTearDown(db.close);
    Future<void> row(String id, String state, {String? ih = ''}) => db
        .into(db.downloads)
        .insert(
          DownloadsCompanion.insert(
            id: id,
            mediaId: 'tt200',
            videoId: 'tt200:4:$id',
            type: 'series',
            title: 'Lupin',
            releaseName: 'Lupin.S04E0$id.1080p',
            kind: 'torrent',
            infoHash: Value(ih == '' ? hash : ih),
            fileIndex: const Value(2),
            directory: '/tmp/k',
            state: state,
          ),
        );
    await row('6', 'downloading');
    await row('7', 'completed');
    await row('8', 'queued', ih: null); // still finding a version
    final six = await unfinishedTorrentDownload(db, 'tt200:4:6');
    expect(six?.infoHash, hash);
    expect(six?.fileIndex, 2);
    expect(await unfinishedTorrentDownload(db, 'tt200:4:7'), isNull);
    expect(await unfinishedTorrentDownload(db, 'tt200:4:8'), isNull);
  });
}
