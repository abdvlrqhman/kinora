import 'package:flutter/material.dart';

import '../../app/desktop.dart';
import '../../app/router.dart';
import '../glass.dart';
import '../tint.dart';
import '../layout.dart';
import '../tokens.dart';

/// Shows a floating glass sheet that keeps the caller's accent. In a wide
/// window it's a centered dialog instead (Esc or a click outside closes it).
Future<T?> showGlassSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  final accent = KinoraTint.of(context);
  final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  // Opened from outside the pages (the side rail): the app's navigator.
  final host = Navigator.maybeOf(context) != null
      ? context
      : rootNavigatorKey.currentContext!;
  if (KLayout.isWide(host)) {
    return showDialog<T>(
      context: host,
      barrierColor: const Color(0xA6000000),
      builder: (dialogContext) => KinoraTint(
        accent: accent,
        child: Center(
          child: Padding(
            padding: EdgeInsets.only(
              left: KSpace.margin,
              right: KSpace.margin,
              bottom: MediaQuery.viewInsetsOf(dialogContext).bottom,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: KLayout.sheet,
                maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.86,
              ),
              child: Material(
                type: MaterialType.transparency,
                child: _Closable(
                  onClose: () => Navigator.pop(dialogContext),
                  child: _Panel(
                    top: const SizedBox(height: KSpace.x3),
                    // Content 24 from the edges (its own 20 plus 4).
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: builder(dialogContext),
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
  return showModalBottomSheet<T>(
    context: host,
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
            // A computer has no drag: a close button, not a handle.
            child: isDesktop
                ? _Closable(
                    onClose: () => Navigator.pop(sheetContext),
                    child: _Panel(
                      top: const SizedBox(height: KSpace.x3),
                      child: builder(sheetContext),
                    ),
                  )
                : _Panel(top: const _Grabber(), child: builder(sheetContext)),
          ),
        ),
      ),
    ),
  );
}

/// A panel with a close button in its corner, 16 from the edges.
class _Closable extends StatelessWidget {
  const _Closable({required this.onClose, required this.child});

  final VoidCallback onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      child,
      Positioned(
        top: KSpace.x4,
        right: KSpace.x4,
        child: GlassIconButton(
          icon: Icons.close_rounded,
          label: 'Close',
          size: 36,
          onPressed: onClose,
        ),
      ),
    ],
  );
}

/// The sheet's glass, on a Seat underlay so lit buttons behind don't blur
/// through as a highlighted row.
class _Panel extends StatelessWidget {
  const _Panel({required this.top, required this.child});

  final Widget top;
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
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
            top,
            Flexible(child: child),
          ],
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
