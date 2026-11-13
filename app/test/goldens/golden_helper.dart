import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads every font in the app's FontManifest (BigShoulders, Figtree and
/// MaterialIcons) under its pubspec family name, so goldens show real type.
Future<void> loadAppFonts() async {
  final manifest = jsonDecode(
    await rootBundle.loadString('FontManifest.json'),
  ) as List<Object?>;
  for (final entry in manifest.cast<Map<String, Object?>>()) {
    final loader = FontLoader(entry['family']! as String);
    for (final font
        in (entry['fonts']! as List<Object?>).cast<Map<String, Object?>>()) {
      loader.addFont(rootBundle.load(font['asset']! as String));
    }
    await loader.load();
  }
}

/// `file:` URI of a generated test image in `test/goldens/assets/`.
String art(String name) =>
    Uri.file(File('test/goldens/assets/$name.png').absolute.path).toString();

/// iPhone-sized safe areas (status bar, home indicator) at 3x.
void phoneInsets(WidgetTester tester) =>
    tester.view.padding = const FakeViewPadding(top: 141, bottom: 102);

/// Lets every image on screen load and decode for real, then settles.
/// Loads start inside the test's fake-async zone, so their callbacks only
/// run on a pump: alternate short real waits with pumps until all decode.
Future<void> settleImages(WidgetTester tester) async {
  await tester.pumpAndSettle();
  for (var i = 0; i < 200; i++) {
    final loading = find
        .byType(RawImage)
        .evaluate()
        .where((e) => (e.widget as RawImage).image == null);
    if (loading.isEmpty) break;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}
