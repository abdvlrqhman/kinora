import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/updates/update_prompt.dart';

import '../ui/glass.dart';
import '../ui/tint.dart';
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

  /// The bar's labels stop growing here so the bar never outgrows the
  /// screen; pages keep the full text size.
  static const _maxBarTextScale = 1.3;

  static double _barHeight(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context)
        .clamp(maxScaleFactor: _maxBarTextScale);
    return math.max(64, 40 + scaler.scale(16));
  }

  /// Height the tab bar occupies, so pages can pad their last item.
  static double bottomInset(BuildContext context) =>
      MediaQuery.paddingOf(context).bottom +
      12 +
      _barHeight(context) +
      KSpace.x4;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    // Typing (Search): the keyboard gets the space, not the bar and its scrim.
    final typing = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: shell),
          // A newer Kinora on GitHub: offered once a launch (optional).
          const UpdateCheck(),
          // Content passing under the bar dims instead of competing with it.
          if (!typing)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: bottom + 140,
              child: const LegibilityScrim(stops: [0, 1]),
            ),
          if (!typing)
            Positioned(
              left: KSpace.margin,
              right: KSpace.margin,
              bottom: bottom + 12,
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: _maxBarTextScale,
                child: GlassGroup(
                  child: Glass(
                    tintStrength: 0.10,
                    child: SizedBox(
                      height: _barHeight(context),
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
                                  initialLocation:
                                      t.index == shell.currentIndex,
                                ),
                              ),
                            ),
                        ],
                      ),
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
    final color = selected ? KColors.lamp : KColors.haze;
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
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: KType.small.copyWith(
                color: color,
                fontWeight: selected ? FontWeight.w700 : null,
                fontVariations: selected
                    ? const [FontVariation.weight(700)]
                    : null,
              ),
            ),
            const SizedBox(height: 4),
            // State isn't carried by color alone: the chosen tab has a dot.
            SizedBox.square(
              dimension: 4,
              child: selected
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        color: KinoraTint.of(context),
                        shape: BoxShape.circle,
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
