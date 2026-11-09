import 'dart:async';

import 'package:dlna/dlna.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../services/cast_service.dart';
import '../../../ui/glass.dart';
import '../../../ui/tint.dart';
import '../../../ui/tokens.dart';
import '../../../ui/widgets/artwork.dart';
import '../player_controller.dart';
import 'panels.dart';
import 'scrubber.dart';

/// Pick a TV. Searches on open; warns when the TV can't decode this version.
class CastPanel extends ConsumerStatefulWidget {
  const CastPanel({
    super.key,
    required this.controller,
    required this.onClose,
    required this.onVersions,
  });

  final PlayerController controller;
  final VoidCallback onClose;
  final VoidCallback onVersions;

  @override
  ConsumerState<CastPanel> createState() => _CastPanelState();
}

class _CastPanelState extends ConsumerState<CastPanel> {
  final _address = TextEditingController();

  @override
  void initState() {
    super.initState();
    unawaited(ref.read(castServiceProvider).search());
  }

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  Future<void> _castTo(DlnaDevice d) async {
    final c = widget.controller;
    final cast = ref.read(castServiceProvider);
    final source = c.source;
    if (source == null) return;
    final sub = await c.subtitleForTv();
    final at = c.player.state.position;
    await c.player.pause();
    widget.onClose();
    await cast.cast(
      d: d,
      source: source,
      request: c.request,
      startAt: at,
      length: c.player.state.duration,
      subtitlePath: sub?.path,
      subtitleLanguage: sub?.language,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cast = ref.watch(castServiceProvider);
    return ListenableBuilder(
      listenable: cast,
      builder: (context, _) {
        final source = widget.controller.source;
        return SidePanel(
          title: 'Play on TV',
          onClose: widget.onClose,
          child: ListView(
            padding: const EdgeInsets.only(bottom: KSpace.x4),
            children: [
              if (cast.searching)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: KSpace.margin,
                    vertical: KSpace.x2,
                  ),
                  child: Text(
                    'Looking for TVs on this Wi-Fi…',
                    style: KType.small,
                  ),
                ),
              for (final d in cast.devices)
                Builder(
                  builder: (context) {
                    final check = source == null ? null : cast.check(d, source);
                    final ok = check?.isPlayable ?? true;
                    return Semantics(
                      button: true,
                      label: 'Play on ${d.friendlyName}',
                      excludeSemantics: true,
                      child: InkWell(
                        onTap: () => _castTo(d),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: KSpace.margin,
                            vertical: 12,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.tv_rounded),
                              const SizedBox(width: KSpace.x3),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(d.friendlyName, style: KType.body),
                                    if (d.modelName != null)
                                      Text(d.modelName!, style: KType.small),
                                    if (!ok)
                                      Text(
                                        check!.problems.join('\n'),
                                        style: KType.small.copyWith(
                                          color: KColors.marquee,
                                        ),
                                      ),
                                    if (ok &&
                                        (check?.warnings.isNotEmpty ?? false))
                                      Text(
                                        check!.warnings.join('\n'),
                                        style: KType.small,
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              if (cast.devices.any(
                (d) => source != null && !cast.check(d, source).isPlayable,
              ))
                Padding(
                  padding: const EdgeInsets.all(KSpace.margin),
                  child: GlassButton(
                    label: 'Choose a version the TV can play',
                    onPressed: () {
                      widget.onClose();
                      widget.onVersions();
                    },
                  ),
                ),
              if (cast.message != null && !cast.searching)
                Padding(
                  padding: const EdgeInsets.all(KSpace.margin),
                  child: Text(cast.message!, style: KType.body),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  KSpace.margin,
                  KSpace.x4,
                  KSpace.margin,
                  0,
                ),
                child: Text(
                  'TV not listed? Enter its address (Settings › Network on the TV).',
                  style: KType.small,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: KSpace.margin,
                  vertical: KSpace.x2,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _address,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          hintText: '192.168.1.20',
                        ),
                        onSubmitted: cast.addByAddress,
                      ),
                    ),
                    const SizedBox(width: KSpace.x2),
                    GlassButton(
                      label: 'Add',
                      onPressed: () => cast.addByAddress(_address.text),
                    ),
                  ],
                ),
              ),
              if (!cast.searching)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: KSpace.margin,
                  ),
                  child: TextButton(
                    onPressed: cast.search,
                    child: const Text('Search again'),
                  ),
                ),
            ],
          ),
        );
      },
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
    final pad = MediaQuery.paddingOf(context);
    return ListenableBuilder(
      listenable: cast,
      builder: (context, _) {
        final name = cast.device?.friendlyName ?? 'your TV';
        final status = switch (cast.phase) {
          CastPhase.connecting => 'Starting on $name',
          CastPhase.playing => 'Playing on $name',
          CastPhase.paused => 'Paused on $name',
          CastPhase.lost => cast.message ?? '$name stopped answering',
          _ => cast.message ?? 'Stopped on $name',
        };
        return Stack(
          fit: StackFit.expand,
          children: [
            Opacity(
              opacity: 0.4,
              child: Artwork(url: req.still ?? req.background ?? req.poster),
            ),
            const LegibilityScrim(stops: [0, 1]),
            Padding(
              padding: EdgeInsets.fromLTRB(
                pad.left + KSpace.margin * 2,
                pad.top + KSpace.x4,
                pad.right + KSpace.margin * 2,
                pad.bottom + KSpace.margin,
              ),
              child: GlassGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.tv_rounded, color: KinoraTint.of(context)),
                        const SizedBox(width: KSpace.x2),
                        Expanded(child: Text(status, style: KType.title)),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      req.title,
                      style: KType.hero,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (req.isEpisode)
                      Text(
                        'S${req.season} E${req.episode}${req.episodeTitle == null ? '' : '  ${req.episodeTitle}'}',
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
                    Row(
                      children: [
                        GlassIconButton(
                          icon: Icons.replay_10_rounded,
                          label: 'Back 10 seconds',
                          onPressed: () => cast.seek(
                            cast.position - const Duration(seconds: 10),
                          ),
                        ),
                        const SizedBox(width: KSpace.x3),
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
                        const SizedBox(width: KSpace.x3),
                        GlassIconButton(
                          icon: Icons.forward_10_rounded,
                          label: 'Forward 10 seconds',
                          onPressed: () => cast.seek(
                            cast.position + const Duration(seconds: 10),
                          ),
                        ),
                        const SizedBox(width: KSpace.section),
                        GlassIconButton(
                          icon: Icons.volume_down_rounded,
                          label: 'TV volume down',
                          onPressed: () => cast.changeVolume(-5),
                        ),
                        const SizedBox(width: KSpace.x2),
                        GlassIconButton(
                          icon: Icons.volume_up_rounded,
                          label: 'TV volume up',
                          onPressed: () => cast.changeVolume(5),
                        ),
                        const Spacer(),
                        GlassButton(
                          label: 'Watch on this phone',
                          icon: Icons.phone_iphone_rounded,
                          prominent: true,
                          onPressed: () async {
                            final at = await cast.stop();
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
