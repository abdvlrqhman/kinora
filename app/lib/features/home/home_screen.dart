import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:stremio/stremio.dart';

import '../../app/shell.dart';
import '../../services/sources.dart';
import '../../ui/tint.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/artwork.dart';
import '../../ui/widgets/media.dart';
import '../../ui/widgets/states.dart';
import 'billboard.dart';
import 'rows.dart';

/// The billboard title: the first catalog item with a backdrop, upgraded to
/// its full details (logo, runtime) once they load.
final featuredProvider = Provider.autoDispose<MetaPreview?>((ref) {
  final rows = ref.watch(homeCatalogsProvider).value;
  if (rows == null || rows.isEmpty) return null;
  final pick =
      rows
          .expand((r) => r.items)
          .where((m) => m.background != null)
          .firstOrNull ??
      rows.first.items.first;
  return ref.watch(metaProvider((type: pick.type, id: pick.id))).value ?? pick;
});

/// Home: a billboard, then Continue watching, My list and every catalog.
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

class _Feed extends ConsumerWidget {
  const _Feed();

  Future<void> _refresh(WidgetRef ref) async {
    ref
      ..invalidate(addonsProvider)
      ..invalidate(homeCatalogsProvider);
    try {
      await ref.read(homeCatalogsProvider.future);
    } on Object {
      // The feed shows the error itself.
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final featured = ref.watch(featuredProvider);
    final catalogs = ref.watch(homeCatalogsProvider);
    final top = MediaQuery.paddingOf(context).top;
    return ArtworkTintScope(
      image: artworkProvider(featured?.background ?? featured?.poster),
      child: RefreshIndicator.adaptive(
        onRefresh: () => _refresh(ref),
        edgeOffset: top,
        color: KColors.lamp,
        backgroundColor: KColors.seat,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: featured != null
                  ? Billboard(meta: featured)
                  : catalogs.isLoading
                  ? const BillboardSkeleton()
                  : SizedBox(height: top + KSpace.x2),
            ),
            const SliverToBoxAdapter(child: ContinueRow()),
            const SliverToBoxAdapter(child: MyListRow()),
            switch (catalogs) {
              AsyncData(value: []) => SliverToBoxAdapter(
                child: EmptyState(
                  title: 'Nothing to show',
                  message:
                      'Your sources don’t list any movies or shows. Add one '
                      'that does, like Cinemeta.',
                  actionLabel: 'Add a source',
                  onAction: () => HomeScreen._addSource(context),
                ),
              ),
              AsyncValue(:final value?) => SliverList.builder(
                itemCount: value.length,
                itemBuilder: (_, i) => CatalogRowView(row: value[i]),
              ),
              AsyncError(:final error) => SliverToBoxAdapter(
                child: ErrorState(
                  message: friendlyError(error),
                  onRetry: () => ref.invalidate(homeCatalogsProvider),
                ),
              ),
              _ => const SliverToBoxAdapter(child: _SkeletonRows()),
            },
            SliverToBoxAdapter(
              child: SizedBox(height: AppShell.bottomInset(context)),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkeletonRows extends StatelessWidget {
  const _SkeletonRows();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: KSpace.margin),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var r = 0; r < 2; r++) ...[
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
