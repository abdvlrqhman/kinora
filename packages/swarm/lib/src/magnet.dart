import 'errors.dart';
import 'info_hash.dart';

final _btmh = RegExp(r'^1220[0-9a-f]{64}$');

/// A BitTorrent magnet link (BEP 9, plus the v2 `urn:btmh:` form).
final class Magnet {
  /// Builds a magnet. [infoHash] (v1, hex or base32) or [infoHashV2]
  /// (`1220…` multihash) is required; empty and duplicate trackers are
  /// dropped. Throws [MagnetFormatException] for malformed hashes.
  factory Magnet({
    String? infoHash,
    String? infoHashV2,
    String? name,
    Iterable<String> trackers = const [],
    int? exactLength,
    Iterable<String> webSeeds = const [],
    Iterable<String> peers = const [],
  }) {
    final v1 = infoHash == null
        ? null
        : normalizeInfoHash(infoHash) ??
              (throw MagnetFormatException('invalid btih hash', infoHash));
    final v2 = infoHashV2?.trim().toLowerCase();
    if (v2 != null && !_btmh.hasMatch(v2)) {
      throw MagnetFormatException('invalid btmh hash', infoHashV2!);
    }
    if (v1 == null && v2 == null) {
      throw const MagnetFormatException('no info hash', '');
    }
    List<String> clean(Iterable<String> values) => List.unmodifiable({
      for (final v in values)
        if (v.trim().isNotEmpty) v.trim(),
    });
    return Magnet._(
      v1,
      v2,
      name == null || name.trim().isEmpty ? null : name,
      clean(trackers),
      exactLength != null && exactLength >= 0 ? exactLength : null,
      clean(webSeeds),
      clean(peers),
    );
  }

  const Magnet._(
    this.infoHash,
    this.infoHashV2,
    this.name,
    this.trackers,
    this.exactLength,
    this.webSeeds,
    this.peers,
  );

  /// Parses `magnet:?xt=urn:btih:…&dn=…&tr=…`.
  ///
  /// Hex and base32 `btih` hashes become lowercase hex. Repeated and indexed
  /// keys (`tr.1`) are supported; unknown keys and non-BitTorrent `xt` values
  /// are ignored. Throws [MagnetFormatException].
  factory Magnet.parse(String input) {
    final text = input.trim();
    if (!text.toLowerCase().startsWith('magnet:?')) {
      throw MagnetFormatException('not a magnet link', input);
    }
    String? v1;
    String? v2;
    String? name;
    int? length;
    final trackers = <String>[];
    final webSeeds = <String>[];
    final peers = <String>[];
    for (final pair in text.substring('magnet:?'.length).split('&')) {
      final eq = pair.indexOf('=');
      if (eq <= 0) continue;
      final key = pair
          .substring(0, eq)
          .toLowerCase()
          .replaceFirst(RegExp(r'\.\d+$'), '');
      final value = _decode(pair.substring(eq + 1));
      final lower = value.toLowerCase();
      switch (key) {
        case 'xt' when lower.startsWith('urn:btih:'):
          v1 ??=
              normalizeInfoHash(value.substring(9)) ??
              (throw MagnetFormatException('invalid btih hash', input));
        case 'xt' when lower.startsWith('urn:btmh:'):
          v2 ??= value.substring(9);
        case 'dn':
          name ??= value;
        case 'xl':
          length ??= int.tryParse(value);
        case 'tr':
          trackers.add(value);
        case 'ws':
          webSeeds.add(value);
        case 'x.pe':
          peers.add(value);
      }
    }
    if (v1 == null && v2 == null) {
      throw MagnetFormatException('no urn:btih or urn:btmh', input);
    }
    try {
      return Magnet(
        infoHash: v1,
        infoHashV2: v2,
        name: name,
        trackers: trackers,
        exactLength: length,
        webSeeds: webSeeds,
        peers: peers,
      );
    } on MagnetFormatException catch (e) {
      throw MagnetFormatException(e.message, input);
    }
  }

  /// [Magnet.parse] that returns null instead of throwing.
  static Magnet? tryParse(String input) {
    try {
      return Magnet.parse(input);
    } on MagnetFormatException {
      return null;
    }
  }

  /// v1 info hash, 40 lowercase hex characters.
  final String? infoHash;

  /// v2 info hash as a lowercase hex multihash (`1220` + 64 hex).
  final String? infoHashV2;

  /// Display name (`dn`).
  final String? name;

  /// Tracker URLs (`tr`), de-duplicated, in order.
  final List<String> trackers;

  /// Total size in bytes (`xl`).
  final int? exactLength;

  /// Web seed URLs (`ws`).
  final List<String> webSeeds;

  /// Peer addresses (`x.pe`, `host:port`).
  final List<String> peers;

  /// The magnet as a [Uri].
  Uri toUri() => Uri.parse(toString());

  /// The magnet link text.
  @override
  String toString() {
    String enc(String s) => Uri.encodeComponent(s);
    return 'magnet:?${[if (infoHash != null) 'xt=urn:btih:$infoHash', if (infoHashV2 != null) 'xt=urn:btmh:$infoHashV2', if (name != null) 'dn=${enc(name!)}', if (exactLength != null) 'xl=$exactLength', for (final t in trackers) 'tr=${enc(t)}', for (final w in webSeeds) 'ws=${enc(w)}', for (final p in peers) 'x.pe=${enc(p)}'].join('&')}';
  }

  @override
  bool operator ==(Object other) =>
      other is Magnet && other.toString() == toString();

  @override
  int get hashCode => toString().hashCode;
}

String _decode(String value) {
  try {
    return Uri.decodeQueryComponent(value);
  } on ArgumentError {
    // Stray '%' in the wild: keep the raw text rather than reject the link.
    return value;
  }
}
