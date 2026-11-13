import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/desktop.dart';
import '../../app/providers.dart';
import '../../services/trakt.dart';
import '../../services/sources.dart';
import '../../services/subtitles_service.dart';
import 'help_pages.dart';
import 'languages.dart';
import 'preference_pages.dart';
import 'backup_page.dart';
import 'trakt_page.dart';
import 'sources.dart';
import 'storage_page.dart';
import 'subtitle_sites.dart';
import 'subtitle_style_page.dart';
import 'widgets/settings_ui.dart';

/// Sub-pages of Settings, under `/settings`.
final List<RouteBase> settingsRoutes = [
  GoRoute(path: 'sources', builder: (_, _) => const SourcesPage()),
  GoRoute(
    path: 'languages',
    builder: (_, _) => const LanguagesPage(),
    routes: [
      GoRoute(path: 'style', builder: (_, _) => const SubtitleStylePage()),
    ],
  ),
  GoRoute(path: 'subtitle-sites', builder: (_, _) => const SubtitleSitesPage()),
  GoRoute(path: 'trakt', builder: (_, _) => const TraktPage()),
  GoRoute(path: 'backup', builder: (_, _) => const BackupPage()),
  GoRoute(path: 'playback', builder: (_, _) => const PlaybackPage()),
  GoRoute(path: 'downloads', builder: (_, _) => const DownloadSettingsPage()),
  GoRoute(path: 'network', builder: (_, _) => const NetworkPage()),
  GoRoute(path: 'storage', builder: (_, _) => const StoragePage()),
  GoRoute(path: 'diagnostics', builder: (_, _) => const DiagnosticsPage()),
  GoRoute(path: 'about', builder: (_, _) => const AboutPage()),
];

/// "3 sources, all on", "3 sources, 2 on", "1 source, off".
String sourcesSummary(int count, int on) {
  final n = count == 1 ? '1 source' : '$count sources';
  if (on == count) return count == 1 ? '$n, on' : '$n, all on';
  if (on == 0) return count == 1 ? '$n, off' : '$n, all off';
  return '$n, $on on';
}

/// Settings: plain rows in three groups, each opening its page.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final trakt = ref.watch(traktSyncProvider);
    final addons = ref.watch(addonsProvider).value;
    final on = addons?.where((a) => a.enabled).length ?? 0;
    final sites = [
      for (final p in subtitleProviderCatalog)
        if (s.enabledSubtitleProviders.contains(p.id)) p.name,
    ];
    final dub = s.audioLanguages.firstOrNull;
    void go(String page) => context.go('/settings/$page');
    return SettingsPage(
      title: 'Settings',
      back: false,
      children: [
        const SectionTitle('Account'),
        _TraktRow(trakt: trakt, onTap: () => go('trakt')),
        NavRow(
          label: 'Backup',

          icon: Icons.settings_backup_restore_rounded,
          value: 'Move your sources and keys to another device',
          onTap: () => go('backup'),
        ),
        const SectionTitle('Watching'),
        NavRow(
          label: 'Sources',

          icon: Icons.extension_outlined,
          value: addons == null
              ? null
              : addons.isEmpty
              ? 'None yet. Add one to see movies and shows.'
              : sourcesSummary(addons.length, on),
          onTap: () => go('sources'),
        ),
        NavRow(
          label: 'Languages and subtitles',

          icon: Icons.translate_rounded,
          value: [
            switch (languageList(s.subtitleLanguages)) {
              final l? => 'Subtitles in $l',
              null => 'No subtitle languages yet',
            },
            if (dub != null && dub != 'original')
              'dubbed in ${languageName(dub)}',
          ].join(', '),
          onTap: () => go('languages'),
        ),
        NavRow(
          label: 'Subtitle sites',

          icon: Icons.subtitles_outlined,
          value: sites.isEmpty ? 'None on' : sites.join(', '),
          onTap: () => go('subtitle-sites'),
        ),
        NavRow(
          label: 'Playback',

          icon: Icons.play_circle_outline_rounded,
          value: [
            'Up to ${resolutionLabel(s.maxResolution)}',
            if (s.dataSaver) 'data saver',
          ].join(', '),
          onTap: () => go('playback'),
        ),
        SectionTitle(thisDeviceTitle),
        NavRow(
          label: 'Downloads',

          icon: Icons.file_download_outlined,
          value: isDesktop
              ? switch (s.downloadsAtOnce) {
                  0 => 'All at once',
                  1 => 'One at a time',
                  final n => '$n at once',
                }
              : s.wifiOnlyDownloads
              ? 'On Wi-Fi only'
              : 'On any network',
          onTap: () => go('downloads'),
        ),
        NavRow(
          label: 'Network',

          icon: Icons.wifi_rounded,
          value: s.vpnInterface.isNotEmpty
              ? 'Only through ${s.vpnInterface}'
              : s.uploadLimitKBps == 0 && s.downloadLimitKBps == 0
              ? 'No speed limits'
              : 'Speed limits on',
          onTap: () => go('network'),
        ),
        NavRow(
          label: 'Storage',

          icon: Icons.storage_rounded,
          value: 'See and clear what Kinora keeps',
          onTap: () => go('storage'),
        ),
        const SectionTitle('Help'),
        NavRow(
          label: 'Diagnostics',

          icon: Icons.monitor_heart_outlined,
          value: 'App version and recent log',
          onTap: () => go('diagnostics'),
        ),
        NavRow(
          label: 'About Kinora',
          icon: Icons.info_outline_rounded,
          value: 'Version $kinoraVersion',
          onTap: () => go('about'),
        ),
      ],
    );
  }
}

/// The Trakt row, kept current as the sign-in changes.
class _TraktRow extends StatelessWidget implements SettingsRow {
  const _TraktRow({required this.trakt, required this.onTap});

  final TraktSync trakt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: trakt,
    builder: (_, _) => NavRow(
      label: 'Trakt',
      icon: Icons.sync_alt_rounded,
      value: !trakt.available
          ? 'Not in this version'
          : trakt.signedIn
          ? 'Syncing as ${trakt.user}'
          : 'Sign in to keep what you watch the same everywhere',
      onTap: onTap,
    ),
  );
}
