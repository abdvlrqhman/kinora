import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../app/desktop.dart';

/// Layout for wide windows (Kinora on a computer).
abstract final class KLayout {
  /// From this width the tabs move to a side rail (a phone held sideways
  /// keeps its tab bar).
  static double get wide => isDesktop ? 640 : 900;

  /// Lists of rows and text stay this wide at most.
  static const double readable = 760;

  /// Dialogs (sheets on a phone) stay this wide at most.
  static const double sheet = 560;

  static bool isWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= wide;

  /// Right padding that keeps a column at most [max] wide, starting at the
  /// same left edge as every other page.
  static double rest(BuildContext context, [double max = readable]) =>
      math.max(0, MediaQuery.sizeOf(context).width - max);
}
