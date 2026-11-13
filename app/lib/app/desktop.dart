import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show kBackMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../core/log.dart';
import '../ui/tokens.dart';
import 'router.dart';
import 'shell.dart' show focusSearch;

/// Kinora draws its own window frame (Windows): the title bar, its drag
/// area and the minimize, maximize and close buttons.
bool get isDesktop => desktopOverride ?? Platform.isWindows;

/// Tests turn the desktop frame on or off.
@visibleForTesting
bool? desktopOverride;

/// Height of Kinora's title bar.
const double kTitleBarHeight = 40;

/// Outside the player a phone stays upright, as streaming apps do (its
/// pages are laid out for it); tablets and computers turn freely.
Future<void> keepPhoneUpright() async {
  try {
    final display =
        WidgetsBinding.instance.platformDispatcher.views.first.display;
    final shortest = display.size.shortestSide / display.devicePixelRatio;
    // Unknown (no display yet): leave rotation as it is.
    if (!shortest.isFinite || shortest <= 0) {
      Log.i('app', 'rotation: screen size not known yet');
      return;
    }
    final phone = !isDesktop && shortest < 600;
    Log.i('app', 'rotation: ${phone ? 'phone, upright' : 'free'}');
    await SystemChrome.setPreferredOrientations(
      phone ? const [DeviceOrientation.portraitUp] : const [],
    );
  } on Object catch (e) {
    // Rotation is a nicety: it never stops the app from starting.
    Log.w('app', 'rotation: $e');
  }
}

/// The window's first size and smallest size on a screen of [screen]
/// (logical pixels): 1280 × 800 and 960 × 640, shrunk to fit a small or
/// scaled-up screen with room for the taskbar (a 1366 × 768 laptop at
/// 125 % is 1093 × 614).
({Size size, Size minimum}) windowSizes(Size screen) {
  if (screen.isEmpty || !screen.isFinite) {
    return (size: const Size(1280, 800), minimum: const Size(960, 640));
  }
  final fit = Size(screen.width * 0.92, screen.height * 0.85);
  Size within(Size s) =>
      Size(math.min(s.width, fit.width), math.min(s.height, fit.height));
  return (
    size: within(const Size(1280, 800)),
    minimum: within(const Size(960, 640)),
  );
}

/// Opens the window without the system frame, sized for watching.
Future<void> initDesktopWindow() async {
  await windowManager.ensureInitialized();
  var screen = Size.zero;
  try {
    final display =
        WidgetsBinding.instance.platformDispatcher.views.first.display;
    screen = display.size / display.devicePixelRatio;
  } on Object catch (e) {
    debugPrint('display unknown: $e');
  }
  final sizes = windowSizes(screen);
  await windowManager.waitUntilReadyToShow(
    WindowOptions(
      title: 'Kinora',
      size: sizes.size,
      minimumSize: sizes.minimum,
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
  // Kinora's runner does it (windows/runner/flutter_window.cpp):
  // window_manager's left a grey window under the hidden title bar.
  await const MethodChannel('kinora/window')
      .invokeMethod<void>('setFullScreen', on);
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
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowFullScreen.addListener(_changed);
    unawaited(_read());
  }

  Future<void> _read() async {
    try {
      windowMaximized.value = await windowManager.isMaximized();
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
  void onWindowMaximize() => windowMaximized.value = true;
  @override
  void onWindowUnmaximize() => windowMaximized.value = false;
  @override
  void onWindowEnterFullScreen() => windowFullScreen.value = true;
  @override
  void onWindowLeaveFullScreen() => windowFullScreen.value = false;

  @override
  Widget build(BuildContext context) {
    final full = windowFullScreen.value;
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

    void search() {
      final router = ProviderScope.containerOf(context).read(routerProvider);
      rootNavigatorKey.currentState?.popUntil((r) => r.isFirst);
      router.go('/search');
      focusSearch.value++;
    }

    // Esc, Alt+Left and the mouse's back button go back, as in a browser;
    // Ctrl+K searches. In full screen Esc leaves it, as in every Windows
    // player. (The frame itself is drawn by WideNav.) The same widgets
    // either way: a different shape here would rebuild the whole app below,
    // player and router included.
    return CallbackShortcuts(
      bindings: full
          ? {
              const SingleActivator(LogicalKeyboardKey.escape): () =>
                  unawaited(setFullScreen(false)),
            }
          : {
              const SingleActivator(LogicalKeyboardKey.escape): back,
              const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true):
                  back,
              const SingleActivator(LogicalKeyboardKey.keyK, control: true):
                  search,
            },
      child: Listener(
        onPointerDown: (e) {
          if (!full && e.buttons & kBackMouseButton != 0) back();
        },
        child: widget.child,
      ),
    );
  }
}

/// Whether the window fills the screen (maximized), for the window buttons.
final windowMaximized = ValueNotifier<bool>(false);

/// Minimize, maximize (or restore) and close, [height] tall.
class WindowButtons extends StatelessWidget {
  const WindowButtons({super.key, this.height = kTitleBarHeight});

  final double height;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: windowMaximized,
    builder: (context, maximized, _) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CaptionButton(
          glyph: CaptionGlyph.minimize,
          label: 'Minimize',
          height: height,
          onPressed: () => unawaited(windowManager.minimize()),
        ),
        CaptionButton(
          glyph: maximized ? CaptionGlyph.restore : CaptionGlyph.maximize,
          label: maximized ? 'Restore' : 'Maximize',
          height: height,
          onPressed: () => unawaited(
            maximized ? windowManager.unmaximize() : windowManager.maximize(),
          ),
        ),
        CaptionButton(
          glyph: CaptionGlyph.close,
          label: 'Close',
          height: height,
          onPressed: () => unawaited(windowManager.close()),
        ),
      ],
    ),
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
    this.height = kTitleBarHeight,
  });

  final CaptionGlyph glyph;
  final String label;
  final VoidCallback onPressed;
  final double height;

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
            height: widget.height,
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
