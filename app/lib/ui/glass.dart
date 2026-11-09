import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import 'glass_mode.dart';
import 'tint.dart';
import 'tokens.dart';

/// Shares one backdrop sample among the [Glass] widgets below it (cheaper
/// than one layer per control). Use it around rows of controls.
class GlassGroup extends StatelessWidget {
  /// Creates a group.
  const GlassGroup({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => LiquidGlassLayer(
    settings: LiquidGlassSettings.ios27RegularDark(),
    fake: !realGlass,
    child: child,
  );
}

/// A liquid-glass surface tinted by the current accent.
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

  /// How much of the accent mixes into the glass (0..1).
  final double tintStrength;

  @override
  Widget build(BuildContext context) {
    final accent = KinoraTint.of(context);
    return LiquidGlass.auto(
      shape: LiquidRoundedSuperellipse(borderRadius: radius ?? 999),
      settings: LiquidGlassSettings.ios27RegularDark(),
      fake: !realGlass,
      appearance: LiquidGlassAppearance.ios27RegularDark(
        tint: accent.withValues(alpha: tintStrength),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
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
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  /// Stronger accent tint for the primary action on a screen.
  final bool prominent;
  final String? semanticLabel;

  @override
  State<GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<GlassButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    // The primary action is lit: a solid accent capsule with a dark label.
    final lit = widget.prominent && enabled;
    final fg = lit
        ? KColors.blackout
        : enabled
        ? KColors.lamp
        : KColors.reel;
    const padding = EdgeInsets.symmetric(horizontal: 20, vertical: 13);
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      // Centers the label when the button is stretched full width.
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.icon != null) ...[
          Icon(widget.icon, size: 20, color: fg),
          if (widget.label.isNotEmpty) const SizedBox(width: KSpace.x2),
        ],
        if (widget.label.isNotEmpty)
          Flexible(
            child: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: KType.title.copyWith(
                color: fg,
                fontWeight: lit ? FontWeight.w700 : null,
                fontVariations: lit ? const [FontVariation.weight(700)] : null,
              ),
            ),
          ),
      ],
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel ?? widget.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTap: enabled
            ? () {
                HapticFeedback.selectionClick();
                widget.onPressed!();
              }
            : null,
        child: AnimatedScale(
          scale: _down && !reduce ? 0.96 : 1,
          duration: KMotion.fast,
          curve: KMotion.curve,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
            child: lit
                ? LitCapsule(padding: padding, child: content)
                : Glass(tintStrength: 0.14, padding: padding, child: content),
          ),
        ),
      ),
    );
  }
}

/// A solid capsule in the readable accent ([KinoraTint.lit]): the one
/// projector-lit control on a screen. Put Blackout content on it.
class LitCapsule extends StatelessWidget {
  /// Creates a lit capsule.
  const LitCapsule({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.shape = const StadiumBorder(),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final ShapeBorder shape;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: ShapeDecoration(color: KinoraTint.lit(context), shape: shape),
    child: Padding(padding: padding, child: child),
  );
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
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onPressed!();
              },
        child: SizedBox.square(
          dimension: size,
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
