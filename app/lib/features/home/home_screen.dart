import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:stremio/stremio.dart';

import '../../app/shell.dart';
import '../../services/sources.dart';
import '../../services/tmdb.dart';
import '../../ui/glass.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/media.dart';
import '../../ui/widgets/states.dart';
import '../cast/cast_picker.dart';
import 'billboard.dart';
import 'home_feed.dart';
import 'rows.dart';

/// Home: a billboard, then Continue watching, New episodes, My list and
/// every catalog as it arrives.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  static void _addSource(BuildContext context) =>
      context.go('/settings/sources');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = ref.watch(enabledAddonsProvider);
    return Scaffold(
      body: switch (sources) {
        AsyncData(value: []) => EmptyState(
          icon: Icons.movie_filter_rounded,
          title: 'Nothing playing yet',
          message: 'Add a source to see movies and shows.',
          actionLabel: 'Add a source',
          onAction: () => _addSource(context),
        ),
        AsyncError(:final error) when !sources.hasValue => ErrorState(
          message: friendlyError(error),
          onRetry: () => ref.invalidate(addonsProvider),
        ),
        _ => const _Feed(),
      },
    );
  }
}

class _Feed extends ConsumerStatefulWidget {
  const _Feed();

  @override
  ConsumerState<_Feed> createState() => _FeedState();
}

class _FeedState extends ConsumerState<_Feed> {
  /// Today's billboard, kept for the visit so it doesn't jump as more rows
  /// arrive (cleared on refresh).
  MetaPreview? _featured;

  void _reload() {
    _featured = null;
    ref
      ..invalidate(addonsProvider)
      ..invalidate(homeRowsProvider)
      ..invalidate(newEpisodesProvider);
  }

  Future<void> _refresh() async {
    _reload();
    try {
      await ref.read(homeRowsProvider.future);
    } on Object {
      // The feed shows the error itself.
    }
  }

  /// Picks the billboard once rows have started arriving and the shows you
  /// follow have been checked for new episodes.
  MetaPreview? _pick(HomeRows? feed, AsyncValue<List<NewEpisodes>> fresh) {
    if (_featured != null || feed == null || fresh.isLoading) {
      return _featured;
    }
    return _featured = pickFeatured(
      feed.rows,
      fresh.value ?? const [],
      DateTime.now(),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Back online: whatever failed loads again on its own.
    ref.listen(onlineProvider, (prev, next) {
      if (next.value == true && prev?.value == false) {
        setState(_reload);
      }
    });
    final rows = ref.watch(homeRowsProvider);
    final fresh = ref.watch(newEpisodesProvider);
    final pick = _pick(rows.value, fresh);
    final featured = pick == null
        ? null
        : ref.watch(richMetaProvider((type: pick.type, id: pick.id))).value ??
              pick;
    final pad = MediaQuery.paddingOf(context);
    return Stack(
      children: [
        RefreshIndicator.adaptive(
          onRefresh: _refresh,
          edgeOffset: pad.top,
          color: KColors.lamp,
          backgroundColor: KColors.seat,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: featured != null
                    ? Billboard(meta: featured)
                    : rows.isLoading ||
                          (rows.value?.complete == false) ||
                          fresh.isLoading
                    ? const BillboardSkeleton()
                    : SizedBox(height: pad.top + 56),
              ),
              const SliverToBoxAdapter(child: ContinueRow()),
              const SliverToBoxAdapter(child: NewEpisodesRow()),
              const SliverToBoxAdapter(child: MyListRow()),
              ..._rows(rows),
              SliverToBoxAdapter(
                child: SizedBox(height: AppShell.bottomInset(context)),
              ),
            ],
          ),
        ),
        // Fixed: scrolled content fades under the status bar and Cast.
        const TopShade(),
        Positioned(
          top: pad.top + KSpace.x1,
          right: KSpace.margin,
          child: const GlassGroup(child: CastButton()),
        ),
      ],
    );
  }

  List<Widget> _rows(AsyncValue<HomeRows> rows) => switch (rows) {
    AsyncValue(value: final v?) when v.complete && v.rows.isEmpty => [
      SliverToBoxAdapter(
        child: v.offline
            ? ErrorState(
                title: 'You’re offline',
                message:
                    'Check your connection. Home reloads when you’re back '
                    'online.',
                onRetry: () => setState(_reload),
              )
            : v.failed
            ? ErrorState(
                message:
                    'Your sources didn’t answer. Try again, or check them in '
                    'Settings › Sources.',
                onRetry: () => setState(_reload),
              )
            : EmptyState(
                title: 'Nothing to show',
                message:
                    'Your sources don’t list any movies or shows. Add one '
                    'that does, like Cinemeta.',
                actionLabel: 'Add a source',
                onAction: () => HomeScreen._addSource(context),
              ),
      ),
    ],
    AsyncValue(value: final v?) => [
      SliverList.builder(
        itemCount: v.rows.length,
        itemBuilder: (_, i) => CatalogRowView(row: v.rows[i]),
      ),
      // More sources still answering.
      if (!v.complete) const SliverToBoxAdapter(child: _SkeletonRows(rows: 1)),
    ],
    AsyncError(:final error) => [
      SliverToBoxAdapter(
        child: ErrorState(
          message: friendlyError(error),
          onRetry: () => setState(_reload),
        ),
      ),
    ],
    _ => const [SliverToBoxAdapter(child: _SkeletonRows())],
  };
}

class _SkeletonRows extends StatelessWidget {
  const _SkeletonRows({this.rows = 2});

  final int rows;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: KSpace.margin),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var r = 0; r < rows; r++) ...[
          const SizedBox(height: KSpace.section),
          const SizedBox(
            width: 160,
            child: LoadingBlock(height: 24, radius: 6),
          ),
          const SizedBox(height: KSpace.x3),
          SizedBox(
            height: PosterSize.height,
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                maxWidth: double.infinity,
                child: Row(
                  children: [
                    for (var i = 0; i < 4; i++) ...[
                      const SizedBox(
                        width: PosterSize.width,
                        child: LoadingBlock(height: PosterSize.height),
                      ),
                      const SizedBox(width: KSpace.x3),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}
