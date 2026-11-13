import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinora/app/desktop.dart';

/// Counts how often it's built from scratch (a new State).
class _Probe extends StatefulWidget {
  const _Probe(this.created);
  final List<int> created;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.created.add(1);
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  testWidgets('full screen keeps the app inside the frame as it is', (
    tester,
  ) async {
    // (A rebuild from scratch lost the player and its route: a grey page.)
    desktopOverride = true;
    final created = <int>[];
    await tester.pumpWidget(
      MaterialApp(home: DesktopFrame(child: _Probe(created))),
    );
    windowFullScreen.value = true;
    await tester.pump();
    windowFullScreen.value = false;
    await tester.pump();
    expect(created, hasLength(1));
    desktopOverride = null;
  });
}
