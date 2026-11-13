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
import '../../ui/layout.dart';
import '../../ui/tint.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/artwork.dart';
import '../../ui/widgets/media.dart';
import '../../ui/widgets/pointer.dart';
import '../../ui/widgets/sheet.dart';
import 'home_feed.dart';

/// Home's sizes: a wide window (the sidebar) or a phone.
abstract final class HomeSizes {
  static bool _wide(BuildContext c) => KLayout.isWide(c);

  /// Page edge.
  static double gutter(BuildContext c) => _wide(c) ? 24 : 16;
  static double gap(BuildContext c) => _wide(c) ? 16 : 12;
  static double sectionGap(BuildContext c) => _wide(c) ? 32 : 24;

  /// Keep watching (16:9).
  static double upNext(BuildContext c) => _wide(c) ? 196 : 150;

  /// New episodes (16:9).
  static double episode(BuildContext c) => _wide(c) ? 262 : 228;

  /// Posters (2:3).
  static double poster(BuildContext c) => _wide(c) ? 150 : 110;

  /// Trending: the whole item, and its poster.
  static double ranked(BuildContext c) => _wide(c) ? 190 : 146;
  static double rankedPoster(BuildContext c) => _wide(c) ? 128 : 104;
  static double numeral(BuildContext c) => _wide(c) ? 140 : 104;
}

/// A row's header: its title in Unbounded, an optional coral count or
/// muted subtitle, and (wide windows) arrows that page the row.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.count,
    this.subtitle,
    this.controller,
  });

  final String title;

  /// Coral and in caps: "3 NEW".
  final String? count;
  final String? subtitle;

  /// The row it pages (arrows on a wide window).
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final g = HomeSizes.gutter(context);
    return Padding(
      padding: EdgeInsets.only(left: g, right: g),
      child: SizedBox(
        height: 30,
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: KType.h2.copyWith(color: KColors.title),
                    ),
                  ),
                  if (count != null) ...[
                    const SizedBox(width: 10),
                    Text(
                      count!.toUpperCase(),
                      style: KType.meta.copyWith(color: KColors.coralText),
                    ),
                  ],
                  if (subtitle != null) ...[
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: KType.small.copyWith(color: KColors.muted),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (controller != null && KLayout.isWide(context))
              _RowArrows(controller: controller!, title: title),
          ],
        ),
      ),
    );
  }
}

/// ‹ › for a row: pages it by a screenful less one card; each is disabled
/// at its end.
class _RowArrows extends StatefulWidget {
  const _RowArrows({required this.controller, required this.title});

  final ScrollController controller;
  final String title;

  @override
  State<_RowArrows> createState() => _RowArrowsState();
}

class _RowArrowsState extends State<_RowArrows> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) => _changed());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _page(int dir) {
    final c = widget.controller;
    if (!c.hasClients) return;
    final p = c.position;
    final to = (p.pixels + dir * (p.viewportDimension - 200)).clamp(
      p.minScrollExtent,
      p.maxScrollExtent,
    );
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      c.jumpTo(to);
    } else {
      unawaited(c.animateTo(to, duration: KMotion.slow, curve: KMotion.curve));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final ready = c.hasClients && c.position.hasContentDimensions;
    final back = ready && c.position.pixels > c.position.minScrollExtent + 1;
    final forward = ready && c.position.pixels < c.position.maxScrollExtent - 1;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Arrow(
          icon: Icons.chevron_left_rounded,
          label: 'Scroll ${widget.title} back',
          onTap: back ? () => _page(-1) : null,
        ),
        const SizedBox(width: 8),
        _Arrow(
          icon: Icons.chevron_right_rounded,
          label: 'Scroll ${widget.title} forward',
          onTap: forward ? () => _page(1) : null,
        ),
      ],
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onTap != null,
    label: label,
    excludeSemantics: true,
    child: PointerFocus(
      onActivate: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      builder: (context, hovered) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: KMotion.fast,
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: hovered ? KColors.raised : KColors.panel,
            border: Border.all(color: KColors.strongEdge),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 18,
            color: onTap == null ? KColors.fieldEdge : KColors.title,
          ),
        ),
      ),
    ),
  );
}

