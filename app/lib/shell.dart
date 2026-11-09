import 'package:flutter/material.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

enum AppTab {
  home('Home', Icons.home_rounded),
  search('Search', Icons.search_rounded),
  downloads('Downloads', Icons.download_rounded),
  settings('Settings', Icons.tune_rounded);

  const AppTab(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// App frame: tab pages under a floating liquid-glass tab bar.
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  AppTab _tab = AppTab.home;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: IndexedStack(
              index: _tab.index,
              children: [for (final t in AppTab.values) _PlaceholderPage(t)],
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: bottom + 12,
            child: LiquidGlassLayer(
              settings: LiquidGlassSettings.ios27RegularDark(),
              child: LiquidGlass(
                shape: const LiquidRoundedSuperellipse(borderRadius: 32),
                child: SizedBox(
                  height: 64,
                  child: Row(
                    children: [
                      for (final t in AppTab.values)
                        Expanded(
                          child: _TabButton(
                            key: ValueKey('tab-${t.name}'),
                            tab: t,
                            selected: t == _tab,
                            onTap: () => setState(() => _tab = t),
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
    final color = selected ? Colors.white : Colors.white54;
    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(tab.icon, color: color),
            const SizedBox(height: 2),
            Text(tab.label, style: TextStyle(color: color, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

// shortcut: placeholder pages until Phase 1 brings real screens.
class _PlaceholderPage extends StatelessWidget {
  const _PlaceholderPage(this.tab);

  final AppTab tab;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B2140), Color(0xFF07080C), Color(0xFF3A1838)],
        ),
      ),
      child: Center(
        child: Text(
          tab.label,
          key: ValueKey('page-${tab.name}'),
          style: Theme.of(context).textTheme.displaySmall,
        ),
      ),
    );
  }
}
