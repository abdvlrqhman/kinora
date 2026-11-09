import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// WCAG contrast ratio between two opaque colors (1 to 21).
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// [fill] with its HSL lightness moved away from [label] until [label] reads
/// on it at [minRatio] or better. A dark label lightens the fill; a light
/// one darkens it.
Color readableFill(Color fill, Color label, {double minRatio = 4.5}) {
  final lighten = label.computeLuminance() < 0.5;
  var hsl = HSLColor.fromColor(fill.withValues(alpha: 1));
  while (contrastRatio(hsl.toColor(), label) < minRatio) {
    final l = hsl.lightness + (lighten ? 0.02 : -0.02);
    if (l < 0 || l > 1) break;
    hsl = hsl.withLightness(l);
  }
  return hsl.toColor();
}

/// Provides the accent (the brand violet) to glass and controls below it.
class KinoraTint extends InheritedWidget {
  /// Creates a tint scope.
  const KinoraTint({super.key, required this.accent, required super.child});

  /// Current accent.
  final Color accent;

  /// The nearest accent, or [KColors.marquee].
  static Color of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<KinoraTint>()?.accent ??
      KColors.marquee;

  /// The accent as a solid fill that a Blackout label reads on (4.5:1 or
  /// better): the "lit" primary control.
  static Color lit(BuildContext context) =>
      readableFill(of(context), KColors.blackout);

  @override
  bool updateShouldNotify(KinoraTint old) => old.accent != accent;
}
