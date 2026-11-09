import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stremio/stremio.dart';

import '../../services/sources.dart';
import '../../ui/glass.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/sheet.dart';
import 'widgets/settings_ui.dart';

/// The only suggestions: official Stremio metadata and subtitle addons.
/// Kinora never suggests stream indexers.
const suggestedAddons = [
  (
    name: 'Cinemeta',
    url: 'https://v3-cinemeta.strem.io/manifest.json',
    detail:
        'Official Stremio addon. Catalogs and details for movies and '
        'shows.',
  ),
  (
    name: 'OpenSubtitles v3',
    url: 'https://opensubtitles-v3.strem.io/manifest.json',
    detail: 'Official Stremio addon. Subtitles in many languages.',
  ),
];

/// The addon link without anything that could be a key: host only, with
/// "/…" when the link carries a configuration.
String maskAddonUrl(Uri url) {
  final config = url.path
      .replaceFirst(RegExp(r'/manifest\.json$'), '')
      .replaceAll('/', '');
  return config.isEmpty ? url.host : '${url.host}/…';
}

/// "Catalogs, details and streams".
String addonProvides(Addon addon) {
  final r = {for (final x in addon.manifest.resources) x.name};
  final parts = [
    if (r.contains('catalog') || addon.manifest.catalogs.isNotEmpty) 'catalogs',
    if (r.contains('meta')) 'details',
    if (r.contains('stream')) 'streams',
    if (r.contains('subtitles')) 'subtitles',
  ];
  if (parts.isEmpty) return 'Nothing Kinora can use';
  final text = parts.length == 1
      ? parts.first
      : '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
  return text[0].toUpperCase() + text.substring(1);
}

/// What went wrong with an addon, in words. Never includes the URL.
String addonError(Object e) => switch (e) {
  InvalidAddonUrlException() =>
    'That isn’t an addon link. Paste the full link, usually ending in '
        'manifest.json.',
  AddonHttpException(statusCode: 404) =>
    'Nothing was found at that link. Check that it’s complete.',
  AddonHttpException(:final statusCode) =>
    'The addon answered with error $statusCode. Try again later.',
  AddonNetworkException() =>
    'Couldn’t reach the addon. Check your connection and the link.',
  AddonTimeoutException() => 'The addon took too long to answer. Try again.',
  AddonResponseException() =>
    'That link isn’t a Stremio addon, or it sent something Kinora can’t '
        'read.',
  AddonCancelledException() => 'Cancelled.',
  DebridKeyRejectedException() =>
    'Your debrid service rejected the key set in this addon. Configure the '
        'addon again and add the new link.',
  _ => 'The addon couldn’t be added. Try again.',
};

/// Health of one addon in words, and its color.
(String, Color) addonHealthText(AddonHealth? h) {
  if (h == null || h.lastCheckedAt == null) {
    return ('Not used yet', KColors.haze);
  }
  if (!h.isHealthy) {
    final why = h.lastError == null ? '' : ' ${addonError(h.lastError!)}';
    return ('Failing.$why', KColors.cut);
  }
  final ms = h.lastLatency?.inMilliseconds ?? 0;
  final secs = (ms / 1000).toStringAsFixed(1);
  if (ms >= 3000) return ('Slow, answers in $secs s', KColors.marquee);
  return ('Healthy, answers in $secs s', KColors.go);
}

/// Settings › Sources.
class SourcesPage extends ConsumerWidget {
  const SourcesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final installed = ref.watch(addonsProvider).value ?? const [];
    final missing = suggestedAddons.where(
      (s) => !installed.any((a) => a.addon.transportUrl.toString() == s.url),
    );
    return SettingsPage(
      title: 'Sources',
      intro:
          'Kinora has no movies or shows of its own. Sources are '
          'Stremio-compatible addons you add by their link. They bring '
          'catalogs, streams and subtitles.',
      children: [
        const AddAddonField(),
        const SectionTitle('Your sources'),
        const AddonList(showHealth: true),
        if (missing.isNotEmpty) ...[
          const SectionTitle('Suggestions'),
          const SuggestedAddons(),
        ],
      ],
    );
  }
}

