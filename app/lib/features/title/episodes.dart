import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stremio/stremio.dart';

import '../../app/router.dart';
import '../../core/db/database.dart';
import '../../core/format.dart';
import '../../services/downloads.dart';
import '../../services/library.dart';
import '../../services/play_request.dart';
import '../../ui/glass.dart';
import '../../ui/layout.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/artwork.dart';
import '../../ui/widgets/media.dart';
import 'title_actions.dart';
import 'title_model.dart';

String _seasonName(int s) => s == 0 ? 'Specials' : 'Season $s';

/// "Season 1  2  3  Specials": the chosen one sits in glass.
class SeasonPicker extends StatelessWidget {
  const SeasonPicker({
    super.key,
    required this.seasons,
    required this.selected,
    required this.onSelect,
  });

  final List<int> seasons;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    if (seasons.length < 2) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: KSpace.margin),
        child: Semantics(
          header: true,
          child: Text(
            seasons.isEmpty ? 'Episodes' : _seasonName(seasons.first),
            style: KType.h2,
          ),
        ),
      );
    }
    final height = math.max(
      48.0,
      MediaQuery.textScalerOf(context).scale(28) + 16,
    );
    return SizedBox(
      height: height,
      child: GlassGroup(
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: KSpace.margin - 4),
          itemCount: seasons.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.only(left: 4, right: KSpace.x1),
                child: Center(
                  child: ExcludeSemantics(
                    child: Text('Season', style: KType.h2),
                  ),
                ),
              );
            }
            final s = seasons[i - 1];
            final isSelected = s == selected;
            final text = Text(
              s == 0 ? 'Specials' : '$s',
              style: KType.h2.copyWith(
                color: isSelected ? KColors.lamp : KColors.reel,
              ),
            );
            return Semantics(
              button: true,
              selected: isSelected,
              label: _seasonName(s),
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelect(s),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 48),
                  child: isSelected
                      ? Glass(
                          tintStrength: 0.3,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Center(child: text),
                        )
                      : Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Center(child: text),
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

const double _stillWidth = 128;

/// One episode: still with progress (a full Haze line once watched), "E3"
/// and title, air date, a download control whose icon says when it's
/// downloaded, and a two-line overview that opens on tap. Unaired episodes
/// say when they air and can't be played yet.
class EpisodeRow extends ConsumerWidget {
  const EpisodeRow({
    super.key,
    required this.model,
    required this.episode,
    required this.now,
  });

  final TitleModel model;
  final Episode episode;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = episode;
    final progress = ref.watch(
      mediaProgressProvider(model.meta.id).select((a) => a.value?[e.id]),
    );
    final download = ref.watch(
      downloadForVideoProvider(e.id).select((a) => a.value),
    );
    final isAired = aired(e, now);
    final watched = progress?.completed ?? false;
    final partial =
        progress != null &&
        !watched &&
        progress.positionMs > 0 &&
        progress.durationMs > 0;
    final downloaded = download?.state == 'completed';
    final number = 'E${e.episode ?? '?'}';
    final name = e.title?.trim().isNotEmpty ?? false
        ? e.title!
        : 'Episode ${e.episode ?? ''}';
    final released = e.released;
    final when = released == null
        ? null
        : isAired
        ? shortDate(released, now)
        : 'Airs ${shortDate(released, now)}';
    final runtime = isAired ? lengthOfEpisode(model) : null;
    final meta = KType.tabular(KType.small);
    // A wide window: a larger still, the overview beside it.
    final wide = KLayout.isWide(context);
    final stillWidth = wide ? 220.0 : _stillWidth;
    final overview = e.overview?.trim().isNotEmpty ?? false
        ? ExpandableText(
            e.overview!.trim(),
            maxLines: 2,
            style: KType.label.copyWith(color: KColors.haze),
          )
        : null;

    final request = model.request(
      episode: e,
      startAt: partial
          ? Duration(milliseconds: progress.positionMs)
          : watched
          ? Duration.zero
          : null,
    );

    final row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KSpace.margin,
        vertical: KSpace.x3,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Pressable(
                  label: [
                    'Episode ${e.episode ?? ''}, $name',
                    ?when,
                    if (watched) 'Watched',
                    if (partial) 'In progress',
                    if (downloaded) 'Downloaded',
                  ].join('. '),
                  hint: isAired ? 'Plays the episode' : null,
                  onTap: isAired ? () => openPlayer(context, request) : null,
                  child: Row(
                    children: [
                      SizedBox(
                        width: stillWidth,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(KRadius.still),
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                ArtHero(
                                  videoId: e.id,
                                  child: Artwork(
                                    url: e.thumbnail,
                                    memCacheWidth: decodeWidth(
                                      context,
                                      stillWidth,
                                    ),
                                  ),
                                ),
                                if (watched)
                                  const Positioned(
                                    left: 0,
                                    right: 0,
                                    bottom: 0,
                                    child: ProgressLine(
                                      fraction: 1,
                                      color: KColors.haze,
                                    ),
                                  ),
                                if (partial) ...[
                                  stillShade,
                                  Positioned(
                                    left: KSpace.x2,
                                    right: KSpace.x2,
                                    bottom: KSpace.x2,
                                    child: ProgressLine(
                                      fraction:
                                          progress.positionMs /
                                          progress.durationMs,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: KSpace.x3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: '$number  ',
                                    style: KType.tabular(
                                      KType.label.copyWith(
                                        color: KColors.haze,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  TextSpan(
                                    text: isolate(name),
                                    style: KType.body.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Wrap(
                              spacing: KSpace.x3,
                              runSpacing: 2,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                if (runtime != null) Text(runtime, style: meta),
                                if (when != null) Text(when, style: meta),
                              ],
                            ),
                            if (wide && overview != null) ...[
                              const SizedBox(height: KSpace.x2),
                              overview,
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (isAired)
                _EpisodeDownload(
                  row: download,
                  request: request,
                  number: number,
                ),
            ],
          ),
          if (!wide && overview != null) ...[
            const SizedBox(height: KSpace.x2),
            overview,
          ],
        ],
      ),
    );
    return row;
  }
}

/// "49m": the show's runtime, when the source gives one.
String? lengthOfEpisode(TitleModel t) {
  final m = runtimeMinutes(t.meta.runtime);
  return m == null ? null : Fmt.duration(Duration(minutes: m));
}

class _EpisodeDownload extends ConsumerWidget {
  const _EpisodeDownload({
    required this.row,
    required this.request,
    required this.number,
  });

  final DownloadRow? row;
  final PlayRequest request;
  final String number;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final look = downloadLook(row);
    final r = row;
    final active = r?.state == 'downloading' && r!.totalBytes > 0;
    return Semantics(
      button: true,
      label: '${look.label} $number',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onDownloadTap(context, ref, row, request),
        child: SizedBox.square(
          dimension: 48,
          child: Center(
            child: active
                ? SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(
                      value: r.doneBytes / r.totalBytes,
                      strokeWidth: 2.5,
                      color: KColors.lamp,
                      backgroundColor: KColors.lamp.withValues(alpha: 0.18),
                    ),
                  )
                : Icon(
                    look.icon,
                    size: 24,
                    color: look.color == KColors.lamp
                        ? KColors.haze
                        : look.color,
                  ),
          ),
        ),
      ),
    );
  }
}
