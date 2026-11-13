import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stremio/stremio.dart';

import '../../services/sources.dart';
import '../home/home_feed.dart';
import '../../ui/layout.dart';
import '../../ui/tint.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/pointer.dart';

/// A catalog Discovery can browse: listed by an addon, needing nothing but
/// (optionally) a genre.
typedef BrowseSource = ({Addon addon, ManifestCatalog catalog});

/// Every browsable catalog of the enabled sources, grouped by type (movies
/// first, then shows, then the rest).
final browseSourcesProvider = FutureProvider<Map<String, List<BrowseSource>>>((
  ref,
) async {
  final addons = await ref.watch(enabledAddonsProvider.future);
  final byType = <String, List<BrowseSource>>{};
  for (final a in addons) {
    for (final c in a.manifest.catalogs) {
      if (c.requiredExtras.every((e) => e.name == 'genre')) {
        (byType[c.type] ??= []).add((addon: a, catalog: c));
      }
    }
  }
  int rank(String t) => switch (t) {
    'movie' => 0,
    'series' => 1,
    _ => 2,
  };
  return Map.fromEntries(
    byType.entries.toList()..sort((a, b) => rank(a.key) - rank(b.key)),
  );
});

/// The genres a catalog offers, and whether one must be chosen.
({List<String> options, bool required}) genresOf(ManifestCatalog c) {
  final g = c.extra.where((e) => e.name == 'genre').firstOrNull;
  return (options: g?.options ?? const [], required: g?.isRequired ?? false);
}

/// One page more of a catalog: what's new in [next] (each title once).
/// Paging stops at an empty page or one with nothing new.
({List<MetaPreview> items, bool more}) mergePage(
  List<MetaPreview> have,
  List<MetaPreview> next,
) {
  final seen = {for (final m in have) m.id};
  final fresh = [
    for (final m in next)
      if (seen.add(m.id)) m,
  ];
  return (items: [...have, ...fresh], more: fresh.isNotEmpty);
}

/// What a browse shows so far.
final class BrowsePage {
  const BrowsePage(this.items, {this.more = false, this.loadingMore = false});

  final List<MetaPreview> items;

  /// The catalog pages (`skip`) and the last page brought something new.
  final bool more;
  final bool loadingMore;
}

/// Which catalog, and genre, to browse (strings: providers compare keys).
typedef BrowseKey = ({
  String addon,
  String type,
  String catalog,
  String? genre,
});

BrowseKey browseKey(BrowseSource s, String? genre) => (
  addon: s.addon.transportUrl.toString(),
  type: s.catalog.type,
  catalog: s.catalog.id,
  genre: genre,
);

final browseProvider = AsyncNotifierProvider.autoDispose
    .family<BrowseNotifier, BrowsePage, BrowseKey>(BrowseNotifier.new);

class BrowseNotifier extends AsyncNotifier<BrowsePage> {
  BrowseNotifier(this.key);

  final BrowseKey key;
  late BrowseSource _source;

  Future<List<MetaPreview>> _fetch(int skip) => ref
      .read(addonClientProvider)
      .catalog(
        _source.addon,
        key.type,
        key.catalog,
        extra: {'genre': ?key.genre, if (skip > 0) 'skip': '$skip'},
      )
      .timeout(const Duration(seconds: 20));

  @override
  Future<BrowsePage> build() async {
    final sources = await ref.watch(browseSourcesProvider.future);
    _source = (sources[key.type] ?? const []).firstWhere(
      (s) =>
          s.addon.transportUrl.toString() == key.addon &&
          s.catalog.id == key.catalog,
    );
    // Home loads this catalog's first page anyway: no second request.
    // (Its first answer comes within a moment; past that, fetch. Listened
    // to while waiting: Riverpod pauses providers nobody listens to.)
    final keep = ref.listen(homeRowsProvider, (_, _) {});
    HomeRows rows;
    try {
      rows =
          ref.read(homeRowsProvider).value ??
          await ref
              .read(homeRowsProvider.future)
              .timeout(const Duration(seconds: 3));
    } on Object {
      rows = const HomeRows([]);
    } finally {
      keep.close();
    }
    final home = rows.rows
        .where(
          (r) =>
              r.addon.transportUrl.toString() == key.addon &&
              r.type == key.type &&
              r.catalog.id == key.catalog,
        )
        .firstOrNull;
    final items = key.genre == null && home != null
        ? home.items
        : await _fetch(0);
    return BrowsePage(
      mergePage(const [], items).items,
      more: _source.catalog.supportsExtra('skip') && items.isNotEmpty,
    );
  }

