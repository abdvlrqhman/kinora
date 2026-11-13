import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stremio/stremio.dart';

import '../../ui/layout.dart';
import '../../app/router.dart';
import '../../services/play_request.dart';
import '../../services/resolver.dart';
import '../../services/tmdb.dart';
import '../../ui/glass.dart';
import '../../ui/tint.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/artwork.dart';
import '../../ui/widgets/media.dart';
import '../../ui/widgets/states.dart';
import '../cast/cast_picker.dart';
import '../title/title_actions.dart';
import '../title/title_model.dart';

/// Short enough that Keep watching shows at rest.
double billboardHeight(BuildContext context) =>
    (MediaQuery.sizeOf(context).height * 0.56).clamp(420, 600);

/// Full-bleed featured title: backdrop, logo, facts, then Play (which says
/// what it plays and which version), My list and Details.
class Billboard extends ConsumerWidget {
  const Billboard({super.key, required this.meta});

  final MetaPreview meta;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    final genres = meta.genres.take(3).join(', ');
    final key = (type: meta.type, id: meta.id);
    final model = ref.watch(titleProvider(key)).value;
    final next = ref.watch(nextUpProvider(key));
    final isMovie = meta.type == 'movie';
    // Movies can start before details load; shows wait for "next up".
    final PlayRequest? request = model != null && next != null
        ? model.request(episode: next.episode, startAt: next.startAt)
        : isMovie
        ? PlayRequest(
            type: 'movie',
            mediaId: meta.id,
            videoId: meta.id,
            title: meta.name,
            poster: meta.poster,
            background: meta.background,
            logo: meta.logo,
          )
        : null;
    final video =
        model?.video(next?.episode) ??
        (isMovie
            ? VideoRef(type: 'movie', mediaId: meta.id, videoId: meta.id)
            : null);
    final left = next?.resume ?? false
        ? timeLeftLabel(ref, meta.id, request!.videoId)
        : null;
    void details() => openTitle(context, type: meta.type, id: meta.id);

    return SizedBox(
      height: billboardHeight(context),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Artwork(
            url: meta.background ?? meta.poster,
            memCacheWidth: decodeWidth(context, width),
          ),
          const LegibilityScrim(stops: [0.3, 0.96]),
          Positioned(
            left: KSpace.margin,
            right: KSpace.margin,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  button: true,
                  hint: 'Opens details',
                  child: GestureDetector(
                    onTap: details,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TitleLogo(
                          name: meta.name,
                          logo: meta.logo,
                          maxWidth: width * 0.7,
                          height: 96,
                        ),
                        const SizedBox(height: KSpace.x3),
                        FactLine(meta: meta),
                        if (genres.isNotEmpty) ...[
                          const SizedBox(height: KSpace.x1),
                          Text(genres, style: KType.small),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: KSpace.x4),
                CastTargetBuilder(
                  builder: (context, tv) {
                    final label = playOn(next?.label ?? 'Play', tv);
                    return GlassGroup(
                      child: Wrap(
                        spacing: KSpace.x3,
                        runSpacing: KSpace.x3,
                        children: [
                          GlassButton(
                            key: const ValueKey('billboard-play'),
                            label: label,
                            icon: Icons.play_arrow_rounded,
                            prominent: true,
                            semanticLabel: '$label ${meta.name}',
                            // No details for a show: its page explains why.
                            onPressed: request != null
                                ? () => openPlayer(context, request)
                                : details,
                          ),
                          MyListButton(meta: meta),
                          // A wide window: a labelled capsule like its
                          // neighbours.
                          if (KLayout.isWide(context))
                            GlassButton(
                              label: 'Details',
                              icon: Icons.info_outline_rounded,
                              onPressed: details,
                            )
                          else
                            GlassIconButton(
                              icon: Icons.info_outline_rounded,
                              label: 'Details',
                              onPressed: details,
                            ),
                        ],
                      ),
                    );
                  },
                ),
                if (video != null) ...[
                  const SizedBox(height: 10),
                  ReleaseLine(video: video, maxLines: 1, extra: left),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Billboard-sized calm placeholder while catalogs load.
class BillboardSkeleton extends StatelessWidget {
  const BillboardSkeleton({super.key});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: billboardHeight(context),
    child: const Padding(
      padding: EdgeInsets.all(KSpace.margin),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 220, child: LoadingBlock(height: 72, radius: 8)),
          SizedBox(height: KSpace.x4),
          SizedBox(width: 200, child: LoadingBlock(height: 48, radius: 24)),
        ],
      ),
    ),
  );
}

/// The top of Home: featured titles you swipe (or page with the arrows and
/// the arrow keys on a computer), one at a time, with dots for where you
/// are. It never moves on its own.
class HeroCarousel extends StatefulWidget {
  const HeroCarousel({super.key, required this.items});

  final List<MetaPreview> items;

  @override
  State<HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<HeroCarousel> {
  final _pages = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int page) {
    final to = page.clamp(0, widget.items.length - 1);
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _pages.jumpToPage(to);
    } else {
      unawaited(
        _pages.animateToPage(to, duration: KMotion.slow, curve: KMotion.curve),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final wide = KLayout.isWide(context);
    final accent = KinoraTint.of(context);
    return SizedBox(
      height: billboardHeight(context),
      child: Stack(
        children: [
          PageView.builder(
            controller: _pages,
            itemCount: items.length,
            onPageChanged: (p) => setState(() => _page = p),
            itemBuilder: (context, i) => Consumer(
              builder: (context, ref, _) {
                final m = items[i];
                final rich = ref
                    .watch(richMetaProvider((type: m.type, id: m.id)))
                    .value;
                return Billboard(meta: rich ?? m);
              },
            ),
          ),
          if (items.length > 1)
            Positioned(
              right: wide ? 24 : 16,
              bottom: wide ? 26 : 22,
              child: Semantics(
                label: 'Featured ${_page + 1} of ${items.length}',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < items.length; i++)
                      GestureDetector(
                        onTap: () => _go(i),
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 3,
                            vertical: 8,
                          ),
                          child: AnimatedContainer(
                            duration: KMotion.base,
                            curve: KMotion.curve,
                            width: i == _page ? 20 : 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: i == _page
                                  ? accent
                                  : const Color(0x4DFFFFFF),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                    if (wide) ...[
                      const SizedBox(width: 14),
                      GlassIconButton(
                        icon: Icons.chevron_left_rounded,
                        label: 'Previous featured title',
                        size: 34,
                        onPressed: _page > 0 ? () => _go(_page - 1) : null,
                      ),
                      const SizedBox(width: 8),
                      GlassIconButton(
                        icon: Icons.chevron_right_rounded,
                        label: 'Next featured title',
                        size: 34,
                        onPressed: _page < items.length - 1
                            ? () => _go(_page + 1)
                            : null,
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
