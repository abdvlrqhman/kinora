import 'dart:convert';
import 'dart:io';

import 'models.dart';
import 'provider_http.dart' show Clock;

/// On-disk cache of downloaded subtitles, keyed by provider + subtitle id.
///
/// The app owns [directory] (and can clear it from its storage screen).
/// Per subtitle: `<key>.raw` (bytes as downloaded), `<key>.json` (file name
/// and format) and any converted text (`<key>.srt`, `<key>.vtt`, ...).
final class SubtitleCache {
  SubtitleCache(this.directory, {Clock? clock})
    : _clock = clock ?? DateTime.now;

  final Directory directory;
  final Clock _clock;

  /// File-name-safe key for [result] (FNV-1a 64 of `providerId:id`).
  static String keyFor(SubtitleResult result) => _fnv1a64(result.key);

  File _file(SubtitleResult r, String ext) =>
      File('${directory.path}${Platform.pathSeparator}${keyFor(r)}.$ext');

  /// Stores the raw download for [result].
  Future<void> putRaw(SubtitleResult result, SubtitleDownload download) async {
    await directory.create(recursive: true);
    await _file(result, 'raw').writeAsBytes(download.bytes, flush: true);
    await _file(result, 'json').writeAsString(
      jsonEncode({
        'fileName': download.fileName,
        'format': download.format?.name,
      }),
      flush: true,
    );
  }

  /// The cached raw download for [result], or null.
  Future<SubtitleDownload?> getRaw(SubtitleResult result) async {
    final raw = _file(result, 'raw');
    final meta = _file(result, 'json');
    if (!raw.existsSync() || !meta.existsSync()) return null;
    try {
      final m = jsonDecode(await meta.readAsString()) as Map<String, Object?>;
      final format = m['format'];
      return SubtitleDownload(
        bytes: await raw.readAsBytes(),
        fileName: m['fileName']! as String,
        format: SubtitleFormat.values
            .where((f) => f.name == format)
            .firstOrNull,
      );
    } on Object {
      return null; // corrupt entry: treat as a miss
    }
  }

  /// Stores converted text (e.g. `ext: 'srt'`) and returns its file, which
  /// the stream server can serve directly.
  Future<File> putText(SubtitleResult result, String ext, String text) async {
    await directory.create(recursive: true);
    final f = _file(result, ext);
    await f.writeAsString(text, flush: true);
    return f;
  }

  /// The converted file for [result] and [ext], or null.
  File? getText(SubtitleResult result, String ext) {
    final f = _file(result, ext);
    return f.existsSync() ? f : null;
  }

  /// Total bytes used.
  Future<int> sizeBytes() async {
    if (!directory.existsSync()) return 0;
    var total = 0;
    await for (final e in directory.list(followLinks: false)) {
      if (e is File) total += await e.length();
    }
    return total;
  }

  /// Deletes everything in the cache.
  Future<void> clear() async {
    if (!directory.existsSync()) return;
    await for (final e in directory.list(followLinks: false)) {
      await e.delete(recursive: true);
    }
  }

  /// Deletes files not written for [maxAge]; returns bytes freed.
  Future<int> prune({required Duration maxAge}) async {
    if (!directory.existsSync()) return 0;
    final cutoff = _clock().subtract(maxAge);
    var freed = 0;
    await for (final e in directory.list(followLinks: false)) {
      if (e is! File) continue;
      final stat = e.statSync();
      if (stat.modified.isBefore(cutoff)) {
        freed += stat.size;
        await e.delete();
      }
    }
    return freed;
  }
}

String _fnv1a64(String s) {
  // Native ints wrap at 64 bits on the VM, which is exactly FNV's modulus.
  var h = 0xcbf29ce484222325;
  for (final b in utf8.encode(s)) {
    h = (h ^ b) * 0x100000001b3;
  }
  return '${(h >>> 32).toRadixString(16).padLeft(8, '0')}'
      '${(h & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0')}';
}
