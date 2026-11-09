import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kinora/core/paths.dart';

void main() {
  const old = '0B5D6C1A-2F3E-4A5B-9C8D-7E6F5A4B3C2D';
  const now = 'A1B2C3D4-E5F6-4789-ABCD-EF0123456789';
  AppPaths at(String root) => AppPaths(
    support: Directory('$root/Library/Application Support'),
    downloadsRoot: Directory('$root/Documents'),
    cache: Directory('$root/Library/Caches'),
  );

  test('a path saved before an iOS update moves into today’s app folder', () {
    final paths = at('/var/mobile/Containers/Data/Application/$now');
    expect(
      paths.rebased(
        '/var/mobile/Containers/Data/Application/$old/Documents/Kinora/Lupin/S04E06.mkv',
      ),
      '/var/mobile/Containers/Data/Application/$now/Documents/Kinora/Lupin/S04E06.mkv',
    );
    expect(
      paths.rebased(
        '/var/mobile/Containers/Data/Application/$now/Documents/x.mkv',
      ),
      isNull,
      reason: 'already today’s folder',
    );
  });

  test('Android paths never move', () {
    final paths = at('/storage/emulated/0/Android/data/io.kinora/files');
    expect(
      paths.rebased('/storage/emulated/0/Android/data/x/files/a.mkv'),
      isNull,
    );
  });

  test('a moved app folder is noticed once', () {
    final support = Directory.systemTemp.createTempSync('kinora-root');
    addTearDown(() => support.deleteSync(recursive: true));
    expect(
      AppPaths.noteRoot(support, '/A/Documents'),
      isTrue,
      reason: 'unknown',
    );
    expect(AppPaths.noteRoot(support, '/A/Documents'), isFalse);
    expect(AppPaths.noteRoot(support, '/B/Documents'), isTrue);
    expect(AppPaths.noteRoot(support, '/B/Documents'), isFalse);
  });
}
