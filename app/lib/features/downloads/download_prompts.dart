import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/desktop.dart';
import '../../core/db/database.dart';
import '../../core/format.dart';
import '../../core/log.dart';
import '../../services/background.dart';
import '../../services/downloads.dart';
import '../../services/play_request.dart';
import '../../ui/glass.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/sheet.dart';
import '../settings/widgets/settings_ui.dart';

/// The pause reason the downloads service sets when Wi-Fi drops.
const waitingForWifi = 'Waiting for Wi-Fi';

/// Asks what a download waiting for Wi-Fi should do: use mobile data now
/// (naming how much), or keep waiting.
Future<void> showWifiWaitSheet(
  BuildContext context,
  WidgetRef ref,
  DownloadRow row,
) async {
  final left = row.totalBytes > row.doneBytes
      ? row.totalBytes - row.doneBytes
      : 0;
  final now = await showGlassSheet<bool>(
    context,
    builder: (sheet) => SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              KSpace.margin,
              KSpace.x3,
              KSpace.margin,
              KSpace.x2,
            ),
            child: Semantics(
              header: true,
              child: Text(waitingForWifi, style: KType.h2),
            ),
          ),
          Note(
            'This download continues on its own when $thisDevice is on Wi-Fi.',
          ),
          SheetAction(
            icon: Icons.signal_cellular_alt_rounded,
            label: left > 0
                ? 'Download on mobile data (${Fmt.bytes(left)})'
                : 'Download on mobile data',
            onTap: () => Navigator.pop(sheet, true),
          ),
          SheetAction(
            icon: Icons.wifi_rounded,
            label: 'Wait for Wi-Fi',
            onTap: () => Navigator.pop(sheet, false),
          ),
          const SizedBox(height: KSpace.x2),
        ],
      ),
    ),
  );
  if (now ?? false) await ref.read(downloadActionsProvider).resume(row.id);
}

// shortcut: remembered for this run only (no settings field for it); the OS
// state below keeps it from asking again once both are allowed.
bool _explained = false;

/// Starts downloading [request]. The first time, says in one sentence each
/// why a notification (and on Android, background running) is needed,
/// before the system asks.
Future<void> startDownload(
  BuildContext context,
  WidgetRef ref,
  PlayRequest request,
) async {
  final actions = ref.read(downloadActionsProvider);
  if (Platform.isAndroid && !_explained) {
    _explained = true;
    try {
      final notify =
          await FlutterForegroundTask.checkNotificationPermission() !=
          NotificationPermission.granted;
      final battery =
          !await FlutterForegroundTask.isIgnoringBatteryOptimizations;
      if ((notify || battery) && context.mounted) {
        final go = await _explain(context, notify: notify, battery: battery);
        if (go ?? false) {
          if (notify)
            await FlutterForegroundTask.requestNotificationPermission();
          if (battery)
            await BackgroundKeeper.instance.requestBatteryExemption();
        }
      }
    } on Object catch (e) {
      Log.w('downloads', 'permission prompt: $e');
    }
  } else if (Platform.isIOS && !_explained) {
    _explained = true;
    // Only before iPhone has asked: after a no, Kinora doesn't nag.
    final keeper = BackgroundKeeper.instance;
    if (await keeper.notificationsUndecided() && context.mounted) {
      final go = await _explain(context, notify: true, battery: false);
      if (go ?? false) await keeper.askNotifications();
    }
  }
  await actions.download(request);
}

Future<bool?> _explain(
  BuildContext context, {
  required bool notify,
  required bool battery,
}) => showGlassSheet<bool>(
  context,
  builder: (sheet) => SingleChildScrollView(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            KSpace.margin,
            KSpace.x3,
            KSpace.margin,
            KSpace.x2,
          ),
          child: Semantics(
            header: true,
            child: Text('Downloads in the background', style: KType.h2),
          ),
        ),
        if (notify)
          Note(
            Platform.isIOS
                ? 'Kinora shows how downloads are going in a quiet '
                      'notification and tells you when one is ready, so '
                      'iPhone will ask you to allow notifications.'
                : 'Kinora shows download progress in a notification, so '
                      'Android will ask you to allow notifications.',
          ),
        if (battery)
          const Note(
            'Allow Kinora to keep running when it’s closed, so long '
            'downloads finish.',
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            KSpace.margin,
            KSpace.x2,
            KSpace.margin,
            0,
          ),
          child: GlassGroup(
            child: Wrap(
              spacing: KSpace.x3,
              runSpacing: KSpace.x3,
              children: [
                GlassButton(
                  label: 'Continue',
                  prominent: true,
                  onPressed: () => Navigator.pop(sheet, true),
                ),
                GlassButton(
                  label: 'Not now',
                  onPressed: () => Navigator.pop(sheet, false),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: KSpace.x3),
      ],
    ),
  ),
);
