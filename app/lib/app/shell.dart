import 'dart:math' as math;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/cast/cast_picker.dart';
import '../features/trakt/trakt_ui.dart';
import '../features/updates/update_prompt.dart';
import 'router.dart';

import '../ui/glass.dart';
import '../ui/layout.dart';
import '../ui/tint.dart';
import '../ui/tokens.dart';
import '../ui/widgets/pointer.dart';

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

  /// The tabs, for the side rail (it sits outside them).
  static StatefulNavigationShell? current;

  /// True beside the side rail: no tab bar at the bottom.
  static bool onRail(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_OnRail>()?.on ?? false;

  /// Height the tab bar occupies, so pages can pad their last item.
  static double bottomInset(BuildContext context) =>
      MediaQuery.paddingOf(context).bottom +
      (onRail(context) ? 0 : 12 + _barHeight(context)) +
      KSpace.x4;

  void _go(AppTab t) =>
      shell.goBranch(t.index, initialLocation: t.index == shell.currentIndex);

  @override
  Widget build(BuildContext context) {
    current = shell;
    if (onRail(context)) {
      return Scaffold(
        body: Stack(
          children: [
            Positioned.fill(child: shell),
            const Positioned(left: 0, top: 0, child: UpdateCheck()),
          ],
        ),
      );
    }
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
              // (A narrow window: a bar, not a strip across it.)
              left: math.max(
                KSpace.margin,
                (MediaQuery.sizeOf(context).width - 440) / 2,
              ),
              right: math.max(
                KSpace.margin,
                (MediaQuery.sizeOf(context).width - 440) / 2,
              ),
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
}

/// Wide windows: the tabs in a glass rail on the left of every page (title
/// pages too), with Trakt and Cast at its foot; pages see their own width.
/// Hidden for the player and onboarding. The tree keeps one shape either
/// way, so the pages' state survives a resize.
class WideNav extends ConsumerStatefulWidget {
  const WideNav({super.key, required this.child});

  final Widget child;

  static const double width = 76 + KSpace.x3 * 2;

  @override
  ConsumerState<WideNav> createState() => _WideNavState();
}

class _WideNavState extends ConsumerState<WideNav> {
  late final GoRouter _router = ref.read(routerProvider);

  @override
  void initState() {
    super.initState();
    _router.routeInformationProvider.addListener(_changed);
  }

  @override
  void dispose() {
    _router.routeInformationProvider.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  String get _path => _router.routeInformationProvider.value.uri.path;

  int get _tab => switch (_path) {
    final p when p.startsWith('/search') => 1,
    final p when p.startsWith('/downloads') => 2,
    final p when p.startsWith('/settings') => 3,
    '/' => 0,
    // A title page: the tab it was opened from.
    _ => AppShell.current?.currentIndex ?? 0,
  };

  void _go(int tab) {
    final shell = AppShell.current;
    // Leave a title page first, back to the tabs.
    rootNavigatorKey.currentState?.popUntil((r) => r.isFirst);
    if (shell == null) {
      _router.go(const ['/', '/search', '/downloads', '/settings'][tab]);
    } else {
      shell.goBranch(tab, initialLocation: tab == shell.currentIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final path = _path;
    final on =
        KLayout.isWide(context) &&
        !path.startsWith('/player') &&
        !path.startsWith('/onboarding');
    final tab = _tab;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: on ? WideNav.width : 0,
          // (Outside the pages: no Material above it, so it brings its own
          // text style.)
          child: on
              ? _DimWithPopups(
                  child: Semantics(
                    // The tabs as one navigation region for screen readers.
                    container: true,
                    explicitChildNodes: true,
                    label: 'Tabs',
                    child: Material(
                      color: KColors.blackout,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          KSpace.x3,
                          mq.padding.top + KSpace.x3,
                          KSpace.x3,
                          mq.padding.bottom + KSpace.x3,
                        ),
                        child: MediaQuery.withClampedTextScaling(
                          maxScaleFactor: AppShell._maxBarTextScale,
                          child: Column(
                            children: [
                              GlassGroup(
                                child: Glass(
                                  tintStrength: 0.10,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const SizedBox(height: KSpace.x2),
                                      for (final t in AppTab.values)
                                        SizedBox(
                                          width: 76,
                                          height: 72,
                                          child: _TabButton(
                                            key: ValueKey('tab-${t.name}'),
                                            tab: t,
                                            selected: t.index == tab,
                                            rail: true,
                                            onTap: () => _go(t.index),
                                          ),
                                        ),
                                      const SizedBox(height: KSpace.x2),
                                    ],
                                  ),
                                ),
                              ),
                              const Spacer(),
                              const GlassGroup(
                                child: Column(
                                  children: [
                                    TraktButton(),
                                    SizedBox(height: KSpace.x2),
                                    _RailCast(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              : null,
        ),
        Expanded(
          child: MediaQuery(
            data: on
                ? mq.copyWith(
                    size: Size(mq.size.width - WideNav.width, mq.size.height),
                  )
                : mq,
            // Its own semantics container: a page's modal barrier would
            // otherwise hide the rail (painted before it) from screen
            // readers.
            child: _OnRail(
              on: on,
              child: Semantics(container: true, child: widget.child),
            ),
          ),
        ),
      ],
    );
  }
}

/// The rail dims with the page while a dialog or sheet is open; a click on
/// it closes the dialog, as a click beside it does.
class _DimWithPopups extends StatelessWidget {
  const _DimWithPopups({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: popupOpen,
    builder: (context, open, child) => Stack(
      fit: StackFit.expand,
      children: [
        child!,
        if (open)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => rootNavigatorKey.currentState?.maybePop(),
            child: const ColoredBox(color: Color(0xA6000000)),
          ),
      ],
    ),
    child: child,
  );
}

/// Cast in the rail: the icon alone (the TV's name is in its label).
class _RailCast extends StatelessWidget {
  const _RailCast();

  @override
  Widget build(BuildContext context) => CastTargetBuilder(
    builder: (context, tv) => GlassIconButton(
      icon: tv == null ? Icons.cast_rounded : Icons.cast_connected_rounded,
      label: tv == null
          ? 'Cast to a TV'
          : 'Cast to ${tv.friendlyName} is on. Change TV',
      onPressed: () => unawaited(showCastPicker(context)),
    ),
  );
}

/// Marks pages beside the side rail (no tab bar to clear at the bottom).
class _OnRail extends InheritedWidget {
  const _OnRail({required this.on, required super.child});

  final bool on;

  @override
  bool updateShouldNotify(_OnRail old) => old.on != on;
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    super.key,
    required this.tab,
    required this.selected,
    required this.onTap,
    this.rail = false,
  });

  final AppTab tab;
  final bool selected;
  final VoidCallback onTap;

  /// In the side rail: the chosen tab's icon sits on a soft accent pill.
  final bool rail;

  @override
  Widget build(BuildContext context) {
    final accent = KinoraTint.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      excludeSemantics: true,
      child: PointerFocus(
        onActivate: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        builder: (context, hovered) {
          final color = selected || hovered ? KColors.lamp : KColors.haze;
          final icon = Icon(tab.icon, color: color, size: 24);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (rail)
                  AnimatedContainer(
                    duration: KMotion.fast,
                    width: 56,
                    height: 32,
                    decoration: BoxDecoration(
                      color: selected
                          ? accent.withValues(alpha: 0.18)
                          : hovered
                          ? const Color(0x10FFFFFF)
                          : const Color(0x00000000),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: icon,
                  )
                else
                  icon,
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
                if (!rail) ...[
                  const SizedBox(height: 4),
                  // State isn't carried by color alone: the chosen tab has a
                  // dot.
                  SizedBox.square(
                    dimension: 4,
                    child: selected
                        ? DecoratedBox(
                            decoration: BoxDecoration(
                              color: accent,
                              shape: BoxShape.circle,
                            ),
                          )
                        : null,
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
