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
import '../../ui/tokens.dart';
import '../../ui/widgets/artwork.dart';
import '../../ui/widgets/media.dart';
import '../../ui/widgets/states.dart';
import '../home/home_feed.dart';
import 'search_model.dart';

/// Search: a glass field, recent searches, results grouped by type, and
/// "Play this link" for pasted magnets and video URLs.
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
  void dispose() {
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
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              KSpace.margin,
              top + KSpace.x3,
              KSpace.margin,
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
    if (q.isEmpty) return _Idle(onPick: _useRecent);
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
  Widget build(BuildContext context) => GlassGroup(
    child: Glass(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Row(
          children: [
            const SizedBox(width: KSpace.x4),
            const Icon(Icons.search_rounded, color: KColors.haze, size: 22),
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
                  hintText: 'Movies, shows or a link',
                  hintStyle: KType.body.copyWith(color: KColors.reel),
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
    ),
  );
}

/// Idle Search: recent searches as capsules, then what's popular in your
/// first catalog, to browse without typing.
class _Idle extends ConsumerWidget {
  const _Idle({required this.onPick});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recents = ref.watch(recentSearchesProvider).value ?? const [];
    final row = ref.watch(homeRowsProvider).value?.rows.firstOrNull;
    final popular = row?.items.take(12) ?? const <MetaPreview>[];
    if (recents.isEmpty && popular.isEmpty) {
      return const EmptyState(
        icon: Icons.search_rounded,
        title: 'Find something to watch',
        message:
            'Search your sources by title. Paste a magnet link or a video '
            'link to play it right away.',
      );
    }
    final store = ref.read(searchHistoryProvider);
    final capsuleHeight = math.max(
      48.0,
      MediaQuery.textScalerOf(context).scale(22) + 26,
    );
    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        if (recents.isNotEmpty) ...[
          const _Header('Recent searches'),
          SliverToBoxAdapter(
            child: SizedBox(
              height: capsuleHeight,
              child: GlassGroup(
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: KSpace.margin,
                  ),
                  itemCount: recents.length,
                  separatorBuilder: (_, _) => const SizedBox(width: KSpace.x2),
                  itemBuilder: (context, i) => _RecentCapsule(
                    query: recents[i],
                    onTap: () => onPick(recents[i]),
                    onRemove: () => unawaited(store.remove(recents[i])),
                  ),
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: KSpace.section)),
        ],
        if (popular.isNotEmpty) ...[
          // The source's own name for it ("Top anime"), not a guess.
          _Header(row!.title),
          _PosterGrid(
            items: popular.toList(),
            onOpen: (m) => openTitle(context, type: m.type, id: m.id),
          ),
        ],
        SliverToBoxAdapter(
          child: SizedBox(height: AppShell.bottomInset(context)),
        ),
      ],
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
      child: Semantics(header: true, child: Text(text, style: KType.h2)),
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

/// Columns and tile extent for a poster grid with two caption lines.
({int columns, double width, double extent}) _gridMetrics(
  BuildContext context,
  double crossAxisExtent,
) {
  final columns = ((crossAxisExtent - 2 * KSpace.margin) / 128).floor().clamp(
    3,
    6,
  );
  final width =
      (crossAxisExtent - 2 * KSpace.margin - (columns - 1) * KSpace.x3) /
      columns;
  final scaler = MediaQuery.textScalerOf(context);
  return (
    columns: columns,
    width: width,
    extent: width * 1.5 + 6 + scaler.scale(18) + scaler.scale(16) + 4,
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
            mainAxisSpacing: KSpace.x3,
            crossAxisSpacing: KSpace.x3,
            mainAxisExtent: g.extent,
          ),
          itemCount: items.length,
          itemBuilder: (context, i) {
            final m = items[i];
            return Pressable(
              label: [m.name, ?m.releaseInfo].join(', '),
              onTap: () => onOpen(m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Artwork(
                    url: m.poster,
                    fallbackText: m.name,
                    radius: KRadius.poster,
                    aspectRatio: 2 / 3,
                    memCacheWidth: decodeWidth(context, g.width),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    m.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: contentDir(m.name),
                    style: KType.label.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (m.releaseInfo != null)
                    Text(
                      m.releaseInfo!,
                      maxLines: 1,
                      style: KType.tabular(KType.small),
                    ),
                ],
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
    label: 'Searching',
    child: CustomScrollView(
      physics: const NeverScrollableScrollPhysics(),
      slivers: [
        SliverLayoutBuilder(
          builder: (context, constraints) {
            final g = _gridMetrics(context, constraints.crossAxisExtent);
            return SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                KSpace.margin,
                KSpace.x3,
                KSpace.margin,
                0,
              ),
              sliver: SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: g.columns,
                  mainAxisSpacing: KSpace.x3,
                  crossAxisSpacing: KSpace.x3,
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
        ),
      ],
    ),
  );
}
