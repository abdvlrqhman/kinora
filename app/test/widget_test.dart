import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:kinora/main.dart';
import 'package:kinora/shell.dart';

void main() {
  testWidgets('tab bar switches pages', (tester) async {
    await tester.pumpWidget(const KinoraApp());

    expect(find.byKey(const ValueKey('page-home')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tab-search')));
    await tester.pump();

    final stack = tester.widget<IndexedStack>(find.byType(IndexedStack));
    expect(stack.index, AppTab.search.index);
  });
}
