import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kinora_engine/kinora_engine.dart';

import '../../app/providers.dart';
import '../../core/log.dart';
import '../../services/sources.dart';
import '../../services/subtitles_service.dart';
import '../../ui/glass.dart';
import '../../ui/tokens.dart';
import 'widgets/settings_ui.dart';

/// Native engine version, or null when the library isn't loaded (tests,
/// unsupported platforms).
final engineVersionProvider = Provider<String?>((_) {
  try {
    final v = KinoraEngine.version();
    return v.isEmpty ? null : v;
  } on Object {
    return null;
  }
});

final _url = RegExp(r'\b(https?|stremio)://([^/\s)"]+)([^\s)"]*)');
final _token = RegExp(r'\b[A-Za-z0-9_\-]{24,}\b');
final _infoHash = RegExp(r'^[0-9a-fA-F]{40}$');

/// Hides anything that could be a key: the user's saved [secrets], URL
/// paths and queries (addon links carry debrid keys), and long tokens.
/// Info-hashes stay: they identify torrents, not people.
String redact(String text, [Iterable<String> secrets = const []]) {
  var out = text;
  for (final s in secrets) {
    if (s.length >= 4) out = out.replaceAll(s, '[key]');
  }
  out = out.replaceAllMapped(
    _url,
    (m) => '${m[1]}://${m[2]}${(m[3] ?? '').length > 1 ? '/…' : ''}',
  );
  return out.replaceAllMapped(
    _token,
    (m) => _infoHash.hasMatch(m[0]!) ? m[0]! : '[hidden]',
  );
}

/// Settings › Diagnostics.
class DiagnosticsPage extends ConsumerStatefulWidget {
  const DiagnosticsPage({super.key});

  @override
  ConsumerState<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends ConsumerState<DiagnosticsPage> {
  LogLevel _min = LogLevel.info;

  Future<List<String>> _secrets() async {
    final keys = ref.read(secureKeysProvider);
    return [
      for (final p in subtitleProviderCatalog)
        ...await keys
            .read(p.id)
            .then(
              (c) => [c.apiKey, c.username, c.password],
              onError: (Object _) => const <String>[],
            ),
    ];
  }

  Future<void> _copy() async {
    final s = ref.read(settingsProvider);
    final addons = ref.read(addonsProvider).value ?? const [];
    final settings = Map.of(s.toJson())..remove('lastCastDevice');
    final text = [
      'Kinora $kinoraVersion',
      'Engine ${ref.read(engineVersionProvider) ?? 'not available'}',
      'System ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      'Sources: ${[for (final a in addons) '${a.name}${a.enabled ? '' : ' (off)'}'].join(', ')}',
      'Settings: ${jsonEncode(settings)}',
      '',
      Log.dump(),
    ].join('\n');
    await Clipboard.setData(
      ClipboardData(text: redact(text, await _secrets())),
    );
    if (mounted) showNote(context, 'Copied. Keys and links are left out.');
  }

  @override
  Widget build(BuildContext context) {
    final engine = ref.watch(engineVersionProvider);
    final lines = Log.lines.reversed
        .where((l) => l.level.index >= _min.index)
        .take(300)
        .toList();
    return SettingsPage(
      title: 'Diagnostics',
      intro:
          'Logs stay on this phone. Copy them to share with someone who '
          'helps you; keys and addon links are left out.',
      children: [
        const _Fact('App version', kinoraVersion),
        _Fact('Engine version', engine ?? 'Not available on this device'),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            KSpace.margin,
            KSpace.x3,
            KSpace.margin,
            0,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: GlassGroup(
              child: GlassButton(
                label: 'Copy diagnostics',
                icon: Icons.copy_rounded,
                prominent: true,
                onPressed: () => unawaited(_copy()),
              ),
            ),
          ),
        ),
        const SectionTitle('Recent log'),
        Segmented<LogLevel>(
          options: const [
            (LogLevel.debug, 'All'),
            (LogLevel.info, 'Info'),
            (LogLevel.warn, 'Warnings'),
            (LogLevel.error, 'Errors'),
          ],
          value: _min,
          onChanged: (v) => setState(() => _min = v),
        ),
        if (lines.isEmpty)
          const Note('Nothing logged at this level yet.')
        else
          for (final l in lines) _LogLineRow(l),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KSpace.margin,
        vertical: KSpace.x2,
      ),
      child: Wrap(
        spacing: KSpace.x3,
        children: [
          Text(label, style: KType.title),
          Text(
            value,
            style: KType.tabular(KType.body.copyWith(color: KColors.haze)),
          ),
        ],
      ),
    ),
  );
}

class _LogLineRow extends StatelessWidget {
  const _LogLineRow(this.line);

  final LogLine line;

  @override
  Widget build(BuildContext context) {
    final t = line.time;
    String two(int n) => n.toString().padLeft(2, '0');
    final time = '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
    final color = switch (line.level) {
      LogLevel.error => KColors.cut,
      LogLevel.warn => KColors.marquee,
      _ => KColors.haze,
    };
    final level = switch (line.level) {
      LogLevel.error => 'Error',
      LogLevel.warn => 'Warning',
      LogLevel.info => 'Info',
      LogLevel.debug => 'Debug',
    };
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: KSpace.margin,
          vertical: KSpace.x1 + 2,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$time  $level  ${line.tag}',
              style: KType.tabular(KType.small.copyWith(color: color)),
            ),
            Text(
              redact(line.message),
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
              style: KType.label.copyWith(color: KColors.lamp),
            ),
          ],
        ),
      ),
    );
  }
}

/// Settings › About.
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) => SettingsPage(
    title: 'About Kinora',
    intro:
        'Kinora streams or downloads movies and shows from the sources you '
        'add, with one player for both, casting to your TV, and subtitles '
        'from the sites you choose. Everything stays on this phone: no '
        'account, no tracking.',
    children: [
      const _Fact('Version', kinoraVersion),
      const SectionTitle('What you watch'),
      const Note(
        'Kinora is a media player and BitTorrent and HTTP client. It ships '
        'with no content, sources, addons or keys: you add the ones you '
        'choose. You’re responsible for what you access and for following '
        'the laws where you live.',
      ),
      const SectionTitle('License'),
      const Note(
        'Kinora is free software under the GNU General Public License, '
        'version 3 (GPL-3.0). You may share and change it under the same '
        'license. It comes with no warranty. Third-party parts keep their '
        'own licenses.',
      ),
      ActionRow(
        icon: Icons.description_outlined,
        label: 'Open-source licenses',
        onTap: () => showLicensePage(
          context: context,
          applicationName: 'Kinora',
          applicationVersion: kinoraVersion,
          applicationLegalese: 'GPL-3.0',
        ),
      ),
    ],
  );
}
