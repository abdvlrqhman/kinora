import 'dart:typed_data';

/// Bytes of the head and tail chunks [osHash] needs.
const osHashChunkSize = 65536;

/// OpenSubtitles movie hash: file size plus the 64-bit little-endian words
/// of the first and last 64 KiB, summed with 64-bit wrap-around, as 16
/// lowercase hex digits.
///
/// [head64k] and [tail64k] must be the first and last [osHashChunkSize]
/// bytes (they overlap for files under 128 KiB; shorter chunks are
/// zero-padded). Needs 64-bit ints (Dart VM / AOT, not web).
String osHash(int fileSize, Uint8List head64k, Uint8List tail64k) {
  var hash = fileSize;
  for (final chunk in [head64k, tail64k]) {
    final padded = Uint8List(osHashChunkSize)
      ..setRange(0, chunk.length.clamp(0, osHashChunkSize), chunk);
    final words = ByteData.sublistView(padded);
    for (var i = 0; i < osHashChunkSize; i += 8) {
      hash += words.getUint64(i, Endian.little);
    }
  }
  final hi = (hash >>> 32).toRadixString(16).padLeft(8, '0');
  final lo = (hash & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
  return '$hi$lo';
}
