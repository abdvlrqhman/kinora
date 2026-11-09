import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinora/core/db/database.dart';
import 'package:kinora/features/title/episodes.dart';
import 'package:kinora/features/title/title_model.dart';
import 'package:kinora/features/title/title_screen.dart';
import 'package:kinora/services/downloads.dart';
import 'package:kinora/services/play_request.dart';
import 'package:kinora/services/resolver.dart';
import 'package:kinora/services/sources.dart';
import 'package:kinora/ui/glass.dart';

import '../harness.dart';

void main() {
  final series = seriesMeta();
  final movie = movieMeta();
  final day = DateTime(2026, 10);

  Future<Nav> pumpTitle(
    WidgetTester tester,
    AppDatabase db, {
    bool isMovie = false,
    double textScale = 1,
    List<ResolvedRelease> releases = fakeReleases,
    String? message,
  }) async {
    final nav = await pumpScreen(
      tester,
      TitleScreen(
        type: isMovie ? 'movie' : 'series',
        id: isMovie ? 'tt100' : 'tt200',
      ),
      db: db,
      textScale: textScale,
      size: const Size(390, 1400),
      overrides: [
        ...withSource(),
        metaProvider.overrideWith((ref, key) async => isMovie ? movie : series),
        resolveWith(releases, message: message),
      ],
    );
    await tester.pumpAndSettle();
    return nav;
  }

  String playLabel(WidgetTester tester) =>
      tester.widget<GlassButton>(find.byKey(const ValueKey('play'))).label;

  group('movie', () {
    testScreen('plays and names the version it will use', (tester) async {
      final nav = await pumpTitle(tester, testDb(), isMovie: true);
      // The backdrop's title, and the header strip's (shown once scrolled).
      expect(find.text('The Long Light'), findsNWidgets(2));
      expect(find.text('2h 10m'), findsOneWidget);
      expect(find.text('Drama, Mystery'), findsOneWidget);
      expect(find.textContaining('1080p WEB-DL, 214 seeds'), findsOneWidget);
      expect(find.textContaining('Arabic subtitles match'), findsOneWidget);
      expect(playLabel(tester), 'Play');

      await tester.tap(find.byKey(const ValueKey('play')));
      await tester.pumpAndSettle();
      final req = nav.played.last;
      expect(req.type, 'movie');
      expect(req.videoId, 'tt100');
      expect(req.title, 'The Long Light');
      expect(req.startAt, isNull);
    });

    testScreen('resumes a half-watched movie', (tester) async {
      final db = testDb();
      await saveProgress(
        db,
        videoId: 'tt100',
        mediaId: 'tt100',
        type: 'movie',
        name: 'The Long Light',
        positionMs: 600000,
        at: day,
      );
      final nav = await pumpTitle(tester, db, isMovie: true);
      expect(playLabel(tester), 'Resume');
      await tester.tap(find.byKey(const ValueKey('play')));
      await tester.pumpAndSettle();
      expect(nav.played.last.startAt, const Duration(minutes: 10));
    });

    testScreen('says calmly when no version is found', (tester) async {
      await pumpTitle(
        tester,
        testDb(),
        isMovie: true,
        releases: const [],
        message: 'Add a source to find versions.',
      );
      expect(find.text('Add a source to find versions.'), findsOneWidget);
    });
  });

  group('series', () {
    testScreen('starts at S1 E1 with no progress', (tester) async {
      await pumpTitle(tester, testDb());
      expect(playLabel(tester), 'Play S1 E1');
      expect(find.text('3 seasons'), findsOneWidget);
    });

    testScreen('resumes the episode in progress', (tester) async {
      final db = testDb();
      await saveProgress(
        db,
        videoId: 'tt200:1:1',
        mediaId: 'tt200',
        season: 1,
        episode: 1,
        positionMs: 3000000,
        completed: true,
        at: day,
      );
      await saveProgress(
        db,
        videoId: 'tt200:1:3',
        mediaId: 'tt200',
        season: 1,
        episode: 3,
        positionMs: 900000,
        at: day.add(const Duration(days: 1)),
      );
      final nav = await pumpTitle(tester, db);
      expect(playLabel(tester), 'Resume S1 E3');
      await tester.tap(find.byKey(const ValueKey('play')));
      await tester.pumpAndSettle();
      final req = nav.played.last;
      expect(req.videoId, 'tt200:1:3');
      expect(req.season, 1);
      expect(req.episode, 3);
      expect(req.episodeTitle, 'Salt and Iron');
      expect(req.startAt, const Duration(minutes: 15));
    });

    testScreen('moves on to the next season after a finale', (tester) async {
      final db = testDb();
      await saveProgress(
        db,
        videoId: 'tt200:1:4',
        mediaId: 'tt200',
        season: 1,
        episode: 4,
        positionMs: 3000000,
        completed: true,
        at: day,
      );
      await pumpTitle(tester, db);
      expect(playLabel(tester), 'Play S2 E1');
      // The picker follows the next episode's season.
      expect(find.textContaining('North Wind'), findsOneWidget);
    });

    testScreen(
      'switches seasons, dates unaired episodes, lists specials last',
      (tester) async {
        final nav = await pumpTitle(tester, testDb());
        expect(find.textContaining('Low Tide'), findsOneWidget);
        expect(find.bySemanticsLabel('Season 1'), findsOneWidget);

        await tester.tap(find.bySemanticsLabel('Season 2'));
        await tester.pumpAndSettle();
        expect(find.textContaining('North Wind'), findsOneWidget);
        expect(find.textContaining('Low Tide'), findsNothing);
        // Unaired: full contrast, says when it airs, and doesn't play.
        expect(find.textContaining('Airs '), findsOneWidget);
        expect(
          find.ancestor(
            of: find.textContaining('Open Water'),
            matching: find.byType(Opacity),
          ),
          findsNothing,
        );

        // Past the end of the picker's row (it shares it with the ⋯ menu).
        await tester.ensureVisible(find.text('Specials'));
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsLabel('Specials'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Behind the lights'), findsOneWidget);

        // Tapping an episode plays it.
        await tester.drag(find.byType(SeasonPicker), const Offset(400, 0));
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsLabel('Season 1'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.bySemanticsLabel(RegExp('^Episode 2, The Keeper')),
        );
        await tester.pumpAndSettle();
        expect(nav.played.last.videoId, 'tt200:1:2');
      },
    );

    testScreen('marks watched and downloaded episodes', (tester) async {
      final db = testDb();
      await saveProgress(
        db,
        videoId: 'tt200:1:1',
        mediaId: 'tt200',
        season: 1,
        episode: 1,
        positionMs: 3000000,
        completed: true,
        at: day,
      );
      await db
          .into(db.downloads)
          .insert(
            DownloadsCompanion.insert(
              id: 'd1',
              mediaId: 'tt200',
              videoId: 'tt200:1:2',
              type: 'series',
              title: 'Harbor Lights',
              releaseName: 'x',
              kind: 'torrent',
              directory: '/tmp',
              state: 'completed',
              filePath: const Value('/tmp/x.mkv'),
            ),
          );
      await pumpTitle(tester, db);
      expect(
        find.bySemanticsLabel(RegExp(r'^Episode 1, Low Tide.*Watched')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'^Episode 2, The Keeper.*Downloaded')),
        findsOneWidget,
      );
      // Next up is E2: the Download action says Downloaded; the row's
      // trailing icon alone marks it.
      expect(find.text('Downloaded'), findsOneWidget);
      expect(find.byIcon(Icons.download_done_rounded), findsNWidgets(2));
    });

    testScreen('picks another version from the sheet', (tester) async {
      final nav = await pumpTitle(tester, testDb());
      await tester.tap(find.bySemanticsLabel('Choose another version'));
      await tester.pumpAndSettle();

      // Quality and source only; seeds sit in the facts, and Instant is the
      // one word for cached.
      expect(find.text('4K Dolby Vision WEB'), findsOneWidget);
      expect(find.text('720p HDTV'), findsOneWidget);
      expect(find.text('41 seeds'), findsOneWidget);
      expect(find.text('Instant'), findsWidgets);
      expect(find.text('Starts instantly'), findsNothing);
      expect(find.text('Best'), findsOneWidget);
      expect(find.textContaining('Few seeds'), findsOneWidget);
      expect(find.text('2 GB'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('4K, 1 versions'));
      await tester.pumpAndSettle();
      expect(find.text('720p HDTV'), findsNothing);

      await tester.tap(find.bySemanticsLabel(RegExp('^4K Dolby Vision')));
      await tester.pumpAndSettle();
      expect(nav.played.last.candidateId, 'c2');
      expect(nav.played.last.videoId, 'tt200:1:1');
    });

    testScreen('fits at 1.5x text size, sheet included', (tester) async {
      await pumpTitle(tester, testDb(), textScale: 1.5);
      expect(tester.takeException(), isNull);
      await tester.tap(find.bySemanticsLabel('Choose another version'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('nextUp', () {
    final model = TitleModel(series);
    final now = DateTime.now();

    WatchProgressData p(String id, {bool done = true, int days = 0}) =>
        WatchProgressData(
          videoId: id,
          mediaId: 'tt200',
          type: 'series',
          name: 'Harbor Lights',
          positionMs: done ? 3000000 : 60000,
          durationMs: 3000000,
          completed: done,
          dismissed: false,
          updatedAt: day.add(Duration(days: days)),
        );

    test('skips episodes already watched', () {
      final next = nextUp(model, {
        'tt200:1:1': p('tt200:1:1', days: 2),
        'tt200:1:2': p('tt200:1:2'),
      }, now);
      expect(next.label, 'Play S1 E3');
    });

    test('skips unaired episodes and starts over when caught up', () {
      final next = nextUp(model, {
        'tt200:2:2': p('tt200:2:2', days: 1),
        'tt200:3:1': p('tt200:3:1'),
        'tt200:3:2': p('tt200:3:2'),
      }, now);
      expect(next.label, 'Play S1 E1');
    });

    test('a watched special does not hijack the order', () {
      final next = nextUp(model, {'tt200:0:1': p('tt200:0:1')}, now);
      expect(next.label, 'Play S1 E1');
    });

    test('seasons run 1, 2, 3, then specials', () {
      expect(model.seasons, [1, 2, 3, 0]);
    });
  });

  testScreen('downloads a chosen version, or the whole season', (tester) async {
    final actions = _Downloads();
    final db = testDb();
    await pumpScreen(
      tester,
      const TitleScreen(type: 'series', id: 'tt200'),
      db: db,
      size: const Size(390, 1400),
      overrides: [
        ...withSource(),
        metaProvider.overrideWith((ref, key) async => series),
        resolveWith(fakeReleases),
        downloadActionsProvider.overrideWithValue(actions),
      ],
    );
    await tester.pumpAndSettle();
    // "Versions" on screen; the full phrase for screen readers.
    expect(find.text('Versions'), findsOneWidget);
    expect(find.text('Download E1'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Choose another version'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Download this version, 720p HDTV'));
    await tester.pumpAndSettle();
    expect(actions.requests.single.candidateId, 'c3');
    expect(find.text('Added to Downloads.'), findsOneWidget);

    await tester.ensureVisible(find.bySemanticsLabel('More for Season 1'));
    await tester.tap(find.bySemanticsLabel('More for Season 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download season 1'));
    await tester.pumpAndSettle();
    expect(
      [for (final r in actions.requests.skip(1)) r.videoId],
      ['tt200:1:1', 'tt200:1:2', 'tt200:1:3', 'tt200:1:4'],
    );
  });
}

final class _Downloads implements DownloadActions {
  final requests = <PlayRequest>[];

  @override
  Future<void> download(PlayRequest request) async => requests.add(request);
  @override
  Future<void> pause(String downloadId) async {}
  @override
  Future<void> resume(String downloadId) async {}
  @override
  Future<void> remove(String downloadId) async {}
}
