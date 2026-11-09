import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinora/app/app.dart';
import 'package:kinora/app/providers.dart';
import 'package:kinora/features/home/home_screen.dart';
import 'package:kinora/core/settings.dart';

void main() {
  testWidgets('first launch opens onboarding', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: KinoraApp()));
    await tester.pumpAndSettle();
    expect(find.text('Your own cinema'), findsOneWidget);
  });

  testWidgets('onboarded users land on Home and can switch tabs', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialSettingsProvider.overrideWithValue(
            const AppSettings(onboarded: true),
          ),
        ],
        child: const KinoraApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsWidgets);
    // Laid out at the screen's size, not just present in the tree.
    expect(
      tester.getSize(find.byType(HomeScreen)),
      tester.view.physicalSize / tester.view.devicePixelRatio,
    );
    await tester.tap(find.byKey(const ValueKey('tab-search')));
    await tester.pumpAndSettle();
    expect(find.text('Search'), findsWidgets);
  });
}
