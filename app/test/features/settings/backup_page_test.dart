import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinora/services/backup.dart';

import 'settings_harness.dart';

void main() {
  testWidgets('a long backup code typed or pasted into Restore restores', (
    tester,
  ) async {
    // Sources with real-sized manifests make a code far past 2,048 letters.
    final random = Random(7);
    String noise(int n) =>
        String.fromCharCodes(List.generate(n, (_) => 97 + random.nextInt(26)));
    final code = (await tester.runAsync(
      () => BackupCode.seal(
        {
          'sources': [
            for (var i = 0; i < 6; i++)
              {
                'url': 'https://source$i.test/manifest.json',
                'manifest': jsonEncode({'id': 'a$i', 'name': noise(900)}),
                'enabled': true,
              },
          ],
        },
        'correct horse',
        iterations: 1000,
      ),
    ))!;
    expect(code.length, greaterThan(4096));

    final kit = await pumpKit(tester, location: '/settings/backup');
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('restore-code'));
    await tester.scrollUntilVisible(
      field,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    // (enterText goes through the field's input formatters, like a paste.)
    await tester.enterText(field, code);
    await tester.enterText(
      find.byKey(const ValueKey('restore-pass')),
      'correct horse',
    );
    await tester.tap(find.text('Restore').last);
    // The passphrase is stretched on another isolate: let it run for real.
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      if (find.textContaining('Restored').evaluate().isNotEmpty) break;
    }
    expect(find.text('Restored 6 sources and 0 keys.'), findsOneWidget);
    expect(await kit.db.select(kit.db.addons).get(), hasLength(6));
  });
}
