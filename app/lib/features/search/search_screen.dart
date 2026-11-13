import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:stremio/stremio.dart';

import '../../app/router.dart';
import '../../app/shell.dart';
import '../../services/play_request.dart';
import '../../services/sources.dart';
import '../../ui/glass.dart';
import '../../ui/tint.dart';
import '../../ui/layout.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/artwork.dart';
import '../../ui/widgets/media.dart';
import '../../ui/widgets/chips.dart';
import '../../ui/widgets/states.dart';
import '../home/home_feed.dart';
import '../../ui/widgets/page_header.dart';
import '../home/rows.dart' show HoverArt;
import 'discovery.dart';
import 'search_model.dart';

/// Discovery: browse your sources' catalogs by type and genre, or search
/// them (results grouped by type); a pasted magnet or video link plays.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  static const debounce = Duration(milliseconds: 350);

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  // The keyboard opens only when the field is tapped: idle Search is a
  // place to browse, not a keyboard over the tab bar.
  final _focus = FocusNode();
  Timer? _debounce;
  String _query = '';

  @override
  void initState() {
    super.initState();
    focusSearch.addListener(_takeKeyboard);
  }

  /// The window bar's search field or Ctrl+K: type straight away.
  void _takeKeyboard() {
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _focus.requestFocus(),
      );
    }
  }

  @override
  void dispose() {
    focusSearch.removeListener(_takeKeyboard);
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(SearchScreen.debounce, () => _search(text));
  }

  void _search(String text) {
    _debounce?.cancel();
    if (mounted) setState(() => _query = text.trim());
  }

  void _remember(String query) {
    if (query.length >= 2 && parsePlayLink(query) == null) {
      unawaited(ref.read(searchHistoryProvider).add(query));
    }
  }

  void _submit(String text) {
    _search(text);
    _remember(text.trim());
  }

  void _useRecent(String query) {
    _controller.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
    _focus.unfocus();
    _submit(query);
  }

  void _clear() {
    _controller.clear();
    _search('');
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    // Back online: searches that failed offline run again.
    ref.listen(onlineProvider, (prev, next) {
      if (next.value == true && prev?.value == false) {
        ref.invalidate(searchProvider);
      }
    });
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PageHeader(title: 'Discovery'),
          Padding(
            padding: EdgeInsets.fromLTRB(
              KSpace.margin,
              PageHeader.gap,
              // (A wide window: a field, not a bar across it.)
              KSpace.margin + KLayout.rest(context, 720),
              KSpace.x3,
            ),
            child: _SearchField(
              controller: _controller,
              focus: _focus,
              onChanged: _onChanged,
              onSubmitted: _submit,
              onClear: _clear,
            ),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    final q = _query;
    if (q.isEmpty) return _Browse(onPick: _useRecent);
    final link = parsePlayLink(q);
    if (link != null) return _LinkResult(link: link);
    return _Results(
      query: q,
      onOpen: (m) {
        _remember(q);
        openTitle(context, type: m.type, id: m.id);
      },
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focus,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: KColors.panel,
      border: Border.all(color: KColors.fieldEdge),
      borderRadius: BorderRadius.circular(KRadius.button),
    ),
    child: ConstrainedBox(
      constraints: BoxConstraints(minHeight: KLayout.isWide(context) ? 44 : 48),
      child: Row(
        children: [
          const SizedBox(width: KSpace.x3),
          const Icon(Icons.search_rounded, color: KColors.muted, size: 20),
          const SizedBox(width: KSpace.x2),
          Expanded(
            child: TextField(
              key: const ValueKey('search-field'),
              controller: controller,
              focusNode: focus,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              style: KType.body,
              cursorColor: KinoraTint.of(context),
              keyboardAppearance: Brightness.dark,
              textInputAction: TextInputAction.search,
              autocorrect: false,
              inputFormatters: [LengthLimitingTextInputFormatter(2048)],
              decoration: InputDecoration.collapsed(
                hintText: 'Search movies, shows or paste a link…',
                hintStyle: KType.body.copyWith(color: KColors.muted),
              ),
            ),
          ),
          ValueListenableBuilder(
            valueListenable: controller,
            builder: (_, value, _) => value.text.isEmpty
                ? const SizedBox(width: KSpace.x3)
                : Semantics(
                    button: true,
                    label: 'Clear search',
                    excludeSemantics: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onClear,
                      child: const SizedBox.square(
                        dimension: 48,
                        child: Icon(
                          Icons.cancel_rounded,
                          color: KColors.haze,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    ),
  );
}

/// Idle Discovery: recent searches as capsules, then browsing: a type,
/// a catalog, a genre, and the catalog's titles in a grid that loads more
/// as you near its end.
class _Browse extends ConsumerStatefulWidget {
  const _Browse({required this.onPick});

  final ValueChanged<String> onPick;

  @override
  ConsumerState<_Browse> createState() => _BrowseState();
}

class _BrowseState extends ConsumerState<_Browse> {
  String? _type;
  int _catalog = 0;
  String? _genre;

  @override
  Widget build(BuildContext context) {
    final recents = ref.watch(recentSearchesProvider).value ?? const [];
    final sources = ref.watch(browseSourcesProvider);
    final byType = sources.value;
    final capsuleHeight = math.max(
      48.0,
      MediaQuery.textScalerOf(context).scale(22) + 26,
    );
    const gap = SliverToBoxAdapter(child: SizedBox(height: KSpace.x3));
    // Recent searches show at once; browsing follows when sources answer.
    final recentSlivers = [
      gap,
      if (recents.isNotEmpty) ...[
        const _Header('Recent searches'),
        SliverToBoxAdapter(
          child: SizedBox(
            height: capsuleHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: KSpace.margin),
              itemCount: recents.length,
              separatorBuilder: (_, _) => const SizedBox(width: KSpace.x2),
              itemBuilder: (context, i) => _RecentCapsule(
                query: recents[i],
                onTap: () => widget.onPick(recents[i]),
                onRemove: () => unawaited(
                  ref.read(searchHistoryProvider).remove(recents[i]),
                ),
              ),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: KSpace.section)),
      ],
    ];
    if (byType == null || byType.isEmpty) {
      return CustomScrollView(
        slivers: [
          ...recentSlivers,
          if (byType == null && sources.hasError)
            SliverToBoxAdapter(
              child: ErrorState(
                message: friendlyError(sources.error!),
                onRetry: () => ref.invalidate(addonsProvider),
              ),
            )
          else if (byType == null)
            const _SkeletonSliver()
          else
            SliverToBoxAdapter(
              child: EmptyState(
                icon: Icons.explore_outlined,
                title: 'Nothing to browse yet',
                message:
                    'Add a source with catalogs, like Cinemeta, to browse '
                    'movies and shows. Or search, or paste a magnet or video '
                    'link to play it.',
                actionLabel: 'Add a source',
                onAction: () => context.go('/settings/sources'),
              ),
            ),
        ],
      );
    }
    final type = byType.containsKey(_type) ? _type! : byType.keys.first;
    final list = byType[type]!;
    final source = list[_catalog.clamp(0, list.length - 1)];
    final genres = genresOf(source.catalog);
    final genre = genres.options.contains(_genre)
        ? _genre
        : genres.required
        ? genres.options.firstOrNull
        : null;
    final key = browseKey(source, genre);
    final page = ref.watch(browseProvider(key));
    String name(BrowseSource s) {
      final n = s.catalog.name?.trim().isNotEmpty ?? false
          ? s.catalog.name!.trim()
          : s.catalog.id;
      // The same name from two sources: say whose.
      return list.where((o) => o.catalog.name == s.catalog.name).length > 1
          ? '$n · ${s.addon.manifest.name}'
          : n;
    }

    final items = page.value?.items ?? const <MetaPreview>[];
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        maybeLoadMore(ref, key, n.metrics);
        return false;
      },
      child: CustomScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          ...recentSlivers,
          if (byType.length > 1) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: KSpace.margin),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TypeSwitch(
                    types: byType.keys.toList(),
                    selected: type,
                    onSelect: (t) => setState(() {
                      _type = t;
                      _catalog = 0;
                      _genre = null;
                    }),
                  ),
                ),
              ),
            ),
            gap,
          ],
          if (list.length > 1) ...[
            SliverToBoxAdapter(
              child: ChipRow(
                gutter: KSpace.margin,
                children: [
                  for (final (i, s) in list.indexed)
                    ChoiceChipButton(
                      label: name(s),
                      selected: s == source,
                      onTap: () => setState(() {
                        _catalog = i;
                        _genre = null;
                      }),
                    ),
                ],
              ),
            ),
            gap,
          ],
          if (genres.options.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: ChipRow(
                gutter: KSpace.margin,
                children: [
                  if (!genres.required)
                    ChoiceChipButton(
                      label: 'All',
                      selected: genre == null,
                      onTap: () => setState(() => _genre = null),
                    ),
                  for (final g in genres.options)
                    ChoiceChipButton(
                      label: g,
                      selected: g == genre,
                      onTap: () => setState(() => _genre = g),
                    ),
                ],
              ),
            ),
            gap,
          ],
          const SliverToBoxAdapter(child: SizedBox(height: KSpace.x2)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                KSpace.margin,
                0,
                KSpace.margin,
                KSpace.x3,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: Semantics(
                      header: true,
                      child: Text(
                        [name(source), ?genre].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: KType.h2.copyWith(color: KColors.title),
                      ),
                    ),
                  ),
                  if (items.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    Text(
                      '${items.length}${page.value?.more ?? false ? '+' : ''} '
                      'TITLES',
                      style: KType.meta,
                    ),
                  ],
                ],
              ),
            ),
          ),
          switch (page) {
            AsyncValue(value: final p?) when p.items.isEmpty =>
              const SliverToBoxAdapter(
                child: EmptyState(
                  icon: Icons.explore_outlined,
                  title: 'Nothing here',
                  message: 'This catalog has no titles for that choice.',
                ),
              ),
            AsyncValue(value: final p?) => _PosterGrid(
              items: p.items,
              onOpen: (m) => openTitle(context, type: m.type, id: m.id),
              bottom: p.loadingMore ? KSpace.x4 : KSpace.section,
            ),
            AsyncError(:final error) => SliverToBoxAdapter(
              child: ErrorState(
                message: friendlyError(error),
                onRetry: () => ref.invalidate(browseProvider(key)),
              ),
            ),
            _ => const _SkeletonSliver(),
          },
          if (page.value?.loadingMore ?? false)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(bottom: KSpace.section),
                child: Center(
                  child: SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: SizedBox(height: AppShell.bottomInset(context)),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => SliverPadding(
    padding: const EdgeInsets.fromLTRB(
      KSpace.margin,
      0,
      KSpace.margin,
      KSpace.x3,
    ),
    sliver: SliverToBoxAdapter(
      child: Semantics(
        header: true,
        child: Text(text, style: KType.h2.copyWith(color: KColors.title)),
      ),
    ),
  );
}

