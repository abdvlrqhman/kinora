import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinora/app/intro.dart';
import 'package:kinora/ui/widgets/spacie_logo.dart';

/// Counts its own builds' state: a rebuild from scratch resets it.
class _Counter extends StatefulWidget {
  const _Counter();
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int taps = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => setState(() => taps++),
        child: Text('taps $taps'),
      ),
    ),
  );
}

Future<void> _pump(WidgetTester tester, {bool reduceMotion = false}) async {
  IntroOverlay.debugReset();
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: const MaterialApp(home: IntroOverlay(child: _Counter())),
    ),
  );
}

void main() {
  testWidgets('a tap skips the intro and the app takes over', (tester) async {
    await _pump(tester);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SpacieLogo), findsOneWidget);
    await tester.tapAt(const Offset(200, 200));
    await tester.pumpAndSettle();
    expect(find.byType(SpacieLogo), findsNothing);
    await tester.tap(find.text('taps 0'));
    await tester.pump();
    expect(find.text('taps 1'), findsOneWidget);
  });

  testWidgets('with reduced motion it still ends', (tester) async {
    await _pump(tester, reduceMotion: true);
    await tester.pumpAndSettle();
    expect(find.byType(SpacieLogo), findsNothing);
  });

  testWidgets('the app underneath keeps its state when it ends', (
    tester,
  ) async {
    await _pump(tester);
    final state = tester.state<_CounterState>(find.byType(_Counter));
    await tester.pumpAndSettle();
    expect(find.byType(SpacieLogo), findsNothing);
    expect(tester.state<_CounterState>(find.byType(_Counter)), same(state));
  });
}
