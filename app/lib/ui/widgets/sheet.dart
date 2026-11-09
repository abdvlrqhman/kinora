import 'package:flutter/material.dart';

import '../glass.dart';
import '../tint.dart';
import '../tokens.dart';

/// Shows a floating glass sheet that keeps the caller's accent.
Future<T?> showGlassSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  final accent = KinoraTint.of(context);
  final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0xA6000000),
    sheetAnimationStyle: reduce ? AnimationStyle.noAnimation : null,
    builder: (sheetContext) => KinoraTint(
      accent: accent,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: KSpace.x2),
        child: Padding(
          // Lifts the sheet above the keyboard when a field inside has focus.
          padding: EdgeInsets.only(
            left: KSpace.x2,
            right: KSpace.x2,
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.86,
            ),
            // A Seat underlay so lit buttons behind don't blur through as a
            // highlighted row.
            child: DecoratedBox(
              decoration: BoxDecoration(
                // Opaque: a lit button behind would glow through like a
                // selected row.
                color: KColors.seat,
                borderRadius: BorderRadius.circular(KRadius.sheet),
              ),
              child: GlassGroup(
                child: Glass(
                  radius: KRadius.sheet,
                  tintStrength: 0.10,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _Grabber(),
                      Flexible(child: builder(sheetContext)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _Grabber extends StatelessWidget {
  const _Grabber();

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      margin: const EdgeInsets.only(top: KSpace.x2, bottom: KSpace.x1),
      width: 36,
      height: 5,
      decoration: BoxDecoration(
        color: KColors.lamp.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(3),
      ),
    ),
  );
}

/// One plain action row in a sheet (icon + verb), 56 pt tall.
class SheetAction extends StatelessWidget {
  const SheetAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = KColors.lamp,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    child: InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: KSpace.margin,
            vertical: KSpace.x3,
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: KSpace.x4),
              Expanded(
                child: Text(label, style: KType.title.copyWith(color: color)),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
