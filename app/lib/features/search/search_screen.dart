import 'dart:async';

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
  final _focus = FocusNode();
  Timer? _debounce;
  String _query = '';
  bool _visible = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Tabs stay alive offstage with tickers off: focus each time the tab opens.
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible && !_visible && _controller.text.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
    _visible = visible;
  }

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
    if (q.isEmpty) return _Recents(onPick: _useRecent);
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

class _Recents extends ConsumerWidget {
  const _Recents({required this.onPick});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recents = ref.watch(recentSearchesProvider).value ?? const [];
    if (recents.isEmpty) {
      return const EmptyState(
        icon: Icons.search_rounded,
        title: 'Find something to watch',
        message:
            'Search your sources by title. Paste a magnet link or a video '
            'link to play it right away.',
      );
    }
    final store = ref.read(searchHistoryProvider);
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.only(
        top: KSpace.x3,
        bottom: AppShell.bottomInset(context),
      ),
      itemCount: recents.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(
              KSpace.margin,
              0,
              KSpace.margin,
              KSpace.x2,
            ),
            child: Semantics(
              header: true,
              child: Text('Recent searches', style: KType.h2),
            ),
          );
        }
        final q = recents[i - 1];
        return Row(
          children: [
            Expanded(
              child: Pressable(
                label: 'Search for $q',
                onTap: () => onPick(q),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Padding(
                    padding: const EdgeInsets.only(left: KSpace.margin),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.history_rounded,
                          color: KColors.reel,
                          size: 20,
                        ),
                        const SizedBox(width: KSpace.x3),
                        Expanded(
                          child: Text(
                            q,
                            style: KType.body,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Semantics(
              button: true,
              label: 'Remove $q from recent searches',
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => unawaited(store.remove(q)),
                child: const SizedBox.square(
                  dimension: 48,
                  child: Icon(
                    Icons.close_rounded,
                    color: KColors.reel,
                    size: 20,
                  ),
                ),
              ),
            ),
            const SizedBox(width: KSpace.margin - 14),
          ],
        );
      },
    );
  }
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
              child: GlassGroup(
                child: Glass(
                  tintStrength: 0.42,
                  child: Center(
                    child: Icon(
                      Icons.play_arrow_rounded,
                      color: KColors.lamp,
                      size: 28,
                    ),
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

class _Results extends ConsumerWidget {
  const _Results({required this.query, required this.onOpen});

  final String query;
  final ValueChanged<MetaPreview> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              padding: const EdgeInsets.fromLTRB(
                KSpace.margin,
                KSpace.x3,
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
  const _PosterGrid({required this.items, required this.onOpen});

  final List<MetaPreview> items;
  final ValueChanged<MetaPreview> onOpen;

  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
    builder: (context, constraints) {
      final g = _gridMetrics(context, constraints.crossAxisExtent);
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(
          KSpace.margin,
          0,
          KSpace.margin,
          KSpace.section,
        ),
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
