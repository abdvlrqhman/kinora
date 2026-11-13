import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Layout for wide windows (Kinora on a computer, or a tablet held wide).
abstract final class KLayout {
  /// From this width the tabs move to a side rail.
  static const double wide = 900;

  /// Lists of rows and text stay this wide at most, centered.
  static const double readable = 760;

  /// Sheets stay this wide at most.
  static const double sheet = 600;

  static bool isWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= wide;

  /// Side padding that keeps a column at most [max] wide, centered.
  static double side(BuildContext context, [double max = readable]) =>
      math.max(0, (MediaQuery.sizeOf(context).width - max) / 2);
}