/// Link field with Paste and Add; errors appear under it in words.
class AddAddonField extends ConsumerStatefulWidget {
  const AddAddonField({super.key});

  @override
  ConsumerState<AddAddonField> createState() => _AddAddonFieldState();
}

class _AddAddonFieldState extends ConsumerState<AddAddonField> {
  final _url = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final text = _url.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Paste an addon link first.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final a = await ref.read(addonsProvider.notifier).install(text);
      _url.clear();
      if (mounted) showNote(context, 'Added ${a.name}.');
    } on Object catch (e) {
      if (mounted) setState(() => _error = addonError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      GlassField(
        controller: _url,
        label: 'Addon link',
        hint: 'https://…/manifest.json',
        paste: true,
        keyboardType: TextInputType.url,
        onSubmitted: (_) => unawaited(_add()),
        fieldKey: const ValueKey('addon-url'),
      ),
      if (_error != null)
        Semantics(liveRegion: true, child: Note(_error!, color: KColors.cut)),
      Padding(
        padding: const EdgeInsets.fromLTRB(
          KSpace.margin,
          KSpace.x1,
          KSpace.margin,
          0,
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: GlassGroup(
            child: GlassButton(
              label: _busy ? 'Adding' : 'Add source',
              icon: Icons.add_rounded,
              prominent: true,
              onPressed: _busy ? null : () => unawaited(_add()),
            ),
          ),
        ),
      ),
    ],
  );
}

/// One-tap Cinemeta and OpenSubtitles v3.
class SuggestedAddons extends ConsumerStatefulWidget {
  const SuggestedAddons({super.key});

  @override
  ConsumerState<SuggestedAddons> createState() => _SuggestedAddonsState();
}

class _SuggestedAddonsState extends ConsumerState<SuggestedAddons> {
  final _busy = <String>{};

  Future<void> _add(String url, String name) async {
    setState(() => _busy.add(url));
    try {
      await ref.read(addonsProvider.notifier).install(url);
      if (mounted) showNote(context, 'Added $name.');
    } on Object catch (e) {
      if (mounted) showNote(context, addonError(e));
    } finally {
      if (mounted) setState(() => _busy.remove(url));
    }
  }

  @override
  Widget build(BuildContext context) {
    final installed = ref.watch(addonsProvider).value ?? const [];
    return Column(
      children: [
        for (final s in suggestedAddons)
          if (installed.any((a) => a.addon.transportUrl.toString() == s.url))
            ActionRow(
              icon: Icons.check_rounded,
              label: '${s.name} added',
              detail: s.detail,
              color: KColors.go,
              onTap: null,
            )
          else
            ActionRow(
              icon: Icons.add_circle_outline_rounded,
              label: _busy.contains(s.url) ? 'Adding ${s.name}' : s.name,
              detail: s.detail,
              onTap: _busy.contains(s.url)
                  ? null
                  : () => unawaited(_add(s.url, s.name)),
            ),
      ],
    );
  }
}

/// Installed addons: on/off, drag to reorder, swipe or long-press to remove.
class AddonList extends ConsumerStatefulWidget {
  const AddonList({super.key, this.showHealth = false});

  final bool showHealth;

  @override
  ConsumerState<AddonList> createState() => _AddonListState();
}

class _AddonListState extends ConsumerState<AddonList> {
  // Hidden at once so a dismissed row leaves the tree before the reload.
  final _removed = <int>{};

  Future<bool> _confirmRemove(InstalledAddon a) => confirmAction(
    context,
    title: 'Remove ${a.name}?',
    message:
        'Its catalogs, streams and subtitles disappear from Kinora. You can '
        'add it again with its link.',
    action: 'Remove',
  );

  Future<void> _remove(InstalledAddon a) async {
    setState(() => _removed.add(a.id));
    await ref.read(addonsProvider.notifier).remove(a.id);
    if (mounted) showNote(context, 'Removed ${a.name}.');
  }

