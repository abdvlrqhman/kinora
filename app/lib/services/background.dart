import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../core/log.dart';

/// Keeps torrent downloads running while Kinora is in the background.
///
/// Android: a foreground service (type `specialUse`: no 6-hour `dataSync`
/// budget; Kinora is sideloaded) with wake and Wi-Fi locks and a progress
/// notification. iOS: a silent audio session keeps the process alive (the
/// approach sideloaded torrent clients use) plus, on iOS 26+, a continued
/// processing task with system progress UI. HTTP/debrid downloads don't need
/// this: they use the OS background transfer services.
final class BackgroundKeeper {
  BackgroundKeeper._();
  static final instance = BackgroundKeeper._();

  static const _ios = MethodChannel('kinora/background');
  bool _running = false;
  bool _androidInit = false;

  /// Why the app must stay alive ('downloads', 'cast'), newest status each.
  final _reasons = <String, ({String title, String text, double? progress})>{};

  bool get isRunning => _running;

  /// Keeps the app alive for [reason]; several reasons share one service.
  Future<void> hold(
    String reason, {
    required String title,
    required String text,
    double? progress,
  }) {
    _reasons[reason] = (title: title, text: text, progress: progress);
    return keepAlive(title: title, text: text, progress: progress);
  }

  /// [reason] no longer needs the app alive; stops when no reason is left.
  Future<void> drop(String reason, {bool success = true}) async {
    if (_reasons.remove(reason) == null) return;
    if (_reasons.isEmpty) {
      await release(success: success);
    } else {
      final next = _reasons.values.last;
      await keepAlive(
        title: next.title,
        text: next.text,
        progress: next.progress,
      );
    }
  }

  /// Starts (or updates) keeping the app alive with a status line.
  Future<void> keepAlive({
    required String title,
    required String text,
    double? progress,
  }) async {
    try {
      if (Platform.isAndroid) {
        _initAndroid();
        if (_running) {
          await FlutterForegroundTask.updateService(
            notificationTitle: title,
            notificationText: text,
          );
        } else {
          // No permission prompt here: this runs on every progress tick, and
          // the service runs without it (only its notification is hidden).
          // The first download asks once, with a reason (download_prompts).
          await FlutterForegroundTask.startService(
            serviceId: 4242,
            serviceTypes: [ForegroundServiceTypes.specialUse],
            notificationIcon: const NotificationIcon(
              metaDataName: 'io.github.abdvlrqhman.kinora.NOTIFICATION_ICON',
            ),
            notificationTitle: title,
            notificationText: text,
          );
        }
      } else if (Platform.isIOS) {
        await _ios.invokeMethod<void>(_running ? 'update' : 'start', {
          'title': title,
          'text': text,
          'progress': progress,
        });
      }
      _running = true;
    } on Object catch (e) {
      Log.w('background', 'keep-alive failed: $e');
    }
  }

  /// Stops keeping the app alive (all transfers done or paused).
  Future<void> release({bool success = true}) async {
    if (!_running) return;
    _running = false;
    try {
      if (Platform.isAndroid) {
        await FlutterForegroundTask.stopService();
      } else if (Platform.isIOS) {
        await _ios.invokeMethod<void>('stop', {'success': success});
      }
    } on Object catch (e) {
      Log.w('background', 'release failed: $e');
    }
  }

  /// Asks Android to stop killing Kinora for battery (asked once, by the
  /// downloads screen, with an explanation first).
  Future<bool> requestBatteryExemption() async {
    if (!Platform.isAndroid) return true;
    if (await FlutterForegroundTask.isIgnoringBatteryOptimizations) return true;
    return FlutterForegroundTask.requestIgnoreBatteryOptimization();
  }

  void _initAndroid() {
    if (_androidInit) return;
    _androidInit = true;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'kinora_transfers',
        channelName: 'Downloads',
        channelDescription:
            'Shows download progress while Kinora works in the background.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        allowWifiLock: true,
        allowAutoRestart: false,
      ),
    );
  }
}
