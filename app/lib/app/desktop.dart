import 'dart:async';
import 'dart:io';

import 'dart:ui' show ImageFilter;

import 'package:flutter/gestures.dart' show kBackMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../ui/tokens.dart';
import 'router.dart';
import '../ui/widgets/brand.dart';

/// Kinora draws its own window frame (Windows): the title bar, its drag
/// area and the minimize, maximize and close buttons.
bool get isDesktop => desktopOverride ?? Platform.isWindows;

/// Tests turn the desktop frame on or off.
@visibleForTesting
bool? desktopOverride;

/// Height of Kinora's title bar.
const double kTitleBarHeight = 40;

/// Opens the window without the system frame, sized for watching.
Future<void> initDesktopWindow() async {
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      title: 'Kinora',
      size: Size(1280, 800),
      minimumSize: Size(400, 600),
      center: true,
      backgroundColor: KColors.blackout,
      titleBarStyle: TitleBarStyle.hidden,
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );
}

/// Whether the window fills the display (the player's full screen).
final windowFullScreen = ValueNotifier<bool>(false);

/// Full screen (the player): no title bar, the whole display.
Future<void> setFullScreen(bool on) async {
  if (!isDesktop || windowFullScreen.value == on) return;
  await windowManager.setFullScreen(on);
  windowFullScreen.value = on;
}

/// The app inside Kinora's own window frame. Pages draw under the title bar
/// (artwork reaches the top edge) and keep their controls below it, as
/// they do under a phone's status bar.
class DesktopFrame extends StatefulWidget {
  const DesktopFrame({super.key, required this.child});

  final Widget child;

  @override
  State<DesktopFrame> createState() => _DesktopFrameState();
}

class _DesktopFrameState extends State<DesktopFrame> with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowFullScreen.addListener(_changed);
    unawaited(_read());
  }

  Future<void> _read() async {
    try {
      final maximized = await windowManager.isMaximized();
      if (mounted) setState(() => _maximized = maximized);
    } on Object {
      // (Tests: no window.)
    }
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    windowManager.removeListener(this);
    windowFullScreen.removeListener(_changed);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);
  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);
  @override
  void onWindowEnterFullScreen() => windowFullScreen.value = true;
  @override
  void onWindowLeaveFullScreen() => windowFullScreen.value = false;

  @override
  Widget build(BuildContext context) {
    if (windowFullScreen.value) {
      // Esc leaves full screen anywhere, as in every Windows player.
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              unawaited(setFullScreen(false)),
        },
        child: widget.child,
      );
    }
    final mq = MediaQuery.of(context);
    void back() {
      final router = ProviderScope.containerOf(context).read(routerProvider);
      // (Esc doesn't close the player: it only leaves full screen.)
      if (router.canPop() &&
          !router.routeInformationProvider.value.uri.path.startsWith(
            '/player',
          )) {
        router.pop();
      }
    }

    // Esc and the mouse's back button go back, as in a browser.
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): back},
      child: Listener(
        onPointerDown: (e) {
          if (e.buttons & kBackMouseButton != 0) back();
        },
        child: _frame(mq),
      ),
    );
  }

  Widget _frame(MediaQueryData mq) {
    return Stack(
      children: [
        Positioned.fill(
          child: MediaQuery(
            data: mq.copyWith(
              padding: mq.padding.copyWith(top: kTitleBarHeight),
              viewPadding: mq.viewPadding.copyWith(top: kTitleBarHeight),
            ),
            child: widget.child,
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: kTitleBarHeight,
          child: TitleBar(maximized: _maximized),
        ),
      ],
    );
  }
}

/// Kinora's title bar: the mark and name, a drag area (double-click to
/// maximize) and the window buttons.
class TitleBar extends StatelessWidget {
  const TitleBar({super.key, required this.maximized});

  final bool maximized;

