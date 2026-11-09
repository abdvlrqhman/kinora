import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../ui/glass.dart';
import '../ui/tokens.dart';

enum AppTab {
  home('Home', Icons.home_rounded),
  search('Search', Icons.search_rounded),
  downloads('Downloads', Icons.download_rounded),
  settings('Settings', Icons.tune_rounded);

  const AppTab(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Tab pages under a floating liquid-glass tab bar.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  /// Height the tab bar occupies, so pages can pad their last item.
  static double bottomInset(BuildContext context) =>
      MediaQuery.paddingOf(context).bottom + 12 + 64 + KSpace.x4;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: shell),
          Positioned(
            left: KSpace.margin,
            right: KSpace.margin,
            bottom: bottom + 12,
            child: GlassGroup(
              child: Glass(
                tintStrength: 0.10,
                child: SizedBox(
                  height: 64,
                  child: Row(
                    children: [
                      for (final t in AppTab.values)
                        Expanded(
                          child: _TabButton(
                            key: ValueKey('tab-${t.name}'),
                            tab: t,
                            selected: t.index == shell.currentIndex,
                            onTap: () => shell.goBranch(
                              t.index,
                              initialLocation: t.index == shell.currentIndex,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    super.key,
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final AppTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? KColors.lamp : KColors.reel;
    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(tab.icon, color: color, size: 24),
            const SizedBox(height: 2),
            Text(
              tab.label,
              style: KType.small.copyWith(color: color, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
