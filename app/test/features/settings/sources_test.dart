import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinora/features/settings/sources.dart';
import 'package:stremio/stremio.dart';

import 'settings_harness.dart';

const _cinemeta = 'https://v3-cinemeta.strem.io/manifest.json';
const _configured =
    'https://streams.test/realdebrid=SECRETDEBRIDKEY42/manifest.json';

void main() {
  test('addon links are masked down to the host', () {
    expect(maskAddonUrl(Uri.parse(_cinemeta)), 'v3-cinemeta.strem.io');
    final masked = maskAddonUrl(Uri.parse(_configured));
    expect(masked, 'streams.test/…');
    expect(masked, isNot(contains('SECRET')));
  });

  test('errors are words, never the link', () {
    final e = AddonHttpException(404, Uri.parse(_configured));
    expect(
      addonError(e),
      'Nothing was found at that link. Check that it’s '
      'complete.',
    );
    expect(
      addonError(AddonNetworkException('reset', uri: Uri.parse(_configured))),
      isNot(contains('SECRET')),
    );
  });

  kitTest('adds a source by link and shows what it provides, not its key', (
    tester,
  ) async {
    final kit = await pumpKit(
      tester,
      location: '/settings/sources',
      manifests: {
        _configured: manifestJson('Stream Finder', resources: ['stream']),
      },
    );
    await tester.pumpAndSettle();
    expect(
      find.text('No sources yet. Add one by its link, or pick a suggestion.'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('addon-url')),
      _configured,
    );
    await tester.tap(find.text('Add source'));
    await tester.pumpAndSettle();
    expect(find.text('Stream Finder'), findsOneWidget);
    expect(find.text('Streams'), findsOneWidget);
    expect(find.text('streams.test/…'), findsOneWidget);
    expect(find.text('Not used yet'), findsOneWidget);
    expect(find.textContaining('SECRETDEBRIDKEY42'), findsNothing);
    expect(find.text('Added Stream Finder.'), findsOneWidget);

    // Turn it off.
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect((await kit.db.select(kit.db.addons).getSingle()).enabled, isFalse);

    // Long-press, confirm, gone.
    await tester.longPress(find.text('Stream Finder'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Remove source'));
    await tester.pumpAndSettle();
    expect(find.text('Remove Stream Finder?'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Remove'));
    await tester.pumpAndSettle();
    expect(await kit.db.select(kit.db.addons).get(), isEmpty);
    expect(find.text('Stream Finder'), findsNothing);
  });

  kitTest('says what went wrong with a bad link', (tester) async {
    await pumpKit(tester, location: '/settings/sources');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add source'));
    await tester.pumpAndSettle();
    expect(find.text('Paste an addon link first.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('addon-url')),
      'https://nothing.test/abc/manifest.json',
    );
    await tester.tap(find.text('Add source'));
    await tester.pumpAndSettle();
    expect(
      find.text('Nothing was found at that link. Check that it’s complete.'),
      findsOneWidget,
    );
  });

  kitTest('suggests only Cinemeta and OpenSubtitles, added in one tap', (
    tester,
  ) async {
    final kit = await pumpKit(
      tester,
      location: '/settings/sources',
      size: const Size(390, 1200),
      manifests: {
        _cinemeta: manifestJson('Cinemeta'),
        _configured: manifestJson('Stream Finder', resources: ['stream']),
      },
    );
    await tester.pumpAndSettle();
    expect(find.text('Cinemeta'), findsOneWidget);
    expect(find.text('OpenSubtitles v3'), findsOneWidget);
    expect(suggestedAddons, hasLength(2));

    await tester.tap(find.text('Cinemeta'));
    await tester.pumpAndSettle();
    expect(find.text('Catalogs and details'), findsOneWidget);
    expect(find.text('v3-cinemeta.strem.io'), findsOneWidget);
    // The suggestion now confirms it's installed.
    expect(find.text('Cinemeta added'), findsOneWidget);
    expect(find.text('OpenSubtitles v3'), findsOneWidget);

    // Drag the second source above the first.
    await tester.enterText(
      find.byKey(const ValueKey('addon-url')),
      _configured,
    );
    await tester.tap(find.text('Add source'));
    await tester.pumpAndSettle();
    final handle = find.byIcon(Icons.drag_handle_rounded).last;
    final drag = await tester.startGesture(tester.getCenter(handle));
    for (var i = 0; i < 10; i++) {
      await drag.moveBy(const Offset(0, -15));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await drag.up();
    await tester.pumpAndSettle();
    final rows = await kit.db.select(kit.db.addons).get()
      ..sort((a, b) => a.position.compareTo(b.position));
    expect(rows.first.transportUrl, _configured);
  });
}
