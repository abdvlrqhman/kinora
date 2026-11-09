import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/format.dart';
import '../../services/pip.dart';
import '../../services/play_request.dart';
import '../../services/resolver.dart';
import '../../ui/glass.dart';
import '../../ui/tint.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/artwork.dart';
import '../../services/cast_service.dart';
import 'player_controller.dart';
import 'widgets/cast_panel.dart';
import 'widgets/panels.dart';
import 'widgets/scrubber.dart';
import 'widgets/subtitle_overlay.dart';

enum _Panel { none, tracks, episodes, speed, versions, cast }

/// Full-screen player for streams and downloads alike.
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key, required this.request});

  final PlayRequest request;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  late final PlayerController c;
  late final CastService _cast;
  bool _inPip = false;
  StreamSubscription<bool>? _pipSub;
  bool _pipAllowed = false;
  bool _controls = true;
  bool _locked = false;
  bool _scrubbing = false;
  bool _fill = false;
  _Panel _panel = _Panel.none;
  Timer? _hide;
  String? _flash; // transient feedback: "+10s", "Volume 60%"
  Timer? _flashTimer;

  @override
  void initState() {
    super.initState();
    c = PlayerController(
      ProviderScope.containerOf(context, listen: false),
      widget.request,
    )..addListener(_onChange);
    _cast = ref.read(castServiceProvider)..addListener(_onChange);
    unawaited(c.start());
    unawaited(WakelockPlus.enable());
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
    unawaited(
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]),
    );
    _scheduleHide();
    _pipSub = Pip.instance.changes.listen((v) {
      if (mounted) setState(() => _inPip = v);
    });
  }

  /// PiP is offered only while something is actually playing.
  void _syncPip() {
    final allow =
        c.phase == PlayerPhase.playing &&
        c.player.state.playing &&
        !_cast.isCasting;
    if (allow == _pipAllowed) return;
    _pipAllowed = allow;
    unawaited(
      Pip.instance.setAllowed(
        allowed: allow,
        width: c.player.state.width,
        height: c.player.state.height,
      ),
    );
  }

  void _onChange() {
    if (!mounted) return;
    final notice = c.notice;
    if (notice != null) {
      c.notice = null;
      _showFlash(notice);
    }
    _syncPip();
    setState(() {});
  }

  @override
  void dispose() {
    _hide?.cancel();
    _flashTimer?.cancel();
    _cast.removeListener(_onChange);
    unawaited(_pipSub?.cancel());
    unawaited(Pip.instance.setAllowed(allowed: false));
    // The stream route closes with the player, so the TV would stall: stop it.
    if (_cast.isCasting) unawaited(_cast.stop());
    c
      ..removeListener(_onChange)
      ..dispose();
    unawaited(WakelockPlus.disable());
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    unawaited(SystemChrome.setPreferredOrientations(const []));
    unawaited(ScreenBrightness.instance.resetApplicationScreenBrightness());
    super.dispose();
  }

  void _scheduleHide() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 4), () {
      if (mounted &&
          c.player.state.playing &&
          !_scrubbing &&
          _panel == _Panel.none) {
        setState(() => _controls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _controls = !_controls);
    if (_controls) _scheduleHide();
  }

  void _showFlash(String text) {
    _flashTimer?.cancel();
    setState(() => _flash = text);
    _flashTimer = Timer(
      Duration(milliseconds: text.length > 24 ? 2600 : 900),
      () {
        if (mounted) setState(() => _flash = null);
      },
    );
  }

  void _open(_Panel p) {
    _hide?.cancel();
    setState(() {
      _panel = p;
      _controls = false;
    });
  }

  void _closePanel() {
    setState(() {
      _panel = _Panel.none;
      _controls = true;
    });
    _scheduleHide();
  }

  // -------------------------------------------------------------- gestures --

  double? _dragStartValue;
  bool _dragLeft = false;

  Future<void> _verticalStart(DragStartDetails d, double width) async {
    _dragLeft = d.localPosition.dx < width / 2;
    _dragStartValue = _dragLeft
        ? await ScreenBrightness.instance.application
        : await VolumeController.instance.getVolume();
  }

  Future<void> _verticalUpdate(DragUpdateDetails d, double height) async {
    final start = _dragStartValue;
    if (start == null) return;
    final next = (start - d.delta.dy / height * 1.2).clamp(0.0, 1.0);
    _dragStartValue = next;
    if (_dragLeft) {
      await ScreenBrightness.instance.setApplicationScreenBrightness(next);
      _showFlash('Brightness ${(next * 100).round()}%');
    } else {
      VolumeController.instance.showSystemUI = false;
      await VolumeController.instance.setVolume(next);
      _showFlash('Volume ${(next * 100).round()}%');
    }
  }

  void _doubleTap(TapDownDetails d, double width) {
    final x = d.localPosition.dx;
    if (x < width * 0.35) {
      unawaited(c.seekRelative(const Duration(seconds: -10)));
      _showFlash('−10 s');
    } else if (x > width * 0.65) {
      unawaited(c.seekRelative(const Duration(seconds: 10)));
      _showFlash('+10 s');
    } else {
      unawaited(c.player.playOrPause());
    }
  }

  // ---------------------------------------------------------------- build --

  @override
  Widget build(BuildContext context) {
    final req = c.request;
    return ArtworkTintScope(
      image: artworkProvider(req.still ?? req.background ?? req.poster),
      child: Scaffold(
        backgroundColor: KColors.blackout,
        body: LayoutBuilder(
          builder: (context, box) {
            TapDownDetails? lastDown;
            return Stack(
              fit: StackFit.expand,
              children: [
                Video(
                  controller: c.video,
                  controls: null,
                  fit: _fill ? BoxFit.cover : BoxFit.contain,
                  subtitleViewConfiguration: const SubtitleViewConfiguration(
                    visible: false,
                  ),
                ),
                SubtitleOverlay(
                  player: c.player,
                  lift: _controls && !_inPip ? 96 : 0,
                ),
                if (!_inPip) ...[
                  // Gesture layer.
                  GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _locked
                        ? () => setState(() => _controls = !_controls)
                        : _toggleControls,
                    onDoubleTapDown: (d) => lastDown = d,
                    onDoubleTap: _locked
                        ? null
                        : () => _doubleTap(lastDown!, box.maxWidth),
                    onVerticalDragStart: _locked
                        ? null
                        : (d) => _verticalStart(d, box.maxWidth),
                    onVerticalDragUpdate: _locked
                        ? null
                        : (d) => _verticalUpdate(d, box.maxHeight),
                    onScaleUpdate: null,
                  ),
                  if (c.phase != PlayerPhase.playing)
                    _PrepareView(
                      controller: c,
                      onBack: () => Navigator.of(context).maybePop(),
                      onVersions: () => _open(_Panel.versions),
                    ),
                  if (c.phase == PlayerPhase.playing && _cast.isCasting)
                    CastingView(controller: c)
                  else if (c.phase == PlayerPhase.playing) ...[
                    _BufferingHint(controller: c),
                    if (_flash != null)
                      Center(child: _FlashLabel(text: _flash!)),
                    AnimatedOpacity(
                      opacity: _controls ? 1 : 0,
                      duration: KMotion.base,
                      child: IgnorePointer(
                        ignoring: !_controls,
                        child: _locked
                            ? _LockedControls(
                                onUnlock: () => setState(() => _locked = false),
                              )
                            : _Controls(
                                controller: c,
                                fill: _fill,
                                onBack: () => Navigator.of(context).maybePop(),
                                onPanel: _open,
                                onLock: () => setState(() {
                                  _locked = true;
                                  _controls = false;
                                }),
                                onFill: () => setState(() => _fill = !_fill),
                                onScrubbing: (s) {
                                  _scrubbing = s;
                                  if (!s) _scheduleHide();
                                },
                                onInteract: _scheduleHide,
                              ),
                      ),
                    ),
                    if (c.skippable case final skip? when _panel == _Panel.none)
                      Align(
                        alignment: Alignment.bottomRight,
                        child: Padding(
                          padding: EdgeInsets.only(
                            right:
                                MediaQuery.paddingOf(context).right +
                                KSpace.margin,
                            bottom:
                                MediaQuery.paddingOf(context).bottom +
                                (_controls ? 120 : 40),
                          ),
                          child: GlassButton(
                            label: skip.label,
                            icon: Icons.fast_forward_rounded,
                            prominent: true,
                            onPressed: c.skip,
                          ),
                        ),
                      ),
                    if (c.inCredits &&
                        !c.upNextDismissed &&
                        _panel == _Panel.none)
                      _UpNext(controller: c),
                  ],
                  if (_panel != _Panel.none)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _closePanel,
                      child: const ColoredBox(color: Color(0x66000000)),
                    ),
                  AnimatedSlide(
                    offset: _panel == _Panel.none
                        ? const Offset(1.1, 0)
                        : Offset.zero,
                    duration: KMotion.base,
                    curve: KMotion.curve,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: switch (_panel) {
                        _Panel.tracks => TracksPanel(
                          controller: c,
                          onClose: _closePanel,
                        ),
                        _Panel.episodes => EpisodesPanel(
                          controller: c,
                          onClose: _closePanel,
                        ),
                        _Panel.speed => SpeedPanel(
                          controller: c,
                          onClose: _closePanel,
                        ),
                        _Panel.cast => CastPanel(
                          controller: c,
                          onClose: _closePanel,
                          onVersions: () => _open(_Panel.versions),
                        ),
                        _Panel.versions => _VersionsPanel(
                          controller: c,
                          onClose: _closePanel,
                        ),
                        _Panel.none => const SizedBox.shrink(),
                      },
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ parts --

class _Controls extends StatelessWidget {
  const _Controls({
    required this.controller,
    required this.fill,
    required this.onBack,
    required this.onPanel,
    required this.onLock,
    required this.onFill,
    required this.onScrubbing,
    required this.onInteract,
  });

  final PlayerController controller;
  final bool fill;
  final VoidCallback onBack;
  final void Function(_Panel) onPanel;
  final VoidCallback onLock;
  final VoidCallback onFill;
  final ValueChanged<bool> onScrubbing;
  final VoidCallback onInteract;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final req = c.request;
    final pad = MediaQuery.paddingOf(context);
    final playing = c.player.state.playing;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0, 0.22, 0.7, 1],
          colors: [
            Color(0x99000000),
            Color(0x00000000),
            Color(0x00000000),
            Color(0xB3000000),
          ],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          pad.left + KSpace.margin,
          pad.top + KSpace.x3,
          pad.right + KSpace.margin,
          pad.bottom + KSpace.x3,
        ),
        child: GlassGroup(
          child: Column(
            children: [
              Row(
                children: [
                  GlassIconButton(
                    icon: Icons.arrow_back_rounded,
                    label: 'Close player',
                    onPressed: onBack,
                  ),
                  const SizedBox(width: KSpace.x3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          req.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: KType.title,
                        ),
                        if (req.isEpisode)
                          Text(
                            'S${req.season} E${req.episode}${req.episodeTitle == null ? '' : '  ${req.episodeTitle}'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: KType.small,
                          ),
                      ],
                    ),
                  ),
                  if (c.engineStats != null) _EngineChip(controller: c),
                  const SizedBox(width: KSpace.x2),
                  GlassIconButton(
                    icon: Icons.cast_rounded,
                    label: 'Play on TV',
                    onPressed: () => onPanel(_Panel.cast),
                  ),
                  const SizedBox(width: KSpace.x2),
                  GlassIconButton(
                    icon: Icons.lock_outline_rounded,
                    label: 'Lock controls',
                    onPressed: onLock,
                  ),
                ],
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (c.previousEpisode != null)
                    GlassIconButton(
                      icon: Icons.skip_previous_rounded,
                      label: 'Previous episode',
                      onPressed: c.playPrevious,
                    ),
                  const SizedBox(width: KSpace.section),
                  GlassIconButton(
                    icon: Icons.replay_10_rounded,
                    label: 'Back 10 seconds',
                    onPressed: () {
                      onInteract();
                      c.seekRelative(const Duration(seconds: -10));
                    },
                    size: 56,
                  ),
                  const SizedBox(width: KSpace.section),
                  GlassIconButton(
                    icon: playing
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    label: playing ? 'Pause' : 'Play',
                    onPressed: () {
                      onInteract();
                      c.player.playOrPause();
                    },
                    size: 76,
                  ),
                  const SizedBox(width: KSpace.section),
                  GlassIconButton(
                    icon: Icons.forward_10_rounded,
                    label: 'Forward 10 seconds',
                    onPressed: () {
                      onInteract();
                      c.seekRelative(const Duration(seconds: 10));
                    },
                    size: 56,
                  ),
                  const SizedBox(width: KSpace.section),
                  if (c.nextEpisode != null)
                    GlassIconButton(
                      icon: Icons.skip_next_rounded,
                      label: 'Next episode',
                      onPressed: c.playNext,
                    ),
                ],
              ),
              const Spacer(),
              StreamBuilder<Duration>(
                stream: c.player.stream.position,
                builder: (context, _) {
                  final st = c.player.state;
                  final es = c.engineStats;
                  return Scrubber(
                    position: st.position,
                    duration: st.duration,
                    buffered: st.buffer,
                    downloaded: es == null || es.size == 0
                        ? null
                        : es.have / es.size,
                    onSeek: c.player.seek,
                    onScrubbing: onScrubbing,
                  );
                },
              ),
              const SizedBox(height: KSpace.x2),
              Row(
                children: [
                  if (req.isEpisode)
                    GlassButton(
                      label: 'Episodes',
                      icon: Icons.video_library_rounded,
                      onPressed: () => onPanel(_Panel.episodes),
                    ),
                  const SizedBox(width: KSpace.x2),
                  GlassButton(
                    label: 'Audio and subtitles',
                    icon: Icons.subtitles_rounded,
                    onPressed: () => onPanel(_Panel.tracks),
                  ),
                  const SizedBox(width: KSpace.x2),
                  GlassButton(
                    label: c.rate == 1 ? 'Speed' : '${c.rate}×',
                    icon: Icons.speed_rounded,
                    onPressed: () => onPanel(_Panel.speed),
                  ),
                  const Spacer(),
                  GlassIconButton(
                    icon: fill
                        ? Icons.fit_screen_rounded
                        : Icons.fullscreen_rounded,
                    label: fill ? 'Fit to screen' : 'Fill screen',
                    onPressed: onFill,
                  ),
                  if (c.nextEpisode != null) ...[
                    const SizedBox(width: KSpace.x2),
                    GlassButton(
                      label: 'Next episode',
                      icon: Icons.skip_next_rounded,
                      prominent: true,
                      onPressed: c.playNext,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EngineChip extends StatelessWidget {
  const _EngineChip({required this.controller});
  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    final s = controller.engineStats!;
    final done = s.size > 0 && s.have >= s.size;
    return Semantics(
      label: done
          ? 'Fully downloaded'
          : '${s.peers} peers, ${Fmt.speed(s.rate)}',
      excludeSemantics: true,
      child: Glass(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Text(
          done
              ? 'Saved on this device'
              : '${s.peers} peers  ${Fmt.speed(s.rate)}',
          style: KType.tabular(
            KType.small.copyWith(color: done ? KColors.go : KColors.lamp),
          ),
        ),
      ),
    );
  }
}

class _LockedControls extends StatelessWidget {
  const _LockedControls({required this.onUnlock});
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.all(KSpace.margin),
        child: GlassButton(
          label: 'Unlock',
          icon: Icons.lock_open_rounded,
          onPressed: onUnlock,
        ),
      ),
    ),
  );
}

class _FlashLabel extends StatelessWidget {
  const _FlashLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Glass(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Text(text, style: KType.tabular(KType.title)),
    ),
  );
}

/// "Buffering" pill when playback stalls mid-way.
class _BufferingHint extends StatelessWidget {
  const _BufferingHint({required this.controller});
  final PlayerController controller;

  @override
  Widget build(BuildContext context) => StreamBuilder<bool>(
    stream: controller.player.stream.buffering,
    initialData: controller.player.state.buffering,
    builder: (context, snap) {
      if (snap.data != true) return const SizedBox.shrink();
      final s = controller.engineStats;
      final detail = s == null
          ? ''
          : '  ${s.peers} peers  ${Fmt.speed(s.rate)}';
      return Center(
        child: IgnorePointer(
          child: Glass(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Text('Buffering$detail', style: KType.tabular(KType.label)),
          ),
        ),
      );
    },
  );
}

/// While preparing: the artwork, the title and what's happening, in words.
class _PrepareView extends StatelessWidget {
  const _PrepareView({
    required this.controller,
    required this.onBack,
    required this.onVersions,
  });

  final PlayerController controller;
  final VoidCallback onBack;
  final VoidCallback onVersions;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final req = c.request;
    final failed = c.phase == PlayerPhase.failed;
    final pad = MediaQuery.paddingOf(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        Opacity(
          opacity: 0.45,
          child: Artwork(url: req.still ?? req.background ?? req.poster),
        ),
        const LegibilityScrim(stops: [0, 1]),
        Padding(
          padding: EdgeInsets.fromLTRB(
            pad.left + KSpace.margin * 2,
            pad.top + KSpace.x3,
            pad.right + KSpace.margin,
            pad.bottom + KSpace.margin,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GlassIconButton(
                icon: Icons.arrow_back_rounded,
                label: 'Close player',
                onPressed: onBack,
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
              if (!failed)
                Glass(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _Pulse(),
                      const SizedBox(width: KSpace.x3),
                      Text(c.status, style: KType.label),
                    ],
                  ),
                )
              else ...[
                Text(c.error ?? 'Playback couldn’t start.', style: KType.body),
                const SizedBox(height: KSpace.x4),
                GlassGroup(
                  child: Row(
                    children: [
                      GlassButton(
                        label: 'Choose another version',
                        prominent: true,
                        onPressed: onVersions,
                      ),
                      const SizedBox(width: KSpace.x3),
                      GlassButton(label: 'Try again', onPressed: c.retry),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A slow breathing dot: shows life without a spinner.
class _Pulse extends StatefulWidget {
  const _Pulse();

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _a.value = 1;
    } else if (!_a.isAnimating) {
      unawaited(_a.repeat(reverse: true));
    }
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween<double>(begin: 0.35, end: 1).animate(_a),
    child: Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: KinoraTint.of(context),
        shape: BoxShape.circle,
      ),
    ),
  );
}

/// Up Next near the credits: counts down, then plays the next episode.
class _UpNext extends StatefulWidget {
  const _UpNext({required this.controller});
  final PlayerController controller;

  @override
  State<_UpNext> createState() => _UpNextState();
}

class _UpNextState extends State<_UpNext> {
  int _left = 10;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    if (widget.controller.request.isEpisode) {
      _t = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return;
        setState(() => _left--);
        if (_left <= 0) {
          t.cancel();
          unawaited(widget.controller.playNext());
        }
      });
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final next = widget.controller.nextEpisode!;
    final pad = MediaQuery.paddingOf(context);
    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          0,
          0,
          pad.right + KSpace.margin,
          pad.bottom + 110,
        ),
        child: SizedBox(
          width: 340,
          child: Glass(
            radius: KRadius.sheet,
            padding: const EdgeInsets.all(KSpace.x4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Next episode in $_left', style: KType.small),
                const SizedBox(height: KSpace.x2),
                Row(
                  children: [
                    SizedBox(
                      width: 112,
                      child: Artwork(
                        url: next.still,
                        radius: KRadius.still,
                        aspectRatio: 16 / 9,
                        memCacheWidth: 260,
                      ),
                    ),
                    const SizedBox(width: KSpace.x3),
                    Expanded(
                      child: Text(
                        'S${next.season} E${next.episode}${next.episodeTitle == null ? '' : '\n${next.episodeTitle}'}',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: KType.label,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: KSpace.x3),
                Row(
                  children: [
                    GlassButton(
                      label: 'Play now',
                      prominent: true,
                      onPressed: widget.controller.playNext,
                    ),
                    const SizedBox(width: KSpace.x2),
                    GlassButton(
                      label: 'Keep watching',
                      onPressed: () {
                        _t?.cancel();
                        widget.controller.upNextDismissed = true;
                        setState(() {});
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Switch to another version without leaving (keeps the position).
class _VersionsPanel extends ConsumerWidget {
  const _VersionsPanel({required this.controller, required this.onClose});

  final PlayerController controller;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = controller.request;
    final result = ref.watch(
      resolveProvider(
        VideoRef(
          type: r.type,
          mediaId: r.mediaId,
          videoId: r.videoId,
          season: r.season,
          episode: r.episode,
        ),
      ),
    );
    return SidePanel(
      title: 'Versions',
      onClose: onClose,
      child: result.when(
        loading: () => Padding(
          padding: const EdgeInsets.all(KSpace.margin),
          child: Text('Finding versions…', style: KType.small),
        ),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(KSpace.margin),
          child: Text('Couldn’t load versions. $e', style: KType.small),
        ),
        data: (res) => res.releases.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(KSpace.margin),
                child: Text(
                  res.message ?? 'No versions found.',
                  style: KType.body,
                ),
              )
            : ListView.builder(
                itemCount: res.releases.length,
                itemBuilder: (context, i) {
                  final v = res.releases[i];
                  final current =
                      controller.source?.release?.candidateId == v.candidateId;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: KSpace.margin,
                      vertical: 4,
                    ),
                    title: Text(v.headline, style: KType.body),
                    subtitle: Text(
                      [...v.reasons.take(2), ...v.warnings.take(1)].join('\n'),
                      style: KType.small,
                    ),
                    trailing: current
                        ? Icon(
                            Icons.check_rounded,
                            color: KinoraTint.of(context),
                          )
                        : null,
                    onTap: current
                        ? null
                        : () {
                            onClose();
                            controller.switchTo(
                              r.copyWith(
                                candidateId: v.candidateId,
                                startAt: controller.player.state.position,
                              ),
                            );
                          },
                  );
                },
              ),
      ),
    );
  }
}
