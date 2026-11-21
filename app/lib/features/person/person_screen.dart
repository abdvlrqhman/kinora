import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stremio/stremio.dart';

import '../../app/router.dart';
import '../../app/shell.dart';
import '../../services/suggestions.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/artwork.dart';
import '../../ui/widgets/media.dart';
import '../../ui/widgets/page_header.dart';
import '../../ui/widgets/states.dart';
import '../search/search_screen.dart' show PosterGrid;

/// A person's movies and shows: what they directed, acted in and wrote.
class PersonScreen extends ConsumerWidget {
  const PersonScreen({
    super.key,
    required this.slug,
    required this.name,
    this.photo,
  });

  final String slug;
  final String name;
  final String? photo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final credits = ref.watch(personCreditsProvider(slug));
    void open(MetaPreview m) => openTitle(context, type: m.type, id: m.id);
    List<Widget> section(String title, List<MetaPreview> items) => [
      if (items.isNotEmpty) ...[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            KSpace.margin,
            KSpace.x2,
            KSpace.margin,
            KSpace.x3,
          ),
          sliver: SliverToBoxAdapter(
            child: Semantics(
              header: true,
              child: Text(
                '$title  ${items.length}',
                style: KType.h2.copyWith(color: KColors.title),
              ),
            ),
          ),
        ),
        PosterGrid(items: items, onOpen: open),
      ],
    ];
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: PageHeader(title: name)),
          if (photo != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  KSpace.margin,
                  KSpace.x2,
                  KSpace.margin,
                  KSpace.x4,
                ),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: ClipOval(
                    child: SizedBox.square(
                      dimension: 96,
                      child: Artwork(
                        url: photo,
                        fallbackText: name,
                        memCacheWidth: decodeWidth(context, 96),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ...switch (credits) {
            AsyncValue(:final value?)
                when value.directed.isEmpty &&
                    value.acted.isEmpty &&
                    value.wrote.isEmpty =>
              [
                const SliverToBoxAdapter(
                  child: EmptyState(
                    title: 'Nothing listed',
                    message: 'Trakt has no movies or shows for this person.',
                  ),
                ),
              ],
            AsyncValue(:final value?) => [
              ...section('Directed', value.directed),
              ...section('Acted in', value.acted),
              ...section('Wrote', value.wrote),
            ],
            AsyncError(:final error) => [
              SliverToBoxAdapter(
                child: ErrorState(
                  message: friendlyError(error),
                  onRetry: () => ref.invalidate(personCreditsProvider(slug)),
                ),
              ),
            ],
            _ => [
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(top: KSpace.section * 2),
                  child: Center(child: CircularProgressIndicator.adaptive()),
                ),
              ),
            ],
          },
          SliverToBoxAdapter(
            child: SizedBox(
              height: AppShell.bottomInset(context) + KSpace.section,
            ),
          ),
        ],
      ),
    );
  }
}
