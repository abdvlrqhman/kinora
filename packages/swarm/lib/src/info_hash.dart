import 'dart:typed_data';

final _hex40 = RegExp(r'^[0-9a-fA-F]{40}$');
final _base32 = RegExp(r'^[A-Za-z2-7]{32}$');

/// Normalizes a BitTorrent v1 info hash to 40 lowercase hex characters.
///
/// Accepts 40 hex characters (any case) or 32 base32 characters; returns
/// null for anything else.
String? normalizeInfoHash(String hash) {
  final h = hash.trim();
  if (_hex40.hasMatch(h)) return h.toLowerCase();
  if (!_base32.hasMatch(h)) return null;
  // RFC 4648 base32: 32 chars x 5 bits = 160 bits = 20 bytes.
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  final out = StringBuffer();
  var buffer = 0;
  var bits = 0;
  for (final c in h.toUpperCase().codeUnits) {
    buffer = (buffer << 5) | alphabet.indexOf(String.fromCharCode(c));
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      out.write(((buffer >> bits) & 0xff).toRadixString(16).padLeft(2, '0'));
    }
  }
  return out.toString();
}

/// 20 raw bytes of a normalized hex info hash.
Uint8List infoHashBytes(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);

/// Lowercase hex of [bytes].
String toHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
