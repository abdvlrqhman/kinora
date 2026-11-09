// Runs on an iOS simulator in CI (.github/workflows/glass.yml): reports
// whether Impeller draws the real liquid glass, prints a screenshot as
// base64 chunks (the workflow puts it back together), then holds the
// scene so the workflow can also grab the simulator's own screen.
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glass_probe/main.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real liquid glass draws frames', (tester) async {
    // ignore: avoid_print
    print('GLASS impeller: ${ui.ImageFilter.isShaderFilterSupported}');
    var frames = 0;
    void count(List<ui.FrameTiming> t) => frames += t.length;
    SchedulerBinding.instance.addTimingsCallback(count);
    const shot = Key('shot');
    await tester.pumpWidget(
      const RepaintBoundary(key: shot, child: ProbeApp()),
    );
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(shot),
    );
    final image = await boundary.toImage();
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final data = base64Encode(png!.buffer.asUint8List());
    const size = 2000;
    final n = (data.length / size).ceil();
    for (var i = 0; i < n; i++) {
      final end = (i + 1) * size < data.length ? (i + 1) * size : data.length;
      // ignore: avoid_print
      print('GLASS-SHOT probe ${i + 1}/$n ${data.substring(i * size, end)}');
    }

    // ignore: avoid_print
    print('GLASS ready');
    for (var i = 0; i < 200; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    SchedulerBinding.instance.removeTimingsCallback(count);
    // The package draws frosted FakeGlass when Impeller or Flutter GPU
    // isn't there: none of it on screen means the real glass drew.
    final fake = tester.allRenderObjects
        .where((r) => r.runtimeType.toString().contains('FakeGlass'))
        .length;
    // ignore: avoid_print
    print('GLASS frames rasterized: $frames, frosted fallbacks: $fake');
    expect(frames, greaterThan(0), reason: 'no frame was drawn');
    expect(fake, 0, reason: 'the glass fell back to frosted');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
