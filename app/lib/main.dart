import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'core/db/database.dart';
import 'core/log.dart';
import 'core/paths.dart';
import 'data/settings_store.dart';
import 'services/engine_service.dart';

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
  final container = ProviderContainer(
    overrides: [
      pathsProvider.overrideWithValue(paths),
      databaseProvider.overrideWithValue(db),
      initialSettingsProvider.overrideWithValue(settings),
    ],
  );
  AppLifecycleListener(
    onPause: () {
      container.read(engineServiceProvider).checkpoint();
      unawaited(Log.flush());
    },
  );
  runApp(
    UncontrolledProviderScope(container: container, child: const KinoraApp()),
  );
}