  @override
  Widget build(BuildContext context) => ClipRect(
    // Frosted: artwork shows through, and pages scrolled under it blur
    // instead of running through the name. (Outside the app's pages: no
    // Material above it, so its text sets its own style.)
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
      child: ColoredBox(color: const Color(0xB3000000), child: _bar()),
    ),
  );

  Widget _bar() => Row(
    children: [
      Expanded(
        child: DragToMoveArea(
          child: Semantics(
            label: 'Kinora',
            excludeSemantics: true,
            child: Row(
              children: [
                const SizedBox(width: KSpace.x3),
                const SizedBox.square(
                  dimension: 22,
                  child: CustomPaint(painter: KinoraMark()),
                ),
                const SizedBox(width: KSpace.x2),
                Text(
                  'Kinora',
                  style: KType.label.copyWith(
                    color: KColors.lamp,
                    decoration: TextDecoration.none,
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
      CaptionButton(
        glyph: CaptionGlyph.minimize,
        label: 'Minimize',
        onPressed: () => unawaited(windowManager.minimize()),
      ),
      CaptionButton(
        glyph: maximized ? CaptionGlyph.restore : CaptionGlyph.maximize,
        label: maximized ? 'Restore' : 'Maximize',
        onPressed: () => unawaited(
          maximized ? windowManager.unmaximize() : windowManager.maximize(),
        ),
      ),
      CaptionButton(
        glyph: CaptionGlyph.close,
        label: 'Close',
        onPressed: () => unawaited(windowManager.close()),
      ),
    ],
  );
}

enum CaptionGlyph { minimize, maximize, restore, close }

/// One window button: a thin glyph, a soft highlight on hover, and red for
/// Close (where Windows puts it).
class CaptionButton extends StatefulWidget {
  const CaptionButton({
    super.key,
    required this.glyph,
    required this.label,
    required this.onPressed,
  });

  final CaptionGlyph glyph;
  final String label;
  final VoidCallback onPressed;

  @override
  State<CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<CaptionButton> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final close = widget.glyph == CaptionGlyph.close;
    final background = !_hover
        ? const Color(0x00000000)
        : close
        ? (_down ? const Color(0xFFA1281C) : const Color(0xFFC42B1C))
        : (_down ? const Color(0x14FFFFFF) : const Color(0x1FFFFFFF));
    return Semantics(
      button: true,
      label: widget.label,
      excludeSemantics: true,
      // (No tooltip: the bar sits outside the app's overlay.)
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() {
          _hover = false;
          _down = false;
        }),
        child: GestureDetector(
          onTapDown: (_) => setState(() => _down = true),
          onTapCancel: () => setState(() => _down = false),
          onTapUp: (_) => setState(() => _down = false),
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: KMotion.fast,
            width: 46,
            height: kTitleBarHeight,
            color: background,
            alignment: Alignment.center,
            child: SizedBox.square(
              dimension: 10,
              child: CustomPaint(
                painter: _Glyph(
                  widget.glyph,
                  close && _hover ? const Color(0xFFFFFFFF) : KColors.lamp,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Glyph extends CustomPainter {
  const _Glyph(this.glyph, this.color);

  final CaptionGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final s = size.width;
    switch (glyph) {
      case CaptionGlyph.minimize:
        canvas.drawLine(Offset(0, s / 2), Offset(s, s / 2), paint);
      case CaptionGlyph.maximize:
        canvas.drawRRect(
          RRect.fromLTRBR(
            0.5,
            0.5,
            s - 0.5,
            s - 0.5,
            const Radius.circular(1.5),
          ),
          paint,
        );
      case CaptionGlyph.restore:
        canvas
          ..drawRRect(
            RRect.fromLTRBR(
              0.5,
              2.5,
              s - 2.5,
              s - 0.5,
              const Radius.circular(1.5),
            ),
            paint,
          )
          ..drawPath(
            Path()
              ..moveTo(2.5, 0.5)
              ..lineTo(s - 0.5, 0.5)
              ..lineTo(s - 0.5, s - 2.5),
            paint,
          );
      case CaptionGlyph.close:
        canvas
          ..drawLine(Offset.zero, Offset(s, s), paint)
          ..drawLine(Offset(s, 0), Offset(0, s), paint);
    }
  }

  @override
  bool shouldRepaint(_Glyph old) => old.glyph != glyph || old.color != color;
}

/// What Kinora calls the device it runs on, inside sentences.
String get thisDevice => isDesktop ? 'this computer' : 'this phone';

/// The same, starting a label.
String get thisDeviceTitle => isDesktop ? 'This computer' : 'This phone';

/// "your phone" / "your computer".
String get yourDevice => isDesktop ? 'your computer' : 'your phone';
