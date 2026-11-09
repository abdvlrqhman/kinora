import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router.dart';
import '../../core/db/database.dart';
import '../../core/format.dart';
import '../../services/library.dart';
import '../../services/play_request.dart';
import '../../services/sources.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/artwork.dart';
import '../../ui/widgets/media.dart';
import '../../ui/widgets/sheet.dart';
import 'home_feed.dart';

/// A titled, lazily built horizontal row aligned to the page margin.
class RowSection extends StatelessWidget {
  const RowSection({
    super.key,
    required this.title,
    required this.height,
    required this.itemWidth,
    required this.itemCount,
    required this.itemBuilder,
  });

  final String title;
  final double height;
  final double itemWidth;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: KSpace.section),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: KSpace.margin),
          child: Semantics(header: true, child: Text(title, style: KType.h2)),
        ),
        const SizedBox(height: KSpace.x3),
        SizedBox(
          height: height,
          child: ListView.builder(
            key: PageStorageKey(title),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(
              left: KSpace.margin,
              right: KSpace.margin - KSpace.x3,
            ),
            itemExtent: itemWidth + KSpace.x3,
            itemCount: itemCount,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.only(right: KSpace.x3),
              child: itemBuilder(context, i),
            ),
          ),
        ),
      ],
    ),
  );
}

/// One addon catalog as a poster row.
class CatalogRowView extends StatelessWidget {
  const CatalogRowView({super.key, required this.row});

  final CatalogRow row;

  @override
  Widget build(BuildContext context) => RowSection(
    title: row.title,
    height: PosterSize.height,
    itemWidth: PosterSize.width,
    itemCount: row.items.length,
    itemBuilder: (context, i) {
      final m = row.items[i];
      return PosterTile(
        name: m.name,
        poster: m.poster,
        onTap: () => openTitle(context, type: m.type, id: m.id),
      );
    },
  );
}

/// "My list" as a poster row; hidden when empty.
class MyListRow extends ConsumerWidget {
  const MyListRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(myListProvider).value ?? const [];
    if (items.isEmpty) return const SizedBox.shrink();
    return RowSection(
      title: 'My list',
      height: PosterSize.height,
      itemWidth: PosterSize.width,
      itemCount: items.length,
      itemBuilder: (context, i) {
        final m = items[i];
        return PosterTile(
          name: m.name,
          poster: m.poster,
          onTap: () => openTitle(context, type: m.type, id: m.mediaId),
        );
      },
    );
  }
}

const double _stillWidth = 240;

/// Unfinished titles with their progress; hidden when empty.
class ContinueRow extends ConsumerWidget {
  const ContinueRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(continueItemsProvider).value ?? const [];
    if (items.isEmpty) return const SizedBox.shrink();
    final scaler = MediaQuery.textScalerOf(context);
    return RowSection(
      title: 'Continue watching',
      height:
          _stillWidth * 9 / 16 +
          KSpace.x2 +
          scaler.scale(18) +
          scaler.scale(16) +
          4,
      itemWidth: _stillWidth,
      itemCount: items.length,
      itemBuilder: (_, i) =>
          ContinueTile(key: ValueKey(items[i].videoId), item: items[i]),
    );
  }
}

/// A landscape still with a progress line. Tap resumes; long-press offers
/// Go to title, Mark as watched and Remove from row.
class ContinueTile extends ConsumerWidget {
  const ContinueTile({super.key, required this.item});

  final WatchProgressData item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Movies have no still: borrow the backdrop from (cached) details.
    final backdrop = item.still == null
        ? ref.watch(
            metaProvider((type: item.type, id: item.mediaId))
                .select((a) => a.value?.background),
          )
        : null;
    final left = Fmt.duration(
      Duration(milliseconds: math.max(0, item.durationMs - item.positionMs)),
    );
    final episode = item.season != null && item.episode != null
        ? Fmt.episode(item.season!, item.episode!)
        : null;
    final fraction = item.durationMs > 0
        ? item.positionMs / item.durationMs
        : 0.0;
    final repo = ref.read(progressRepositoryProvider);
    // The episode after a finished one, not started yet.
    final fresh = item.positionMs == 0;

    void resume() => openPlayer(
      context,
      PlayRequest(
        type: item.type,
        mediaId: item.mediaId,
        videoId: item.videoId,
        title: item.name,
        episodeTitle: item.episodeTitle,
        season: item.season,
        episode: item.episode,
        poster: item.poster,
        background: backdrop,
        still: item.still,
        startAt: fresh ? null : Duration(milliseconds: item.positionMs),
      ),
    );
    void goToTitle() => openTitle(context, type: item.type, id: item.mediaId);
    // (The next episode has no progress yet: saved as watched through.)
    void markWatched() => unawaited(
      fresh
          ? repo.save(
              videoId: item.videoId,
              mediaId: item.mediaId,
              type: item.type,
              name: item.name,
              episodeTitle: item.episodeTitle,
              season: item.season,
              episode: item.episode,
              poster: item.poster,
              still: item.still,
              position: const Duration(seconds: 1),
              duration: const Duration(seconds: 1),
            )
          : repo.setWatched(item.videoId, watched: true),
    );
    void remove() => unawaited(repo.dismiss(item.mediaId));

