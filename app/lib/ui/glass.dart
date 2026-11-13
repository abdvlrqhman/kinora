import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tint.dart';
import 'tokens.dart';
import 'widgets/pointer.dart';

/// Groups glass controls. (The flat panels need no shared backdrop; kept so
/// screens mark their control rows the same way.)
class GlassGroup extends StatelessWidget {
  /// Creates a group.
  const GlassGroup({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// A control's surface: a near-black panel at 85% with a faint white edge,
/// readable over artwork and on the black ground alike.
///
/// Capsule by default; pass [radius] for rounded rectangles (sheets, panels).
class Glass extends StatelessWidget {
  /// Creates a glass surface.
  const Glass({
    super.key,
    required this.child,
    this.radius,
    this.padding = EdgeInsets.zero,
    this.tintStrength = 0.16,
  });

  final Widget child;

  /// Corner radius; null makes a capsule.
  final double? radius;
  final EdgeInsetsGeometry padding;

  /// (Unused by the flat panel; kept for callers.)
  final double tintStrength;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xD90E0E0C),
      border: Border.all(color: const Color(0x1FFFFFFF)),
      borderRadius: BorderRadius.circular(radius ?? 999),
    ),
    child: Padding(padding: padding, child: child),
  );
}

/// A glass capsule button. Presses scale down slightly (motion that answers
/// the touch); hit area is at least 44×44.
class GlassButton extends StatefulWidget {
  /// Creates a button with an optional [icon] and a [label].
  const GlassButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.prominent = false,
    this.semanticLabel,
    this.compact = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  /// Stronger accent tint for the primary action on a screen.
  final bool prominent;
  final String? semanticLabel;

  /// Smaller (the player's controls): 44 pt tall, still a full touch target.
  final bool compact;

  @override
  State<GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<GlassButton> {
  bool _down = false;

  static final _shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(KRadius.button),
  );

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    // The main action wears the accent as a tint and an edge, never a fill.
    final lit = widget.prominent && enabled;
    final fg = lit
        ? KColors.onLime
        : enabled
        ? KColors.lamp
        : KColors.reel;
    final padding = widget.compact
        ? const EdgeInsets.symmetric(horizontal: 16, vertical: 10)
        : const EdgeInsets.symmetric(horizontal: 20, vertical: 13);
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      // Centers the label when the button is stretched full width.
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.icon != null) ...[
          Icon(widget.icon, size: widget.compact ? 18 : 20, color: fg),
          if (widget.label.isNotEmpty) const SizedBox(width: KSpace.x2),
        ],
        if (widget.label.isNotEmpty)
          Flexible(
            child: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: (widget.compact ? KType.label : KType.title).copyWith(
                color: fg,
                fontWeight: FontWeight.w600,
                fontVariations: const [FontVariation.weight(600)],
              ),
            ),
          ),
      ],
    );
    void press() {
      HapticFeedback.selectionClick();
      widget.onPressed!();
    }

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel ?? widget.label,
      excludeSemantics: true,
      child: PointerFocus(
        onActivate: enabled ? press : null,
        shape: _shape,
        builder: (context, hovered) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (_) => setState(() => _down = true) : null,
          onTapCancel: () => setState(() => _down = false),
          onTapUp: enabled ? (_) => setState(() => _down = false) : null,
          onTap: enabled ? press : null,
          child: AnimatedScale(
            scale: _down && !reduce ? 0.96 : 1,
            duration: KMotion.fast,
            curve: KMotion.curve,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: widget.compact ? 40 : 44,
                minWidth: widget.compact ? 40 : 44,
              ),
              child: DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: ShapeDecoration(
                  color: hovered ? hoverGlow : const Color(0x00000000),
                  shape: _shape,
                ),
                child: lit
                    ? LitCapsule(
                        padding: padding,
                        shape: _shape,
                        child: content,
                      )
                    : Glass(
                        radius: KRadius.button,
                        padding: padding,
                        child: content,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The main action's look: the accent as a soft tint over a dark base and
/// a 1.5 px accent edge. Put [KColors.onLime] content on it.
class LitCapsule extends StatelessWidget {
  /// Creates the main action's surface.
  const LitCapsule({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.shape = const StadiumBorder(),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final OutlinedBorder shape;

  @override
  Widget build(BuildContext context) {
    final accent = KinoraTint.of(context);
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: Color.alphaBlend(
          accent.withValues(alpha: 0.12),
          const Color(0xE60E0E0C),
        ),
        shape: shape.copyWith(
          side: BorderSide(color: accent.withValues(alpha: 0.75), width: 1.5),
        ),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// Round glass icon button (player controls, close, cast).
class GlassIconButton extends StatelessWidget {
  /// Creates an icon button; [label] is read by screen readers.
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.size = 48,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final press = onPressed == null
        ? null
        : () {
            HapticFeedback.selectionClick();
            onPressed!();
          };
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: PointerFocus(
        onActivate: press,
        shape: const CircleBorder(),
        builder: (context, hovered) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: press,
          child: SizedBox.square(
            dimension: size,
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: ShapeDecoration(
                color: hovered ? hoverGlow : const Color(0x00000000),
                shape: const CircleBorder(),
              ),
              child: Glass(
                child: Center(
                  child: Icon(
                    icon,
                    size: size * 0.46,
                    color: onPressed == null ? KColors.reel : KColors.lamp,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom gradient that keeps text legible over bright artwork.
class LegibilityScrim extends StatelessWidget {
  /// Creates a scrim fading from transparent to [KColors.blackout].
  const LegibilityScrim({super.key, this.stops = const [0.35, 1]});

  final List<double> stops;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: stops,
          colors: const [Color(0x00000000), KColors.blackout],
        ),
      ),
    ),
  );
}
