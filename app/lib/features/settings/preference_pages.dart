import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/desktop.dart';
import '../../app/providers.dart';
import '../../core/format.dart';
import '../../core/settings.dart';
import '../../services/background.dart';
import '../../services/trakt.dart';
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
        const SectionTitle('Intros, recaps and credits'),
        Segmented<int>(
          options: const [
            (2, 'Skip automatically'),
            (1, 'Show a Skip button'),
            (0, 'Off'),
          ],
          value: !s.skipIntros
              ? 0
              : s.autoSkip
              ? 2
              : 1,
          onChanged: (v) => _save(
            ref,
            (s) => s.copyWith(skipIntros: v > 0, autoSkip: v == 2),
          ),
        ),
        if (s.skipIntros)
          SwitchRow(
            label: 'Look up where they are',
            detail:
                'For videos that don\'t mark them: TheIntroDB for shows and '
                'movies, AniSkip for anime. They learn which episode you play.',
            value: s.skipLookup,
            onChanged: (v) => _save(ref, (s) => s.copyWith(skipLookup: v)),
          ),
      ],
    );
  }
}

/// Settings › Notifications (phones).
class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  /// Quiet hours on offer: (from, to) o'clock; equal is none.
  static const quietOptions = [
    ((22, 9), '10 PM–9 AM'),
    ((23, 8), '11 PM–8 AM'),
    ((0, 10), 'Midnight–10 AM'),
    ((0, 0), 'None'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final trakt = ref.watch(traktSyncProvider);
    final quiet = quietOptions
        .map((o) => o.$1)
        .firstWhere(
          (q) => q == (s.quietFrom, s.quietTo),
          orElse: () => (s.quietFrom, s.quietTo),
        );
    return SettingsPage(
      title: 'Notifications',
      children: [
        const SectionTitle('Your shows'),
        SwitchRow(
          label: 'Shows you follow',
          detail:
              'When they air, at most one notice per show a day. Several '
              'shows on one day come as one notice.',
          value: s.notifyShows,
          onChanged: (v) => _save(ref, (s) => s.copyWith(notifyShows: v)),
        ),
        if (s.notifyShows) ...[
          Segmented<bool>(
            options: const [
              (true, 'Every episode'),
              (false, 'Premieres and finales'),
            ],
            value: s.notifyEveryEpisode,
            onChanged: (v) =>
                _save(ref, (s) => s.copyWith(notifyEveryEpisode: v)),
          ),
          SwitchRow(
            label: 'Shows you watched lately',
            detail: 'Off: only shows in My list.',
            value: s.notifyWatchedLately,
            onChanged: (v) =>
                _save(ref, (s) => s.copyWith(notifyWatchedLately: v)),
          ),
          SwitchRow(
            label: 'New seasons announced',
            detail: 'Once, when a date is set months ahead.',
            value: s.notifySeasons,
            onChanged: (v) => _save(ref, (s) => s.copyWith(notifySeasons: v)),
          ),
        ],
        const SectionTitle('Suggestions'),
        ListenableBuilder(
          listenable: trakt,
          builder: (context, _) => SwitchRow(
            label: 'Picked for you',
            detail: trakt.signedIn
                ? 'One title a week, Friday evening, from what you watch '
                      'and rate.'
                : 'One title a week, Friday evening. Needs Trakt.',
            value: s.notifyPicks,
            onChanged: (v) => _save(ref, (s) => s.copyWith(notifyPicks: v)),
          ),
        ),
        const SectionTitle('Downloads'),
        SwitchRow(
          label: 'When a download is ready',
          detail: 'Says it finished, so you can watch it offline.',
          value: s.notifyDownloads,
          onChanged: (v) => _save(ref, (s) => s.copyWith(notifyDownloads: v)),
        ),
        const SectionTitle('Quiet hours'),
        const Note('Notices that would come then wait until they end.'),
        Segmented<(int, int)>(
          options: [
            for (final (q, label) in quietOptions) (q, label),
            if (!quietOptions.any((o) => o.$1 == quiet))
              (quiet, '${quiet.$1}:00–${quiet.$2}:00'),
          ],
          value: quiet,
          onChanged: (q) =>
              _save(ref, (s) => s.copyWith(quietFrom: q.$1, quietTo: q.$2)),
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
        // (A computer has no mobile data to save.)
        if (!isDesktop)
          SwitchRow(
            label: 'Download on Wi-Fi only',
            detail: 'Downloads wait for Wi-Fi instead of using mobile data.',
            value: s.wifiOnlyDownloads,
            onChanged: (v) =>
                _save(ref, (s) => s.copyWith(wifiOnlyDownloads: v)),
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
        const SectionTitle('Downloads at once'),
        const Note(
          'One at a time finishes each episode sooner; more share your '
          'connection. The others wait for their turn.',
        ),
        Segmented<int>(
          options: const [(1, '1'), (2, '2'), (3, '3'), (0, 'All')],
          value: s.downloadsAtOnce,
          onChanged: (v) => _save(ref, (s) => s.copyWith(downloadsAtOnce: v)),
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
