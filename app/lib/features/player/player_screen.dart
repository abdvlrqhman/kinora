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

import '../../app/desktop.dart';
import '../../core/log.dart';
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
    _castWasActive = _cast.isCasting;
    unawaited(c.start());
    unawaited(WakelockPlus.enable());
    if (!isDesktop) {
      unawaited(
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
      );
      unawaited(
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]),
      );
      // (A computer's screen and speakers aren't the player's to change.)
      unawaited(_readLevels());
    } else {
      // Autofocus can lose to the route's own focus as the page opens.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _takeKeys();
      });
    }
    _scheduleHide();
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
    // A cast from this player that ended on the TV's side says why, once,
    // over the phone view. Older failures stay in the cast picker.
    final castNote = _cast.message;
    if (_cast.phase == CastPhase.stopped &&
        _castWasActive &&
        castNote != null &&
        castNote != _castNoticeShown) {
      _castNoticeShown = castNote;
      _showFlash(castNote);
    }
    _castWasActive = _cast.isCasting;
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
    _keyFocus.dispose();
    _cast.removeListener(_onChange);
    unawaited(_pipSub?.cancel());
    unawaited(Pip.instance.setAllowed(allowed: false));
    // The stream route closes with the player, so the TV would stall: stop it.
    if (_cast.isCasting) unawaited(_cast.stop());
    c
      ..removeListener(_onChange)
      ..dispose();
    unawaited(WakelockPlus.disable());
    if (isDesktop) {
      unawaited(setFullScreen(false));
    } else {
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
      unawaited(keepPhoneUpright());
      unawaited(ScreenBrightness.instance.resetApplicationScreenBrightness());
    }
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
    _takeKeys();
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
    try {
      if (left) {
        await ScreenBrightness.instance.setApplicationScreenBrightness(next);
      } else {
        VolumeController.instance.showSystemUI = false;
        await VolumeController.instance.setVolume(next);
      }
    } on Object catch (e) {
      // iOS can't always reach its volume slider (the simulator, AirPlay):
      // the player's own volume instead. Brightness just stays.
      Log.d('player', 'level: $e');
      if (!left) await c.player.setVolume(next * 100);
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

  // --------------------------------------------------------------- desktop --

  /// Volume before M muted it.
  double? _unmuted;

  /// Holds the keys. Focus inside it reaches [_keys]; a closed panel or
  /// sheet drops focus to the route, above it, so the keys went dead.
  final _keyFocus = FocusNode(debugLabel: 'player keys');

  /// Takes the keys back unless a panel or a control inside has them.
  void _takeKeys() {
    if (isDesktop && _panel == _Panel.none && !_keyFocus.hasFocus) {
      _keyFocus.requestFocus();
    }
  }

  void _desktopShow() {
    if (!_controls) setState(() => _controls = true);
    _scheduleHide();
    _takeKeys();
  }

  void _togglePlay() {
    unawaited(c.player.playOrPause());
    _desktopShow();
  }

  void _volumeBy(double step) {
    final v = (c.player.state.volume + step).clamp(0.0, 100.0);
    _unmuted = null;
    unawaited(c.player.setVolume(v));
    _showFlash('Volume ${v.round()}%');
  }

  void _toggleMute() {
    final before = _unmuted;
    if (before == null) {
      _unmuted = c.player.state.volume;
      unawaited(c.player.setVolume(0));
      _showFlash('Muted');
    } else {
      _unmuted = null;
      unawaited(c.player.setVolume(before));
      _showFlash('Volume ${before.round()}%');
    }
  }

  void _toggleFullScreen() => unawaited(setFullScreen(!windowFullScreen.value));

  /// The keys every computer video player answers to.
  Map<ShortcutActivator, VoidCallback> get _keys => {
    const SingleActivator(LogicalKeyboardKey.space): _togglePlay,
    const SingleActivator(LogicalKeyboardKey.keyK): _togglePlay,
    const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _seekBy(-10),
    const SingleActivator(LogicalKeyboardKey.keyJ): () => _seekBy(-10),
    const SingleActivator(LogicalKeyboardKey.arrowRight): () => _seekBy(10),
    const SingleActivator(LogicalKeyboardKey.keyL): () => _seekBy(10),
    const SingleActivator(LogicalKeyboardKey.arrowUp): () => _volumeBy(5),
    const SingleActivator(LogicalKeyboardKey.arrowDown): () => _volumeBy(-5),
    const SingleActivator(LogicalKeyboardKey.keyM): _toggleMute,
    const SingleActivator(LogicalKeyboardKey.keyF): _toggleFullScreen,
  };

  /// Height of the scrubber and bottom row, so subtitles sit above them.
  double _controlsHeight(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return MediaQuery.paddingOf(context).bottom +
        KSpace.x3 +
        math.max(44, scaler.scale(18)) +
        KSpace.x2 +
        math.max(44, scaler.scale(22) + 20) +
        KSpace.x2;
  }

  // ---------------------------------------------------------------- build --

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final motion = reduce ? Duration.zero : KMotion.base;
    final page = Scaffold(
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
                // Play row (64) and its buffering ring (72), plus a gap.
                belowCenter: _controls && !_inPip && !_locked ? 46 : 0,
                rightCover: _panel == _Panel.none || _inPip
                    ? 0
                    : SidePanel.coverOf(context),
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
                    // A computer: click to pause, double-click for full
                    // screen, no swipes (a mouse drag isn't a level).
                    onTap: isDesktop
                        ? _togglePlay
                        : _locked
                        ? () => setState(() => _controls = !_controls)
                        : _toggleControls,
                    onDoubleTapDown: (d) => _lastDown = d,
                    onDoubleTap: isDesktop
                        ? _toggleFullScreen
                        : _locked
                        ? null
                        : () {
                            if (_lastDown case final d?) {
                              _doubleTap(d, box.maxWidth);
                            }
                          },
                    onScaleStart: _locked || isDesktop
                        ? null
                        : (d) => _gestureStart(d, box.maxWidth),
                    onScaleUpdate: _locked || isDesktop
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
                  CastingView(
                    controller: c,
                    onBack: () => Navigator.of(context).maybePop(),
                  )
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
                              // Seek/zoom feedback and buffering share the
                              // top bar's chip slot here: never over a row.
                              flash: _flash,
                              onSeekBy: _seekBy,
                              fill: _fill,
                              onBack: () => Navigator.of(context).maybePop(),
                              onPanel: _open,
                              onLock: () => setState(() {
                                _locked = true;
                                _controls = false;
                              }),
                              onFullScreen: isDesktop
                                  ? _toggleFullScreen
                                  : null,
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
                          right: playerEdges(context).right + KSpace.margin,
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
    if (!isDesktop) return page;
    // The pointer shows the controls (and hides with them); keys work
    // without a click first.
    return CallbackShortcuts(
      bindings: _keys,
      child: Focus(
        focusNode: _keyFocus,
        autofocus: true,
        child: MouseRegion(
          cursor: _controls || c.phase != PlayerPhase.playing
              ? MouseCursor.defer
              : SystemMouseCursors.none,
          onHover: (_) => _desktopShow(),
          child: page,
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ parts --

class _Controls extends StatelessWidget {
  const _Controls({
    required this.controller,
    required this.flash,
    required this.onSeekBy,
    required this.fill,
    required this.onBack,
    required this.onPanel,
    required this.onLock,
    this.onFullScreen,
    required this.onFill,
    required this.onScrubbing,
    required this.onInteract,
  });

  final PlayerController controller;

  /// Seek, zoom or level feedback, shown in the top bar's chip slot.
  final String? flash;
  final ValueChanged<int> onSeekBy;
  final bool fill;
  final VoidCallback onBack;
  final void Function(_Panel) onPanel;
  final VoidCallback onLock;

  /// A computer: full screen in Lock's place (a mouse can't tap by mistake).
  final VoidCallback? onFullScreen;
  final VoidCallback onFill;
  final ValueChanged<bool> onScrubbing;
  final VoidCallback onInteract;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final req = c.request;
    final pad = playerEdges(context);
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
                // Dark enough behind the title and the times for AA contrast
                // over a white scene; clear in the middle.
                stops: [0, 0.12, 0.32, 0.5, 0.75, 1],
                colors: [
                  Color(0xCC000000),
                  Color(0xCC000000),
                  Color(0x00000000),
                  Color(0x00000000),
                  Color(0xCC000000),
                  Color(0xCC000000),
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
                      size: 44,
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
                    // Its slot ends at the buttons: Cast and Lock stay at
                    // the edge (a loose Flexible left the rest empty).
                    if (flash != null)
                      Flexible(
                        child: Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: _FlashChip(text: flash!),
                        ),
                      )
                    else if (c.engineStats case final es?
                        when (es.size > 0 && es.have >= es.size) ||
                            c.player.state.buffering)
                      Flexible(
                        child: Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: _EngineChip(controller: c),
                        ),
                      ),
                    const SizedBox(width: KSpace.x2),
                    GlassIconButton(
                      icon: Icons.cast_rounded,
                      label: 'Cast to a TV',
                      onPressed: () => onPanel(_Panel.cast),
                      size: 44,
                    ),
                    const SizedBox(width: KSpace.x2),
                    if (onFullScreen case final full?)
                      ValueListenableBuilder(
                        valueListenable: windowFullScreen,
                        builder: (_, on, _) => GlassIconButton(
                          icon: on
                              ? Icons.fullscreen_exit_rounded
                              : Icons.fullscreen_rounded,
                          label: on
                              ? 'Exit full screen (F)'
                              : 'Full screen (F)',
                          onPressed: full,
                          size: 44,
                        ),
                      )
                    else
                      GlassIconButton(
                        icon: Icons.lock_outline_rounded,
                        label: 'Lock controls',
                        onPressed: onLock,
                        size: 44,
                      ),
                  ],
                ),
                // Between the bars (not the screen's exact middle): on a
                // short screen the subtitles above the scrubber stay clear.
                const Spacer(),
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
                      size: 48,
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
                          size: 64,
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
                      size: 48,
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
                        size: 44,
                      ),
                      const SizedBox(width: KSpace.x2),
                    ],
                    GlassIconButton(
                      icon: Icons.subtitles_rounded,
                      label: 'Audio and subtitles',
                      onPressed: () => onPanel(_Panel.tracks),
                      size: 44,
                    ),
                    const SizedBox(width: KSpace.x2),
                    if (c.rate == 1)
                      GlassIconButton(
                        icon: Icons.speed_rounded,
                        label: 'Playback speed',
                        onPressed: () => onPanel(_Panel.speed),
                        size: 44,
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
                          // Fill (crop to the screen), not "fullscreen":
                          // the player already is.
                          : Icons.aspect_ratio_rounded,
                      label: fill ? 'Fit to screen' : 'Fill screen',
                      onPressed: onFill,
                      size: 44,
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
                                compact: true,
                                // Quiet glass until the credits: during the
                                // episode Play leads, and a stray thumb in
                                // this corner shouldn't land on a lit button.
                                prominent: c.inCredits,
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
    final pad = playerEdges(context);
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
          left: pad.left + KSpace.margin,
          right: pad.right + KSpace.margin,
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
                    '${(value * 100).round()}%',
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
          dimension: 72,
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

/// Seek or zoom feedback in the top bar while the controls show.
class _FlashChip extends StatelessWidget {
  const _FlashChip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    liveRegion: true,
    label: text,
    excludeSemantics: true,
    child: Glass(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: KType.tabular(KType.small.copyWith(color: KColors.lamp)),
      ),
    ),
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
          ? '${_buffering(s)}, ${s.peers} peers, ${Fmt.speed(s.rate)}'
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
              ? '${_buffering(s)}  ${s.peers} peers  ${Fmt.speed(s.rate)}'
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

  // Where the Lock button was.
  @override
  Widget build(BuildContext context) {
    final pad = playerEdges(context);
    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: EdgeInsets.only(
          top: pad.top + KSpace.x3,
          right: pad.right + KSpace.margin,
        ),
        child: GlassButton(
          label: 'Unlock',
          icon: Icons.lock_open_rounded,
          onPressed: onUnlock,
        ),
      ),
    );
  }
}

