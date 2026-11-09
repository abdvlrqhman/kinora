import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../settings/settings_harness.dart';

const _cinemeta = 'https://v3-cinemeta.strem.io/manifest.json';

Future<void> _next(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('onboarding-next')));
  await tester.pumpAndSettle();
}

void main() {
  kitTest('walks from welcome to Home, saving each choice', (tester) async {
    final kit = await pumpKit(
      tester,
      location: '/onboarding',
      manifests: {_cinemeta: manifestJson('Cinemeta')},
    );
    await tester.pumpAndSettle();
    expect(find.text('Your own cinema'), findsOneWidget);
    expect(find.text('Set up Kinora'), findsOneWidget);
    // No skipping before the welcome is read.
    expect(find.text('Skip'), findsNothing);
    await _next(tester);

    // Languages.
    expect(find.text('Your languages'), findsOneWidget);
    expect(find.bySemanticsLabel('Step 1 of 6'), findsOneWidget);
    await tester.tap(find.text('Add a language'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('language-search')),
      'arabic',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel(RegExp('^Arabic')).first);
    await tester.pumpAndSettle();
    expect(kit.settings.subtitleLanguages, ['ar']);
    await _next(tester);

    // Sources: plain explanation, link field, two official suggestions.
    expect(find.text('Add your sources'), findsOneWidget);
    expect(find.textContaining('no movies or shows of its own'), findsOne);
    expect(find.byKey(const ValueKey('addon-url')), findsOneWidget);
    await tester.tap(find.text('Cinemeta'));
    await tester.pumpAndSettle();
    expect(find.text('Cinemeta added'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Catalogs and details'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await _next(tester);

    // Debrid is optional: added as a configured stream source.
    expect(find.text('Instant playback'), findsOneWidget);
    expect(find.byKey(const ValueKey('addon-url')), findsOneWidget);
    await _next(tester);

    // Subtitle sites are optional.
    expect(find.text('Subtitle sites'), findsOneWidget);
    expect(find.textContaining('Optional.'), findsOneWidget);
    await _next(tester);

    // So is a TV; this phone is the default.
    expect(find.text('Your TV'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('^Play on this phone. Chosen')),
      findsOne,
    );
    await _next(tester);

    // Done: a summary, then Home. Cinemeta lists titles but streams none.
    expect(find.text('You’re set'), findsOneWidget);
    expect(find.text('Subtitles in Arabic'), findsOneWidget);
    expect(find.text('1 source: Cinemeta'), findsOneWidget);
    expect(
      find.text('Nothing will play yet: add a source that provides streams.'),
      findsOneWidget,
    );
    expect(kit.settings.onboarded, isFalse);
    await tester.tap(find.text('Start watching'));
    await tester.pumpAndSettle();
    expect(kit.settings.onboarded, isTrue);
  });

  kitTest('Skip jumps to the end and Back returns', (tester) async {
    final kit = await pumpKit(tester, location: '/onboarding');
    await tester.pumpAndSettle();
    await _next(tester);
    await tester.tap(find.bySemanticsLabel('Skip setup'));
    await tester.pumpAndSettle();
    expect(find.text('You’re set'), findsOneWidget);
    expect(
      find.text('No sources yet. Add one in Settings to see movies and shows.'),
      findsOneWidget,
    );
    await tester.tap(find.byIcon(Icons.chevron_left_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Your TV'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Skip setup'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start watching'));
    await tester.pumpAndSettle();
    expect(kit.settings.onboarded, isTrue);
  });

  kitTest('every step fits at 1.5x text, with motion off', (tester) async {
    await pumpKit(tester, location: '/onboarding', textScale: 1.5);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpAndSettle();
    for (var step = 0; step < 7; step++) {
      expect(tester.takeException(), isNull, reason: 'step $step');
      final scrollable = find.byType(Scrollable);
      if (scrollable.evaluate().isNotEmpty) {
        await tester.fling(scrollable.first, const Offset(0, -3000), 3000);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'step $step end');
      }
      if (step < 6) await _next(tester);
    }
  });
}
