import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Family that supplies glyphs Figtree lacks (Arabic native names) in
/// tests; phones fall back to system fonts on their own.
const testFallbackFamily = 'KinoraTestFallback';

bool _loaded = false;

/// Loads Figtree, Big Shoulders Display, Material Icons and a fallback for
/// other scripts so widget tests and goldens measure and draw real text.
/// Run from the app folder (as `flutter test` does).
Future<void> loadKinoraFonts() async {
  if (_loaded) return;
  _loaded = true;
  TestWidgetsFlutterBinding.ensureInitialized();
  final flutterRoot =
      Platform.environment['FLUTTER_ROOT'] ??
      // .../bin/cache/artifacts/engine/<platform>/flutter_tester
      p.normalize(
        p.join(p.dirname(Platform.resolvedExecutable), '../../../../..'),
      );
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    var any = false;
    for (final f in files) {
      final file = File(f);
      if (!file.existsSync()) continue;
      any = true;
      loader.addFont(
        Future.value(ByteData.sublistView(file.readAsBytesSync())),
      );
    }
    if (any) await loader.load();
  }

  await load('ReadexPro', ['assets/fonts/ReadexPro.ttf']);
  await load('Unbounded', ['assets/fonts/Unbounded.ttf']);
  await load('GeistMono', ['assets/fonts/GeistMono.ttf']);
  await load('MaterialIcons', [
    p.join(
      flutterRoot,
      'bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ),
  ]);
  await load(testFallbackFamily, [
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    '/usr/share/fonts/truetype/noto/NotoSansArabic-Regular.ttf',
  ]);
}

/// [theme] with the test fallback font behind every text style.
ThemeData withTestFallback(ThemeData theme) => theme.copyWith(
  textTheme: theme.textTheme.apply(
    fontFamilyFallback: const [testFallbackFamily],
  ),
);
