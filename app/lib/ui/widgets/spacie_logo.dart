import 'package:flutter/widgets.dart';

import 'spacie_logo_data.dart';

/// Spacie's mark (from spacie.net), drawn from its own paths.
class SpacieLogo extends StatelessWidget {
  const SpacieLogo({super.key, this.size = 28});

  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Spacie',
    image: true,
    child: CustomPaint(size: Size.square(size), painter: const _Spacie()),
  );
}

class _Spacie extends CustomPainter {
  const _Spacie();

  static final _shapes = [
    for (final (argb, d) in spaciePaths) (Color(argb), _parse(d)),
  ];

  /// SVG path data made only of M, L and Z commands.
  static Path _parse(String d) {
    final path = Path();
    for (final m in RegExp('([MLZ])([^MLZ]*)').allMatches(d)) {
      final n = m[2]!.trim().split(RegExp(r'\s+'));
      switch (m[1]) {
        case 'M':
          path.moveTo(double.parse(n[0]), double.parse(n[1]));
        case 'L':
          path.lineTo(double.parse(n[0]), double.parse(n[1]));
        case 'Z':
          path.close();
      }
    }
    return path;
  }

  // The drawing doesn't fill its square: fit the shapes themselves.
  static final _bounds = _shapes
      .map((s) => s.$2.getBounds())
      .reduce((a, b) => a.expandToInclude(b));

  @override
  void paint(Canvas canvas, Size size) {
    final b = _bounds;
    final scale = size.shortestSide / b.longestSide;
    canvas
      ..translate(
        (size.width - b.width * scale) / 2,
        (size.height - b.height * scale) / 2,
      )
      ..scale(scale)
      ..translate(-b.left, -b.top);
    for (final (color, path) in _shapes) {
      canvas.drawPath(path, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_Spacie oldDelegate) => false;
}
