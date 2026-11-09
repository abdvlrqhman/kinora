// End-to-end: the real app, on a real device/emulator, plays an episode
// from a real torrent swarm (a seeder in this process, found through a
// tracker), with subtitles from a source, switches to the next episode, and
// keeps the fully downloaded stream in Downloads.
import 'dart:async';
import 'dart:io';

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
import 'package:kinora/services/downloads.dart';
import 'package:kinora/services/play_request.dart';
import 'package:kinora/services/playback.dart';
import 'package:kinora/services/resolver.dart';
import 'package:kinora/services/sources.dart';
import 'package:media_kit/media_kit.dart';

import 'support/fake_world.dart';

Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  Duration timeout = const Duration(seconds: 90),
  String? reason,
}) async {
  final end = DateTime.now().add(timeout);
  while (!done()) {
    if (DateTime.now().isAfter(end))
      fail('Timed out: ${reason ?? 'condition'}');
    await tester.pump(const Duration(milliseconds: 250));
  }
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
      final kept = container
          .read(downloadsProvider)
          .value!
          .firstWhere((d) => d.state == 'completed');
      expect(File(kept.filePath!).existsSync(), isTrue);
      expect(File(kept.filePath!).lengthSync(), world.videoBytes.length);
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
