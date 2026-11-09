/// One UPnP protocolInfo entry: `protocol:network:contentFormat:additionalInfo`,
/// e.g. `http-get:*:video/mp4:DLNA.ORG_PN=AVC_MP4_HP_HD_AAC`.
final class ProtocolInfo {
  /// Creates an entry from its four fields.
  const ProtocolInfo({
    required this.protocol,
    required this.network,
    required this.contentFormat,
    required this.additionalInfo,
  });

  /// Parses one entry. Throws [FormatException] if it has fewer than four
  /// fields.
  factory ProtocolInfo.parse(String text) {
    final parts = text.trim().split(':');
    if (parts.length < 4) {
      throw FormatException('Not a protocolInfo', text);
    }
    return ProtocolInfo(
      protocol: parts[0],
      network: parts[1],
      contentFormat: parts[2],
      additionalInfo: parts.sublist(3).join(':'),
    );
  }

  /// Parses a comma-separated list (the `Sink`/`Source` of
  /// ConnectionManager `GetProtocolInfo`), skipping malformed entries.
  static List<ProtocolInfo> parseList(String csv) => [
    for (final entry in csv.split(','))
      if (entry.trim().split(':').length >= 4) ProtocolInfo.parse(entry),
  ];

  /// Transport protocol, e.g. `http-get`.
  final String protocol;

  /// Network, usually `*`.
  final String network;

  /// MIME type (or `*`), as sent by the device.
  final String contentFormat;

  /// DLNA parameters (`DLNA.ORG_PN=…;DLNA.ORG_OP=…`) or `*`.
  final String additionalInfo;

  /// Lower-cased [contentFormat].
  String get mimeType => contentFormat.toLowerCase();

  /// The DLNA media format profile (`DLNA.ORG_PN`), if present.
  String? get dlnaProfile {
    for (final param in additionalInfo.split(';')) {
      final kv = param.split('=');
      if (kv.length == 2 && kv[0].trim().toUpperCase() == 'DLNA.ORG_PN') {
        return kv[1].trim();
      }
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is ProtocolInfo &&
      other.protocol == protocol &&
      other.network == network &&
      other.contentFormat == contentFormat &&
      other.additionalInfo == additionalInfo;

  @override
  int get hashCode =>
      Object.hash(protocol, network, contentFormat, additionalInfo);

  @override
  String toString() => '$protocol:$network:$contentFormat:$additionalInfo';
}
