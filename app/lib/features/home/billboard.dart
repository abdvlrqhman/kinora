import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stremio/stremio.dart';

import '../../ui/layout.dart';
import '../../app/router.dart';
import '../../services/play_request.dart';
import '../../services/resolver.dart';
import '../../ui/glass.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/artwork.dart';
import '../../ui/widgets/media.dart';
import '../../ui/widgets/states.dart';
import '../cast/cast_picker.dart';
import '../title/title_actions.dart';
import '../title/title_model.dart';

/// Short enough that Continue watching clears the tab bar at rest.
double _height(BuildContext context) =>
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
      height: _height(context),
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
    height: _height(context),
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
