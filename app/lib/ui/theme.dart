import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'tokens.dart';

/// The app theme built from DESIGN.md tokens. Dark only: Kinora is used in
/// dark rooms and on top of artwork.
ThemeData kinoraTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: KColors.marquee,
        brightness: Brightness.dark,
      ).copyWith(
        surface: KColors.blackout,
        onSurface: KColors.lamp,
        onSurfaceVariant: KColors.haze,
        surfaceContainerHighest: KColors.seat,
        primary: KColors.marquee,
        onPrimary: KColors.blackout,
        error: KColors.cut,
        outline: KColors.reel,
      );
  final text = TextTheme(
    displayLarge: KType.hero,
    headlineLarge: KType.h1,
    headlineMedium: KType.h2,
    titleLarge: KType.title,
    titleMedium: KType.title,
    bodyLarge: KType.body,
    bodyMedium: KType.body,
    labelLarge: KType.label,
    labelMedium: KType.label,
    bodySmall: KType.small,
    labelSmall: KType.small,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: KColors.blackout,
    canvasColor: KColors.blackout,
    fontFamily: KType.text,
    textTheme: text,
    iconTheme: const IconThemeData(color: KColors.lamp, size: 22),
    splashFactory: NoSplash.splashFactory,
    highlightColor: KColors.lamp.withValues(alpha: 0.06),
    dividerTheme: DividerThemeData(
      color: KColors.lamp.withValues(alpha: 0.08),
      space: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: KColors.seat,
      contentTextStyle: KType.body,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.transparent,
      modalBackgroundColor: Colors.transparent,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
      },
    ),
    sliderTheme: SliderThemeData(
      trackHeight: 3,
      tickMarkShape: SliderTickMarkShape.noTickMark,
      inactiveTrackColor: KColors.lamp.withValues(alpha: 0.18),
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
      overlayShape: SliderComponentShape.noOverlay,
    ),
    // On: Lamp thumb on the brand accent (Marquee). Go stays reserved for
    // ready and downloaded.
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? KColors.lamp : KColors.haze,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        // Off: the slider's inactive track (Seat on black was ~1.1:1).
        (s) => s.contains(WidgetState.selected)
            ? KColors.marquee
            : KColors.lamp.withValues(alpha: 0.18),
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Color(0x00000000)),
    ),
  );
}