/// A titled, lazily built horizontal row from the page edge to the
/// window's edge.
class RowSection extends StatefulWidget {
  const RowSection({
    super.key,
    required this.title,
    required this.height,
    required this.itemWidth,
    required this.itemCount,
    required this.itemBuilder,
    this.count,
    this.subtitle,
    this.gap,
  });

  final String title;
  final String? count;
  final String? subtitle;
  final double height;
  final double itemWidth;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  /// Space between cards (default: the layout's card gap).
  final double? gap;

  @override
  State<RowSection> createState() => _RowSectionState();
}

class _RowSectionState extends State<RowSection> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = HomeSizes.gutter(context);
    final gap = widget.gap ?? HomeSizes.gap(context);
    return Padding(
      padding: EdgeInsets.only(top: HomeSizes.sectionGap(context)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: widget.title,
            count: widget.count,
            subtitle: widget.subtitle,
            controller: _controller,
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: widget.height,
            child: ListView.builder(
              key: PageStorageKey(widget.title),
              controller: _controller,
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.only(left: g, right: g - gap),
              itemExtent: widget.itemWidth + gap,
              itemCount: widget.itemCount,
              // Cards keep their size: their text stops growing at 1.3x.
              itemBuilder: (context, i) => Padding(
                padding: EdgeInsets.only(right: gap),
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.3,
                  child: widget.itemBuilder(context, i),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Artwork that answers the mouse the way the design asks: a lime outline,
/// a dark scrim and, for something that plays, a round play button.
class HoverArt extends StatefulWidget {
  const HoverArt({
    super.key,
    required this.child,
    this.play = false,
    this.radius = KRadius.poster,
  });

  final Widget child;
  final bool play;
  final double radius;

  @override
  State<HoverArt> createState() => _HoverArtState();
}

class _HoverArtState extends State<HoverArt> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final accent = KinoraTint.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _hover ? 1 : 0,
                duration: KMotion.fast,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0x73000000),
                    borderRadius: BorderRadius.circular(widget.radius),
                  ),
                  child: widget.play
                      ? Center(
                          child: Container(
                            width: 46,
                            height: 46,
                            decoration: const BoxDecoration(
                              color: Color(0xFFFFFFFF),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              color: KColors.blackout,
                              size: 26,
                            ),
                          ),
                        )
                      : null,
                ),
              ),
            ),
          ),
          Positioned(
            left: -3,
            top: -3,
            right: -3,
            bottom: -3,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _hover ? 1 : 0,
                duration: KMotion.fast,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: accent, width: 2),
                    borderRadius: BorderRadius.circular(widget.radius + 3),
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

/// A small dark badge on artwork, in mono caps ("S1 E4", "NEW").
class ArtBadge extends StatelessWidget {
  const ArtBadge(this.text, {super.key, this.fresh = false});

  final String text;

  /// Coral: something new.
  final bool fresh;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: fresh ? KColors.coral : const Color(0xB3000000),
      borderRadius: BorderRadius.circular(KRadius.badge),
    ),
    child: Text(
      text.toUpperCase(),
      style: KType.badge.copyWith(
        color: fresh ? const Color(0xFF1A0209) : KColors.title,
      ),
    ),
  );
}

/// One line under a card: the title.
Widget _cardTitle(String text) => Text(
  text,
  maxLines: 1,
  overflow: TextOverflow.ellipsis,
  textDirection: contentDir(text),
  style: KType.title.copyWith(color: KColors.lamp),
);

/// Height of a 16:9 card of [width] with a title and a state line.
double _stillRowHeight(BuildContext context, double width) {
  final s = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);
  return width * 9 / 16 + 10 + s.scale(20) + 2 + s.scale(14) + 2;
}

