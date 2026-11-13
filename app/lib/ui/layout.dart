import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Layout for wide windows (Kinora on a computer).
abstract final class KLayout {
  /// From this width the tabs move to a side rail (a phone held sideways
  /// keeps its tab bar).
  static const double wide = 900;

  /// Lists of rows and text stay this wide at most.
  static const double readable = 760;

  /// Dialogs (sheets on a phone) stay this wide at most.
  static const double sheet = 560;

  /// A computer's layout: beside the sidebar, or a window this wide.
  static bool isWide(BuildContext context) =>
      RailScope.of(context) || MediaQuery.sizeOf(context).width >= wide;

  /// Right padding that keeps a column at most [max] wide, starting at the
  /// same left edge as every other page.
  static double rest(BuildContext context, [double max = readable]) =>
      math.max(0, MediaQuery.sizeOf(context).width - max);
}

/// Marks pages beside the sidebar: they lay out for a computer even when
/// the sidebar leaves them narrower than [KLayout.wide].
class RailScope extends InheritedWidget {
  const RailScope({super.key, required this.on, required super.child});

  final bool on;

  static bool of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<RailScope>()?.on ?? false;

  @override
  bool updateShouldNotify(RailScope old) => old.on != on;
}
