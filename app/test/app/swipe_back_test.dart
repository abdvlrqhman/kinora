import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinora/app/app.dart';
import 'package:kinora/app/providers.dart';
import 'package:kinora/app/router.dart';
import 'package:kinora/core/settings.dart';
import 'package:kinora/features/settings/settings_screen.dart';

import '../features/harness.dart';

void main() {
  testWidgets('iPhone: a swipe from the left edge goes back a page', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(testDb()),
          initialSettingsProvider.overrideWithValue(
            const AppSettings(onboarded: true),
          ),
        ],
        child: const KinoraApp(showIntro: false),
      ),
    );
    await tester.pumpAndSettle();
    final router = ProviderScope.containerOf(
      tester.element(find.byType(KinoraApp)),
    ).read(routerProvider);

    Future<void> swipeBack() async {
      final size = tester.view.physicalSize / tester.view.devicePixelRatio;
      await tester.dragFrom(
        Offset(4, size.height / 2),
        Offset(size.width * 0.7, 0),
      );
      await tester.pumpAndSettle();
    }

    // A settings page, opened from Settings.
    router.go('/settings');
    await tester.pumpAndSettle();
    router.go('/settings/about');
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/settings/about');
    await swipeBack();
    expect(router.state.uri.path, '/settings');
    expect(find.byType(SettingsScreen), findsOneWidget);

    // A title page, opened over Home.
    router.go('/');
    await tester.pumpAndSettle();
    unawaited(router.push('/title/movie/tt0000001'));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/title/movie/tt0000001');
    await swipeBack();
    expect(router.state.uri.path, '/');
    // Let the title page's lookups time out before the test ends.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 1));
    debugDefaultTargetPlatformOverride = null;
  });
}