class _FlashLabel extends StatelessWidget {
  const _FlashLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    // Its own node, so a screen reader says "Volume 60%" as it changes.
    child: Semantics(
      container: true,
      liveRegion: true,
      label: text,
      excludeSemantics: true,
      child: Glass(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Text(text, style: KType.tabular(KType.title)),
      ),
    ),
  );
}

/// "Buffering" pill when playback stalls mid-way.
/// Buffering and the latest seek/volume/brightness feedback, stacked.
class _Status extends StatelessWidget {
  const _Status({required this.controller, required this.flash});
  final PlayerController controller;
  final String? flash;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _BufferingHint(controller: controller),
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
      final text = s == null
          ? 'Buffering'
          : '${_buffering(s)}  ${s.peers} peers  ${Fmt.speed(s.rate)}';
      return IgnorePointer(
        child: Glass(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Text(text, style: KType.tabular(KType.label)),
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
    final pad = playerEdges(context);
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
              size: 44,
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
    final pad = playerEdges(context);
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

/// "Buffering 45%", or "Almost ready" once start-up got near done and the
/// player is reading another part of the file (see startupReady).
String _buffering(
  ({
    int bufferedAhead,
    int have,
    int size,
    int peers,
    int rate,
    int ready,
    bool finishing,
  })
  s,
) => s.finishing ? 'Almost ready' : 'Buffering ${s.ready}%';
