import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kinora/core/paths.dart';
import 'package:kinora/services/engine_service.dart';

void main() {
  late Directory root;
  late AppPaths paths;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('kinora-cache-');
    paths = AppPaths(
      support: Directory('${root.path}/support'),
      downloadsRoot: Directory('${root.path}/docs'),
      cache: Directory('${root.path}/cache'),
    );
    await paths.ensure();
  });
  tearDown(() => root.delete(recursive: true));

  File touch(String path, {DateTime? at}) {
    final f = File(path)..createSync(recursive: true);
    if (at != null) f.setLastModifiedSync(at);
    return f;
  }

  test(
    'keep 0 hours: every stream leftover goes, download resume data stays',
    () async {
      final stream = touch('${paths.streams.path}/Show.S01E01/ep.mkv');
      final orphan = touch('${paths.resume.path}/${'a' * 40}.fastresume');
      final owned = touch('${paths.resume.path}/${'b' * 40}.fastresume');
      await EngineService.cleanStreamCache(
        paths,
        keepHours: 0,
        downloadHashes: {'b' * 40},
      );
      expect(stream.existsSync(), isFalse);
      expect(orphan.existsSync(), isFalse);
      expect(owned.existsSync(), isTrue);
    },
  );

  test('keep 24 hours: only older leftovers go', () async {
    final old = touch(
      '${paths.streams.path}/old.mkv',
      at: DateTime.now().subtract(const Duration(hours: 30)),
    );
    final recent = touch(
      '${paths.streams.path}/recent.mkv',
      at: DateTime.now().subtract(const Duration(hours: 2)),
    );
    await EngineService.cleanStreamCache(
      paths,
      keepHours: 24,
      downloadHashes: const {},
    );
    expect(old.existsSync(), isFalse);
    expect(recent.existsSync(), isTrue);
  });
}
