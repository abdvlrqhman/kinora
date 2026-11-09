import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// Picks a vivid accent from raw RGBA pixels, tuned to read on black next to
/// Lamp text. Returns null when the image has no usable color (greyscale).
Color? accentFromPixels(Uint8List rgba) {
  var sumX = 0.0, sumY = 0.0, weightSum = 0.0, satSum = 0.0;
  for (var i = 0; i + 3 < rgba.length; i += 4) {
    if (rgba[i + 3] < 128) continue;
    final hsv = HSVColor.fromColor(
      Color.fromARGB(255, rgba[i], rgba[i + 1], rgba[i + 2]),
    );
    // Vivid, mid-to-bright pixels dominate; dark and grey ones barely count.
    final w = math.pow(hsv.saturation, 2) * math.pow(hsv.value, 1.5);
    if (w < 0.02) continue;
    final rad = hsv.hue * math.pi / 180;
    sumX += math.cos(rad) * w;
    sumY += math.sin(rad) * w;
    weightSum += w;
    satSum += hsv.saturation * w;
  }
  if (weightSum < 0.5) return null;
  var hue = math.atan2(sumY, sumX) * 180 / math.pi;
  if (hue < 0) hue += 360;
  final sat = (satSum / weightSum).clamp(0.45, 0.80);
  return HSLColor.fromAHSL(1, hue, sat, 0.66).toColor();
}

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

/// Extracts and caches artwork accents.
final class ArtworkTint {
  ArtworkTint._();

  static final _cache = <Object, Future<Color>>{};
  static final _known = <Object, Color>{};

  /// Accent for [image] (decoded at 24 px wide), or [KColors.marquee].
  static Future<Color> of(ImageProvider image) =>
      _cache[image] ??= _extract(image).then((c) => _known[image] = c);

  /// The accent already worked out for [image], if any (no waiting).
  static Color? known(ImageProvider image) => _known[image];

  static Future<Color> _extract(ImageProvider image) async {
    try {
      final resized = ResizeImage(
        image,
        width: 24,
        policy: ResizeImagePolicy.fit,
      );
      final completer = Completer<ui.Image>();
      final stream = resized.resolve(ImageConfiguration.empty);
      late final ImageStreamListener listener;
      listener = ImageStreamListener(
        (info, _) {
          completer.complete(info.image.clone());
          stream.removeListener(listener);
        },
        onError: (e, st) {
          completer.completeError(e, st);
          stream.removeListener(listener);
        },
      );
      stream.addListener(listener);
      final img = await completer.future.timeout(const Duration(seconds: 8));
      try {
        final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (data == null) return KColors.marquee;
        return accentFromPixels(data.buffer.asUint8List()) ?? KColors.marquee;
      } finally {
        img.dispose();
      }
    } on Object {
      return KColors.marquee;
    }
  }
}

/// Provides the current accent ("Spill") to glass and controls below it.
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

/// Tints its subtree with the accent of [image], animating changes.
class ArtworkTintScope extends StatefulWidget {
  /// Creates a scope; null [image] keeps the parent accent.
  const ArtworkTintScope({super.key, required this.image, required this.child});

  final ImageProvider? image;
  final Widget child;

  @override
  State<ArtworkTintScope> createState() => _ArtworkTintScopeState();
}

class _ArtworkTintScopeState extends State<ArtworkTintScope> {
  // Known at once when this art was seen before.
  late Color? _accent = widget.image == null
      ? null
      : ArtworkTint.known(widget.image!);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ArtworkTintScope old) {
    super.didUpdateWidget(old);
    if (old.image != widget.image) _load();
  }

  void _load() {
    final image = widget.image;
    if (image == null) return;
    unawaited(
      ArtworkTint.of(image).then((c) {
        if (mounted && c != _accent) setState(() => _accent = c);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    // While the art's own color is worked out: neutral projector white, not
    // the brand violet (which would flash before a warm poster's orange).
    final target =
        _accent ??
        (widget.image == null ? KinoraTint.of(context) : KColors.lamp);
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: target),
      duration: reduce ? Duration.zero : KMotion.slow,
      curve: KMotion.curve,
      builder: (context, color, child) =>
          KinoraTint(accent: color ?? target, child: child!),
      child: widget.child,
    );
  }
}
