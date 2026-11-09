import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Side insets for everything in the player. In landscape an iPhone reports
/// its Dynamic Island inset (59 pt) on both sides, though the island only
/// takes the first ~48 pt of one edge: capped at 32, plus each element's
/// own margin (20 or more), nothing reaches it and the controls use the
/// screen's width. Android reports its cutout's real side, so its insets
/// stay. Every overlay uses this, so their edges line up.
EdgeInsets playerEdges(BuildContext context) =>
    PlayerGestures.edges(MediaQuery.paddingOf(context), ios: Platform.isIOS);

/// Gesture math for the player, kept pure so it can be tested.
abstract final class PlayerGestures {
  /// Zoom limits: the whole picture up to three times its size.
  static const minZoom = 1.0, maxZoom = 3.0;

  /// Below this a pinch settles back to the whole picture.
  static const snapBelow = 1.06;

  /// Movement before a one-finger drag counts as a vertical swipe.
  static const swipeSlop = 12.0;

  /// The zoom for a pinch that started at [start] and has scaled by [scale].
  static double zoom(double start, double scale) =>
      (start * scale).clamp(minZoom, maxZoom);

  /// Where a pinch settles when the fingers lift.
  static double settle(double zoom) => zoom < snapBelow ? minZoom : zoom;

  /// Whether a one-finger drag that has moved [dx], [dy] is a vertical
  /// swipe (brightness or volume) rather than a stray touch.
  static bool isVerticalSwipe(double dx, double dy) =>
      dy.abs() >= swipeSlop && dy.abs() > dx.abs();

  /// The player's side insets (see playerEdges): an iPhone's symmetric
  /// landscape insets capped at 32 pt, Android's real cutout side as is.
  static EdgeInsets edges(EdgeInsets pad, {required bool ios}) => ios
      ? pad.copyWith(
          left: math.min(pad.left, 32),
          right: math.min(pad.right, 32),
        )
      : pad;

  /// The new brightness or volume after moving [dy] (down is positive) on
  /// a screen [height] tall: the full range in about 80% of the height.
  static double level(double from, double dy, double height) =>
      (from - dy / height * 1.25).clamp(0.0, 1.0);
}

/// One touch session on the player, from the first finger down to the last
/// finger up. Counted from raw pointer events: Flutter's scale gesture
/// ends and restarts whenever a finger lifts, so a pinch would otherwise
/// turn into a swipe with the finger left on the screen.
final class TouchSession {
  int _down = 0;
  int _most = 0;
  bool _swiping = false;
  double _dx = 0, _dy = 0;

  /// Two or more fingers were down at once in this session.
  bool get pinching => _most >= 2;

  /// This session is a one-finger vertical swipe.
  bool get swiping => _swiping;

  /// No finger is on the screen.
  bool get idle => _down == 0;

  void fingerDown() {
    _down++;
    if (_down > _most) _most = _down;
  }

  /// Returns true when this was the last finger: the session is over.
  bool fingerUp() {
    if (_down > 0) _down--;
    if (_down > 0) return false;
    _most = 0;
    _swiping = false;
    _dx = _dy = 0;
    return true;
  }

  /// A one-finger move of [dx], [dy]; true once (and from then on) it's a
  /// vertical swipe. Never after a pinch in the same session.
  bool swipe(double dx, double dy) {
    if (pinching) return false;
    _dx += dx;
    _dy += dy;
    if (!_swiping && PlayerGestures.isVerticalSwipe(_dx, _dy)) {
      _swiping = true;
    }
    return _swiping;
  }
}
