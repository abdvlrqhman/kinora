// Renders the app icon to assets/icon/ (1024 px): icon.png (iOS, legacy
// Android) and foreground.png (Android adaptive, transparent).
// Run: flutter test tool/render_icon_test.dart
// Then: dart run flutter_launcher_icons
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinora/ui/widgets/brand.dart';

const _seat = Color(0xFF17141B);

class KinoraIcon extends StatelessWidget {
  const KinoraIcon({super.key, this.foregroundOnly = false});

  /// Android adaptive foreground: transparent background.
  final bool foregroundOnly;

  @override
  Widget build(BuildContext context) {
    const mark = CustomPaint(size: Size(1024, 1024), painter: KinoraMark());
    return SizedBox(
      width: 1024,
      height: 1024,
      child: foregroundOnly
          // flutter_launcher_icons insets the foreground by 16% itself.
          ? mark
          : const ColoredBox(color: _seat, child: mark),
    );
  }
}

Future<void> _render(WidgetTester tester, Widget w, String path) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(key: key, child: w),
      ),
    ),
  );
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage();
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  await File(path).writeAsBytes(bytes!.buffer.asUint8List());
}

void main() {
  testWidgets('render icon', (tester) async {
    tester.view
      ..physicalSize = const Size(1024, 1024)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await _render(tester, const KinoraIcon(), 'assets/icon/icon.png');
      await _render(
        tester,
        const KinoraIcon(foregroundOnly: true),
        'assets/icon/foreground.png',
      );
    });
  });
}
