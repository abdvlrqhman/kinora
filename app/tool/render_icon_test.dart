// Renders the app icon to assets/icon/icon.png (1024 px) with the real fonts.
// Run: flutter test tool/render_icon_test.dart
// Then: dart run flutter_launcher_icons
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _lamp = Color(0xFFF5EEE4);
const _marquee = Color(0xFFFFC15E);

class KinoraIcon extends StatelessWidget {
  const KinoraIcon({super.key, this.foregroundOnly = false});

  /// Android adaptive foreground: transparent background, content in the
  /// central safe zone.
  final bool foregroundOnly;

  @override
  Widget build(BuildContext context) {
    final mark = Stack(
      alignment: Alignment.center,
      children: [
        // The lens: projector light through glass.
        Container(
          width: 1000,
          height: 1000,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [Color(0xCCFFC15E), Color(0x55FF8A3D), Color(0x00000000)],
              stops: [0, 0.55, 1],
            ),
          ),
        ),
        Container(
          width: 760,
          height: 760,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: _lamp.withValues(alpha: 0.4), width: 10),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0x40FFFFFF), Color(0x08FFFFFF)],
            ),
          ),
        ),
        Transform.translate(
          offset: const Offset(0, 46),
          child: const Text(
            'K',
            style: TextStyle(
              fontFamily: 'BigShoulders',
              fontSize: 600,
              height: 1,
              color: _lamp,
              fontWeight: FontWeight.w800,
              fontVariations: [FontVariation.weight(800)],
              shadows: [Shadow(color: _marquee, blurRadius: 80)],
            ),
          ),
        ),
      ],
    );
    return SizedBox(
      width: 1024,
      height: 1024,
      child: foregroundOnly
          ? Center(child: Transform.scale(scale: 0.62, child: mark))
          : ColoredBox(
              color: const Color(0xFF000000),
              child: Center(child: mark),
            ),
    );
  }
}

Future<void> _render(WidgetTester tester, Widget icon, String path) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(size: Size(1024, 1024)),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(key: key, child: icon),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(path).create(recursive: true);
    await File(path).writeAsBytes(png!.buffer.asUint8List());
  });
}

void main() {
  testWidgets('render icon', (tester) async {
    tester.view.physicalSize = const Size(1024, 1024);
    tester.view.devicePixelRatio = 1;
    final loader = FontLoader('BigShoulders')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            File('assets/fonts/BigShouldersDisplay.ttf').readAsBytesSync(),
          ),
        ),
      );
    await loader.load();
    await _render(tester, const KinoraIcon(), 'assets/icon/icon.png');
    await _render(
      tester,
      const KinoraIcon(foregroundOnly: true),
      'assets/icon/foreground.png',
    );
  });
}
