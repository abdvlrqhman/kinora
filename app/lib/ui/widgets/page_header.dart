import 'package:flutter/widgets.dart';

import '../layout.dart';
import '../tokens.dart';

/// The top of a tab page, the same on every page. A phone: a 56 px row
/// under the status bar with the title centred in it, [leading] before it
/// and [actions] at the end. A wide window: the window bar already names
/// the page and goes back, so the page starts 24 px under it with [actions]
/// only.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.leading,
    this.actions = const [],
  });

  final String title;
  final Widget? leading;
  final List<Widget> actions;

  /// Space under the header before the page's content.
  static const double gap = KSpace.x2;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    if (KLayout.isWide(context)) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          KSpace.margin,
          top + KSpace.x4,
          KSpace.margin,
          0,
        ),
        // (Back is in the window bar too.)
        child: actions.isEmpty
            ? const SizedBox(height: KSpace.x2)
            : SizedBox(
                height: 40,
                child: Row(children: [const Spacer(), ...actions]),
              ),
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(KSpace.margin, top, KSpace.margin, 0),
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: KType.h1.copyWith(color: KColors.title),
                ),
              ),
            ),
            ...actions,
          ],
        ),
      ),
    );
  }
}
