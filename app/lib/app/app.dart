import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ui/theme.dart';
import '../ui/tint.dart';
import '../ui/tokens.dart';
import 'router.dart';

/// Root widget.
class KinoraApp extends ConsumerWidget {
  const KinoraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Kinora',
      debugShowCheckedModeBanner: false,
      theme: kinoraTheme(),
      darkTheme: kinoraTheme(),
      themeMode: ThemeMode.dark,
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) =>
          KinoraTint(accent: KColors.marquee, child: child!),
    );
  }
}
