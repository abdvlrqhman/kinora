import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
import '../../ui/widgets/media.dart';
import '../../ui/widgets/states.dart';
import '../../services/cast_service.dart';
import '../title/versions_sheet.dart';
import 'gestures.dart';
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

  /// Screen reader on: controls stay up (they'd vanish mid-swipe).
  bool _accessible = false;

  /// Double-tap seeks in a row add up ("+30 s").
  int _seekSum = 0;
  Timer? _seekReset;

  /// The last cast failure already shown, so each shows once.
  String? _castNoticeShown;

  /// Whether this player had a cast going at the last change.
  bool _castWasActive = false;

  @override
  void initState() {
    super.initState();
    c = PlayerController(
      ProviderScope.containerOf(context, listen: false),
      widget.request,
    )..addListener(_onChange);
    _cast = ref.read(castServiceProvider)..addListener(_onChange);
    _castWasActive =
        _cast.phase != CastPhase.idle &&
        _cast.phase != CastPhase.stopped &&
        _cast.phase != CastPhase.lost;
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
    unawaited(_readLevels());
    _pipSub = Pip.instance.changes.listen((v) {
      if (mounted) setState(() => _inPip = v);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _accessible = MediaQuery.maybeAccessibleNavigationOf(context) ?? false;
    if (_accessible) {
      _hide?.cancel();
      _controls = true;
    }
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
    // Another episode or version starts at the whole picture.
    final video = '${c.request.videoId}|${c.request.candidateId}';
    if (video != _zoomedVideo) {
      _zoomedVideo = video;
      _zoom = 1;
    }
    final notice = c.notice;
    if (notice != null) {
      c.notice = null;
      _showFlash(notice);
    }
    // A cast from this player that failed or lost the TV says why, once,
    // over the phone view. Older failures stay in the cast picker.
    final phase = _cast.phase;
    final ended = phase == CastPhase.stopped || phase == CastPhase.lost;
    final castNote = _cast.message;
    if (ended &&
        _castWasActive &&
        castNote != null &&
        castNote != _castNoticeShown) {
      _castNoticeShown = castNote;
      _showFlash(castNote);
    }
    _castWasActive = !ended && phase != CastPhase.idle;
    _syncPip();
    setState(() {});
  }

  @override
  void dispose() {
    // After the return flight; listeners can't rebuild while the tree is locked.
    scheduleMicrotask(() => launchingArt.value = null);
    _hide?.cancel();
    _levelHide?.cancel();
    _flashTimer?.cancel();
    _seekReset?.cancel();
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
    if (_accessible) return;
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

  // One finger, vertical: brightness on the left half, volume on the
  // right. Two fingers: pinch to zoom the picture.

  /// Picture zoom, on top of fit/fill (1× to 3×); back to 1× on another
  /// video.
  double _zoom = 1;
  double _zoomStart = 1;
  String? _zoomedVideo;

  /// Fingers on the screen, from the first down to the last up.
  final _touch = TouchSession();

  /// Side of the current session's swipe (set by its first finger).
  bool? _swipeLeftSide;

  /// The brightness or volume being set by the current swipe.
  double? _level;

  /// Last known levels, read when the player opens and refreshed at each
  /// session, so a swipe never waits on the platform before it responds.
  double? _brightnessNow, _volumeNow;

  /// Bumped by every level a swipe sets: a read that started before it is
  /// stale and is dropped.
  int _levelWrites = 0;

  /// Shown on the side being adjusted while swiping.
  ({bool brightness, double value})? _levelShown;
  Timer? _levelHide;

  /// Last double-tap position (kept on the State: a rebuild between the
  /// two taps must not lose it).
  TapDownDetails? _lastDown;

  Future<void> _readLevels() async {
    final writes = _levelWrites;
    try {
      final brightness = await ScreenBrightness.instance.application;
      final volume = await VolumeController.instance.getVolume();
      if (writes != _levelWrites) return; // a swipe set newer values
      _brightnessNow = brightness;
      _volumeNow = volume;
    } on Object {
      // Unknown: swipes start from the middle.
    }
  }

  void _gestureStart(ScaleStartDetails d, double width) {
    // A finger lifted mid-pinch restarts the gesture: pinch from here.
    _zoomStart = _zoom;
    if (_swipeLeftSide == null) {
      _swipeLeftSide = d.localFocalPoint.dx < width / 2;
      unawaited(_readLevels()); // changed with the buttons meanwhile?
    }
  }

  Future<void> _gestureUpdate(ScaleUpdateDetails d, double height) async {
    if (_touch.pinching) {
      if (d.pointerCount < 2) return;
      final z = PlayerGestures.zoom(_zoomStart, d.scale);
      if (z != _zoom) setState(() => _zoom = z);
      _showFlash('Zoom ${(z * 100).round()}%');
      return;
    }
    if (!_touch.swipe(d.focalPointDelta.dx, d.focalPointDelta.dy)) return;
    final left = _swipeLeftSide ?? false;
    final next = PlayerGestures.level(
      _level ?? (left ? _brightnessNow : _volumeNow) ?? 0.5,
      d.focalPointDelta.dy,
      height,
    );
    _level = next;
    _levelWrites++;
    if (left) {
      _brightnessNow = next;
    } else {
      _volumeNow = next;
    }
    _levelHide?.cancel();
    setState(() => _levelShown = (brightness: left, value: next));
    if (left) {
      await ScreenBrightness.instance.setApplicationScreenBrightness(next);
    } else {
      VolumeController.instance.showSystemUI = false;
      await VolumeController.instance.setVolume(next);
    }
  }

  /// The last finger lifted.
  void _touchEnd() {
    final settled = PlayerGestures.settle(_zoom);
    if (settled != _zoom) setState(() => _zoom = settled);
    _swipeLeftSide = null;
    _level = null;
    _levelHide?.cancel();
    _levelHide = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _levelShown = null);
    });
  }

  void _doubleTap(TapDownDetails d, double width) {
    final x = d.localPosition.dx;
    if (x < width * 0.35) {
      _seekBy(-10);
    } else if (x > width * 0.65) {
      _seekBy(10);
    } else {
      unawaited(c.player.playOrPause());
    }
  }

  /// Seeks [seconds] and shows the running total of taps within 700 ms.
  void _seekBy(int seconds) {
    _seekSum = _seekSum.sign == seconds.sign ? _seekSum + seconds : seconds;
    _seekReset?.cancel();
    _seekReset = Timer(const Duration(milliseconds: 700), () => _seekSum = 0);
    unawaited(c.seekRelative(Duration(seconds: seconds)));
    _showFlash(_seekSum > 0 ? '+$_seekSum s' : '−${-_seekSum} s');
  }

  /// Height of the scrubber and bottom row, so subtitles sit above them.
  double _controlsHeight(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return MediaQuery.paddingOf(context).bottom +
        KSpace.x3 +
        math.max(44, scaler.scale(18)) +
        KSpace.x2 +
        math.max(48, scaler.scale(22) + 26) +
        KSpace.x2;
  }

  // ---------------------------------------------------------------- build --

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final motion = reduce ? Duration.zero : KMotion.base;
    return Scaffold(
      backgroundColor: KColors.blackout,
      body: LayoutBuilder(
        builder: (context, box) {
          return Stack(
            fit: StackFit.expand,
            children: [
              Transform.scale(
                // The floating window always shows the whole picture.
                scale: _inPip ? 1 : _zoom,
                child: Video(
                  controller: c.video,
                  controls: null,
                  fit: _fill ? BoxFit.cover : BoxFit.contain,
                  subtitleViewConfiguration: const SubtitleViewConfiguration(
                    visible: false,
                  ),
                ),
              ),
              SubtitleOverlay(
                player: c.player,
                clearance: _controls && !_inPip ? _controlsHeight(context) : 0,
                // Play row (76) and its buffering ring (86), plus a gap.
                belowCenter: _controls && !_inPip && !_locked ? 52 : 0,
              ),
              if (!_inPip) ...[
                // Gesture layer. The Listener counts fingers for the
                // whole touch (see TouchSession).
                Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: (_) => _touch.fingerDown(),
                  onPointerUp: (_) {
                    if (_touch.fingerUp()) _touchEnd();
                  },
                  onPointerCancel: (_) {
                    if (_touch.fingerUp()) _touchEnd();
                  },
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _locked
                        ? () => setState(() => _controls = !_controls)
                        : _toggleControls,
                    onDoubleTapDown: (d) => _lastDown = d,
                    onDoubleTap: _locked
                        ? null
                        : () {
                            if (_lastDown case final d?) {
                              _doubleTap(d, box.maxWidth);
                            }
                          },
                    onScaleStart: _locked
                        ? null
                        : (d) => _gestureStart(d, box.maxWidth),
                    onScaleUpdate: _locked
                        ? null
                        : (d) => unawaited(_gestureUpdate(d, box.maxHeight)),
                  ),
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
                  // Buffering and seek/volume feedback: centered while the
                  // controls are hidden, above the play row while they
                  // show, so nothing covers it.
                  if (!_controls || _locked)
                    Center(
                      child: _Status(controller: c, flash: _flash),
                    ),
                  AnimatedOpacity(
                    opacity: _controls ? 1 : 0,
                    duration: motion,
                    child: IgnorePointer(
                      ignoring: !_controls,
                      child: _locked
                          ? _LockedControls(
                              onUnlock: () => setState(() => _locked = false),
                            )
                          : _Controls(
                              controller: c,
                              // Buffering shows as the Play ring and the
                              // top-bar chip here: one pill at most.
                              status: _Status(
                                controller: c,
                                flash: _flash,
                                buffering: false,
                              ),
                              onSeekBy: _seekBy,
                              fill: _fill,
                              onBack: () => Navigator.of(context).maybePop(),
                              onPanel: _open,
                              onLock: () => setState(() {
                                _locked = true;
                                _controls = false;
                              }),
                              onFill: () => setState(() {
                                _fill = !_fill;
                                _zoom = 1;
                              }),
                              onScrubbing: (s) {
                                _scrubbing = s;
                                if (!s) _scheduleHide();
                              },
                              onInteract: _scheduleHide,
                            ),
                    ),
                  ),
                  if (_levelShown case final l?)
                    _LevelIndicator(brightness: l.brightness, value: l.value),
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
                    // Under the controls it would cover Play and +10; the
                    // bar has Next episode then. Kept, so it resumes.
                    // (With a screen reader the controls never hide, so
                    // it stays reachable there.)
                    Offstage(
                      offstage: _controls && !_locked && !_accessible,
                      child: _UpNext(
                        controller: c,
                        paused: _controls && !_locked && !_accessible,
                      ),
                    ),
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
                  duration: motion,
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
    );
  }
}

// ------------------------------------------------------------------ parts --

class _Controls extends StatelessWidget {
  const _Controls({
    required this.controller,
    required this.status,
    required this.onSeekBy,
    required this.fill,
    required this.onBack,
    required this.onPanel,
    required this.onLock,
    required this.onFill,
    required this.onScrubbing,
    required this.onInteract,
  });

  final PlayerController controller;
  final Widget status;
  final ValueChanged<int> onSeekBy;
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
    return Stack(
      fit: StackFit.expand,
      children: [
        // The shade takes no touches: swipes and taps on empty space reach
        // the gesture layer below while the controls show.
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
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
          ),
        ),
        Padding(
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
                      icon: Icons.chevron_left_rounded,
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
                            textDirection: contentDir(req.title),
                            style: KType.title,
                          ),
                          if (req.isEpisode)
                            Text(
                              _episodeLine(req),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: KType.small,
                            ),
                        ],
                      ),
                    ),
                    if (c.engineStats case final es?
                        when (es.size > 0 && es.have >= es.size) ||
                            c.player.state.buffering)
                      Flexible(child: _EngineChip(controller: c)),
                    const SizedBox(width: KSpace.x2),
                    GlassIconButton(
                      icon: Icons.cast_rounded,
                      label: 'Cast to a TV',
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
                // The status sits above the row without moving it off center.
                Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 76 + KSpace.x3,
                      // ~60 pt above the row in landscape: keep it short.
                      child: MediaQuery.withClampedTextScaling(
                        maxScaleFactor: 1.3,
                        child: Center(child: status),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        GlassIconButton(
                          icon: Icons.replay_10_rounded,
                          label: 'Back 10 seconds',
                          onPressed: () {
                            onInteract();
                            onSeekBy(-10);
                          },
                          size: 56,
                        ),
                        const SizedBox(width: KSpace.section),
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            _BufferRing(controller: c),
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
                          ],
                        ),
                        const SizedBox(width: KSpace.section),
                        GlassIconButton(
                          icon: Icons.forward_10_rounded,
                          label: 'Forward 10 seconds',
                          onPressed: () {
                            onInteract();
                            onSeekBy(10);
                          },
                          size: 56,
                        ),
                      ],
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
                    if (req.isEpisode) ...[
                      GlassIconButton(
                        icon: Icons.video_library_rounded,
                        label: 'Episodes',
                        onPressed: () => onPanel(_Panel.episodes),
                      ),
                      const SizedBox(width: KSpace.x2),
                    ],
                    GlassIconButton(
                      icon: Icons.subtitles_rounded,
                      label: 'Audio and subtitles',
                      onPressed: () => onPanel(_Panel.tracks),
                    ),
                    const SizedBox(width: KSpace.x2),
                    if (c.rate == 1)
                      GlassIconButton(
                        icon: Icons.speed_rounded,
                        label: 'Playback speed',
                        onPressed: () => onPanel(_Panel.speed),
                      )
                    else
                      GlassButton(
                        label: '${c.rate}×',
                        semanticLabel: 'Playback speed ${c.rate} times',
                        onPressed: () => onPanel(_Panel.speed),
                      ),
                    const SizedBox(width: KSpace.x2),
                    GlassIconButton(
                      icon: fill
                          ? Icons.fit_screen_rounded
                          : Icons.fullscreen_rounded,
                      label: fill ? 'Fit to screen' : 'Fill screen',
                      onPressed: onFill,
                    ),
                    // All the room that's left, button at its right edge
                    // (a Spacer beside a Flexible split it in half).
                    Expanded(
                      child: Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: c.nextEpisode == null
                            ? null
                            : GlassButton(
                                label: 'Next episode',
                                icon: Icons.skip_next_rounded,
                                prominent: true,
                                onPressed: c.playNext,
                              ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Brightness (left) or volume (right) while swiping: an icon over a
/// level bar, on the side being adjusted.
class _LevelIndicator extends StatelessWidget {
  const _LevelIndicator({required this.brightness, required this.value});

  final bool brightness;
  final double value;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final icon = brightness
        ? Icons.light_mode_rounded
        : value == 0
        ? Icons.volume_off_rounded
        : Icons.volume_up_rounded;
    final label =
        '${brightness ? 'Brightness' : 'Volume'} ${(value * 100).round()}%';
    return Align(
      alignment: brightness ? Alignment.centerLeft : Alignment.centerRight,
      child: Padding(
        padding: EdgeInsets.only(
          left: pad.left + KSpace.section,
          right: pad.right + KSpace.section,
        ),
        child: IgnorePointer(
          child: Semantics(
            liveRegion: true,
            label: label,
            excludeSemantics: true,
            child: Glass(
              radius: KRadius.sheet,
              padding: const EdgeInsets.symmetric(
                horizontal: KSpace.x3,
                vertical: KSpace.x4,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 22, color: KColors.lamp),
                  const SizedBox(height: KSpace.x3),
                  SizedBox(
                    width: 6,
                    height: 120,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: Stack(
                        children: [
                          const Positioned.fill(
                            child: ColoredBox(color: Color(0x33F5EEE4)),
                          ),
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: FractionallySizedBox(
                              heightFactor: value,
                              widthFactor: 1,
                              child: const ColoredBox(color: KColors.lamp),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: KSpace.x2),
                  Text(
                    '${(value * 100).round()}',
                    style: KType.tabular(
                      KType.small.copyWith(color: KColors.lamp),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Around the Play button while buffering (controls up): how close the
/// stream is to playing on.
class _BufferRing extends StatelessWidget {
  const _BufferRing({required this.controller});
  final PlayerController controller;

  @override
  Widget build(BuildContext context) => StreamBuilder<bool>(
    stream: controller.player.stream.buffering,
    initialData: controller.player.state.buffering,
    builder: (context, snap) {
      if (snap.data != true) return const SizedBox.shrink();
      final ready = controller.engineStats?.ready;
      return IgnorePointer(
        child: SizedBox.square(
          dimension: 86,
          child: CircularProgressIndicator(
            value: ready == null ? null : ready / 100,
            strokeWidth: 3,
            color: KColors.lamp,
            backgroundColor: const Color(0x33F5EEE4),
          ),
        ),
      );
    },
  );
}

class _EngineChip extends StatelessWidget {
  const _EngineChip({required this.controller});
  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    final s = controller.engineStats!;
    final done = s.size > 0 && s.have >= s.size;
    final waiting = !done && controller.player.state.buffering;
    return Semantics(
      liveRegion: waiting,
      label: done
          ? 'Fully downloaded'
          : waiting
          ? 'Buffering ${s.ready}%, ${s.peers} peers, ${Fmt.speed(s.rate)}'
          : '${s.peers} peers, ${Fmt.speed(s.rate)}',
      excludeSemantics: true,
      child: Glass(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Text(
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          done
              ? 'Saved on this device'
              : waiting
              ? 'Buffering ${s.ready}%  ${s.peers} peers  ${Fmt.speed(s.rate)}'
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
/// Buffering and the latest seek/volume/brightness feedback, stacked.
class _Status extends StatelessWidget {
  const _Status({
    required this.controller,
    required this.flash,
    this.buffering = true,
  });
  final PlayerController controller;
  final String? flash;
  final bool buffering;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (buffering) _BufferingHint(controller: controller),
      if (flash != null) ...[
        const SizedBox(height: KSpace.x2),
        _FlashLabel(text: flash!),
      ],
    ],
  );
}

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
          : ' ${s.ready}%  ${s.peers} peers  ${Fmt.speed(s.rate)}';
      return IgnorePointer(
        child: Glass(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Text('Buffering$detail', style: KType.tabular(KType.label)),
        ),
      );
    },
  );
}

/// "S1 E3  Pilot", the episode title isolated so its direction can't
/// reorder the line.
String _episodeLine(PlayRequest r) => [
  'S${r.season} E${r.episode}',
  if (r.episodeTitle != null) isolate(r.episodeTitle!),
].join('  ');

/// While preparing: the artwork you tapped (grown into the screen), the
/// title, the version being started and what's happening, in words. On
/// failure, what to do next.
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
    final width = MediaQuery.sizeOf(context).width;
    final art = Artwork(
      url: req.still ?? req.background ?? req.poster,
      memCacheWidth: decodeWidth(context, width),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        Hero(
          tag: artHeroTag(req.videoId),
          curve: KMotion.emphasized,
          // Full strength in the tile, dimmed in the player. The route
          // animation runs 1→0 on pop, so one tween covers both directions.
          flightShuttleBuilder: (_, animation, _, _, _) => FadeTransition(
            opacity: Tween<double>(begin: 1, end: 0.45).animate(animation),
            child: art,
          ),
          child: Opacity(opacity: 0.45, child: art),
        ),
        const LegibilityScrim(stops: [0, 1]),
        FillOrScroll(
          // Same edges as the controls, so Back doesn't jump at playback.
          padding: EdgeInsets.fromLTRB(
            pad.left + KSpace.margin,
            pad.top + KSpace.x3,
            pad.right + KSpace.margin,
            pad.bottom + KSpace.margin,
          ),
          top: GlassGroup(
            child: GlassIconButton(
              icon: Icons.chevron_left_rounded,
              label: 'Close player',
              onPressed: onBack,
            ),
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
                  _episodeLine(req),
                  style: KType.title.copyWith(color: KColors.haze),
                ),
              const SizedBox(height: KSpace.margin),
              // Kinora moved on from a version on its own: say so.
              if (!failed && c.prepareNote != null) ...[
                Semantics(
                  liveRegion: true,
                  child: Text(
                    c.prepareNote!,
                    style: KType.body.copyWith(color: KColors.caution),
                  ),
                ),
                const SizedBox(height: KSpace.x2),
              ],
              if (!failed && c.starting != null) ...[
                Text(
                  [
                    c.starting!.headline,
                    ...c.starting!.reasons.take(1),
                  ].join('  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: KType.label.copyWith(color: KColors.haze),
                ),
                const SizedBox(height: KSpace.x2),
              ],
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
                      Flexible(
                        child: Semantics(
                          liveRegion: true,
                          child: Text(c.status, style: KType.label),
                        ),
                      ),
                    ],
                  ),
                ),
              // A slow start doesn't have to be waited out.
              if (!failed && c.starting != null) ...[
                const SizedBox(height: KSpace.x3),
                GlassButton(
                  label: 'Choose another version',
                  onPressed: onVersions,
                ),
              ],
              if (failed) ...[
                Semantics(
                  liveRegion: true,
                  child: Text(
                    c.error ?? 'Playback couldn’t start.',
                    style: KType.body,
                  ),
                ),
                const SizedBox(height: KSpace.x4),
                GlassGroup(
                  child: Wrap(
                    spacing: KSpace.x3,
                    runSpacing: KSpace.x3,
                    children: switch (c.failureAction) {
                      // Nothing can stream yet: the fix is a source.
                      FailureAction.addSource => [
                        GlassButton(
                          label: 'Add a source',
                          icon: Icons.add_rounded,
                          prominent: true,
                          onPressed: () => context.go('/settings/sources'),
                        ),
                      ],
                      // A pasted link has no other versions.
                      FailureAction.retry => [
                        GlassButton(
                          label: 'Try again',
                          prominent: true,
                          onPressed: c.retry,
                        ),
                      ],
                      FailureAction.versions => [
                        GlassButton(
                          label: 'Choose another version',
                          prominent: true,
                          onPressed: onVersions,
                        ),
                        GlassButton(label: 'Try again', onPressed: c.retry),
                      ],
                    },
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

/// Up Next near the credits: counts down inside its Play button (whose
/// fill drains over 10 s), then plays the next episode.
class _UpNext extends StatefulWidget {
  const _UpNext({required this.controller, this.paused = false});
  final PlayerController controller;

  /// Hidden behind the controls: the countdown waits.
  final bool paused;

  @override
  State<_UpNext> createState() => _UpNextState();
}

class _UpNextState extends State<_UpNext> with SingleTickerProviderStateMixin {
  static const _seconds = 10;
  int _left = _seconds;
  Timer? _t;
  late final AnimationController _drain = AnimationController(
    vsync: this,
    duration: const Duration(seconds: _seconds),
    value: 1,
  );

  bool get _counting =>
      widget.controller.request.isEpisode && widget.controller.autoplayNext;

  @override
  void initState() {
    super.initState();
    if (_counting && !widget.paused) _run();
  }

  void _run() {
    _t?.cancel();
    _t = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _left--);
      if (_left <= 0) {
        t.cancel();
        unawaited(widget.controller.playNext());
      }
    });
  }

  @override
  void didUpdateWidget(_UpNext old) {
    super.didUpdateWidget(old);
    if (old.paused == widget.paused || !_counting || _left <= 0) return;
    if (widget.paused) {
      _t?.cancel();
      _drain.stop();
    } else if (!widget.controller.upNextDismissed) {
      _run();
      final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      if (!reduce) unawaited(_drain.reverse(from: _left / _seconds));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!_counting || reduce) {
      _drain
        ..stop()
        ..value = 1;
    } else if (!_drain.isAnimating && _t != null && _t!.isActive) {
      unawaited(_drain.reverse(from: _left / _seconds));
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    _drain.dispose();
    super.dispose();
  }

  void _keepWatching() {
    _t?.cancel();
    _drain.stop();
    widget.controller.upNextDismissed = true;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final next = widget.controller.nextEpisode!;
    final pad = MediaQuery.paddingOf(context);
    final width = math.min(380.0, MediaQuery.sizeOf(context).width * 0.45);
    final name = next.episodeTitle ?? 'Episode ${next.episode}';
    final counting = _t?.isActive ?? false;
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
          width: width,
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.5,
            child: Glass(
              radius: KRadius.sheet,
              padding: const EdgeInsets.all(KSpace.x4),
              // Scrolls instead of overflowing when space shrinks (rotation
              // back to portrait as the player closes, very large text).
              child: SingleChildScrollView(
                primary: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 112,
                          child: Artwork(
                            url: next.still,
                            radius: KRadius.still,
                            aspectRatio: 16 / 9,
                            memCacheWidth: decodeWidth(context, 112),
                          ),
                        ),
                        const SizedBox(width: KSpace.x3),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Up next  S${next.season} E${next.episode}',
                                style: KType.tabular(KType.small),
                              ),
                              Text(
                                name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textDirection: contentDir(name),
                                style: KType.title,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: KSpace.x3),
                    GlassGroup(
                      child: Wrap(
                        spacing: KSpace.x2,
                        runSpacing: KSpace.x2,
                        children: [
                          _CountdownButton(
                            seconds: counting ? _left : null,
                            drain: _drain,
                            onPressed: widget.controller.playNext,
                          ),
                          GlassButton(
                            label: 'Keep watching',
                            onPressed: _keepWatching,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Play now  7": a lit capsule whose fill drains as the count runs down.
/// The drained part turns pale, so the dark label reads all the way.
class _CountdownButton extends StatelessWidget {
  const _CountdownButton({
    required this.seconds,
    required this.drain,
    required this.onPressed,
  });

  /// Seconds left; null when not counting down.
  final int? seconds;
  final Animation<double> drain;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final lit = KinoraTint.lit(context);
    final label = KType.title.copyWith(
      color: KColors.blackout,
      fontWeight: FontWeight.w700,
      fontVariations: const [FontVariation.weight(700)],
    );
    return Semantics(
      button: true,
      label: seconds == null
          ? 'Play the next episode now'
          : 'Play the next episode now. It starts in $seconds seconds',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onPressed();
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: ClipPath(
            clipper: const ShapeBorderClipper(shape: StadiumBorder()),
            child: Stack(
              children: [
                Positioned.fill(
                  child: ColoredBox(color: Color.lerp(lit, KColors.lamp, 0.6)!),
                ),
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: drain,
                    builder: (_, _) => FractionallySizedBox(
                      alignment: AlignmentDirectional.centerStart,
                      widthFactor: drain.value,
                      child: ColoredBox(color: lit),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 13,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.play_arrow_rounded,
                        size: 20,
                        color: KColors.blackout,
                      ),
                      const SizedBox(width: KSpace.x2),
                      Flexible(
                        child: Text(
                          'Play now',
                          style: label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (seconds != null)
                        Text('  $seconds', style: KType.tabular(label)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Switch to another version without leaving (keeps the position): the
/// same rows as the title page's version sheet.
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
    Widget note(String text) => Padding(
      padding: const EdgeInsets.all(KSpace.margin),
      child: Text(text, style: KType.body.copyWith(color: KColors.haze)),
    );
    return SidePanel(
      title: 'Choose another version',
      onClose: onClose,
      child: switch (result) {
        AsyncValue(:final value?) when value.releases.isNotEmpty =>
          ListView.builder(
            itemCount: value.releases.length,
            itemBuilder: (context, i) {
              final v = value.releases[i];
              return ReleaseTile(
                release: v,
                isBest: i == 0,
                current:
                    controller.source?.release?.candidateId == v.candidateId,
                onTap: () {
                  onClose();
                  controller.switchTo(
                    r.copyWith(
                      candidateId: v.candidateId,
                      // A chosen version streams, even if a download exists.
                      clearLocal: true,
                      startAt: controller.phase == PlayerPhase.playing
                          ? controller.player.state.position
                          : null,
                    ),
                  );
                },
              );
            },
          ),
        AsyncValue(:final value?) when value.noStreamSource => ListView(
          children: [
            note(value.message ?? 'Add a source that provides streams.'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: KSpace.margin),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: GlassButton(
                  label: 'Add a source',
                  icon: Icons.add_rounded,
                  prominent: true,
                  onPressed: () => context.go('/settings/sources'),
                ),
              ),
            ),
          ],
        ),
        AsyncValue(:final value?) => note(
          value.message ?? 'No versions found.',
        ),
        AsyncError(:final error) => note(
          'Couldn’t load versions. ${friendlyError(error)}',
        ),
        _ => note('Finding versions…'),
      },
    );
  }
}
