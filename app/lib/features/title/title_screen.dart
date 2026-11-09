import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';
import 'package:stremio/stremio.dart';

import '../../app/router.dart';
import '../../services/sources.dart';
import '../../services/tmdb.dart';
import '../../ui/glass.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/artwork.dart';
import '../../ui/widgets/media.dart';
import '../../ui/widgets/sheet.dart';
import '../../ui/widgets/states.dart';
import '../cast/cast_picker.dart';
import '../downloads/download_prompts.dart';
import '../settings/widgets/settings_ui.dart';
import 'episodes.dart';
import 'title_actions.dart';
import 'title_model.dart';
import 'tmdb_rows.dart';
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
        AsyncValue(:final value?) => _TitlePage(titleKey: key, model: value),
        // No installed source describes this title: adding one fixes it.
        AsyncError(:final error)
            when error is StateError ||
                error is AddonHttpException && error.statusCode == 404 =>
          _Bare(
            child: EmptyState(
              icon: Icons.cloud_off_rounded,
              title: 'No details for this',
              message:
                  '${friendlyError(error)} Add a source that describes movies '
                  'and shows, like Cinemeta.',
              actionLabel: 'Add a source',
              onAction: () => context.go('/settings/sources'),
            ),
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

  /// Past the backdrop: the header strip with the title shows.
  bool _scrolled = false;

  bool _onScroll(ScrollUpdateNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    final scrolled = n.metrics.pixels > _heroHeight(context) - 120;
    if (scrolled != _scrolled) setState(() => _scrolled = scrolled);
    return false;
  }

  Future<void> _downloadSeason(int season, List<Episode> episodes) async {
    final t = widget.model;
    final ready = [
      for (final e in episodes)
        if (aired(e, _now)) e,
    ];
    for (final e in ready) {
      if (!mounted) return;
      await startDownload(context, ref, t.request(episode: e));
    }
    if (mounted && ready.isNotEmpty) {
      showNote(
        context,
        'Downloading ${season == 0 ? 'the specials' : 'season $season'}. '
        'See it in Downloads.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.model;
    final meta = t.meta;
    // TMDB's extras (cast photos, More like this...), when a key is set.
    final extra = ref.watch(tmdbTitleProvider(widget.titleKey)).value;
    final next = ref.watch(nextUpProvider(widget.titleKey));
    final season =
        _season ?? next?.episode?.season ?? t.seasons.firstOrNull ?? 0;
    final episodes = t.bySeason[season] ?? const <Episode>[];
    final primary = t.request(episode: next?.episode, startAt: next?.startAt);
    final subtitle = primary.isEpisode
        ? [primary.label, ?primary.episodeTitle].join('  ')
        : meta.name;
    final left = next?.resume ?? false
        ? timeLeftLabel(ref, meta.id, primary.videoId)
        : null;

    return Stack(
      children: [
        NotificationListener<ScrollUpdateNotification>(
          onNotification: _onScroll,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _Hero(
                  meta: meta,
                  isMovie: !t.isSeries,
                  certification: extra?.certification,
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: KSpace.margin),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: KSpace.margin),
                      CastTargetBuilder(
                        builder: (context, tv) {
                          final label = playOn(next?.label ?? 'Play', tv);
                          return GlassGroup(
                            child: SizedBox(
                              width: double.infinity,
                              child: GlassButton(
                                key: const ValueKey('play'),
                                label: label,
                                icon: Icons.play_arrow_rounded,
                                prominent: true,
                                semanticLabel: '$label ${meta.name}',
                                onPressed: next == null
                                    ? null
                                    : () => openPlayer(context, primary),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                      if (next != null)
                        ReleaseLine(video: t.video(next.episode), extra: left)
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
                                icon: Icons.layers_rounded,
                                label: 'Other versions',
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
                                        onDownload: (r) async {
                                          await startDownload(
                                            context,
                                            ref,
                                            primary.copyWith(
                                              candidateId: r.candidateId,
                                            ),
                                          );
                                          if (context.mounted) {
                                            showNote(
                                              context,
                                              'Added to Downloads.',
                                            );
                                          }
                                        },
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: KSpace.section),
                      // TMDB's extras arrive after the page: they grow in
                      // instead of pushing the text down in one jump.
                      _Grow(
                        child: extra?.tagline == null
                            ? null
                            : Padding(
                                padding: const EdgeInsets.only(
                                  bottom: KSpace.x2,
                                ),
                                child: Text(
                                  extra!.tagline!,
                                  style: KType.title.copyWith(
                                    color: KColors.haze,
                                  ),
                                ),
                              ),
                      ),
                      if (meta.description?.trim().isNotEmpty ?? false)
                        ExpandableText(
                          meta.description!.trim(),
                          style: KType.body,
                        ),
                      _Credits(
                        meta: meta,
                        // The photo row below names them.
                        showCast: extra?.cast.isEmpty ?? true,
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _Grow(
                  child: (extra?.cast.isNotEmpty ?? false)
                      ? CastRow(people: extra!.cast)
                      : null,
                ),
              ),
              if (!t.isSeries)
                SliverToBoxAdapter(
                  child: _Grow(
                    child: (extra?.similar.isNotEmpty ?? false)
                        ? SimilarRow(titles: extra!.similar)
                        : null,
                  ),
                ),
              if (t.isSeries) ...[
                SliverPadding(
                  padding: const EdgeInsets.only(
                    top: KSpace.section,
                    bottom: KSpace.x1,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      children: [
                        Expanded(
                          child: SeasonPicker(
                            seasons: t.seasons,
                            selected: season,
                            onSelect: (s) => setState(() => _season = s),
                          ),
                        ),
                        _SeasonMenu(
                          season: season,
                          onDownload: () =>
                              unawaited(_downloadSeason(season, episodes)),
                        ),
                        const SizedBox(width: KSpace.margin - 12),
                      ],
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
              if (t.isSeries)
                SliverToBoxAdapter(
                  child: _Grow(
                    child: (extra?.similar.isNotEmpty ?? false)
                        ? SimilarRow(titles: extra!.similar)
                        : null,
                  ),
                ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: MediaQuery.paddingOf(context).bottom + KSpace.section,
                ),
              ),
            ],
          ),
        ),
        _Header(title: meta.name, scrolled: _scrolled),
      ],
    );
  }
}

/// A download button after the season picker; its sheet confirms, since a
/// season can be many gigabytes.
class _SeasonMenu extends StatelessWidget {
  const _SeasonMenu({required this.season, required this.onDownload});

  final int season;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final name = season == 0 ? 'the specials' : 'season $season';
    return Semantics(
      button: true,
      label: 'Download $name',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showGlassSheet<void>(
          context,
          builder: (sheet) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SheetAction(
                  icon: Icons.download_rounded,
                  label: 'Download $name',
                  onTap: () {
                    Navigator.pop(sheet);
                    onDownload();
                  },
                ),
                const SizedBox(height: KSpace.x2),
              ],
            ),
          ),
        ),
        child: const SizedBox.square(
          dimension: 48,
          child: Icon(Icons.download_rounded, color: KColors.haze),
        ),
      ),
    );
  }
}

