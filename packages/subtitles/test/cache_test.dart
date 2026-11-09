import 'dart:io';
import 'dart:typed_data';

import 'package:subtitles/subtitles.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('subs_cache_'));
  tearDown(() => dir.deleteSync(recursive: true));

  final result = SubtitleResult(
    providerId: 'subdl',
    id: '3743681-8665511',
    language: Language.of('ar'),
  );
  final download = SubtitleDownload(
    bytes: Uint8List.fromList([80, 75, 3, 4, 1, 2]),
    fileName: 'Breaking Bad S01E01.zip',
  );

  test('stores raw downloads and converted text', () async {
    final cache = SubtitleCache(Directory('${dir.path}/subs'));
    expect(await cache.getRaw(result), isNull);
    expect(await cache.sizeBytes(), 0);
    await cache.putRaw(result, download);
    expect(await cache.getRaw(result), download);
    final srt = await cache.putText(
      result,
      'srt',
      '1\r\n00:00:01,000 --> 00:00:02,000\r\nمرحبا\r\n',
    );
    expect(cache.getText(result, 'srt')!.path, srt.path);
    expect(cache.getText(result, 'vtt'), isNull);
    expect(await cache.sizeBytes(), greaterThan(download.bytes.length));
    expect(SubtitleCache.keyFor(result), matches(RegExp(r'^[0-9a-f]{16}$')));
    expect(
      SubtitleCache.keyFor(result),
      isNot(
        SubtitleCache.keyFor(
          SubtitleResult(
            providerId: 'subdl',
            id: 'other',
            language: Language.of('ar'),
          ),
        ),
      ),
    );
  });

  test('clear and prune by age', () async {
    var now = DateTime.now();
    final cache = SubtitleCache(dir, clock: () => now);
    await cache.putRaw(result, download);
    expect(await cache.prune(maxAge: const Duration(days: 1)), 0);
    now = now.add(const Duration(days: 2));
    expect(await cache.prune(maxAge: const Duration(days: 1)), greaterThan(0));
    expect(await cache.getRaw(result), isNull);
    await cache.putRaw(result, download);
    await cache.clear();
    expect(await cache.sizeBytes(), 0);
  });

  test('corrupt metadata is a miss, not a crash', () async {
    final cache = SubtitleCache(dir);
    await cache.putRaw(result, download);
    File('${dir.path}/${SubtitleCache.keyFor(result)}.json')
        .writeAsStringSync('{oops');
    expect(await cache.getRaw(result), isNull);
  });
}
