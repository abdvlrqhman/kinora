import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:kinora/features/person/person_screen.dart';
import 'package:kinora/services/suggestions.dart';
import 'package:stremio/stremio.dart';

import '../harness.dart';

void main() {
  testScreen('a person\'s page lists what they directed and acted in', (
    tester,
  ) async {
    final nav = await pumpScreen(
      tester,
      const PersonScreen(slug: 'ada-reyes', name: 'Ada Reyes'),
      db: testDb(),
      size: const Size(390, 1400),
      overrides: [
        personCreditsProvider.overrideWith(
          (ref, slug) async => (
            directed: const [
              MetaPreview(id: 'tt2', type: 'movie', name: 'New Light'),
            ],
            acted: const [
              MetaPreview(id: 'tt3', type: 'series', name: 'Harbor Lights'),
            ],
            wrote: const <MetaPreview>[],
          ),
        ),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.text('Ada Reyes'), findsOneWidget);
    expect(find.text('Directed  1'), findsOneWidget);
    expect(find.text('Acted in  1'), findsOneWidget);
    expect(find.textContaining('Wrote'), findsNothing);
    await tester.tap(find.bySemanticsLabel(RegExp('^Harbor Lights')));
    await tester.pumpAndSettle();
    expect(nav.locations.last, '/title/series/tt3');
  });
}
