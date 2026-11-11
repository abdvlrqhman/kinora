import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinora/core/db/database.dart';
import 'package:kinora/features/downloads/downloads_screen.dart';
import 'package:kinora/features/downloads/storage.dart';

import '../settings/settings_harness.dart';

/// A movie, plus a show with two seasons in every state.
Future<String> seed(AppDatabase db) async {
  final file = File('${Directory.systemTemp.createTempSync().path}/ember.mkv')
    ..writeAsBytesSync([0]);
  addTearDown(() => file.parent.deleteSync(recursive: true));
  await addDownload(
    db,
    id: 'm1',
    mediaId: 'tt100',
    type: 'movie',
    title: 'Ember',
    season: null,
    total: 1610612736,
    done: 1610612736,
    filePath: file.path,
    subtitles: '[{"lang":"ar","path":"/x.ar.srt","label":"x"}]',
    at: DateTime(2026, 11, 2),
  );
  await addDownload(
    db,
    id: 'e1',
    episode: 1,
    episodeTitle: 'Low Tide',
    subtitles:
        '[{"lang":"ar","path":"/a","label":"a"},'
        '{"lang":"en","path":"/b","label":"b"}]',
  );
  await addDownload(
    db,
    id: 'e2',
    episode: 2,
    episodeTitle: 'The Keeper',
    state: 'downloading',
    done: 966367642,
  );
  await addDownload(
    db,
    id: 'e3',
    episode: 3,
    episodeTitle: 'Salt and Iron',
    state: 'paused',
    done: 0,
    error: 'Waiting for Wi-Fi',
  );
  await addDownload(
    db,
    id: 'e4',
    season: 2,
    episode: 1,
    episodeTitle: 'North Wind',
    state: 'failed',
    done: 0,
    error: 'No one is sharing this version right now.',
  );
  return file.path;
}

