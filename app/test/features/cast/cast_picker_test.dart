import 'package:dlna/dlna.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinora/features/cast/cast_picker.dart';
import 'package:kinora/services/cast_service.dart';

import '../harness.dart';

final livingRoom = DlnaDevice(
  udn: 'uuid:tv-1',
  friendlyName: 'Living Room TV',
  modelName: 'Samsung 5 Series',
  location: Uri.parse('http://192.168.1.20:9197/dmr'),
  avTransportControlUrl: Uri.parse('http://192.168.1.20:9197/upnp/control'),
);

void main() {
  test('reads TV addresses typed on any keyboard', () {
    expect(parseTvAddress(' 192.168.1.20 '), '192.168.1.20');
    expect(parseTvAddress('192,168,1,20'), '192.168.1.20');
    expect(parseTvAddress('١٩٢٫١٦٨٫١٫٢٠'), '192.168.1.20');
    expect(parseTvAddress('192.168.1'), isNull);
    expect(parseTvAddress('192.168.1.300'), isNull);
    expect(parseTvAddress('living room'), isNull);
  });

  testScreen('choosing a TV before playing shows it as a capsule', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      const Scaffold(body: Center(child: CastButton())),
      db: testDb(),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CastButton)),
    );
    container.read(castServiceProvider).devices = [livingRoom];
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Cast to a TV'));
    await tester.pumpAndSettle();
    expect(find.text('Cast to a TV'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('^Play on this phone. Chosen')),
      findsOne,
    );

    // A typo says what an address looks like.
    await tester.enterText(find.byKey(const ValueKey('tv-address')), '192.168');
    await tester.tap(find.bySemanticsLabel('Add TV'));
    await tester.pumpAndSettle();
    expect(find.textContaining('It looks like 192.168.1.20'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel(RegExp('^Cast to Living Room TV')));
    await tester.pumpAndSettle();
    expect(container.read(castServiceProvider).target, livingRoom);
    expect(
      find.bySemanticsLabel('Playing on Living Room TV. Change'),
      findsOneWidget,
    );
    expect(playOn('Play S1 E3', livingRoom), 'Play S1 E3 on Living Room TV');
  });
}
