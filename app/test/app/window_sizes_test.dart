import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinora/app/desktop.dart';

void main() {
  test('a big screen gets the full window', () {
    final s = windowSizes(const Size(1920, 1080));
    expect(s.size, const Size(1280, 800));
    expect(s.minimum, const Size(960, 640));
  });

  test('a scaled-up laptop gets a window that fits, taskbar and all', () {
    // 1366 × 768 at 125 %.
    final s = windowSizes(const Size(1092.8, 614.4));
    expect(s.size.height, lessThanOrEqualTo(614.4 * 0.85));
    expect(s.minimum.height, s.size.height);
    expect(s.size.width, 1092.8 * 0.92);
  });

  test('an unknown screen keeps the defaults', () {
    expect(windowSizes(Size.zero).size, const Size(1280, 800));
  });
}