  /// The next page, when there is one (one request at a time).
  Future<void> loadMore() async {
    final page = state.value;
    if (page == null || !page.more || page.loadingMore) return;
    state = AsyncData(BrowsePage(page.items, more: true, loadingMore: true));
    try {
      final next = mergePage(page.items, await _fetch(page.items.length));
      state = AsyncData(BrowsePage(next.items, more: next.more));
    } on Object {
      // shortcut: a failed page ends paging for this visit; a reload retries.
      state = AsyncData(BrowsePage(page.items));
    }
  }
}

/// A choice chip: a field at rest, the accent's tint and edge when chosen.
class ChoiceChipButton extends StatelessWidget {
  const ChoiceChipButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = KinoraTint.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: PointerFocus(
        onActivate: onTap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KRadius.button),
        ),
        builder: (context, hovered) => GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: KMotion.fast,
            height: KLayout.isWide(context) ? 32 : 34,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? accent.withValues(alpha: 0.16)
                  : hovered
                  ? KColors.raised
                  : KColors.panel,
              border: Border.all(
                color: selected
                    ? accent.withValues(alpha: 0.45)
                    : KColors.fieldEdge,
              ),
              borderRadius: BorderRadius.circular(KRadius.button),
            ),
            child: Text(
              label,
              maxLines: 1,
              style: KType.label.copyWith(
                color: selected ? KColors.onLime : KColors.body,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A row of chips that scrolls sideways from the page edge.
class ChipRow extends StatelessWidget {
  const ChipRow({super.key, required this.children, required this.gutter});

  final List<Widget> children;
  final double gutter;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: KLayout.isWide(context) ? 32 : 34,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.symmetric(horizontal: gutter),
      itemCount: children.length,
      separatorBuilder: (_, _) => const SizedBox(width: KSpace.x2),
      itemBuilder: (_, i) => children[i],
    ),
  );
}

/// Movies, Shows, ...: one box, the chosen one tinted.
class TypeSwitch extends StatelessWidget {
  const TypeSwitch({
    super.key,
    required this.types,
    required this.selected,
    required this.onSelect,
  });

  final List<String> types;
  final String selected;
  final ValueChanged<String> onSelect;

  static String labelOf(String type) => switch (type) {
    'movie' => 'Movies',
    'series' => 'Shows',
    'anime' => 'Anime',
    'tv' => 'TV channels',
    'channel' => 'Channels',
    _ => '${type[0].toUpperCase()}${type.substring(1)}',
  };

  @override
  Widget build(BuildContext context) {
    final accent = KinoraTint.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: KColors.panel,
        border: Border.all(color: KColors.edge),
        borderRadius: BorderRadius.circular(KRadius.button),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final t in types)
            Semantics(
              button: true,
              selected: t == selected,
              label: labelOf(t),
              excludeSemantics: true,
              child: PointerFocus(
                onActivate: () => onSelect(t),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                builder: (context, hovered) => GestureDetector(
                  onTap: () => onSelect(t),
                  child: AnimatedContainer(
                    duration: KMotion.fast,
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: t == selected
                          ? accent.withValues(alpha: 0.16)
                          : hovered
                          ? KColors.raised
                          : const Color(0x00000000),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      labelOf(t),
                      style: KType.label.copyWith(
                        color: t == selected ? KColors.onLime : KColors.haze,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Keeps asking for more while the grid's end is in sight.
void maybeLoadMore(WidgetRef ref, BrowseKey key, ScrollMetrics m) {
  if (m.axis == Axis.vertical && m.extentAfter < 600) {
    unawaited(ref.read(browseProvider(key).notifier).loadMore());
  }
}
