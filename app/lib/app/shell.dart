import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';

import '../core/format.dart';
import '../features/cast/cast_picker.dart';
import '../features/trakt/trakt_ui.dart';
import '../features/updates/update_prompt.dart';
import '../services/downloads.dart';
import '../services/trakt.dart';
import '../ui/layout.dart';
import '../ui/tint.dart';
import '../ui/tokens.dart';
import '../ui/widgets/brand.dart';
import '../ui/widgets/pointer.dart';
import 'desktop.dart';
import 'router.dart';

enum AppTab {
  home('Home', Icons.home_outlined),
  search('Discovery', Icons.explore_outlined),
  downloads('Downloads', Icons.file_download_outlined),
  settings('Settings', Icons.tune_rounded);

  const AppTab(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Asks Search to take the keyboard (the window bar's search field, Ctrl+K).
final focusSearch = ValueNotifier<int>(0);

/// Names of pushed pages by location, for the window bar ("Home / Harbor
/// Lights"); title pages fill it in when their details arrive.
final pageNames = ValueNotifier<Map<String, String>>(const {});

/// The tab pages. On a phone they sit above a floating pill tab bar; in a
/// wide window [WideNav] draws the sidebar around them instead.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  /// The tabs, for the sidebar (it sits outside them).
  static StatefulNavigationShell? current;

  /// True beside the sidebar: no tab bar at the bottom.
  static bool onRail(BuildContext context) => RailScope.of(context);

  /// Height the tab bar occupies, so pages can pad their last item.
  static double bottomInset(BuildContext context) =>
      MediaQuery.paddingOf(context).bottom +
      (onRail(context) ? 0 : _PillNav.height + _PillNav.bottom) +
      KSpace.x4;

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
    // Typing (Search): the keyboard gets the space, not the bar.
    final typing = MediaQuery.viewInsetsOf(context).bottom > 0;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: shell),
          const Positioned(left: 0, top: 0, child: UpdateCheck()),
          if (!typing) ...[
            // Content never reads under the bar: it fades to black first.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: bottom + 110,
              child: const IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0, 0.6, 1],
                      colors: [
                        Color(0x00000000),
                        Color(0xD9000000),
                        KColors.blackout,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: bottom + _PillNav.bottom,
              child: _PillNav(
                current: shell.currentIndex,
                onTap: (t) => shell.goBranch(
                  t.index,
                  initialLocation: t.index == shell.currentIndex,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The phone's floating tab bar: a frosted capsule; the chosen tab shows
/// its name on a lime lens, the others their icon alone.
class _PillNav extends ConsumerWidget {
  const _PillNav({required this.current, required this.onTap});

  static const double height = 62;
  static const double bottom = 18;

  final int current;
  final ValueChanged<AppTab> onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = _activeDownloads(ref);
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.2,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(KRadius.sheet),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: const Color(0xD90E0E0C),
              border: Border.all(color: const Color(0x1FFFFFFF)),
              borderRadius: BorderRadius.circular(KRadius.sheet),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final t in AppTab.values)
                  _PillItem(
                    key: ValueKey('tab-${t.name}'),
                    tab: t,
                    selected: t.index == current,
                    count: t == AppTab.downloads ? active : 0,
                    onTap: () => onTap(t),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PillItem extends StatelessWidget {
  const _PillItem({
    super.key,
    required this.tab,
    required this.selected,
    required this.count,
    required this.onTap,
  });

  final AppTab tab;
  final bool selected;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = KinoraTint.of(context);
    final icon = _Counted(
      count: count,
      child: Icon(
        tab.icon,
        size: selected ? 18 : 22,
        color: selected ? KColors.onLime : KColors.muted,
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      label: count > 0 ? '${tab.label}, $count active' : tab.label,
      excludeSemantics: true,
      child: PointerFocus(
        onActivate: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        builder: (context, hovered) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: KMotion.fast,
            height: 42,
            padding: EdgeInsets.symmetric(horizontal: selected ? 15 : 12),
            decoration: BoxDecoration(
              color: selected
                  ? accent.withValues(alpha: 0.10)
                  : hovered
                  ? const Color(0x10FFFFFF)
                  : const Color(0x00000000),
              border: selected
                  ? Border.all(
                      color: accent.withValues(alpha: 0.75),
                      width: 1.5,
                    )
                  : null,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                icon,
                if (selected) ...[
                  const SizedBox(width: KSpace.x2),
                  Text(
                    tab.label,
                    style: KType.label.copyWith(
                      color: KColors.onLime,
                      fontWeight: FontWeight.w600,
                      fontVariations: const [FontVariation.weight(600)],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A coral count on an icon (active downloads).
class _Counted extends StatelessWidget {
  const _Counted({required this.count, required this.child});

  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) => count == 0
      ? child
      : Stack(
          clipBehavior: Clip.none,
          children: [
            child,
            Positioned(
              right: -7,
              top: -6,
              child: Container(
                constraints: const BoxConstraints(minWidth: 16),
                height: 16,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: KColors.coral,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: KType.badge.copyWith(color: const Color(0xFF1A0209)),
                ),
              ),
            ),
          ],
        );
}

int _activeDownloads(WidgetRef ref) =>
    (ref.watch(downloadsProvider).value ?? const [])
        .where((d) => d.state == 'downloading' || d.state == 'queued')
        .length;

/// A wide window's frame around every page (title pages too): the sidebar
/// on the left and the frosted window bar over the content. Hidden for the
/// player and onboarding, which get the whole window (and, on a computer,
/// just the window buttons). The tree keeps one shape either way, so the
/// pages' state survives a resize.
class WideNav extends ConsumerStatefulWidget {
  const WideNav({super.key, required this.child});

  final Widget child;

  static const double width = 248;
  static const double barHeight = 52;

  @override
  ConsumerState<WideNav> createState() => _WideNavState();
}

class _WideNavState extends ConsumerState<WideNav> {
  late final GoRouter _router = ref.read(routerProvider);

  @override
  void initState() {
    super.initState();
    _router.routeInformationProvider.addListener(_changed);
    windowFullScreen.addListener(_changed);
  }

  @override
  void dispose() {
    _router.routeInformationProvider.removeListener(_changed);
    windowFullScreen.removeListener(_changed);
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
    final full = windowFullScreen.value;
    final own =
        path.startsWith('/player') || path.startsWith('/onboarding') || full;
    final on = KLayout.isWide(context) && !own;
    // A computer without the frame still needs its window buttons.
    final bare = isDesktop && !on && !full;
    final top = on
        ? WideNav.barHeight
        : bare
        ? kTitleBarHeight
        : mq.padding.top;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: on ? WideNav.width : 0,
          child: on
              ? _DimWithPopups(
                  child: _Sidebar(tab: _tab, onTab: _go),
                )
              : null,
        ),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: MediaQuery(
                  data: mq.copyWith(
                    size: on
                        ? Size(mq.size.width - WideNav.width, mq.size.height)
                        : mq.size,
                    padding: mq.padding.copyWith(top: top),
                    viewPadding: mq.viewPadding.copyWith(top: top),
                  ),
                  // Its own semantics container: a page's modal barrier
                  // would otherwise hide the sidebar from screen readers.
                  child: RailScope(
                    on: on,
                    child: Semantics(container: true, child: widget.child),
                  ),
                ),
              ),
              if (on)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: WideNav.barHeight,
                  child: _DimWithPopups(
                    child: _WindowBar(router: _router, path: path, tab: _tab),
                  ),
                ),
              if (bare)
                const Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: kTitleBarHeight,
                  child: _BareBar(),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The sidebar: the wordmark, the tabs, and at its foot what's downloading,
/// your Trakt account and Settings.
class _Sidebar extends ConsumerWidget {
  const _Sidebar({required this.tab, required this.onTab});

  final int tab;
  final ValueChanged<int> onTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = _activeDownloads(ref);
    Widget item(AppTab t, {int count = 0}) => _NavItem(
      key: ValueKey('tab-${t.name}'),
      tab: t,
      selected: t.index == tab,
      count: count,
      onTap: () => onTab(t.index),
    );
    const wordmark = Padding(
      padding: EdgeInsets.only(left: 12),
      child: SizedBox(
        height: WideNav.barHeight,
        child: Align(
          alignment: Alignment.centerLeft,
          child: KinoraWordmark(capHeight: 15),
        ),
      ),
    );
    return Material(
      color: KColors.sidebar,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(right: BorderSide(color: Color(0xFF1C1C19))),
        ),
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          label: 'Tabs',
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (isDesktop)
                  const DragToMoveArea(child: wordmark)
                else
                  wordmark,
                const SizedBox(height: 28),
                item(AppTab.home),
                const SizedBox(height: 2),
                item(AppTab.search),
                const SizedBox(height: 2),
                item(AppTab.downloads, count: active),
                // The empty middle moves the window too.
                Expanded(
                  child: isDesktop
                      ? const DragToMoveArea(child: SizedBox.expand())
                      : const SizedBox.expand(),
                ),
                const _DownloadsCard(),
                const _TraktRow(),
                const SizedBox(height: 2),
                item(AppTab.settings),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A sidebar destination: 42 high; the current one on a lime wash with the
/// four-point sparkle beside it.
class _NavItem extends StatelessWidget {
  const _NavItem({
    super.key,
    required this.tab,
    required this.selected,
    required this.onTap,
    this.count = 0,
  });

  final AppTab tab;
  final bool selected;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = KinoraTint.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: count > 0 ? '${tab.label}, $count active' : tab.label,
      excludeSemantics: true,
      child: PointerFocus(
        onActivate: onTap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KRadius.button),
        ),
        builder: (context, hovered) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: KMotion.fast,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(KRadius.button),
              color: selected
                  ? null
                  : hovered
                  ? KColors.raised
                  : const Color(0x00000000),
              gradient: selected
                  ? LinearGradient(
                      colors: [
                        accent.withValues(alpha: 0.20),
                        accent.withValues(alpha: 0.03),
                      ],
                    )
                  : null,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: selected
                      ? const Center(
                          child: SizedBox.square(
                            dimension: 11,
                            child: CustomPaint(
                              painter: Sparkle(KColors.limeLink),
                            ),
                          ),
                        )
                      : null,
                ),
                Icon(
                  tab.icon,
                  size: 19,
                  color: selected ? KColors.title : KColors.haze,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    tab.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: KType.title.copyWith(
                      color: selected ? KColors.title : KColors.haze,
                      fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                      fontVariations: [
                        FontVariation.weight(selected ? 500 : 400),
                      ],
                    ),
                  ),
                ),
                if (count > 0)
                  Container(
                    margin: const EdgeInsets.only(right: 12),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: KColors.raised,
                      border: Border.all(color: KColors.fieldEdge),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$count',
                      style: KType.badge.copyWith(color: KColors.body),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The four-point sparkle from the mark: "you are here".
class Sparkle extends CustomPainter {
  const Sparkle(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height, cx = w / 2, cy = h / 2;
    final p = Path()
      ..moveTo(cx, 0)
      ..quadraticBezierTo(cx + w * 0.08, cy - h * 0.08, w, cy)
      ..quadraticBezierTo(cx + w * 0.08, cy + h * 0.08, cx, h)
      ..quadraticBezierTo(cx - w * 0.08, cy + h * 0.08, 0, cy)
      ..quadraticBezierTo(cx - w * 0.08, cy - h * 0.08, cx, 0)
      ..close();
    canvas.drawPath(p, Paint()..color = color);
  }

  @override
  bool shouldRepaint(Sparkle old) => old.color != color;
}

/// What's downloading, at the sidebar's foot (only while something is).
class _DownloadsCard extends ConsumerWidget {
  const _DownloadsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = (ref.watch(downloadsProvider).value ?? const [])
        .where((d) => d.state == 'downloading' || d.state == 'queued')
        .toList();
    if (rows.isEmpty) return const SizedBox.shrink();
    final total = rows.fold(0, (a, d) => a + d.totalBytes);
    final done = rows.fold(0, (a, d) => a + d.doneBytes);
    final fraction = total == 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
    final first = rows.first;
    final what = first.episode == null
        ? first.title
        : '${first.title} · S${first.season ?? 1} E${first.episode}';
    final accent = KinoraTint.of(context);
    void open() => GoRouter.of(context).go('/downloads');
    return Padding(
      padding: const EdgeInsets.only(bottom: KSpace.x2),
      child: Semantics(
        button: true,
        label:
            'Downloading ${rows.length}, ${(fraction * 100).round()}%. '
            'Open Downloads',
        excludeSemantics: true,
        child: PointerFocus(
          onActivate: open,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(KRadius.panel),
          ),
          builder: (context, hovered) => GestureDetector(
            onTap: open,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: hovered ? const Color(0xFF1D1D1A) : KColors.raised,
                border: Border.all(color: KColors.fieldEdge),
                borderRadius: BorderRadius.circular(KRadius.panel),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.file_download_outlined,
                        size: 15,
                        color: accent,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Downloading ${rows.length}',
                          style: KType.label.copyWith(color: KColors.title),
                        ),
                      ),
                      Text(
                        '${(fraction * 100).round()}%',
                        style: KType.numeric.copyWith(color: accent),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: fraction,
                      minHeight: 3,
                      color: accent,
                      backgroundColor: KColors.fieldEdge,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$what · ${Fmt.bytes(done)} / ${Fmt.bytes(total)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: KType.meta,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Your Trakt account at the sidebar's foot (hidden in builds without it).
class _TraktRow extends ConsumerWidget {
  const _TraktRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trakt = ref.watch(traktSyncProvider);
    return ListenableBuilder(
      listenable: trakt,
      builder: (context, _) {
        if (!trakt.available) return const SizedBox.shrink();
        final name = trakt.signedIn ? (trakt.user ?? 'Trakt') : null;
        void open() => unawaited(showTraktSheet(context));
        return Semantics(
          button: true,
          label: name == null ? 'Sign in with Trakt' : 'Trakt, $name',
          excludeSemantics: true,
          child: PointerFocus(
            onActivate: open,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(KRadius.button),
            ),
            builder: (context, hovered) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: open,
              child: AnimatedContainer(
                duration: KMotion.fast,
                height: 46,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: hovered ? KColors.raised : const Color(0x00000000),
                  borderRadius: BorderRadius.circular(KRadius.button),
                ),
                child: Row(
                  children: [
                    if (name != null)
                      TraktAvatar(user: name, syncing: trakt.syncing, size: 30)
                    else
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: KColors.raised,
                          border: Border.all(color: KColors.fieldEdge),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.person_add_alt_rounded,
                          size: 16,
                          color: KColors.body,
                        ),
                      ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name ?? 'Sign in with Trakt',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: KType.label.copyWith(color: KColors.title),
                          ),
                          Text(
                            name == null
                                ? 'Sync what you watch'
                                : trakt.syncing
                                ? 'SYNCING…'
                                : 'TRAKT · SYNCED',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: name == null ? KType.small : KType.meta,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The window bar over a wide window's content: back, where you are, the
/// search field, Cast, and the window's buttons; the rest moves the window.
class _WindowBar extends StatelessWidget {
  const _WindowBar({
    required this.router,
    required this.path,
    required this.tab,
  });

  final GoRouter router;
  final String path;
  final int tab;

  String get _where {
    if (path.startsWith('/title')) {
      final name = pageNames.value[path];
      return name == null
          ? AppTab.values[tab].label
          : '${AppTab.values[tab].label}  /  $name';
    }
    const pages = {
      'sources': 'Sources',
      'languages': 'Languages',
      'style': 'Subtitle style',
      'subtitle-sites': 'Subtitle sites',
      'trakt': 'Trakt',
      'backup': 'Backup',
      'playback': 'Playback',
      'downloads': 'Downloads',
      'network': 'Network',
      'storage': 'Storage',
      'diagnostics': 'Diagnostics',
      'about': 'About',
    };
    final parts = path.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.length > 1 && parts.first == 'settings') {
      return 'Settings  /  ${pages[parts.last] ?? parts.last}';
    }
    return AppTab.values[tab].label;
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: pageNames,
    builder: (context, _, _) => _bar(context),
  );

  Widget _bar(BuildContext context) {
    // From the address: the navigator's own stack (canPop) lags a page.
    final back = !const {
      '/',
      '/search',
      '/downloads',
      '/settings',
    }.contains(path);
    final title = Align(
      alignment: Alignment.centerLeft,
      child: Text(
        _where,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: KType.label.copyWith(
          color: KColors.title,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          fontVariations: const [FontVariation.weight(600)],
        ),
      ),
    );
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Material(
          color: const Color(0xB8000000),
          child: Container(
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: KColors.divider)),
            ),
            padding: const EdgeInsets.only(left: 24),
            child: Row(
              children: [
                if (back) ...[
                  _BarIcon(
                    icon: Icons.chevron_left_rounded,
                    label: 'Back',
                    // (Opened straight from a link: up to its tab.)
                    onTap: () => router.canPop()
                        ? router.pop()
                        : router.go(
                            path.startsWith('/settings/') ? '/settings' : '/',
                          ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: isDesktop ? DragToMoveArea(child: title) : title,
                ),
                const SizedBox(width: 12),
                // (Discovery has its own field.)
                if (!path.startsWith('/search'))
                  _SearchField(
                    onTap: () {
                      rootNavigatorKey.currentState?.popUntil((r) => r.isFirst);
                      router.go('/search');
                      focusSearch.value++;
                    },
                  ),
                const SizedBox(width: 8),
                CastTargetBuilder(
                  builder: (context, tv) => _BarIcon(
                    icon: tv == null
                        ? Icons.cast_rounded
                        : Icons.cast_connected_rounded,
                    label: tv == null
                        ? 'Cast to a TV'
                        : 'Cast to ${tv.friendlyName} is on. Change TV',
                    lit: tv != null,
                    onTap: () => unawaited(showCastPicker(context)),
                  ),
                ),
                const SizedBox(width: 12),
                if (isDesktop)
                  const WindowButtons(height: WideNav.barHeight)
                else
                  const SizedBox(width: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The window bar's search: a field-looking button that opens Search with
/// the keyboard in it (Ctrl+K anywhere).
class _SearchField extends StatelessWidget {
  const _SearchField({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Search movies and shows',
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
          width: 310,
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: KColors.panel,
            border: Border.all(
              color: hovered ? KColors.strongEdge : KColors.fieldEdge,
            ),
            borderRadius: BorderRadius.circular(KRadius.button),
          ),
          child: Row(
            children: [
              const Icon(Icons.search_rounded, size: 16, color: KColors.muted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Search movies, shows…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: KType.label.copyWith(
                    color: KColors.muted,
                    fontWeight: FontWeight.w400,
                    fontVariations: const [FontVariation.weight(400)],
                  ),
                ),
              ),
              if (isDesktop)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: KColors.strongEdge),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    'Ctrl K',
                    style: KType.badge.copyWith(color: KColors.muted),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// A 32 px square icon button in the window bar.
class _BarIcon extends StatelessWidget {
  const _BarIcon({
    required this.icon,
    required this.label,
    required this.onTap,
    this.lit = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool lit;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    child: PointerFocus(
      onActivate: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      builder: (context, hovered) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: KMotion.fast,
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: hovered ? KColors.raised : KColors.panel,
            border: Border.all(color: KColors.strongEdge),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 17,
            color: lit ? KinoraTint.of(context) : KColors.body,
          ),
        ),
      ),
    ),
  );
}

/// The player and onboarding on a computer: no frame, just a strip to move
/// the window by and its buttons.
class _BareBar extends StatelessWidget {
  const _BareBar();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x99000000), Color(0x00000000)],
      ),
    ),
    child: Row(
      children: [
        Expanded(child: DragToMoveArea(child: SizedBox.expand())),
        WindowButtons(height: kTitleBarHeight),
      ],
    ),
  );
}

/// The frame dims with the page while a dialog or sheet is open; a click on
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
