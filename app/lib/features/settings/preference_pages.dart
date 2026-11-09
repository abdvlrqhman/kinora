import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../core/settings.dart';
import '../../services/background.dart';
import 'widgets/settings_ui.dart';

void _save(WidgetRef ref, AppSettings Function(AppSettings) change) =>
    unawaited(ref.read(settingsProvider.notifier).update(change));

/// "Up to 1080p".
String resolutionLabel(int p) => p >= 2160 ? '4K' : '${p}p';

/// Settings › Playback.
class PlaybackPage extends ConsumerWidget {
  const PlaybackPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    return SettingsPage(
      title: 'Playback',
      children: [
        const SectionTitle('Highest quality'),
        const Note(
          'Kinora picks the best version up to this. Lower uses less data '
          'and storage.',
        ),
        Segmented<int>(
          options: const [(720, '720p'), (1080, '1080p'), (2160, '4K')],
          value: s.maxResolution >= 2160
              ? 2160
              : s.maxResolution >= 1080
              ? 1080
              : 720,
          onChanged: (v) => _save(ref, (s) => s.copyWith(maxResolution: v)),
        ),
        SwitchRow(
          label: 'Data saver',
          detail: 'Prefer smaller files, even at the same quality.',
          value: s.dataSaver,
          onChanged: (v) => _save(ref, (s) => s.copyWith(dataSaver: v)),
        ),
        SwitchRow(
          label: 'Play the next episode',
          detail: 'Starts the next episode when the credits roll.',
          value: s.autoplayNext,
          onChanged: (v) => _save(ref, (s) => s.copyWith(autoplayNext: v)),
        ),
        SwitchRow(
          label: 'Skip intros',
          detail: 'Jumps past intros and recaps when the video marks them.',
          value: s.skipIntros,
          onChanged: (v) => _save(ref, (s) => s.copyWith(skipIntros: v)),
        ),
      ],
    );
  }
}

/// Settings › Downloads.
class DownloadSettingsPage extends ConsumerWidget {
  const DownloadSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    return SettingsPage(
      title: 'Downloads',
      children: [
        SwitchRow(
          label: 'Download on Wi-Fi only',
          detail: 'Downloads wait for Wi-Fi instead of using mobile data.',
          value: s.wifiOnlyDownloads,
          onChanged: (v) => _save(ref, (s) => s.copyWith(wifiOnlyDownloads: v)),
        ),
        SwitchRow(
          label: 'Keep fully streamed episodes',
          detail: 'Episodes you stream to the end are kept in Downloads.',
          value: s.keepCompletedStreams,
          onChanged: (v) =>
              _save(ref, (s) => s.copyWith(keepCompletedStreams: v)),
        ),
        SwitchRow(
          label: 'Download the next episode',
          detail: 'When you finish a downloaded episode, the next one starts.',
          value: s.autoDownloadNext,
          onChanged: (v) => _save(ref, (s) => s.copyWith(autoDownloadNext: v)),
        ),
        SwitchRow(
          label: 'Delete watched downloads',
          detail: 'Frees space once you’ve watched a download to the end.',
          value: s.deleteWatchedDownloads,
          onChanged: (v) =>
              _save(ref, (s) => s.copyWith(deleteWatchedDownloads: v)),
        ),
        SwitchRow(
          label: 'Share after downloading',
          detail:
              'Keeps sharing a finished torrent with others. Uses upload and '
              'battery.',
          value: s.seedAfterDownload,
          onChanged: (v) => _save(ref, (s) => s.copyWith(seedAfterDownload: v)),
        ),
        const SectionTitle('Keep streamed data for'),
        const Note(
          'Lets you rewatch without fetching it again. Off deletes it when '
          'you leave the player.',
        ),
        Segmented<int>(
          options: const [(0, 'Off'), (24, '1 day'), (168, '1 week')],
          value: s.keepStreamsHours >= 168
              ? 168
              : s.keepStreamsHours >= 24
              ? 24
              : 0,
          onChanged: (v) => _save(ref, (s) => s.copyWith(keepStreamsHours: v)),
        ),
        if (defaultTargetPlatform == TargetPlatform.android) ...[
          const SectionTitle('In the background'),
          ActionRow(
            icon: Icons.battery_saver_rounded,
            label: 'Allow background downloads',
            detail:
                'Android may stop downloads to save battery when Kinora is '
                'closed. Allow Kinora to keep running so they finish.',
            onTap: () async {
              final ok = await BackgroundKeeper.instance
                  .requestBatteryExemption();
              if (context.mounted) {
                showNote(
                  context,
                  ok
                      ? 'Downloads can keep running in the background.'
                      : 'Not allowed. Downloads may pause when Kinora is '
                            'closed.',
                );
              }
            },
          ),
        ],
      ],
    );
  }
}

/// Speed limit presets in KB/s (0 = none).
const speedLimits = [0, 256, 1024, 2048, 5120, 10240];

String limitLabel(int kbps) => kbps == 0 ? 'No limit' : Fmt.speed(kbps * 1024);

/// Settings › Network.
class NetworkPage extends ConsumerStatefulWidget {
  const NetworkPage({super.key});

  @override
  ConsumerState<NetworkPage> createState() => _NetworkPageState();
}

class _NetworkPageState extends ConsumerState<NetworkPage> {
  late final _vpn = TextEditingController(
    text: ref.read(settingsProvider).vpnInterface,
  );

  @override
  void dispose() {
    _vpn.dispose();
    super.dispose();
  }

  Future<void> _limit(String title, int current, bool upload) async {
    final v = await pickOption<int>(
      context,
      title: title,
      current: current,
      options: [for (final l in speedLimits) (l, limitLabel(l))],
    );
    if (v == null) return;
    _save(
      ref,
      (s) => upload
          ? s.copyWith(uploadLimitKBps: v)
          : s.copyWith(downloadLimitKBps: v),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    return SettingsPage(
      title: 'Network',
      children: [
        NavRow(
          label: 'Download speed',
          value: limitLabel(s.downloadLimitKBps),
          onTap: () => _limit('Download speed', s.downloadLimitKBps, false),
        ),
        NavRow(
          label: 'Upload speed',
          value: limitLabel(s.uploadLimitKBps),
          onTap: () => _limit('Upload speed', s.uploadLimitKBps, true),
        ),
        SwitchRow(
          label: 'Share while watching',
          detail:
              'Shares pieces with others while you stream. Off saves upload, '
              'but some streams may start slower.',
          value: s.seedWhileWatching,
          onChanged: (v) => _save(ref, (s) => s.copyWith(seedWhileWatching: v)),
        ),
        const SectionTitle('Only use this network interface (VPN)'),
        const Note(
          'Type your VPN’s interface name, such as tun0 or utun3, and Kinora '
          'connects only through it. If the VPN drops, transfers stop '
          'instead of using your normal connection. Leave it empty to use '
          'any network.',
        ),
        GlassField(
          controller: _vpn,
          label: 'Interface name',
          hint: 'Any network',
          fieldKey: const ValueKey('vpn-interface'),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_.:\-]')),
            LengthLimitingTextInputFormatter(32),
          ],
          onChanged: (v) =>
              _save(ref, (s) => s.copyWith(vpnInterface: v.trim())),
        ),
        const Note('Takes effect the next time Kinora starts.'),
      ],
    );
  }
}
