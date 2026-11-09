import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';
import 'package:stremio/stremio.dart';

import '../../app/router.dart';
import '../../services/sources.dart';
import '../../ui/glass.dart';
import '../../ui/tint.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/artwork.dart';
import '../../ui/widgets/media.dart';
import '../../ui/widgets/states.dart';
import 'episodes.dart';
import 'title_actions.dart';
import 'title_model.dart';
import 'versions_sheet.dart';

/// A movie or show: backdrop, Play (naming the version), actions, details
/// and, for shows, seasons and episodes. Tinted by its artwork.
class TitleScreen extends ConsumerWidget {
  const TitleScreen({super.key, required this.type, required this.id});

  final String type;
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (type: type, id: id);
    final title = ref.watch(titleProvider(key));
    return Scaffold(
      body: switch (title) {
        // The page sits under the tint so its sheets inherit the accent.
        AsyncValue(:final value?) => ArtworkTintScope(
          image: artworkProvider(value.meta.background ?? value.meta.poster),
          child: _TitlePage(titleKey: key, model: value),
        ),
        AsyncError(:final error) => _Bare(
          child: ErrorState(
            message: friendlyError(error),
            onRetry: () => ref.invalidate(metaProvider(key)),
          ),
        ),
        _ => const _Bare(child: _Skeleton()),
      },
    );
  }
}

double _heroHeight(BuildContext context) =>
    (MediaQuery.sizeOf(context).height * 0.6).clamp(400, 640);

class _TitlePage extends ConsumerStatefulWidget {
  const _TitlePage({required this.titleKey, required this.model});

  final TitleKey titleKey;
  final TitleModel model;

  @override
  ConsumerState<_TitlePage> createState() => _TitlePageState();
}

class _TitlePageState extends ConsumerState<_TitlePage> {
  /// Season the user picked; until then, the next-up episode's season.
  int? _season;

  /// One clock per visit so every row agrees on what has aired.
  final _now = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final t = widget.model;
    final meta = t.meta;
    final next = ref.watch(nextUpProvider(widget.titleKey));
    final season =
        _season ?? next?.episode?.season ?? t.seasons.firstOrNull ?? 0;
    final episodes = t.bySeason[season] ?? const <Episode>[];
    final primary = t.request(episode: next?.episode, startAt: next?.startAt);
    final subtitle = primary.isEpisode
        ? [primary.label, ?primary.episodeTitle].join('  ')
        : meta.name;

    return Stack(
      children: [
        CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _Hero(meta: meta)),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: KSpace.margin),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: KSpace.margin),
                    GlassGroup(
                      child: SizedBox(
                        width: double.infinity,
                        child: GlassButton(
                          key: const ValueKey('play'),
                          label: next?.label ?? 'Play',
                          icon: Icons.play_arrow_rounded,
                          prominent: true,
                          semanticLabel:
                              '${next?.label ?? 'Play'} ${meta.name}',
                          onPressed: next == null
                              ? null
                              : () => openPlayer(context, primary),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (next != null)
                      ReleaseLine(video: t.video(next.episode))
                    else
                      const SizedBox(height: 18),
                    const SizedBox(height: KSpace.margin),
                    GlassGroup(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: next == null
                                ? const ActionTile(
                                    icon: Icons.download_rounded,
                                    label: 'Download',
                                    semanticLabel: 'Download',
                                    onPressed: null,
                                  )
                                : DownloadAction(request: primary),
                          ),
                          Expanded(child: MyListAction(meta: meta)),
                          if (meta.trailerYouTubeIds.isNotEmpty)
                            Expanded(
                              child: ActionTile(
                                icon: Icons.movie_creation_outlined,
                                label: 'Trailer',
                                semanticLabel: 'Watch the trailer on YouTube',
                                onPressed: () => unawaited(
                                  launchUrl(
                                    Uri.https('www.youtube.com', '/watch', {
                                      'v': meta.trailerYouTubeIds.first,
                                    }),
                                    mode: LaunchMode.externalApplication,
                                  ),
                                ),
                              ),
                            ),
                          Expanded(
                            child: ActionTile(
                              icon: Icons.tune_rounded,
                              label: 'Choose another version',
                              semanticLabel: 'Choose another version',
                              onPressed: next == null
                                  ? null
                                  : () => showVersionsSheet(
                                      context,
                                      video: t.video(next.episode),
                                      subtitle: subtitle,
                                      onPick: (r) => openPlayer(
                                        context,
                                        primary.copyWith(
                                          candidateId: r.candidateId,
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: KSpace.section),
                    if (meta.description?.trim().isNotEmpty ?? false)
                      ExpandableText(
                        meta.description!.trim(),
                        style: KType.body,
                      ),
                    _Credits(meta: meta),
                  ],
                ),
              ),
            ),
            if (t.isSeries) ...[
              SliverPadding(
                padding: const EdgeInsets.only(
                  top: KSpace.section,
                  bottom: KSpace.x1,
                ),
                sliver: SliverToBoxAdapter(
                  child: SeasonPicker(
                    seasons: t.seasons,
                    selected: season,
                    onSelect: (s) => setState(() => _season = s),
                  ),
                ),
              ),
              SliverList.builder(
                itemCount: episodes.length,
                itemBuilder: (_, i) => EpisodeRow(
                  key: ValueKey(episodes[i].id),
                  model: t,
                  episode: episodes[i],
                  now: _now,
                ),
              ),
            ],
            SliverToBoxAdapter(
              child: SizedBox(
                height: MediaQuery.paddingOf(context).bottom + KSpace.section,
              ),
            ),
          ],
        ),
        // Fixed: scrolled content fades under the status bar and Back.
        const TopShade(),
        const _BackButton(),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.meta});

  final MetaDetail meta;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final genres = meta.genres.take(4).join(', ');
    return SizedBox(
      height: _heroHeight(context),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _Parallax(
            child: Artwork(
              url: meta.background ?? meta.poster,
              memCacheWidth: decodeWidth(context, width),
            ),
          ),
          const LegibilityScrim(stops: [0.3, 1]),
          Positioned(
            left: KSpace.margin,
            right: KSpace.margin,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: TitleLogo(
                    name: meta.name,
                    logo: meta.logo,
                    maxWidth: width * 0.72,
                    height: 112,
                  ),
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
        ],
      ),
    );
  }
}

