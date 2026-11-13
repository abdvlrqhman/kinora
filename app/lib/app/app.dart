import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ui/theme.dart';
import '../ui/tint.dart';
import '../ui/tokens.dart';
import 'desktop.dart';
import 'intro.dart';
import 'router.dart';
import 'shell.dart';

/// Root widget.
class KinoraApp extends ConsumerStatefulWidget {
  const KinoraApp({super.key, this.showIntro = true});

  /// The launch intro (off for screenshots of the screens themselves).
  final bool showIntro;

  @override
  ConsumerState<KinoraApp> createState() => _KinoraAppState();
}

class _KinoraAppState extends ConsumerState<KinoraApp> {
  @override
  void initState() {
    super.initState();
    // Again once the screen's size is surely known (main's early try can
    // come before it).
    if (!isDesktop) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(keepPhoneUpright()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final showIntro = widget.showIntro;
    return MaterialApp.router(
      title: 'Kinora',
      debugShowCheckedModeBanner: false,
      theme: kinoraTheme(),
      darkTheme: kinoraTheme(),
      themeMode: ThemeMode.dark,
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) {
        final app = KinoraTint(
          accent: KColors.marquee,
          child: WideNav(child: child!),
        );
        final shown = showIntro ? IntroOverlay(child: app) : app;
        return isDesktop ? DesktopFrame(child: shown) : shown;
      },
    );
  }
}