/// A 2:3 poster with its title under it.
class PosterCard extends StatelessWidget {
  const PosterCard({
    super.key,
    required this.name,
    required this.poster,
    required this.onTap,
  });

  final String name;
  final String? poster;
  final VoidCallback onTap;

  static double heightOf(BuildContext context) {
    final s = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);
    return HomeSizes.poster(context) * 1.5 + 8 + s.scale(20) + 2;
  }

  @override
  Widget build(BuildContext context) {
    final w = HomeSizes.poster(context);
    return Pressable(
      plain: true,
      label: name,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HoverArt(
            child: Artwork(
              url: poster,
              fallbackText: name,
              radius: KRadius.poster,
              aspectRatio: 2 / 3,
              memCacheWidth: decodeWidth(context, w),
            ),
          ),
          const SizedBox(height: 8),
          _cardTitle(name),
        ],
      ),
    );
  }
}

/// One addon catalog as a poster row.
class CatalogRowView extends StatelessWidget {
  const CatalogRowView({super.key, required this.row});

  final CatalogRow row;

  @override
  Widget build(BuildContext context) => RowSection(
    title: row.title,
    height: PosterCard.heightOf(context),
    itemWidth: HomeSizes.poster(context),
    itemCount: row.items.length,
    itemBuilder: (context, i) {
      final m = row.items[i];
      return PosterCard(
        name: m.name,
        poster: m.poster,
        onTap: () => openTitle(context, type: m.type, id: m.id),
      );
    },
  );
}

/// The first catalog's top ten, ranked: big outlined numerals with the
/// poster over them.
class TrendingRow extends StatelessWidget {
  const TrendingRow({super.key, required this.row});

  final CatalogRow row;

  @override
  Widget build(BuildContext context) {
    final items = row.items.take(10).toList();
    if (items.length < 3) return CatalogRowView(row: row);
    final pw = HomeSizes.rankedPoster(context);
    final s = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);
    return RowSection(
      title: 'Trending now',
      subtitle: row.title,
      height: pw * 1.5 + 8 + s.scale(20) + 2,
      itemWidth: HomeSizes.ranked(context),
      gap: KLayout.isWide(context) ? 10 : 4,
      itemCount: items.length,
      itemBuilder: (context, i) {
        final m = items[i];
        return Pressable(
          plain: true,
          label: 'Rank ${i + 1}, ${m.name}',
          onTap: () => openTitle(context, type: m.type, id: m.id),
          child: _Ranked(
            rank: i + 1,
            poster: m.poster,
            name: m.name,
            posterWidth: pw,
          ),
        );
      },
    );
  }
}

class _Ranked extends StatelessWidget {
  const _Ranked({
    required this.rank,
    required this.poster,
    required this.name,
    required this.posterWidth,
  });

  final int rank;
  final String? poster;
  final String name;
  final double posterWidth;

  @override
  Widget build(BuildContext context) {
    final size = HomeSizes.numeral(context);
    final ph = posterWidth * 1.5;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // The numeral: outline only, sitting low behind the poster's left.
        Positioned(
          left: 0,
          top: ph - size * 0.8,
          child: ExcludeSemantics(
            child: Text(
              '$rank',
              style: TextStyle(
                fontFamily: KType.display,
                fontSize: size,
                height: 0.8,
                fontWeight: FontWeight.w700,
                fontVariations: const [FontVariation.weight(700)],
                letterSpacing: -size * 0.04,
                foreground: Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = KLayout.isWide(context) ? 2.5 : 2
                  ..color = KColors.rank,
              ),
            ),
          ),
        ),
        Positioned(
          right: 0,
          top: 0,
          width: posterWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HoverArt(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(KRadius.poster),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0xB3000000),
                        offset: Offset(-10, 0),
                        blurRadius: 24,
                      ),
                    ],
                  ),
                  child: Artwork(
                    url: poster,
                    fallbackText: name,
                    radius: KRadius.poster,
                    aspectRatio: 2 / 3,
                    memCacheWidth: decodeWidth(context, posterWidth),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _cardTitle(name),
            ],
          ),
        ),
      ],
    );
  }
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
      subtitle: '${items.length} saved',
      height: PosterCard.heightOf(context),
      itemWidth: HomeSizes.poster(context),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final m = items[i];
        return PosterCard(
          name: m.name,
          poster: m.poster,
          onTap: () => openTitle(context, type: m.type, id: m.mediaId),
        );
      },
    );
  }
}

