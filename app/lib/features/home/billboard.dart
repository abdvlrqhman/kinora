import 'package:flutter/material.dart';
import 'package:stremio/stremio.dart';

import '../../app/router.dart';
import '../../services/play_request.dart';
import '../../ui/glass.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/artwork.dart';
import '../../ui/widgets/media.dart';
import '../../ui/widgets/states.dart';
import '../title/title_actions.dart';

double _height(BuildContext context) =>
    (MediaQuery.sizeOf(context).height * 0.68).clamp(440, 660);

/// Full-bleed featured title: backdrop, logo, facts, Play and My list.
class Billboard extends StatelessWidget {
  const Billboard({super.key, required this.meta});

  final MetaPreview meta;

  void _play(BuildContext context) => meta.type == 'movie'
      ? openPlayer(
          context,
          PlayRequest(
            type: 'movie',
            mediaId: meta.id,
            videoId: meta.id,
            title: meta.name,
            poster: meta.poster,
            background: meta.background,
            logo: meta.logo,
          ),
        )
      : openTitle(context, type: meta.type, id: meta.id);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final genres = meta.genres.take(3).join(', ');
    return SizedBox(
      height: _height(context),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Artwork(
            url: meta.background ?? meta.poster,
            memCacheWidth: decodeWidth(context, width),
          ),
          const TopShade(),
          const LegibilityScrim(stops: [0.38, 0.96]),
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
                    onTap: () =>
                        openTitle(context, type: meta.type, id: meta.id),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TitleLogo(
                          name: meta.name,
                          logo: meta.logo,
                          maxWidth: width * 0.7,
                          height: 108,
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
                GlassGroup(
                  child: Wrap(
                    spacing: KSpace.x3,
                    runSpacing: KSpace.x3,
                    children: [
                      GlassButton(
                        label: 'Play',
                        icon: Icons.play_arrow_rounded,
                        prominent: true,
                        semanticLabel: 'Play ${meta.name}',
                        onPressed: () => _play(context),
                      ),
                      MyListButton(meta: meta),
                    ],
                  ),
                ),
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