/// A recent search: tap runs it, × forgets it.
class _RecentCapsule extends StatelessWidget {
  const _RecentCapsule({
    required this.query,
    required this.onTap,
    required this.onRemove,
  });

  final String query;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Glass(
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          label: 'Search for $query',
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(start: KSpace.x4),
              child: Center(
                widthFactor: 1,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 200),
                  child: Text(
                    query,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: contentDir(query),
                    style: KType.label.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ),
        ),
        Semantics(
          button: true,
          label: 'Remove $query from recent searches',
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onRemove,
            child: const SizedBox(
              width: 44,
              child: Icon(Icons.close_rounded, color: KColors.haze, size: 18),
            ),
          ),
        ),
      ],
    ),
  );
}

class _LinkResult extends StatelessWidget {
  const _LinkResult({required this.link});

  final PlayLink link;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.symmetric(
      horizontal: KSpace.margin,
      vertical: KSpace.x3,
    ),
    children: [
      Pressable(
        label: 'Play this link, ${link.name}',
        onTap: () => openPlayer(
          context,
          PlayRequest(
            type: 'movie',
            mediaId: link.url,
            videoId: link.url,
            title: link.name,
          ),
        ),
        child: Row(
          children: [
            const SizedBox.square(
              dimension: 56,
              child: LitCapsule(
                shape: CircleBorder(),
                child: Center(
                  child: Icon(
                    Icons.play_arrow_rounded,
                    color: KColors.blackout,
                    size: 28,
                  ),
                ),
              ),
            ),
            const SizedBox(width: KSpace.x4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Play this link', style: KType.title),
                  Text(
                    link.name,
                    style: KType.label.copyWith(color: KColors.haze),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _Results extends ConsumerStatefulWidget {
  const _Results({required this.query, required this.onOpen});

  final String query;
  final ValueChanged<MetaPreview> onOpen;

  @override
  ConsumerState<_Results> createState() => _ResultsState();
}

class _ResultsState extends ConsumerState<_Results> {
  /// Groups opened past their first two rows.
  final _all = <String>{};

  static const _cap = 6;

  @override
  void didUpdateWidget(_Results old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) _all.clear();
  }

  @override
  Widget build(BuildContext context) {
    final query = widget.query;
    final onOpen = widget.onOpen;
    final noSources = ref.watch(
      enabledAddonsProvider.select((a) => a.value?.isEmpty ?? false),
    );
    if (noSources) {
      return EmptyState(
        title: 'No sources yet',
        message: 'Add a source to search movies and shows.',
        actionLabel: 'Add a source',
        onAction: () => context.go('/settings/sources'),
      );
    }
    final groups = ref.watch(searchGroupsProvider(query));
    final bottom = AppShell.bottomInset(context);
    return switch (groups) {
      AsyncValue(value: []) when !groups.isLoading => EmptyState(
        title: 'No matches',
        message:
            'Nothing in your sources matches “$query”. Check the spelling, '
            'or try the original title.',
      ),
      AsyncValue(:final value?) => CustomScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          for (final g in value) ...[
            SliverPadding(
              // The first heading gets room from the search field above.
              padding: EdgeInsets.fromLTRB(
                KSpace.margin,
                identical(g, value.first) ? KSpace.x3 : 0,
                KSpace.margin,
                KSpace.x3,
              ),
              sliver: SliverToBoxAdapter(
                child: Semantics(
                  header: true,
                  label: '${g.label}, ${g.items.length} results',
                  excludeSemantics: true,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: g.label, style: KType.h2),
                        TextSpan(
                          text: '  ${g.items.length}',
                          style: KType.tabular(
                            KType.label.copyWith(color: KColors.haze),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (g.items.length > _cap && !_all.contains(g.label)) ...[
              _PosterGrid(
                items: g.items.take(_cap).toList(),
                onOpen: onOpen,
                bottom: KSpace.x4,
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  KSpace.margin,
                  0,
                  KSpace.margin,
                  KSpace.section,
                ),
                sliver: SliverToBoxAdapter(
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: GlassGroup(
                      child: GlassButton(
                        label: 'Show all ${g.items.length}',
                        semanticLabel:
                            'Show all ${g.items.length} ${g.label.toLowerCase()}',
                        onPressed: () => setState(() => _all.add(g.label)),
                      ),
                    ),
                  ),
                ),
              ),
            ] else
              _PosterGrid(items: g.items, onOpen: onOpen),
          ],
          SliverToBoxAdapter(child: SizedBox(height: bottom)),
        ],
      ),
      AsyncError(:final error) => ErrorState(
        message: friendlyError(error),
        onRetry: () => ref.invalidate(searchProvider(query)),
      ),
      _ => const _GridSkeleton(),
    };
  }
}

/// Columns and tile extent for a poster grid with two caption lines: a
/// wide window fits tiles of at least 140 px; a phone shows three (more on
/// a wide one).
({int columns, double width, double extent, double gap}) _gridMetrics(
  BuildContext context,
  double crossAxisExtent,
) {
  final wide = KLayout.isWide(context);
  final gap = wide ? 16.0 : 12.0;
  final room = crossAxisExtent - 2 * KSpace.margin;
  final columns = ((room + gap) / ((wide ? 140 : 108) + gap)).floor().clamp(
    wide ? 2 : 3,
    12,
  );
  final width = (room - (columns - 1) * gap) / columns;
  final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);
  return (
    columns: columns,
    width: width,
    gap: gap,
    extent: width * 1.5 + 8 + scaler.scale(20) + 2 + scaler.scale(14) + 2,
  );
}

class _PosterGrid extends StatelessWidget {
  const _PosterGrid({
    required this.items,
    required this.onOpen,
    this.bottom = KSpace.section,
  });

  final List<MetaPreview> items;
  final ValueChanged<MetaPreview> onOpen;
  final double bottom;

  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
    builder: (context, constraints) {
      final g = _gridMetrics(context, constraints.crossAxisExtent);
      return SliverPadding(
        padding: EdgeInsets.fromLTRB(KSpace.margin, 0, KSpace.margin, bottom),
        sliver: SliverGrid.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: g.columns,
            mainAxisSpacing: g.gap,
            crossAxisSpacing: g.gap,
            mainAxisExtent: g.extent,
          ),
          itemCount: items.length,
          itemBuilder: (context, i) {
            final m = items[i];
            return MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.3,
              child: Pressable(
                plain: true,
                label: [m.name, ?m.releaseInfo].join(', '),
                onTap: () => onOpen(m),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    HoverArt(
                      child: Artwork(
                        url: m.poster,
                        fallbackText: m.name,
                        radius: KRadius.poster,
                        aspectRatio: 2 / 3,
                        memCacheWidth: decodeWidth(context, g.width),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      m.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: contentDir(m.name),
                      style: KType.title,
                    ),
                    if (m.releaseInfo != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        m.releaseInfo!.toUpperCase(),
                        maxLines: 1,
                        style: KType.meta,
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      );
    },
  );
}

class _GridSkeleton extends StatelessWidget {
  const _GridSkeleton();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading',
    child: const CustomScrollView(
      physics: NeverScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: SizedBox(height: KSpace.x3)),
        _SkeletonSliver(),
      ],
    ),
  );
}

/// Two rows of poster-shaped placeholders, the grid's own geometry.
class _SkeletonSliver extends StatelessWidget {
  const _SkeletonSliver();

  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
    builder: (context, constraints) {
      final g = _gridMetrics(context, constraints.crossAxisExtent);
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: KSpace.margin),
        sliver: SliverGrid.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: g.columns,
            mainAxisSpacing: g.gap,
            crossAxisSpacing: g.gap,
            mainAxisExtent: g.extent,
          ),
          itemCount: g.columns * 2,
          itemBuilder: (_, _) => Align(
            alignment: Alignment.topCenter,
            child: LoadingBlock(height: g.width * 1.5),
          ),
        ),
      );
    },
  );
}
