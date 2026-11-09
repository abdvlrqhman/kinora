import 'dart:async';

import 'package:dlna/dlna.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../cast/cast_picker.dart';
import '../../../services/cast_service.dart';
import '../../../ui/glass.dart';
import '../../../ui/tint.dart';
import '../../../ui/tokens.dart';
import '../gestures.dart';
import '../../../ui/widgets/artwork.dart';
import '../../../ui/widgets/media.dart';
import '../player_controller.dart';
import 'panels.dart';
import 'scrubber.dart';

/// Cast to a TV. Searches on open; warns when a TV can't decode this
/// version and offers one it can.
class CastPanel extends ConsumerWidget {
  const CastPanel({
    super.key,
    required this.controller,
    required this.onClose,
    required this.onVersions,
  });

  final PlayerController controller;
  final VoidCallback onClose;
  final VoidCallback onVersions;

  Future<void> _castTo(WidgetRef ref, DlnaDevice d) async {
    final c = controller;
    final cast = ref.read(castServiceProvider);
    final source = c.source;
    if (source == null) return;
    final sub = await c.subtitleForTv();
    final at = c.player.state.position;
    await c.player.pause();
    onClose();
    final ok = await cast.cast(
      d: d,
      source: source,
      request: c.request,
      startAt: at,
      length: c.player.state.duration,
      subtitlePath: sub?.path,
      subtitleLanguage: sub?.language,
    );
    // The player shows why (cast.message); the phone picks up again.
    if (!ok && !cast.isCasting) await c.player.play();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cast = ref.watch(castServiceProvider);
    final source = controller.source;
    return SidePanel(
      title: 'Cast to a TV',
      onClose: onClose,
      child: ListenableBuilder(
        listenable: cast,
        builder: (context, _) => CastDeviceList(
          onPick: (d) => unawaited(_castTo(ref, d)),
          notes: (d) {
            if (source == null) return const [];
            final check = cast.check(d, source);
            return [
              for (final p in check.problems) (text: p, problem: true),
              if (check.isPlayable)
                for (final w in check.warnings) (text: w, problem: false),
            ];
          },
          trailing: [
            if (source != null &&
                cast.devices.any((d) => !cast.check(d, source).isPlayable))
              Padding(
                padding: const EdgeInsets.all(KSpace.margin),
                child: GlassButton(
                  label: 'Choose a version the TV can play',
                  onPressed: () {
                    onClose();
                    onVersions();
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Shown while the TV plays: remote control for it.
class CastingView extends ConsumerWidget {
  const CastingView({super.key, required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cast = ref.watch(castServiceProvider);
    final req = controller.request;
    final pad = playerEdges(context);
    final width = MediaQuery.sizeOf(context).width;
    return ListenableBuilder(
      listenable: cast,
      builder: (context, _) {
        final name = cast.device?.friendlyName ?? 'your TV';
        final status = switch (cast.phase) {
          CastPhase.connecting => 'Starting on $name',
          CastPhase.lost => '$name isn’t answering. Waiting for it…',
          _ when cast.reconnecting => 'Reconnecting to $name…',
          CastPhase.playing =>
            'Playing on $name'
                '${cast.volume == null ? '' : ', volume ${cast.volume}'}',
          CastPhase.paused => 'Paused on $name',
          _ => cast.message ?? 'Stopped on $name',
        };
        return Stack(
          fit: StackFit.expand,
          children: [
            Opacity(
              opacity: 0.4,
              child: Artwork(
                url: req.still ?? req.background ?? req.poster,
                memCacheWidth: decodeWidth(context, width),
              ),
            ),
            const LegibilityScrim(stops: [0, 1]),
            GlassGroup(
              child: FillOrScroll(
                // The controls' edges.
                padding: EdgeInsets.fromLTRB(
                  pad.left + KSpace.margin,
                  pad.top + KSpace.x3,
                  pad.right + KSpace.margin,
                  pad.bottom + KSpace.margin,
                ),
                top: Row(
                  children: [
                    Icon(Icons.tv_rounded, color: KinoraTint.of(context)),
                    const SizedBox(width: KSpace.x2),
                    Expanded(
                      child: Semantics(
                        liveRegion: true,
                        child: Text(status, style: KType.title),
                      ),
                    ),
                  ],
                ),
                bottom: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      req.title,
                      style: KType.hero,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textDirection: contentDir(req.title),
                    ),
                    if (req.isEpisode)
                      Text(
                        [
                          'S${req.season} E${req.episode}',
                          if (req.episodeTitle != null)
                            isolate(req.episodeTitle!),
                        ].join('  '),
                        style: KType.title.copyWith(color: KColors.haze),
                      ),
                    const SizedBox(height: KSpace.margin),
                    Scrubber(
                      position: cast.position,
                      duration: cast.duration,
                      buffered: cast.duration,
                      onSeek: cast.seek,
                    ),
                    const SizedBox(height: KSpace.x3),
                    Wrap(
                      spacing: KSpace.x3,
                      runSpacing: KSpace.x3,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        GlassIconButton(
                          icon: Icons.replay_10_rounded,
                          label: 'Back 10 seconds',
                          onPressed: () => cast.seek(
                            cast.position - const Duration(seconds: 10),
                          ),
                        ),
                        GlassIconButton(
                          icon: cast.phase == CastPhase.playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          label: cast.phase == CastPhase.playing
                              ? 'Pause'
                              : 'Play',
                          onPressed: cast.togglePlay,
                          size: 64,
                        ),
                        GlassIconButton(
                          icon: Icons.forward_10_rounded,
                          label: 'Forward 10 seconds',
                          onPressed: () => cast.seek(
                            cast.position + const Duration(seconds: 10),
                          ),
                        ),
                        const SizedBox(width: KSpace.x4),
                        GlassIconButton(
                          icon: Icons.volume_down_rounded,
                          label: 'TV volume down',
                          onPressed: () => cast.changeVolume(-5),
                        ),
                        GlassIconButton(
                          icon: Icons.volume_up_rounded,
                          label: 'TV volume up',
                          onPressed: () => cast.changeVolume(5),
                        ),
                        const SizedBox(width: KSpace.x4),
                        GlassButton(
                          label: 'Watch on this phone',
                          icon: Icons.phone_iphone_rounded,
                          prominent: true,
                          onPressed: () async {
                            final at = cast.position;
                            // The phone takes over now; the TV's Stop
                            // follows. Next videos play here too.
                            unawaited(cast.stop());
                            cast.selectTarget(null);
                            await controller.player.seek(at);
                            await controller.player.play();
                          },
                        ),
                      ],
                    ),
                    if (cast.position > Duration.zero)
                      Padding(
                        padding: const EdgeInsets.only(top: KSpace.x2),
                        child: Text(
                          '${Fmt.timecode(cast.position)} of ${Fmt.timecode(cast.duration)}',
                          style: KType.tabular(KType.small),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
