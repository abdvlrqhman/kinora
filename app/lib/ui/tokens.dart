import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';

import '../app/desktop.dart';

/// Kinora palette: a true black ground, near-black neutral panels, one
/// accent (lime) for interaction and progress, coral only for "new", teal
/// only for "saved on this device", red only for failures.
abstract final class KColors {
  /// The ground everything sits on (`bg.canvas`).
  static const blackout = Color(0xFF000000);

  /// Opaque surface for sheets and menus (`bg.raised` family).
  static const seat = Color(0xFF121210);

  /// Primary text (`text.primary`).
  static const lamp = Color(0xFFEFEFEA);

  /// Secondary text (`text.secondary`).
  static const haze = Color(0xFFA8A8A1);

  /// Faint text and disabled controls (`text.faint`, 5.2:1 on black).
  static const reel = Color(0xFF80807A);

  /// The accent: progress, selection, the main action's edge.
  static const marquee = Color(0xFFBEF264);

  /// Warnings (amber): never the accent, so a warning can't read as chosen.
  static const caution = Color(0xFFFFC15E);

  /// Saved on this device, ready, best match (teal: lime is the accent).
  static const go = Color(0xFF5EEAD4);

  /// Errors and destructive actions.
  static const cut = Color(0xFFFB6E6E);

  // Text steps.
  static const title = Color(0xFFF6F6F2);
  static const body = Color(0xFFCACAC4);
  static const muted = Color(0xFF8B8B84);

  // Surfaces.
  static const sidebar = Color(0xFF0A0A09);
  static const panel = Color(0xFF0E0E0C);
  static const raised = Color(0xFF181815);

  // Edges.
  static const divider = Color(0xFF161614);
  static const edge = Color(0xFF1A1A17);
  static const fieldEdge = Color(0xFF22221E);
  static const strongEdge = Color(0xFF2A2A25);

  // The accent's lighter steps: links and episode numbers; text on its tint.
  static const limeLink = Color(0xFFD9F99D);
  static const onLime = Color(0xFFECFCCB);

  /// "New" (badges, counts, dots) and nothing else.
  static const coral = Color(0xFFFF4D6D);
  static const coralText = Color(0xFFFF7390);

  /// Outline of the big rank numerals (decorative).
  static const rank = Color(0xFF5B6150);
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
  static const double badge = 6;
  static const double button = 10;
  static const double still = 10;
  static const double poster = 12;
  static const double panel = 14;
  static const double sheet = 20;
}

/// Durations and curves. Motion answers actions; respect reduced motion.
abstract final class KMotion {
  static const fast = Duration(milliseconds: 140);
  static const base = Duration(milliseconds: 240);
  static const slow = Duration(milliseconds: 420);
  static const curve = Curves.easeOutCubic;
  static const emphasized = Curves.easeInOutCubicEmphasized;
}

/// Type: Unbounded for titles and rank numerals, Readex Pro for text (it
/// covers Arabic too), Geist Mono for numbers and state lines
/// ("S1 E3 · 30M LEFT"). Variable fonts: weight drives the `wght` axis.
/// A computer gets the larger desktop sizes.
abstract final class KType {
  static const display = 'Unbounded';
  static const text = 'ReadexPro';
  static const mono = 'GeistMono';

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

  static bool get _big => isDesktop;

  /// A title over artwork (billboard, title pages).
  static TextStyle get hero => _big
      ? _t(display, 30, 34, FontWeight.w700, letterSpacing: -0.6)
      : _t(display, 24, 28, FontWeight.w700, letterSpacing: -0.5);

  /// A page's title (Settings, Downloads).
  static TextStyle get h1 => _big
      ? _t(display, 22, 28, FontWeight.w600, letterSpacing: -0.2)
      : _t(display, 20, 26, FontWeight.w600, letterSpacing: -0.2);

  /// Section and row titles.
  static TextStyle get h2 => _big
      ? _t(display, 17, 22, FontWeight.w600, letterSpacing: -0.17)
      : _t(display, 15, 20, FontWeight.w600, letterSpacing: -0.15);

  /// Card and row titles, button labels.
  static TextStyle get title => _t(text, 14, 20, FontWeight.w500);

  static TextStyle get body =>
      _t(text, 14, 22, FontWeight.w400, color: KColors.body);

  static TextStyle get label => _t(text, 13, 18, FontWeight.w500);

  static TextStyle get small =>
      _t(text, 12, 16, FontWeight.w400, color: KColors.haze);

  /// Panel labels in caps ("INFORMATION").
  static TextStyle get eyebrow => _t(
    text,
    11,
    14,
    FontWeight.w600,
    letterSpacing: 1.5,
    color: KColors.muted,
  );

  /// State lines, in caps: "S1 E3 · 30M LEFT".
  static TextStyle get meta => _big
      ? _t(mono, 11, 14, FontWeight.w400, color: KColors.muted)
      : _t(mono, 10, 13, FontWeight.w400, color: KColors.muted);

  /// Badges on artwork: "NEW", "E24".
  static TextStyle get badge => _t(mono, 10, 12, FontWeight.w400);

  /// Sizes, times and counts in controls.
  static TextStyle get numeric => _t(mono, 12, 16, FontWeight.w400);

  /// Numbers that change in place (sizes, speeds, times).
  static TextStyle tabular(TextStyle s) =>
      s.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
}
