import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/updates/update_prompt.dart';

import '../ui/glass.dart';
import '../ui/layout.dart';
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

/// Tab pages under a floating liquid-glass tab bar, or beside a glass side
/// rail in a wide window.
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
      (context.getInheritedWidgetOfExactType<_OnRail>() != null
          ? 0
          : 12 + _barHeight(context)) +
      KSpace.x4;

  static const double _railWidth = 76 + KSpace.x3 * 2;

  void _go(AppTab t) =>
      shell.goBranch(t.index, initialLocation: t.index == shell.currentIndex);

  @override
  Widget build(BuildContext context) {
    if (KLayout.isWide(context)) return _wide(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    // Typing (Search): the keyboard gets the space, not the bar and its scrim.
    final typing = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: shell),
          // A newer Kinora on GitHub: offered once a launch (optional).
          // Positioned: a non-positioned 0×0 child would size the whole
          // Stack to nothing (a blank app).
          const Positioned(left: 0, top: 0, child: UpdateCheck()),
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
                                onTap: () => _go(t),
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

  /// Wide windows: the tabs in a glass rail on the left, the page beside it
  /// (pages see their own width, not the window's).
  Widget _wide(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              KSpace.x3,
              mq.padding.top + KSpace.x3,
              KSpace.x3,
              0,
            ),
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: _maxBarTextScale,
              child: GlassGroup(
                child: Glass(
                  tintStrength: 0.10,
                  child: SizedBox(
                    width: 76,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: KSpace.x2),
                        for (final t in AppTab.values)
                          SizedBox(
                            height: 72,
                            child: _TabButton(
                              key: ValueKey('tab-${t.name}'),
                              tab: t,
                              selected: t.index == shell.currentIndex,
                              onTap: () => _go(t),
                            ),
                          ),
                        const SizedBox(height: KSpace.x2),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: MediaQuery(
              data: mq.copyWith(
                size: Size(mq.size.width - _railWidth, mq.size.height),
              ),
              child: _OnRail(
                child: Stack(
                  children: [
                    Positioned.fill(child: shell),
                    const Positioned(left: 0, top: 0, child: UpdateCheck()),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Marks pages beside the side rail (no tab bar to clear at the bottom).
class _OnRail extends InheritedWidget {
  const _OnRail({required super.child});

  @override
  bool updateShouldNotify(_OnRail old) => false;
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
