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

  /// The new brightness or volume after moving [dy] (down is positive) on
  /// a screen [height] tall: the full range in about 80% of the height.
  static double level(double from, double dy, double height) =>
      (from - dy / height * 1.25).clamp(0.0, 1.0);
}
