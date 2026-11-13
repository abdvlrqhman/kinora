// End-to-end: the real app, on a real device/emulator, plays an episode
// from a real torrent swarm (a seeder in this process, found through a
// tracker), with subtitles from a source, switches to the next episode, and
// keeps the fully downloaded stream in Downloads. It also casts to a fake
// Samsung TV that pulls the stream, and plays an explicit download offline.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dlna/testing.dart';
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kinora/app/app.dart';
import 'package:kinora/app/desktop.dart';
import 'package:kinora/app/providers.dart';
import 'package:kinora/app/router.dart';
import 'package:kinora/core/db/database.dart';
import 'package:kinora/core/paths.dart';
import 'package:kinora/core/settings.dart';
import 'package:kinora/features/player/player_controller.dart';
import 'package:kinora/features/player/player_screen.dart';
import 'package:kinora/main.dart';
import 'package:kinora/services/cast_service.dart';
import 'package:kinora/services/downloads.dart';
import 'package:kinora/services/engine_service.dart';
import 'package:kinora/services/play_request.dart';
import 'package:kinora/services/playback.dart';
import 'package:kinora/services/resolver.dart';
import 'package:kinora/services/sources.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'support/fake_world.dart';

Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  Duration timeout = const Duration(seconds: 90),
  String? reason,
  String Function()? state,
}) async {
  final end = DateTime.now().add(timeout);
  final started = DateTime.now();
  // ignore: avoid_print
  print('E2E waiting: ${reason ?? 'condition'}');
  while (!done()) {
    if (DateTime.now().isAfter(end)) {
      fail(
        'Timed out: ${reason ?? 'condition'}'
        '${state == null ? '' : '\n${state()}'}',
      );
    }
    await tester.pump(const Duration(milliseconds: 250));
  }
  // ignore: avoid_print
  print(
    'E2E ok: ${reason ?? 'condition'} (${DateTime.now().difference(started).inMilliseconds} ms)',
  );
}

