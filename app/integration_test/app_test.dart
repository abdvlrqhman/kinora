// End-to-end: the real app, on a real device/emulator, plays an episode
// from a real torrent swarm (a seeder in this process, found through a
// tracker), with subtitles from a source, switches to the next episode, and
// keeps the fully downloaded stream in Downloads. It also casts to a fake
// Samsung TV that pulls the stream, and plays an explicit download offline.
import 'dart:async';
import 'dart:io';

import 'package:dlna/testing.dart';
import 'package:drift/native.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kinora/app/app.dart';
import 'package:kinora/app/router.dart';
import 'package:kinora/core/db/database.dart';
import 'package:kinora/core/paths.dart';
import 'package:kinora/core/settings.dart';
import 'package:kinora/features/player/player_controller.dart';
import 'package:kinora/main.dart';
import 'package:kinora/services/cast_service.dart';
import 'package:kinora/services/downloads.dart';
import 'package:kinora/services/play_request.dart';
import 'package:kinora/services/playback.dart';
import 'package:kinora/services/resolver.dart';
import 'package:kinora/services/sources.dart';
import 'package:kinora/ui/glass_mode.dart';
import 'package:media_kit/media_kit.dart';

import 'support/fake_world.dart';

Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  Duration timeout = const Duration(seconds: 90),
  String? reason,
}) async {
  final end = DateTime.now().add(timeout);
  final started = DateTime.now();
  // ignore: avoid_print
  print('E2E waiting: ${reason ?? 'condition'}');
  while (!done()) {
    if (DateTime.now().isAfter(end))
      fail('Timed out: ${reason ?? 'condition'}');
    await tester.pump(const Duration(milliseconds: 250));
  }
  // ignore: avoid_print
  print(
    'E2E ok: ${reason ?? 'condition'} (${DateTime.now().difference(started).inMilliseconds} ms)',
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  testWidgets(
    'stream an episode end to end, subtitles, next episode, keep it',
    (tester) async {
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
      // The same check as a real launch: emulators draw with OpenGL ES, so
      // this must choose frosted glass (real glass would stall the frames).
      await decideGlass(db);
      // ignore: avoid_print
      print('E2E glass: $glassReason');
      final container = ProviderContainer(
        overrides: [
          ...appOverrides(
            paths: paths,
            db: db,
            settings: const AppSettings(
              onboarded: true,
              subtitleLanguages: ['en'],
              wifiOnlyDownloads: false,
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
        UncontrolledProviderScope(
          container: container,
          child: const KinoraApp(),
        ),
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
        () => c.player.state.subtitle
            .join(' ')
            .contains('Kinora end-to-end test'),
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
      expect(cast.phase, CastPhase.playing);
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
      );
      final offline = PlayerController.debugLast!;
      expect(offline.source!.kind, PlaybackKind.local);
      await pumpUntil(
        tester,
        () => offline.player.state.position > const Duration(seconds: 1),
        reason: 'plays from the downloaded file',
      );
      container.read(routerProvider).pop();
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
