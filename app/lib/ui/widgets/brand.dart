import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../tokens.dart';

const _deep = Color(0xFF84CC16);

/// The Kinora mark: a K whose stem is the lamp and whose arms are one
/// chevron of light leaving it through a narrow gap (the lens). Drawn on a
/// 1024 grid, scaled to the canvas. [lamp] and [light] (0..1) switch the
/// stem and the beam on, for the intro.
class KinoraMark extends CustomPainter {
  const KinoraMark({this.lamp = 1, this.light = 1});

  final double lamp;
  final double light;

  static const _top = 252.0, _bottom = 772.0, _mid = (_top + _bottom) / 2;
  static const _stemLeft = 274.0, _stemWidth = 124.0;
  static const _apex = _stemLeft + _stemWidth + 34;
  // Width of each arm across, and its run per unit of height: their true
  // thickness matches the stem's.
  static const _arm = 148.0, _run = 0.62;
  static const _reach = (_mid - _top) * _run;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 1024);
    if (lamp > 0) {
      canvas.drawRect(
        const Rect.fromLTRB(_stemLeft, _top, _stemLeft + _stemWidth, _bottom),
        Paint()..color = KColors.title.withValues(alpha: lamp.clamp(0, 1)),
      );
    }
    if (light <= 0) return;
    final chevron = Path()
      ..moveTo(_apex, _mid)
      ..lineTo(_apex + _reach, _top)
      ..lineTo(_apex + _reach + _arm, _top)
      ..lineTo(_apex + _arm, _mid)
      ..lineTo(_apex + _reach + _arm, _bottom)
      ..lineTo(_apex + _reach, _bottom)
      ..close();
    canvas.save();
    if (light < 1) {
      // The light spreads out from the lens as it switches on (420 reaches
      // the far corners of the arms).
      canvas.clipPath(
        Path()..addOval(
          Rect.fromCircle(
            center: const Offset(_apex, _mid),
            radius: 420 * light,
          ),
        ),
      );
    }
    canvas
      ..drawPath(
        chevron,
        Paint()
          ..shader = ui.Gradient.radial(
            const Offset(_apex, _mid),
            _reach + _arm + 40,
            // The app's lime: pale at the lens, deeper at the tips.
            const [Color(0xFFF2FDD8), KColors.marquee, _deep],
            const [0, 0.45, 1],
          ),
      )
      ..restore();
  }

  @override
  bool shouldRepaint(KinoraMark oldDelegate) =>
      oldDelegate.lamp != lamp || oldDelegate.light != light;
}

/// The wordmark: the mark is the K, then "INORA" in the display face, both
/// [capHeight] tall.
class KinoraWordmark extends StatelessWidget {
  const KinoraWordmark({super.key, this.capHeight = 14});

  final double capHeight;

  // The K on the mark's 1024 grid: stem left edge, cap top, cap height and
  // the width across the chevron's tips.
  static const _left = 274.0, _top = 252.0, _cap = 520.0, _width = 467.0;

  @override
  Widget build(BuildContext context) {
    final scale = capHeight / _cap;
    // Unbounded's caps are about 0.72 of its size.
    final fontSize = capHeight / 0.72;
    return Semantics(
      label: 'Kinora',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: _width * scale,
            height: capHeight,
            child: CustomPaint(painter: _Letter(scale)),
          ),
          SizedBox(width: fontSize * 0.08),
          Text(
            'INORA',
            // A logo, sized with the drawn K: it doesn't grow with text.
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontFamily: KType.display,
              fontSize: fontSize,
              height: 1,
              fontWeight: FontWeight.w700,
              fontVariations: const [FontVariation.weight(700)],
              letterSpacing: fontSize * 0.06,
              color: KColors.title,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}

class _Letter extends CustomPainter {
  const _Letter(this.scale);

  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..translate(-KinoraWordmark._left * scale, -KinoraWordmark._top * scale)
      ..scale(scale);
    const KinoraMark().paint(canvas, const Size(1024, 1024));
  }

  @override
  bool shouldRepaint(_Letter old) => old.scale != scale;
}
