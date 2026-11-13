import 'package:flutter/material.dart';

import '../layout.dart';
import '../tint.dart';
import '../tokens.dart';
import 'pointer.dart';

/// A choice chip: a field at rest, the accent's tint and edge when chosen.
class ChoiceChipButton extends StatelessWidget {
  const ChoiceChipButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = KinoraTint.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: PointerFocus(
        onActivate: onTap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KRadius.button),
        ),
        builder: (context, hovered) => GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: KMotion.fast,
            height: KLayout.isWide(context) ? 32 : 34,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? accent.withValues(alpha: 0.16)
                  : hovered
                  ? KColors.raised
                  : KColors.panel,
              border: Border.all(
                color: selected
                    ? accent.withValues(alpha: 0.45)
                    : KColors.fieldEdge,
              ),
              borderRadius: BorderRadius.circular(KRadius.button),
            ),
            child: Text(
              label,
              maxLines: 1,
              style: KType.label.copyWith(
                color: selected ? KColors.onLime : KColors.body,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A row of chips that scrolls sideways from the page edge.
class ChipRow extends StatelessWidget {
  const ChipRow({super.key, required this.children, required this.gutter});

  final List<Widget> children;
  final double gutter;

  // (Every chip is built: there are a few dozen at most, and keyboard
  // focus and scrolling into view must reach each one.)
  @override
  Widget build(BuildContext context) => SizedBox(
    height: KLayout.isWide(context) ? 32 : 34,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.symmetric(horizontal: gutter),
      child: Row(
        children: [
          for (final (i, c) in children.indexed) ...[
            if (i > 0) const SizedBox(width: KSpace.x2),
            c,
          ],
        ],
      ),
    ),
  );
}
