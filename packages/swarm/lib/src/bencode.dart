import 'dart:convert';
import 'dart:typed_data';

/// Decodes one bencoded value.
///
/// Integers become [int], byte strings [Uint8List], lists `List<Object>`,
/// dictionaries `Map<String, Object>` with keys decoded as Latin-1 so raw
/// 20-byte info hash keys survive (`latin1.encode(key)` gives the bytes back).
/// Throws [FormatException] on malformed input or trailing data.
Object bdecode(Uint8List data) {
  final reader = _Reader(data);
  final value = reader.value(0);
  if (reader.pos != data.length) {
    throw FormatException('trailing data', data, reader.pos);
  }
  return value;
}

final class _Reader {
  _Reader(this.data);

  final Uint8List data;
  int pos = 0;

  static const _maxDepth = 64;

  int _byte() {
    if (pos >= data.length) throw FormatException('truncated', data, pos);
    return data[pos];
  }

  Object value(int depth) {
    if (depth > _maxDepth) throw FormatException('too deep', data, pos);
    final c = _byte();
    if (c == 0x69) {
      pos++;
      return _int(0x65);
    }
    if (c == 0x6c) {
      pos++;
      final list = <Object>[];
      while (_byte() != 0x65) {
        list.add(value(depth + 1));
      }
      pos++;
      return list;
    }
    if (c == 0x64) {
      pos++;
      final map = <String, Object>{};
      while (_byte() != 0x65) {
        final key = latin1.decode(_bytes());
        map[key] = value(depth + 1);
      }
      pos++;
      return map;
    }
    return _bytes();
  }

  Uint8List _bytes() {
    final length = _int(0x3a);
    if (length < 0 || pos + length > data.length) {
      throw FormatException('bad string length', data, pos);
    }
    final bytes = Uint8List.sublistView(data, pos, pos + length);
    pos += length;
    return bytes;
  }

  int _int(int terminator) {
    final start = pos;
    while (_byte() != terminator) {
      pos++;
    }
    final text = ascii.decode(data.sublist(start, pos), allowInvalid: true);
    pos++;
    return int.tryParse(text) ??
        (throw FormatException('bad integer "$text"', data, start));
  }
}
