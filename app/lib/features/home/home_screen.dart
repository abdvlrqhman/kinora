import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:stremio/stremio.dart';

import '../../app/shell.dart';
import '../../services/sources.dart';
import '../../services/trakt.dart';
import '../../ui/glass.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/brand.dart';
import '../../ui/widgets/media.dart';
import '../../ui/widgets/states.dart';
import '../cast/cast_picker.dart';
import '../trakt/trakt_ui.dart';
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
  /// Today's featured titles, kept for the visit so they don't jump as
  /// more rows arrive (cleared on refresh).
  List<MetaPreview>? _featured;

  void _reload() {
    _featured = null;
    ref
      ..invalidate(addonsProvider)
      ..invalidate(homeRowsProvider)
      ..invalidate(newEpisodesProvider)
      ..invalidate(continueItemsProvider);
    unawaited(ref.read(traktSyncProvider).syncNow());
  }

  Future<void> _refresh() async {
    _reload();
    try {
      await ref.read(homeRowsProvider.future);
    } on Object {
      // The feed shows the error itself.
    }
  }

  /// Picks the featured titles once rows have started arriving and the
  /// shows you follow have been checked for new episodes.
  List<MetaPreview>? _pick(
    HomeRows? feed,
    AsyncValue<List<NewEpisodes>> fresh,
  ) {
    if (_featured != null || feed == null || fresh.isLoading) {
      return _featured;
    }
    final list = pickFeaturedList(
      feed.rows,
      fresh.value ?? const [],
      DateTime.now(),
    );
    return list.isEmpty ? null : _featured = list;
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
    final featured = _pick(rows.value, fresh);
    final pad = MediaQuery.paddingOf(context);
    final catalogs = rows.value?.rows ?? const <CatalogRow>[];
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
                    ? HeroCarousel(items: featured)
                    : rows.isLoading ||
                          (rows.value?.complete == false) ||
                          fresh.isLoading
                    ? const BillboardSkeleton()
                    : SizedBox(height: pad.top + 56),
              ),
              const SliverToBoxAdapter(child: ContinueRow()),
              const SliverToBoxAdapter(child: NewEpisodesRow()),
              // The first catalog, ranked.
              if (catalogs.isNotEmpty)
                SliverToBoxAdapter(child: TrendingRow(row: catalogs.first)),
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
        // A phone: the wordmark over the hero (the sidebar has it otherwise).
        if (!AppShell.onRail(context))
          Positioned(
            top: pad.top + KSpace.x2,
            left: 16,
            child: const _Wordmark(),
          ),
        // (Beside the side rail they're at its foot.)
        if (!AppShell.onRail(context))
          Positioned(
            top: pad.top + KSpace.x1,
            right: KSpace.margin,
            child: const GlassGroup(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TraktButton(),
                  SizedBox(width: KSpace.x2),
                  CastButton(),
                ],
              ),
            ),
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
      // (The first one is Trending now, above My list.)
      SliverList.builder(
        itemCount: math.max(0, v.rows.length - 1),
        itemBuilder: (_, i) => CatalogRowView(row: v.rows[i + 1]),
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
            height: PosterSize.heightOf(context),
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                maxWidth: double.infinity,
                child: Row(
                  children: [
                    for (var i = 0; i < 4; i++) ...[
                      SizedBox(
                        width: PosterSize.widthOf(context),
                        child: LoadingBlock(
                          height: PosterSize.heightOf(context),
                        ),
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

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      height: 44,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox.square(
            dimension: 20,
            child: CustomPaint(painter: KinoraMark()),
          ),
          const SizedBox(width: 8),
          Text(
            'KINORA',
            style: KType.h2.copyWith(
              fontSize: 16,
              letterSpacing: 1.4,
              color: KColors.title,
              fontWeight: FontWeight.w700,
              fontVariations: const [FontVariation.weight(700)],
            ),
          ),
        ],
      ),
    ),
  );
}
