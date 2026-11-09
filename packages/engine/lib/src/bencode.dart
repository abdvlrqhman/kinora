import 'dart:convert';
import 'dart:typed_data';

/// Bencodes [value] (BEP 3).
///
/// Supports `int`, `bool` (as 0/1), `String` (UTF-8), `Uint8List` (raw
/// bytes), `List` and `Map<String, Object?>`. Dictionary keys are sorted by
/// their raw bytes as the spec requires; `null` map values are skipped.
Uint8List bencode(Object value) {
  final out = BytesBuilder(copy: false);
  _write(out, value);
  return out.takeBytes();
}

void _write(BytesBuilder out, Object value) {
  switch (value) {
    case bool():
      _write(out, value ? 1 : 0);
    case int():
      out.add(ascii.encode('i${value}e'));
    case String():
      _writeBytes(out, utf8.encode(value));
    case Uint8List():
      _writeBytes(out, value);
    case List<Object?>():
      out.addByte(0x6c); // l
      for (final item in value) {
        if (item != null) _write(out, item);
      }
      out.addByte(0x65); // e
    case Map<String, Object?>():
      final entries = [
        for (final e in value.entries)
          if (e.value != null) (key: utf8.encode(e.key), value: e.value!),
      ]..sort((a, b) => _compareBytes(a.key, b.key));
      out.addByte(0x64); // d
      for (final e in entries) {
        _writeBytes(out, e.key);
        _write(out, e.value);
      }
      out.addByte(0x65);
    default:
      throw ArgumentError.value(value, 'value', 'cannot be bencoded');
  }
}

void _writeBytes(BytesBuilder out, List<int> bytes) {
  out
    ..add(ascii.encode('${bytes.length}:'))
    ..add(bytes);
}

int _compareBytes(List<int> a, List<int> b) {
  final n = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < n; i++) {
    final d = a[i] - b[i];
    if (d != 0) return d;
  }
  return a.length - b.length;
}
