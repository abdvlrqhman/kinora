import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:kinora_engine/kinora_engine.dart';

/// A single-file `.torrent` built in memory for tests.
final class TestTorrent {
  TestTorrent._(this.bytes, this.infoHash);

  /// Builds a v1 torrent for [data] named [name].
  factory TestTorrent.single(
    String name,
    Uint8List data, {
    int pieceLength = 65536,
  }) {
    final pieces = BytesBuilder(copy: false);
    for (var off = 0; off < data.length; off += pieceLength) {
      final end = off + pieceLength < data.length
          ? off + pieceLength
          : data.length;
      pieces.add(sha1.convert(Uint8List.sublistView(data, off, end)).bytes);
    }
    final info = <String, Object?>{
      'name': name,
      'piece length': pieceLength,
      'pieces': pieces.takeBytes(),
      'length': data.length,
    };
    final infoBytes = bencode(info);
    final torrent = bencode(<String, Object?>{
      'info': info,
      'created by': 'kinora-test',
    });
    return TestTorrent._(torrent, sha1.convert(infoBytes).toString());
  }

  /// The `.torrent` file.
  final Uint8List bytes;

  /// Lowercase hex v1 info-hash.
  final String infoHash;

  /// A magnet link without trackers.
  String magnet(String name) =>
      'magnet:?xt=urn:btih:$infoHash&dn=${Uri.encodeComponent(name)}';
}
