import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kinora/app/providers.dart';

void main() {
  // The update check compares this with GitHub's latest release: a stale
  // one offers the installed version as an update, forever.
  test('the version the app reports is the one it is built as', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final built = RegExp(
      r'^version:\s*([0-9.]+)',
      multiLine: true,
    ).firstMatch(pubspec)![1];
    expect(kinoraVersion, built);
  });
}