    return Pressable(
      label: [
        '${fresh ? 'Play' : 'Resume'} ${item.name}',
        ?episode,
        fresh ? 'next episode' : '$left left',
      ].join(', '),
      hint: 'Long press for more',
      onTap: resume,
      onLongPress: () => showGlassSheet<void>(
        context,
        builder: (sheet) => _ContinueMenu(
          item: item,
          subtitle: episode,
          onGoToTitle: goToTitle,
          onMarkWatched: markWatched,
          onRemove: remove,
        ),
      ),
      actions: {
        const CustomSemanticsAction(label: 'Go to title'): goToTitle,
        const CustomSemanticsAction(label: 'Mark as watched'): markWatched,
        const CustomSemanticsAction(label: 'Remove from row'): remove,
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(KRadius.still),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ArtHero(
                    videoId: item.videoId,
                    child: Artwork(
                      url: item.still ?? backdrop ?? item.poster,
                      fallbackText: item.name,
                      memCacheWidth: decodeWidth(context, _stillWidth),
                    ),
                  ),
                  stillShade,
                  if (!fresh)
                    Positioned(
                      left: KSpace.x3,
                      right: KSpace.x3,
                      bottom: KSpace.x3,
                      child: ProgressLine(fraction: fraction),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: KSpace.x2),
          Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textDirection: contentDir(item.name),
            style: KType.label.copyWith(fontWeight: FontWeight.w600),
          ),
          Text(
            [?episode, fresh ? 'Next episode' : '$left left'].join('  '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: KType.tabular(KType.small),
          ),
        ],
      ),
    );
  }
}

/// Shows you follow with episodes that aired since you last watched; hidden
/// when there are none. Tap plays the first new one.
class NewEpisodesRow extends ConsumerWidget {
  const NewEpisodesRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shows = ref.watch(newEpisodesProvider).value ?? const [];
    if (shows.isEmpty) return const SizedBox.shrink();
    final scaler = MediaQuery.textScalerOf(context);
    return RowSection(
      title: 'New episodes',
      height:
          _stillWidth * 9 / 16 +
          KSpace.x2 +
          scaler.scale(18) +
          scaler.scale(16) +
          4,
      itemWidth: _stillWidth,
      itemCount: shows.length,
      itemBuilder: (context, i) {
        final show = shows[i];
        final meta = show.model.meta;
        final e = show.next;
        final number = Fmt.episode(e.season ?? 0, e.episode ?? 0);
        final count = show.episodes.length;
        final what = [number, if (count == 1) 'New' else '$count new'];
        void goToTitle() => openTitle(context, type: meta.type, id: meta.id);
        return Pressable(
          label: ['${meta.name}, $number', ?e.title, what.last].join(', '),
          hint: 'Plays $number',
          onTap: () => openPlayer(context, show.model.request(episode: e)),
          onLongPress: goToTitle,
          actions: {
            const CustomSemanticsAction(label: 'Go to title'): goToTitle,
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Artwork(
                url: e.thumbnail ?? meta.background ?? meta.poster,
                fallbackText: meta.name,
                radius: KRadius.still,
                aspectRatio: 16 / 9,
                memCacheWidth: decodeWidth(context, _stillWidth),
              ),
              const SizedBox(height: KSpace.x2),
              Text(
                meta.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textDirection: contentDir(meta.name),
                style: KType.label.copyWith(fontWeight: FontWeight.w600),
              ),
              Text(
                what.join('  '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: KType.tabular(KType.small),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ContinueMenu extends StatelessWidget {
  const _ContinueMenu({
    required this.item,
    required this.subtitle,
    required this.onGoToTitle,
    required this.onMarkWatched,
    required this.onRemove,
  });

  final WatchProgressData item;
  final String? subtitle;
  final VoidCallback onGoToTitle;
  final VoidCallback onMarkWatched;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    VoidCallback close(VoidCallback then) => () {
      Navigator.of(context).pop();
      then();
    };
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              KSpace.margin,
              KSpace.x2,
              KSpace.margin,
              KSpace.x2,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: KType.h2,
                  textDirection: contentDir(item.name),
                ),
                if (subtitle != null || item.episodeTitle != null)
                  Text(
                    [?subtitle, ?item.episodeTitle].join('  '),
                    style: KType.label.copyWith(color: KColors.haze),
                  ),
              ],
            ),
          ),
          SheetAction(
            icon: Icons.info_outline_rounded,
            label: 'Go to title',
            onTap: close(onGoToTitle),
          ),
          SheetAction(
            icon: Icons.check_circle_outline_rounded,
            label: 'Mark as watched',
            onTap: close(onMarkWatched),
          ),
          SheetAction(
            icon: Icons.remove_circle_outline_rounded,
            label: 'Remove from row',
            color: KColors.cut,
            onTap: close(onRemove),
          ),
          const SizedBox(height: KSpace.x2),
        ],
      ),
    );
  }
}
