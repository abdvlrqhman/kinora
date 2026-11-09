// Informational: does the real liquid-glass renderer (Flutter GPU) produce
// frames on this device? CI runs it on the emulator with continue-on-error.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kinora/ui/glass.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('glass renders frames', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              const Positioned.fill(child: ColoredBox(color: Colors.indigo)),
              Center(
                child: GlassButton(label: 'Play', onPressed: () {}),
              ),
            ],
          ),
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Play'), findsOneWidget);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
