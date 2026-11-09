import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart'
    show AppLifecycleListener, AppLifecycleState;
import 'package:flutter/services.dart';

import '../core/db/database.dart';
import '../core/log.dart';

/// Build with `--dart-define=KINORA_FAKE_GLASS=true` to use the frosted
/// fallback everywhere.
const kForceFakeGlass = bool.fromEnvironment('KINORA_FAKE_GLASS');

/// Whether glass draws with the real liquid-glass renderer (Flutter GPU)
/// instead of the frosted fallback. Set once at launch by [decideGlass].
bool realGlass = false;

/// Why [realGlass] is what it is, in words (Settings › Diagnostics).
String glassReason = 'Frosted until checked';

/// True when an earlier launch with real glass never drew, so it's off.
bool glassFailed = false;

const _key = 'glass.probe';
const _channel = MethodChannel('kinora/net');

/// Turns real glass on only where it can draw: shader filters available,
/// and on Android, Impeller on Vulkan (on OpenGL ES, emulators included,
/// the glass renderer can stall every frame). A launch that turns it on
/// must draw frames within seconds; if it never does (the app froze or was
/// killed first), the next launch uses frosted glass.
Future<void> decideGlass(
  AppDatabase db, {
  Future<bool> Function()? vulkan,
  bool? shaderFilters,
}) async {
  realGlass = false;
  glassFailed = false;
  try {
    await _decide(db, vulkan: vulkan, shaderFilters: shaderFilters);
  } on Object catch (e) {
    // Never keep Kinora from opening (a full disk fails the write).
    Log.w('glass', 'check failed: $e');
    realGlass = false;
    glassReason = 'Frosted: the glass check couldn’t run';
  }
}

Future<void> _decide(
  AppDatabase db, {
  Future<bool> Function()? vulkan,
  bool? shaderFilters,
}) async {
  if (kForceFakeGlass) {
    glassReason = 'Frosted (set by the build)';
    return;
  }
  final last = await _read(db);
  if (last == 'pending' || last == 'failed') {
    await _write(db, 'failed');
    glassFailed = true;
    glassReason = 'Frosted: an earlier launch with liquid glass drew nothing';
    return;
  }
  if (!(shaderFilters ?? ui.ImageFilter.isShaderFilterSupported)) {
    glassReason = 'Frosted: this phone can’t run the glass shaders';
    return;
  }
  if (Platform.isAndroid && !await (vulkan ?? _androidVulkan)()) {
    glassReason = 'Frosted: this phone draws without Vulkan';
    return;
  }
  realGlass = true;
  glassReason = 'Liquid glass';
  await _probeWhenVisible(db);
}

/// The probe starts once Kinora is on screen: a launch in the background
/// (iOS waking it for downloads) draws nothing and mustn't count as a
/// failure.
Future<void> _probeWhenVisible(AppDatabase db) async {
  Future<void> begin() async {
    await _write(db, 'pending');
    _confirmFrames(db);
  }

  final state = SchedulerBinding.instance.lifecycleState;
  if (state == null || state == AppLifecycleState.resumed) return begin();
  late final AppLifecycleListener listener;
  listener = AppLifecycleListener(
    onResume: () {
      listener.dispose();
      unawaited(begin().catchError((Object e) => Log.w('glass', '$e')));
    },
  );
}

/// Lets the next launch try liquid glass again.
Future<void> retryGlass(AppDatabase db) => _write(db, 'ok');

Future<bool> _androidVulkan() async {
  try {
    return await _channel.invokeMethod<bool>('vulkanRendering') ?? false;
  } on Object catch (e) {
    Log.w('glass', 'vulkan check: $e');
    return false;
  }
}

/// Frames finished after the glass renderer has started (a few seconds in)
/// prove it draws on this device.
void _confirmFrames(AppDatabase db) {
  final binding = SchedulerBinding.instance;
  final started = DateTime.now();
  Timer? nudge;
  late final TimingsCallback onTimings;
  onTimings = (_) {
    if (DateTime.now().difference(started) < const Duration(seconds: 3)) {
      return;
    }
    binding.removeTimingsCallback(onTimings);
    nudge?.cancel();
    unawaited(_write(db, 'ok').catchError((Object e) => Log.w('glass', '$e')));
  };
  binding.addTimingsCallback(onTimings);
  // A still screen draws nothing: ask for frames until one is reported.
  nudge = Timer.periodic(const Duration(seconds: 1), (t) {
    if (t.tick > 30) t.cancel();
    binding.scheduleFrame();
  });
}

Future<String?> _read(AppDatabase db) async {
  final row = await (db.select(
    db.keyValues,
  )..where((t) => t.key.equals(_key))).getSingleOrNull();
  return row?.value;
}

Future<void> _write(AppDatabase db, String value) => db
    .into(db.keyValues)
    .insertOnConflictUpdate(KeyValuesCompanion.insert(key: _key, value: value));