/// A picture of the player for review: printed as base64 chunks (the app
/// is uninstalled after the run, so files on the device are lost). CI puts
/// them back together as the e2e-player-screenshots artifact. Never fails
/// the test.
Future<void> shot(WidgetTester tester, String name) async {
  try {
    await tester.pump(const Duration(milliseconds: 300));
    RenderObject? r = tester.renderObject(find.byType(PlayerScreen));
    while (r != null && r is! RenderRepaintBoundary) {
      r = r.parent;
    }
    final image = await (r! as RenderRepaintBoundary).toImage();
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final data = base64Encode(png!.buffer.asUint8List());
    const size = 2000;
    final n = (data.length / size).ceil();
    for (var i = 0; i < n; i++) {
      final end = (i + 1) * size < data.length ? (i + 1) * size : data.length;
      // ignore: avoid_print
      print('E2E-SHOT $name ${i + 1}/$n ${data.substring(i * size, end)}');
    }
  } on Object catch (e) {
    // ignore: avoid_print
    print('E2E shot $name skipped: $e');
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  testWidgets('stream an episode end to end, subtitles, next episode, keep it', (
    tester,
  ) async {
    final world = await FakeWorld.start();
    addTearDown(world.dispose);

    final paths = AppPaths(
      support: await Directory('${world.root.path}/support').create(),
      downloadsRoot: await Directory('${world.root.path}/docs').create(),
      cache: await Directory('${world.root.path}/cache').create(),
    );
    await paths.ensure();
    final db = AppDatabase.forExecutor(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [
        ...appOverrides(
          paths: paths,
          db: db,
          settings: const AppSettings(
            onboarded: true,
            subtitleLanguages: ['en'],
            wifiOnlyDownloads: false,
            // The test plays this build, whatever GitHub's latest release.
            updateChecks: false,
          ),
        ),
        // Live tracker scraping would reach the internet; the swarm is local.
        onCellularProvider.overrideWith((ref) => Stream.value(false)),
        swarmLookupProvider.overrideWithValue(
          (hashes, extra) async => const {},
        ),
      ],
    );
    addTearDown(container.dispose);

    // A source is added the way a user adds one: by its manifest URL.
    await container.read(addonsProvider.notifier).install(world.manifestUrl);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const KinoraApp()),
    );
    await pumpUntil(
      tester,
      () => find.textContaining('Kinora E2E').evaluate().isNotEmpty,
      reason: 'home row from the source',
    );

    // The best version is found and explained.
    final result = await container.read(
      resolveProvider(
        const VideoRef(
          type: 'series',
          mediaId: FakeWorld.imdb,
          videoId: '${FakeWorld.imdb}:1:1',
          season: 1,
          episode: 1,
        ),
      ).future,
    );
    expect(result.best, isNotNull, reason: result.message);
    expect(result.best!.headline, startsWith('1080p WEB-DL'));

    // Play S1 E1.
    unawaited(
      container
          .read(routerProvider)
          .push(
            '/player',
            extra: const PlayRequest(
              type: 'series',
              mediaId: FakeWorld.imdb,
              videoId: '${FakeWorld.imdb}:1:1',
              title: FakeWorld.show,
              season: 1,
              episode: 1,
              episodeTitle: 'Pilot',
            ),
          ),
    );
    await pumpUntil(
      tester,
      () => PlayerController.debugLast?.phase == PlayerPhase.playing,
      reason: 'player ready',
    );
    final c = PlayerController.debugLast!;
    expect(c.source!.kind, PlaybackKind.torrent);
    await pumpUntil(
      tester,
      () => c.player.state.position > const Duration(seconds: 2),
      reason: 'video plays from the torrent stream',
    );

    // Subtitles from the source show up under English and render.
    await pumpUntil(
      tester,
      () => c.subtitles.any((s) => s.language == 'en' && s.track == null),
      reason: 'external subtitles',
    );
    await c.selectSubtitle(
      c.subtitles.firstWhere((s) => s.language == 'en' && s.track == null),
    );
    await c.player.seek(const Duration(milliseconds: 1200));
    await pumpUntil(
      tester,
      () =>
          c.player.state.subtitle.join(' ').contains('Kinora end-to-end test'),
      reason: 'subtitle line rendered',
    );

    // Cast to the Samsung TV, added by its address the way a user adds
    // one discovery can't see. The TV pulls the video and the subtitles
    // from this phone's stream server over the Wi-Fi address.
    final tv = await FakeSamsungDmr.start(port: 9197, pullOnPlay: true);
    addTearDown(tv.close);
    final cast = container.read(castServiceProvider);
    await cast.addByAddress('127.0.0.1');
    expect(cast.devices, hasLength(1), reason: cast.message);
    final samsung = cast.devices.single;
    expect(samsung.isSamsung, isTrue);
    final tvSub = await c.subtitleForTv();
    expect(tvSub, isNotNull);
    final casting = await cast.cast(
      d: samsung,
      source: c.source!,
      request: c.request,
      startAt: c.player.state.position,
      length: c.player.state.duration,
      subtitlePath: tvSub!.path,
      subtitleLanguage: tvSub.language,
    );
    expect(casting, isTrue, reason: cast.message);
    await pumpUntil(
      tester,
      () => cast.phase == CastPhase.playing,
      timeout: const Duration(seconds: 30),
      reason: 'the TV reports playing',
      state: () => '${cast.phase} ${cast.message}',
    );
    await tv.pulling.timeout(const Duration(seconds: 60));
    expect(tv.pullError, isNull);
    expect(tv.pulled.toBytes(), world.videoBytes);
    expect(tv.pulledHeaders!.value('contentFeatures.dlna.org'), isNotNull);
    expect(tv.pulledCaption, contains('Kinora end-to-end test'));
    // ignore: avoid_print
    print('E2E ok: cast to the TV, which pulled the video and subtitles');
    await cast.stop();
    expect(tv.state, 'STOPPED');
    await c.player.play();

    // Gestures through the real touch pipeline, with the controls hidden and
    // shown (their shade must not swallow touches): a right-half swipe sets
    // the volume, a left-half swipe the brightness, two fingers zoom.
    final semantics = tester.ensureSemantics();
    final screen = tester.getRect(find.byType(PlayerScreen));
    // The 14 s test video always counts as "in the credits", so Up Next
    // would sit on the right half: close it, as Keep watching does.
    // (The screen redraws on the controller's next status tick, each 1 s.)
    c.upNextDismissed = true;
    await tester.pump(const Duration(milliseconds: 1200));
    Future<void> swipe(double x) => tester.timedDragFrom(
      // Between the play row and the scrubber, away from the buttons.
      Offset(screen.left + screen.width * x, screen.top + screen.height * 0.6),
      Offset(0, -screen.height * 0.35),
      const Duration(milliseconds: 700),
    );
    if (isDesktop) {
      // A computer: the keys and the mouse instead of touch.
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: screen.center);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await pumpUntil(
        tester,
        () => find
            .bySemanticsLabel(RegExp(r'^Volume \d+%$'))
            .evaluate()
            .isNotEmpty,
        timeout: const Duration(seconds: 5),
        reason: 'the Down key lowers the volume',
      );
      for (final playing in [false, true]) {
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await pumpUntil(
          tester,
          () => c.player.state.playing == playing,
          timeout: const Duration(seconds: 5),
          reason: 'Space ${playing ? 'plays' : 'pauses'}',
        );
      }
      // The pointer brings the controls back.
      await mouse.moveTo(screen.center + const Offset(12, 12));
      await tester.pump(const Duration(milliseconds: 600));
      await mouse.removePointer();
    }
    for (final round in [
      if (!isDesktop) ...['first', 'after toggling the controls'],
    ]) {
      await swipe(0.8);
      await pumpUntil(
        tester,
        () => find
            .bySemanticsLabel(RegExp(r'^Volume \d+%$'))
            .evaluate()
            .isNotEmpty,
        timeout: const Duration(seconds: 5),
        reason: 'volume swipe ($round)',
        // What a finger at the swipe's start lands on, top first.
        state: () => tester
            .hitTestOnBinding(
              Offset(
                screen.left + screen.width * 0.8,
                screen.top + screen.height * 0.6,
              ),
            )
            .path
            .take(12)
            .map((e) => e.target.runtimeType)
            .join(' < '),
      );
      if (round == 'first') await shot(tester, 'player-volume');
      await swipe(0.2);
      await pumpUntil(
        tester,
        () => find
            .bySemanticsLabel(RegExp(r'^Brightness \d+%$'))
            .evaluate()
            .isNotEmpty,
        timeout: const Duration(seconds: 5),
        reason: 'brightness swipe ($round)',
      );
      await tester.tapAt(screen.center);
      await tester.pump(const Duration(milliseconds: 400));
    }
    double zoom() => tester
        .widget<Transform>(
          find
              .ancestor(
                of: find.byType(Video),
                matching: find.byType(Transform),
              )
              .first,
        )
        .transform
        .getMaxScaleOnAxis();
    expect(zoom(), 1);
    // Above the play row, clear of every control.
    final pinch = Offset(screen.center.dx, screen.top + screen.height * 0.3);
    if (!isDesktop) {
      final f1 = await tester.startGesture(pinch - const Offset(40, 0));
      // (Pointer ids are assigned by the tester: one picked by hand can
      // clash.)
      final f2 = await tester.startGesture(pinch + const Offset(40, 0));
      for (var i = 0; i < 12; i++) {
        await f1.moveBy(const Offset(-8, 0));
        await f2.moveBy(const Offset(8, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await f1.up();
      await f2.up();
      await tester.pump(const Duration(milliseconds: 100));
      expect(zoom(), greaterThan(1.5), reason: 'pinch zooms the picture');
    }
    // The player as it looks, for review: controls up, the Audio and
    // subtitles panel, and Subtitle style inside it.
    try {
      bool controlsUp() =>
          tester
              .widget<AnimatedOpacity>(
                find
                    .ancestor(
                      // (A computer has Full screen in Lock's place.)
                      of: find.bySemanticsLabel(
                        isDesktop ? RegExp('Full screen') : 'Lock controls',
                      ),
                      matching: find.byType(AnimatedOpacity),
                    )
                    .first,
              )
              .opacity ==
          1;
      if (!controlsUp() && !isDesktop) {
        await tester.tapAt(pinch);
        await tester.pump(const Duration(milliseconds: 600));
      }
      await shot(tester, 'player-controls');
      await tester.tap(find.bySemanticsLabel('Audio and subtitles'));
      await tester.pump(const Duration(milliseconds: 600));
      await shot(tester, 'player-tracks');
      // Further down the panel's list: scroll to it first.
      final style = find.text('Subtitle style');
      await tester.scrollUntilVisible(
        style,
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(style);
      await tester.pump(const Duration(milliseconds: 600));
      await shot(tester, 'player-subtitle-style');
      // Close the panel: tap the dimmed video beside it.
      await tester.tapAt(Offset(screen.left + 40, screen.center.dy));
      await tester.pump(const Duration(milliseconds: 600));
    } on Object catch (e) {
      // ignore: avoid_print
      print('E2E shots skipped: $e');
    }
    semantics.dispose();
    // ignore: avoid_print
    print(
      isDesktop
          ? 'E2E ok: volume and pause by keys, controls by the mouse'
          : 'E2E ok: volume, brightness and pinch zoom by touch',
    );

    // Next episode inside the player.
    await pumpUntil(
      tester,
      () => c.nextEpisode != null,
      reason: 'episode list',
    );
    await c.playNext();
    await pumpUntil(
      tester,
      () => c.request.episode == 2 && c.phase == PlayerPhase.playing,
      reason: 'next episode playing',
    );
    // The remembered subtitle language follows to the next episode.
    await pumpUntil(
      tester,
      () => c.activeSubtitleId != null,
      reason: 'subtitle choice remembered',
    );

    // Leaving the player: the fully downloaded stream becomes a download.
    // Keep the downloads stream listened (Riverpod 3 pauses unlistened ones).
    final downloads = container.listen(
      downloadsProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(downloads.close);
    container.read(routerProvider).pop();
    await pumpUntil(
      tester,
      () =>
          container
              .read(downloadsProvider)
              .value
              ?.any((d) => d.state == 'completed') ??
          false,
      reason: 'finished stream kept in Downloads',
    );
    // Both episodes were streamed to the end: both are kept.
    await pumpUntil(
      tester,
      () =>
          (container
                  .read(downloadsProvider)
                  .value
                  ?.where((d) => d.state == 'completed')
                  .length ??
              0) >=
          2,
      reason: 'both episodes kept',
    );
    final kept = container
        .read(downloadsProvider)
        .value!
        .firstWhere((d) => d.state == 'completed');
    expect(File(kept.filePath!).existsSync(), isTrue);
    expect(File(kept.filePath!).lengthSync(), world.videoBytes.length);

    // An explicit download (a torrent of its own) lands in Downloads and
    // plays from the file.
    const third = PlayRequest(
      type: 'series',
      mediaId: FakeWorld.imdb,
      videoId: '${FakeWorld.imdb}:1:3',
      title: FakeWorld.show,
      season: 1,
      episode: 3,
      episodeTitle: 'Third',
    );
    await container.read(downloadActionsProvider).download(third);
    await pumpUntil(
      tester,
      () =>
          container
              .read(downloadsProvider)
              .value
              ?.any(
                (d) => d.videoId == third.videoId && d.state == 'completed',
              ) ??
          false,
      reason: 'explicit download finished',
      state: () {
        final row = container
            .read(downloadsProvider)
            .value
            ?.where((d) => d.videoId == third.videoId)
            .firstOrNull;
        final ih = row?.infoHash;
        final engine = container.read(engineServiceProvider).engine;
        return 'row: ${row?.state} ${row?.error} '
            '${row?.doneBytes}/${row?.totalBytes} file ${row?.fileIndex}\n'
            'torrent: ${ih == null ? '-' : engine.status(ih)}\n'
            'files: ${ih == null ? '-' : engine.files(ih)?.length}\n'
            'claims: ${ih == null ? '-' : container.read(engineServiceProvider).claimsOf(ih)}';
      },
    );
    final saved = container
        .read(downloadsProvider)
        .value!
        .firstWhere((d) => d.videoId == third.videoId);
    expect(saved.filePath, startsWith(paths.downloads.path));
    expect(File(saved.filePath!).readAsBytesSync(), world.videoBytes);
    unawaited(container.read(routerProvider).push('/player', extra: third));
    await pumpUntil(
      tester,
      () =>
          PlayerController.debugLast != c &&
          PlayerController.debugLast?.phase == PlayerPhase.playing,
      reason: 'downloaded episode opens',
      state: () {
        final p = PlayerController.debugLast;
        return 'new: ${p != c} ${p?.phase} "${p?.status}" ${p?.error} '
            'source: ${p?.source?.kind} ${p?.source?.uri} '
            'mpv: playing ${p?.player.state.playing} '
            '${p?.player.state.position}/${p?.player.state.duration} '
            'buffering ${p?.player.state.buffering}';
      },
    );
    final offline = PlayerController.debugLast!;
    expect(offline.source!.kind, PlaybackKind.local);
    await pumpUntil(
      tester,
      () => offline.player.state.position > const Duration(seconds: 1),
      reason: 'plays from the downloaded file',
    );
    container.read(routerProvider).pop();

    // A season pack: three episodes of one torrent, downloaded at the same
    // moment, as when Download is tapped on each in quick succession.
    final pack = [
      for (final e in FakeWorld.packEpisodes)
        PlayRequest(
          type: 'series',
          mediaId: FakeWorld.imdb,
          videoId: '${FakeWorld.imdb}:1:$e',
          title: FakeWorld.show,
          season: 1,
          episode: e,
          episodeTitle: 'Pack $e',
        ),
    ];
    final actions = container.read(downloadActionsProvider);
    List<DownloadRow> packRows() => [
      for (final d
          in container.read(downloadsProvider).value ?? const <DownloadRow>[])
        if (pack.any((r) => r.videoId == d.videoId)) d,
    ];
    // Two at once (Settings › Downloads at once): the third waits its turn.
    await container
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(downloadsAtOnce: 2));
    var mostAtOnce = 0;
    // The first finds the pack's details; the other two, tapped together
    // right after, start from a torrent Kinora already has.
    await actions.download(pack.first);
    await pumpUntil(
      tester,
      () => packRows().any((d) => d.totalBytes > 0),
      reason: 'season pack: the first episode found its file',
    );
    await Future.wait([for (final r in pack.skip(1)) actions.download(r)]);
    await pumpUntil(
      tester,
      () {
        final now = packRows().where((d) => d.state == 'downloading').length;
        if (now > mostAtOnce) mostAtOnce = now;
        return packRows().length == pack.length &&
            packRows().every((d) => d.state == 'completed');
      },
      reason: 'season pack: three downloads, two at once',
      state: () => [
        for (final d in packRows())
          '${d.videoId}: ${d.state} ${d.error} ${d.doneBytes}/${d.totalBytes} '
              'file ${d.fileIndex} at ${d.filePath}',
      ].join('\n'),
    );
    for (final d in packRows()) {
      expect(d.filePath, startsWith(paths.downloads.path), reason: d.videoId);
      expect(File(d.filePath!).readAsBytesSync(), world.videoBytes);
    }
    expect(mostAtOnce, lessThanOrEqualTo(2), reason: 'Downloads at once: 2');
    // ignore: avoid_print
    print('E2E ok: season pack episodes saved in Downloads, two at once');
  }, timeout: const Timeout(Duration(minutes: 6)));
}
