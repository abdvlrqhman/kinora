import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';

/// Kinora palette (see DESIGN.md). The accent ("Spill") is dynamic and
/// comes from artwork; [marquee] is its fallback.
abstract final class KColors {
  /// Base: a dark theater.
  static const blackout = Color(0xFF000000);

  /// Rare opaque surface.
  static const seat = Color(0xFF17141B);

  /// Primary text: warm projector white.
  static const lamp = Color(0xFFF5EEE4);

  /// Secondary text.
  static const haze = Color(0xFFB3ABB5);

  /// Tertiary text, disabled.
  static const reel = Color(0xFF77707A);

  /// Brand accent, and the fallback when there's no artwork: violet
  /// marquee light (Blackout labels read on it at 8:1).
  static const marquee = Color(0xFFB48CFF);

  /// Caution: warnings and things that need attention (amber), never the
  /// brand color, so a warning can't read as selected or lit.
  static const caution = Color(0xFFFFC15E);

  /// Ready / downloaded / best match.
  static const go = Color(0xFF7EE2B8);

  /// Errors, destructive actions.
  static const cut = Color(0xFFFF6B6B);
}

/// 4-pt spacing scale.
abstract final class KSpace {
  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;

  /// Page margin.
  static const double margin = 20;

  /// Gap between rows/sections.
  static const double section = 28;
}

/// Radii follow hierarchy, not one value for everything.
abstract final class KRadius {
  static const double poster = 12;
  static const double still = 10;
  static const double sheet = 28;
}

/// Durations and curves. Motion answers actions; respect reduced motion.
abstract final class KMotion {
  static const fast = Duration(milliseconds: 140);
  static const base = Duration(milliseconds: 240);
  static const slow = Duration(milliseconds: 420);
  static const curve = Curves.easeOutCubic;
  static const emphasized = Curves.easeInOutCubicEmphasized;
}

/// Type scale: Big Shoulders Display for titles and big numbers, Figtree for
/// everything else. Variable fonts, so weight drives the `wght` axis too.
abstract final class KType {
  static const display = 'BigShoulders';
  static const text = 'Figtree';

  static TextStyle _t(
    String family,
    double size,
    double height,
    FontWeight weight, {
    double letterSpacing = 0,
    Color color = KColors.lamp,
  }) => TextStyle(
    fontFamily: family,
    fontSize: size,
    height: height / size,
    fontWeight: weight,
    fontVariations: [FontVariation.weight(weight.value.toDouble())],
    letterSpacing: letterSpacing,
    color: color,
  );

  static final hero = _t(display, 46, 44, FontWeight.w800, letterSpacing: -0.3);
  static final h1 = _t(display, 32, 34, FontWeight.w700);
  static final h2 = _t(display, 24, 28, FontWeight.w700, letterSpacing: 0.2);
  static final title = _t(text, 17, 22, FontWeight.w600);
  static final body = _t(text, 15, 22, FontWeight.w400);
  static final label = _t(text, 13, 18, FontWeight.w500);
  static final small = _t(text, 12, 16, FontWeight.w500, color: KColors.haze);

  /// Numbers that change in place (sizes, speeds, times).
  static TextStyle tabular(TextStyle s) =>
      s.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
}