  Future<void> _menu(InstalledAddon a) async {
    final remove = await showGlassSheet<bool>(
      context,
      builder: (sheet) => Column(
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
            child: Text(a.name, style: KType.h2),
          ),
          SheetAction(
            icon: Icons.delete_outline_rounded,
            label: 'Remove source',
            color: KColors.cut,
            onTap: () => Navigator.pop(sheet, true),
          ),
        ],
      ),
    );
    if (remove == true && mounted && await _confirmRemove(a)) {
      await _remove(a);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(addonsProvider);
    final list = [
      for (final a in async.value ?? const <InstalledAddon>[])
        if (!_removed.contains(a.id)) a,
    ];
    if (async.isLoading && list.isEmpty) return const SizedBox(height: 56);
    if (list.isEmpty) {
      return const Note(
        'No sources yet. Add one by its link, or pick a suggestion.',
      );
    }
    final health = widget.showHealth
        ? ref.read(aggregatorProvider).health
        : const <Uri, AddonHealth>{};
    return ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      proxyDecorator: (child, _, _) =>
          Material(color: KColors.seat, child: child),
      onReorderItem: (from, to) =>
          unawaited(ref.read(addonsProvider.notifier).reorder(from, to)),
      children: [
        for (final (i, a) in list.indexed)
          Dismissible(
            key: ValueKey(a.id),
            direction: DismissDirection.endToStart,
            confirmDismiss: (_) => _confirmRemove(a),
            onDismissed: (_) => unawaited(_remove(a)),
            background: const ColoredBox(
              color: Color(0x33FF6B6B),
              child: Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: EdgeInsets.only(right: KSpace.margin),
                  child: Icon(Icons.delete_outline_rounded, color: KColors.cut),
                ),
              ),
            ),
            child: _AddonRow(
              index: i,
              addon: a,
              health: widget.showHealth
                  ? addonHealthText(health[a.addon.transportUrl])
                  : null,
              onLongPress: () => unawaited(_menu(a)),
              onRemove: () async {
                if (await _confirmRemove(a)) await _remove(a);
              },
              onToggle: (v) => unawaited(
                ref.read(addonsProvider.notifier).setEnabled(a.id, enabled: v),
              ),
            ),
          ),
      ],
    );
  }
}

class _AddonRow extends StatelessWidget {
  const _AddonRow({
    required this.index,
    required this.addon,
    required this.health,
    required this.onLongPress,
    required this.onRemove,
    required this.onToggle,
  });

  final int index;
  final InstalledAddon addon;
  final (String, Color)? health;
  final VoidCallback onLongPress;
  final VoidCallback onRemove;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final provides = addonProvides(addon.addon);
    final where = maskAddonUrl(addon.addon.transportUrl);
    return Semantics(
      customSemanticsActions: {
        const CustomSemanticsAction(label: 'Remove source'): onRemove,
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: onLongPress,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              KSpace.margin,
              KSpace.x3,
              KSpace.x2,
              KSpace.x3,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    label: [
                      addon.name,
                      provides,
                      where,
                      if (health != null) health!.$1,
                    ].join('. '),
                    excludeSemantics: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          addon.name,
                          style: KType.title.copyWith(
                            color: addon.enabled ? KColors.lamp : KColors.reel,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          provides,
                          style: KType.label.copyWith(color: KColors.haze),
                        ),
                        Text(
                          where,
                          style: KType.small.copyWith(color: KColors.reel),
                        ),
                        if (health != null)
                          Text(
                            health!.$1,
                            style: KType.small.copyWith(color: health!.$2),
                          ),
                      ],
                    ),
                  ),
                ),
                Semantics(
                  label: 'Use ${addon.name}',
                  child: Switch(value: addon.enabled, onChanged: onToggle),
                ),
                ReorderableDragStartListener(
                  index: index,
                  child: const ExcludeSemantics(
                    child: SizedBox.square(
                      dimension: 48,
                      child: Icon(
                        Icons.drag_handle_rounded,
                        color: KColors.reel,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
