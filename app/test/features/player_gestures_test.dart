import 'package:flutter/material.dart';
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

  // Through Flutter's real gesture plumbing, wired as in the player: a
  // Listener counts fingers, the scale gesture reports moves.
  Future<({List<bool> swipes, TouchSession touch})> pump(
    WidgetTester tester,
  ) async {
    final touch = TouchSession();
    final swipes = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => touch.fingerDown(),
          onPointerUp: (_) => touch.fingerUp(),
          onPointerCancel: (_) => touch.fingerUp(),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {},
            onDoubleTap: () {},
            onScaleUpdate: (d) {
              if (d.pointerCount < 2) {
                swipes.add(
                  touch.swipe(d.focalPointDelta.dx, d.focalPointDelta.dy),
                );
              }
            },
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    return (swipes: swipes, touch: touch);
  }

  testWidgets('a pinch never turns into a swipe when one finger lifts', (
    tester,
  ) async {
    final (:swipes, :touch) = await pump(tester);
    final a = await tester.createGesture(pointer: 1);
    final b = await tester.createGesture(pointer: 2);
    await a.down(const Offset(300, 300));
    await b.down(const Offset(400, 300));
    for (var i = 0; i < 10; i++) {
      await a.moveBy(const Offset(-5, 0));
      await b.moveBy(const Offset(5, 0));
    }
    await b.up();
    for (var i = 0; i < 6; i++) {
      await a.moveBy(const Offset(0, 8));
    }
    expect(swipes, everyElement(isFalse));
    await a.up();
    expect(touch.idle, isTrue);

    // The next session is a plain swipe again.
    await tester.timedDragFrom(
      const Offset(300, 400),
      const Offset(0, -200),
      const Duration(milliseconds: 300),
    );
    expect(swipes.last, isTrue);
    await tester.pump(const Duration(seconds: 1));
  });
}
