import 'package:flutter_test/flutter_test.dart';
import 'package:kinora/features/player/gestures.dart';

void main() {
  test('pinch zoom stays between the whole picture and 3x', () {
    expect(PlayerGestures.zoom(1, 1.5), 1.5);
    expect(PlayerGestures.zoom(2, 2), 3);
    expect(PlayerGestures.zoom(1.5, 0.5), 1);
    expect(PlayerGestures.settle(1.04), 1, reason: 'almost whole: snaps');
    expect(PlayerGestures.settle(1.3), 1.3);
  });

  test('only a clearly vertical drag changes brightness or volume', () {
    expect(PlayerGestures.isVerticalSwipe(2, 8), isFalse, reason: 'too short');
    expect(PlayerGestures.isVerticalSwipe(30, 20), isFalse, reason: 'sideways');
    expect(PlayerGestures.isVerticalSwipe(4, -20), isTrue);
  });

  test('swiping up raises the level, within 0..1', () {
    expect(PlayerGestures.level(0.5, -80, 400), closeTo(0.75, 1e-9));
    expect(PlayerGestures.level(0.5, 80, 400), closeTo(0.25, 1e-9));
    expect(PlayerGestures.level(0.9, -400, 400), 1);
    expect(PlayerGestures.level(0.1, 400, 400), 0);
  });
}
