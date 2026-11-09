import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:media_kit/media_kit.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'core/db/database.dart';
import 'core/log.dart';
import 'core/paths.dart';
import 'core/settings.dart';
import 'data/settings_store.dart';
import 'features/player/player_controller.dart';
import 'services/downloads.dart';
import 'services/downloads_service.dart';
import 'services/engine_service.dart';
import 'services/subtitles_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final paths = await AppPaths.resolve();
  Log.attach(paths.logs);
  FlutterError.onError = (d) =>
      Log.e('flutter', d.exceptionAsString(), d.exception, d.stack);
  PlatformDispatcher.instance.onError = (e, st) {
    Log.e('uncaught', 'error', e, st);
    return true;
  };
  final db = AppDatabase.open(paths.support.path);
  final settings = await SettingsStore(db).load();
  final owned = await (db.selectOnly(
    db.downloads,
  )..addColumns([db.downloads.infoHash])).get();
  await EngineService.cleanStreamCache(
    paths,
    keepHours: settings.keepStreamsHours,
    downloadHashes: {for (final r in owned) ?r.read(db.downloads.infoHash)},
  );
  final container = ProviderContainer(
    overrides: appOverrides(paths: paths, db: db, settings: settings),
  );
  AppLifecycleListener(
    onPause: () {
      container.read(engineServiceProvider).checkpoint();
      unawaited(Log.flush());
    },
  );
  // Restores unfinished downloads and follows background transfers.
  unawaited(container.read(downloadsServiceProvider).start());
  runApp(
    UncontrolledProviderScope(container: container, child: const KinoraApp()),
  );
}

/// Every override the real app needs; integration tests reuse it.
List<Override> appOverrides({
  required AppPaths paths,
  required AppDatabase db,
  required AppSettings settings,
}) => [
  pathsProvider.overrideWithValue(paths),
  databaseProvider.overrideWithValue(db),
  initialSettingsProvider.overrideWithValue(settings),
  subtitleFitOverride,
  downloadActionsProvider.overrideWith(
    (ref) => ref.watch(downloadsServiceProvider),
  ),
  completedStreamHandlerProvider.overrideWith(
    (ref) => ref.watch(downloadsServiceProvider).adoptCompletedStream,
  ),
];