/// Keep watching: what you started, newest first; hidden when empty.
class ContinueRow extends ConsumerWidget {
  const ContinueRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(continueItemsProvider).value ?? const [];
    if (items.isEmpty) return const SizedBox.shrink();
    final w = HomeSizes.upNext(context);
    return RowSection(
      title: 'Keep watching',
      height: _stillRowHeight(context, w),
      itemWidth: w,
      itemCount: items.length,
      itemBuilder: (_, i) =>
          ContinueTile(key: ValueKey(items[i].videoId), item: items[i]),
    );
  }
}

/// A 16:9 card with the progress along its foot and a state line in lime
/// ("S1 E3 · 30M LEFT"). Tap resumes; long-press offers Go to title, Mark
/// as watched and Remove from row.
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
        ? (item.positionMs / item.durationMs).clamp(0.0, 1.0)
        : 0.0;
    final repo = ref.read(progressRepositoryProvider);
    // The episode after a finished one, not started yet.
    final fresh = item.positionMs == 0;
    final accent = KinoraTint.of(context);
    final w = HomeSizes.upNext(context);

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

    final state = [
      ?episode,
      fresh ? 'Up next' : '$left left',
    ].join(' · ').toUpperCase();

    return Pressable(
      plain: true,
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
          HoverArt(
            play: true,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(KRadius.poster),
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
                        memCacheWidth: decodeWidth(context, w),
                      ),
                    ),
                    if (!fresh)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: 3,
                        child: ColoredBox(
                          color: const Color(0x33FFFFFF),
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: fraction,
                            child: ColoredBox(color: accent),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _cardTitle(item.name),
          const SizedBox(height: 2),
          Text(
            state,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: KType.meta.copyWith(color: KColors.limeLink),
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
    final w = HomeSizes.episode(context);
    final total = shows.fold(0, (a, s) => a + s.episodes.length);
    return RowSection(
      title: 'New episodes',
      count: '$total new',
      height: _stillRowHeight(context, w),
      itemWidth: w,
      itemCount: shows.length,
      itemBuilder: (context, i) {
        final show = shows[i];
        final meta = show.model.meta;
        final e = show.next;
        final number = Fmt.episode(e.season ?? 0, e.episode ?? 0);
        final count = show.episodes.length;
        void goToTitle() => openTitle(context, type: meta.type, id: meta.id);
        return Pressable(
          plain: true,
          label: [
            '${meta.name}, $number',
            ?e.title,
            if (count == 1) 'new' else '$count new',
          ].join(', '),
          hint: 'Plays $number',
          onTap: () => openPlayer(context, show.model.request(episode: e)),
          onLongPress: goToTitle,
          actions: {
            const CustomSemanticsAction(label: 'Go to title'): goToTitle,
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HoverArt(
                play: true,
                child: Stack(
                  children: [
                    Artwork(
                      url: e.thumbnail ?? meta.background ?? meta.poster,
                      fallbackText: meta.name,
                      radius: KRadius.poster,
                      aspectRatio: 16 / 9,
                      alignment: const Alignment(0, -0.2),
                      memCacheWidth: decodeWidth(context, w),
                    ),
                    Positioned(left: 10, bottom: 10, child: ArtBadge(number)),
                    const Positioned(
                      right: 10,
                      top: 10,
                      child: ArtBadge('New', fresh: true),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _cardTitle(meta.name),
              const SizedBox(height: 2),
              Text(
                (count == 1 ? '$number is out' : '$count new · from $number')
                    .toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: KType.meta.copyWith(color: KColors.coralText),
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
