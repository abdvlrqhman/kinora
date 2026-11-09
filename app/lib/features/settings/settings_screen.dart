import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../services/sources.dart';
import '../../services/subtitles_service.dart';
import 'help_pages.dart';
import 'languages.dart';
import 'preference_pages.dart';
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
  GoRoute(path: 'playback', builder: (_, _) => const PlaybackPage()),
  GoRoute(path: 'downloads', builder: (_, _) => const DownloadSettingsPage()),
  GoRoute(path: 'network', builder: (_, _) => const NetworkPage()),
  GoRoute(path: 'storage', builder: (_, _) => const StoragePage()),
  GoRoute(path: 'diagnostics', builder: (_, _) => const DiagnosticsPage()),
  GoRoute(path: 'about', builder: (_, _) => const AboutPage()),
];

/// Settings: plain rows in three groups, each opening its page.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
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
        const SectionTitle('Watching'),
        NavRow(
          icon: Icons.hub_outlined,
          label: 'Sources',
          value: addons == null
              ? null
              : addons.isEmpty
              ? 'None yet. Add one to see movies and shows.'
              : '${addons.length} added, $on on',
          onTap: () => go('sources'),
        ),
        NavRow(
          icon: Icons.translate_rounded,
          label: 'Languages and subtitles',
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
          icon: Icons.subtitles_outlined,
          label: 'Subtitle sites',
          value: sites.isEmpty ? 'None on' : sites.join(', '),
          onTap: () => go('subtitle-sites'),
        ),
        NavRow(
          icon: Icons.play_circle_outline_rounded,
          label: 'Playback',
          value: [
            'Up to ${resolutionLabel(s.maxResolution)}',
            if (s.dataSaver) 'data saver',
          ].join(', '),
          onTap: () => go('playback'),
        ),
        const SectionTitle('This phone'),
        NavRow(
          icon: Icons.download_outlined,
          label: 'Downloads',
          value: s.wifiOnlyDownloads ? 'On Wi-Fi only' : 'On any network',
          onTap: () => go('downloads'),
        ),
        NavRow(
          icon: Icons.network_check_rounded,
          label: 'Network',
          value: s.vpnInterface.isNotEmpty
              ? 'Only through ${s.vpnInterface}'
              : s.uploadLimitKBps == 0 && s.downloadLimitKBps == 0
              ? 'No speed limits'
              : 'Speed limits on',
          onTap: () => go('network'),
        ),
        NavRow(
          icon: Icons.sd_storage_outlined,
          label: 'Storage',
          value: 'See and clear what Kinora keeps',
          onTap: () => go('storage'),
        ),
        const SectionTitle('Help'),
        NavRow(
          icon: Icons.monitor_heart_outlined,
          label: 'Diagnostics',
          value: 'Versions and recent log',
          onTap: () => go('diagnostics'),
        ),
        NavRow(
          icon: Icons.info_outline_rounded,
          label: 'About Kinora',
          value: 'Version $kinoraVersion',
          onTap: () => go('about'),
        ),
      ],
    );
  }
}
