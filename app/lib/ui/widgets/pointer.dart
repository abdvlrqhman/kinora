import 'package:flutter/widgets.dart';

import '../tint.dart';

/// A control as a mouse and keyboard expect it (a computer): the hand
/// cursor, a hover state for [builder], Tab focus drawn as a violet ring
/// just outside [shape], and Enter or Space to activate. Touch is
/// unchanged.
class PointerFocus extends StatefulWidget {
  const PointerFocus({
    super.key,
    required this.onActivate,
    required this.builder,
    this.shape = const StadiumBorder(),
  });

  /// Null: disabled (no cursor, not focusable).
  final VoidCallback? onActivate;
  final ShapeBorder shape;
  final Widget Function(BuildContext context, bool hovered) builder;

  @override
  State<PointerFocus> createState() => _PointerFocusState();
}

class _PointerFocusState extends State<PointerFocus> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onActivate != null;
    return FocusableActionDetector(
      enabled: enabled,
      mouseCursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onShowHoverHighlight: (v) => setState(() => _hovered = v),
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onActivate?.call();
            return null;
          },
        ),
      },
      child: CustomPaint(
        foregroundPainter: _focused && enabled
            ? _Ring(widget.shape, KinoraTint.of(context))
            : null,
        child: widget.builder(context, _hovered && enabled),
      ),
    );
  }
}

/// The focus ring: 2 px, 2 px outside the control's shape.
class _Ring extends CustomPainter {
  const _Ring(this.shape, this.color);

  final ShapeBorder shape;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawPath(
    shape.getOuterPath((Offset.zero & size).inflate(3)),
    Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2,
  );

  @override
  bool shouldRepaint(_Ring old) => old.shape != shape || old.color != color;
}

/// The light a hovered glass control gains.
const hoverGlow = Color(0x10FFFFFF);
