import 'dart:convert';

/// Search target of DLNA media renderers.
const mediaRendererSt = 'urn:schemas-upnp-org:device:MediaRenderer:1';

/// A received SSDP datagram: an M-SEARCH response or a NOTIFY.
final class SsdpMessage {
  SsdpMessage._(this.isNotify, this.headers);

  /// Parses a datagram; returns null for M-SEARCH requests and garbage.
  static SsdpMessage? parse(List<int> datagram) {
    final lines = latin1.decode(datagram).split(RegExp(r'\r?\n'));
    final start = lines.first.trim().toUpperCase();
    final isNotify = start.startsWith('NOTIFY ');
    if (!isNotify && !start.startsWith('HTTP/')) return null;
    final headers = <String, String>{};
    for (final line in lines.skip(1)) {
      final colon = line.indexOf(':');
      if (colon > 0) {
        headers[line.substring(0, colon).trim().toUpperCase()] = line
            .substring(colon + 1)
            .trim();
      }
    }
    return SsdpMessage._(isNotify, headers);
  }

  /// True for NOTIFY (alive/byebye/update), false for search responses.
  final bool isNotify;

  /// Headers keyed by upper-cased name.
  final Map<String, String> headers;

  /// `ST` (search response) or `NT` (notify).
  String get target => headers[isNotify ? 'NT' : 'ST'] ?? '';

  /// True for `NTS: ssdp:byebye`.
  bool get isByeBye => isNotify && headers['NTS'] == 'ssdp:byebye';

  /// The description URL.
  Uri? get location => Uri.tryParse(headers['LOCATION'] ?? '');

  /// The `uuid:…` part of `USN`.
  String? get uuid => headers['USN']?.split('::').first.trim();

  /// True when the message advertises a media renderer (or its AVTransport).
  bool get isRenderer =>
      target.contains(':device:MediaRenderer:') ||
      target.contains(':service:AVTransport:');
}

/// Builds an M-SEARCH request for [st].
List<int> buildMSearch({
  required String host,
  required String st,
  int mx = 2,
}) => latin1.encode(
  'M-SEARCH * HTTP/1.1\r\n'
  'HOST: $host\r\n'
  'MAN: "ssdp:discover"\r\n'
  'MX: $mx\r\n'
  'ST: $st\r\n'
  'USER-AGENT: Dart/3 UPnP/1.1 Kinora/1.0\r\n'
  '\r\n',
);