/// Backdrop that scrolls at half speed and stretches on overscroll.
class _Parallax extends StatelessWidget {
  const _Parallax({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return child;
    return ClipRect(
      clipper: const _OpenTop(),
      child: Flow(
        delegate: _ParallaxDelegate(Scrollable.of(context).position),
        clipBehavior: Clip.none,
        children: [child],
      ),
    );
  }
}

/// Clips below the hero only, so an overscroll stretch can grow upward.
class _OpenTop extends CustomClipper<Rect> {
  const _OpenTop();

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(0, -size.height * 4, size.width, size.height);

  @override
  bool shouldReclip(_OpenTop oldClipper) => false;
}

class _ParallaxDelegate extends FlowDelegate {
  _ParallaxDelegate(this.position) : super(repaint: position);

  final ScrollPosition position;

  @override
  BoxConstraints getConstraintsForChild(int i, BoxConstraints constraints) =>
      BoxConstraints.tight(constraints.biggest);

  @override
  void paintChildren(FlowPaintingContext context) {
    final y = position.hasPixels ? position.pixels : 0.0;
    final size = context.size;
    if (y >= 0) {
      context.paintChild(
        0,
        transform: Matrix4.translationValues(0, y * 0.45, 0),
      );
      return;
    }
    // Overscroll: grow from the bottom edge to fill the gap above.
    final s = (size.height - y) / size.height;
    context.paintChild(
      0,
      transform: Matrix4.translationValues(size.width / 2, size.height, 0)
        ..multiply(Matrix4.diagonal3Values(s, s, 1))
        ..multiply(Matrix4.translationValues(-size.width / 2, -size.height, 0)),
    );
  }

  @override
  bool shouldRepaint(_ParallaxDelegate oldDelegate) =>
      oldDelegate.position != position;
}

class _Credits extends StatelessWidget {
  const _Credits({required this.meta});

  final MetaDetail meta;

  @override
  Widget build(BuildContext context) {
    Widget line(String label, List<String> names) => Padding(
      padding: const EdgeInsets.only(top: KSpace.x2),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '$label  ', style: KType.small),
            TextSpan(
              text: names.take(4).join(', '),
              style: KType.small.copyWith(color: KColors.lamp),
            ),
          ],
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (meta.cast.isNotEmpty) line('Cast', meta.cast),
        if (meta.director.isNotEmpty)
          line(
            meta.director.length > 1 ? 'Directors' : 'Director',
            meta.director,
          ),
      ],
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton();

  @override
  Widget build(BuildContext context) => Positioned(
    top: MediaQuery.paddingOf(context).top + KSpace.x1,
    left: KSpace.x3,
    child: GlassIconButton(
      icon: Icons.chevron_left_rounded,
      label: 'Back',
      onPressed: () => context.canPop() ? context.pop() : context.go('/'),
    ),
  );
}

class _Bare extends StatelessWidget {
  const _Bare({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(child: child),
      const _BackButton(),
    ],
  );
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      LoadingBlock(height: _heroHeight(context), radius: 0),
      const Padding(
        padding: EdgeInsets.all(KSpace.margin),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LoadingBlock(height: 48, radius: 24),
            SizedBox(height: KSpace.x4),
            SizedBox(width: 220, child: LoadingBlock(height: 14, radius: 4)),
          ],
        ),
      ),
    ],
  );
}