/// Back and Cast float over the backdrop; past it, a glass strip with the
/// title fades in behind them (instantly with reduced motion).
class _Header extends StatelessWidget {
  const _Header({required this.title, required this.scrolled});

  final String title;
  final bool scrolled;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final fade = reduce ? Duration.zero : KMotion.base;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Stack(
        children: [
          const TopShade(),
          IgnorePointer(
            child: AnimatedOpacity(
              opacity: scrolled ? 1 : 0,
              duration: fade,
              curve: KMotion.curve,
              child: Column(
                children: [
                  // Content scrolling under the strip fades to near black.
                  SizedBox(
                    height: top + 56 + 32,
                    width: double.infinity,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: [0, 0.7, 1],
                          colors: [
                            Color(0xE6000000),
                            Color(0xE6000000),
                            Color(0x00000000),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          IgnorePointer(
            child: AnimatedOpacity(
              opacity: scrolled ? 1 : 0,
              duration: fade,
              curve: KMotion.curve,
              child: GlassGroup(
                child: Glass(
                  radius: 0,
                  tintStrength: 0.10,
                  child: SizedBox(height: top + 56, width: double.infinity),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              KSpace.margin,
              top + KSpace.x1,
              KSpace.margin,
              0,
            ),
            child: GlassGroup(
              child: Row(
                children: [
                  const _BackButton(),
                  const SizedBox(width: KSpace.x3),
                  Expanded(
                    child: ExcludeSemantics(
                      child: AnimatedOpacity(
                        opacity: scrolled ? 1 : 0,
                        duration: fade,
                        curve: KMotion.curve,
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: contentDir(title),
                          style: KType.h2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: KSpace.x3),
                  const CastButton(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.meta, required this.isMovie, this.certification});

  final MetaDetail meta;
  final String? certification;

  /// A movie's backdrop grows into the player; a show's episode stills do.
  final bool isMovie;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final genres = meta.genres.take(4).join(', ');
    final art = Artwork(
      url: meta.background ?? meta.poster,
      memCacheWidth: decodeWidth(context, width),
    );
    return SizedBox(
      height: _heroHeight(context),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _Parallax(
            child: isMovie ? ArtHero(videoId: meta.id, child: art) : art,
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
                FactLine(meta: meta, certification: certification),
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

/// Content that may arrive late, growing into place (instant with reduced
/// motion).
class _Grow extends StatelessWidget {
  const _Grow({required this.child});
  final Widget? child;

  @override
  Widget build(BuildContext context) => AnimatedSize(
    duration: reduceMotion(context) ? Duration.zero : KMotion.base,
    curve: KMotion.curve,
    alignment: Alignment.topCenter,
    child: child ?? const SizedBox(width: double.infinity),
  );
}

class _Credits extends StatelessWidget {
  const _Credits({required this.meta, this.showCast = true});

  final MetaDetail meta;
  final bool showCast;

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
        if (showCast && meta.cast.isNotEmpty) line('Cast', meta.cast),
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
  Widget build(BuildContext context) => GlassIconButton(
    icon: Icons.chevron_left_rounded,
    label: 'Back',
    onPressed: () => context.canPop() ? context.pop() : context.go('/'),
  );
}

class _Bare extends StatelessWidget {
  const _Bare({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(child: child),
      Positioned(
        top: MediaQuery.paddingOf(context).top + KSpace.x1,
        left: KSpace.margin,
        child: const GlassGroup(child: _BackButton()),
      ),
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