void main() {
  test('free space comes from the OS', () {
    final free = freeBytes(Directory.systemTemp.path);
    expect(free, isNotNull);
    expect(free, greaterThan(0));
  });

  test('groups by title and sorts episodes', () {
    DownloadRow row(String id, int? s, int? e, {String media = 'tt200'}) =>
        DownloadRow(
          id: id,
          mediaId: media,
          videoId: '$media:$s:$e',
          type: s == null ? 'movie' : 'series',
          title: media,
          season: s,
          episode: e,
          releaseName: 'r',
          kind: 'torrent',
          directory: '/',
          totalBytes: 10,
          doneBytes: 4,
          state: 'downloading',
          subtitlesJson: '[]',
          createdAt: DateTime(2026),
        );
    final groups = groupDownloads([
      row('a', 2, 1),
      row('m', null, null, media: 'tt1'),
      row('b', 1, 2),
      row('c', 1, 1),
    ]);
    expect(groups.map((g) => g.first.mediaId), ['tt200', 'tt1']);
    expect(groups.first.rows.map((r) => r.id), ['c', 'b', 'a']);
    expect(groups.first.seasons.keys, [1, 2]);
    expect(groups.first.isShow, isTrue);
    expect(groups.last.isShow, isFalse);
    expect(downloadStatus(row('x', 1, 1)).strong, 'Downloading 40%');
    // While it moves: the speed, then the time left.
    expect(
      downloadStatus(row('x', 1, 1), rate: (2 << 20).toDouble()).soft,
      allOf(contains('2 MB/s'), contains('left')),
    );
  });

  kitTest('invites the next step when empty', (tester) async {
    final kit = await pumpKit(tester, location: '/downloads');
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Downloads you start, and episodes you stream to the end, appear here.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Find something to watch'));
    await tester.pumpAndSettle();
    expect(kit.nav.locations, ['/search']);
  });

  kitTest('shows titles, live states and plays offline', (tester) async {
    final db = kitDb();
    final path = await seed(db);
    final kit = await pumpKit(
      tester,
      db: db,
      location: '/downloads',
      size: const Size(390, 1400),
    );
    await tester.pumpAndSettle();

    // Storage summary.
    expect(
      find.textContaining('4.4 GB used', findRichText: true),
      findsOne,
    ); // 1.5 + 2 + 0.9
    expect(find.textContaining('64 GB free', findRichText: true), findsOne);

    // A movie is one row; it plays its file offline.
    expect(find.bySemanticsLabel(RegExp('^Ember. Downloaded')), findsOne);
    expect(find.text('Subtitles in Arabic'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel(RegExp('^Ember. ')));
    await tester.pumpAndSettle();
    expect(kit.nav.played.single.localFile, path);
    expect(kit.nav.played.single.videoId, 'tt100');
    Navigator.of(tester.element(find.text('player'))).pop();
    await tester.pumpAndSettle();

    // A show expands into seasons and episodes.
    expect(find.textContaining('Low Tide', findRichText: true), findsNothing);
    await tester.tap(find.bySemanticsLabel(RegExp(r'^Harbor Lights\. ')));
    await tester.pumpAndSettle();
    expect(find.text('Season 1'), findsOneWidget);
    expect(find.text('Season 2'), findsOneWidget);
    expect(find.text('Downloaded'), findsNWidgets(2));
    expect(find.text('Subtitles in Arabic, English'), findsOneWidget);
    expect(find.text('Downloading 45%'), findsOneWidget);
    expect(find.text('922 MB of 2 GB'), findsOneWidget);
    expect(find.text('Waiting for Wi-Fi'), findsOneWidget);
    expect(find.text('Couldn’t download'), findsOneWidget);
    expect(
      find.text('No one is sharing this version right now.'),
      findsOneWidget,
    );

    // Pause from the row's control; live update from the database.
    await tester.tap(
      find.bySemanticsLabel('Pause, Harbor Lights, season 1 episode 2'),
    );
    await tester.pumpAndSettle();
    expect(kit.actions.calls.last, 'pause e2');
    expect(find.text('Paused at 45%'), findsOneWidget);
    await tester.tap(
      find.bySemanticsLabel('Try again, Harbor Lights, season 2 episode 1'),
    );
    await tester.pumpAndSettle();
    expect(kit.actions.calls.last, 'resume e4');

    // A file that vanished says so instead of failing in the player.
    await tester.tap(find.textContaining('Low Tide', findRichText: true));
    await tester.pumpAndSettle();
    expect(find.textContaining('no longer on your phone'), findsOneWidget);
  });

  kitTest('deletes an episode, a season and a show after asking', (
    tester,
  ) async {
    final db = kitDb();
    await seed(db);
    final kit = await pumpKit(
      tester,
      db: db,
      location: '/downloads',
      size: const Size(390, 1600),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel(RegExp(r'^Harbor Lights\. ')));
    await tester.pumpAndSettle();

    // One episode, from its options.
    await tester.longPress(find.textContaining('Low Tide', findRichText: true));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Delete download'));
    await tester.pumpAndSettle();
    expect(find.text('Delete Harbor Lights S1 E1?'), findsOneWidget);
    expect(find.textContaining('Frees 2 GB'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Delete'));
    await tester.pumpAndSettle();
    expect(kit.actions.calls, ['remove e1']);
    expect(find.textContaining('Low Tide', findRichText: true), findsNothing);

    // Cancel keeps everything.
    await tester.tap(find.bySemanticsLabel('Delete Season 2 of Harbor Lights'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Cancel'));
    await tester.pumpAndSettle();
    expect(kit.actions.calls, ['remove e1']);

    await tester.tap(find.bySemanticsLabel('Delete Season 2 of Harbor Lights'));
    await tester.pumpAndSettle();
    expect(find.text('Delete season 2 of Harbor Lights?'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Delete'));
    await tester.pumpAndSettle();
    expect(kit.actions.calls.last, 'remove e4');
    expect(find.text('Season 2'), findsNothing);

    // The whole show: from its long-press, not an inline row.
    expect(find.text('Delete show'), findsNothing);
    await tester.longPress(find.bySemanticsLabel(RegExp(r'^Harbor Lights\. ')));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Delete'));
    await tester.pumpAndSettle();
    expect(kit.actions.calls.sublist(2), ['remove e2', 'remove e3']);
    expect(find.bySemanticsLabel(RegExp(r'^Harbor Lights\. ')), findsNothing);
    expect(find.bySemanticsLabel(RegExp('^Ember. ')), findsOne);
  });

  kitTest('fits at 1.5x text', (tester) async {
    final db = kitDb();
    await seed(db);
    await pumpKit(
      tester,
      db: db,
      location: '/downloads',
      textScale: 1.5,
      freeSpace: null,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel(RegExp(r'^Harbor Lights\. ')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.fling(
      find.byType(Scrollable).first,
      const Offset(0, -3000),
      3000,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  test('time left comes from the measured speed', () {
    expect(etaLabel(1 << 30, null), isNull);
    expect(etaLabel(1 << 30, (3 << 20).toDouble()), 'about 6 min left');
    expect(etaLabel(1 << 20, (1 << 20).toDouble()), 'less than a minute left');
    expect(etaLabel(10 << 30, (1 << 20).toDouble()), 'about 2h 51m left');
  });

  kitTest('a row waiting for Wi-Fi asks before using mobile data', (
    tester,
  ) async {
    final db = kitDb();
    await seed(db);
    final kit = await pumpKit(
      tester,
      db: db,
      location: '/downloads',
      size: const Size(390, 1400),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel(RegExp(r'^Harbor Lights\. ')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Salt and Iron', findRichText: true));
    await tester.pumpAndSettle();
    expect(find.text('Wait for Wi-Fi'), findsOneWidget);
    await tester.tap(find.text('Download on mobile data (2 GB)'));
    await tester.pumpAndSettle();
    expect(kit.actions.calls.last, 'resume e3');
  });
}
