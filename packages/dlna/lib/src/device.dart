import 'package:xml/xml.dart';

import 'errors.dart';
import 'xml_util.dart';

/// A DLNA media renderer, parsed from its UPnP device description.
///
/// Immutable; [toJson]/[DlnaDevice.fromJson] let the app remember last-seen
/// TVs and reconnect by re-fetching [location] (see `DlnaDiscovery.refresh`).
final class DlnaDevice {
  /// Creates a device; normally obtained from discovery or
  /// [DlnaDevice.fromDescription].
  DlnaDevice({
    required this.udn,
    required this.friendlyName,
    required this.location,
    required this.avTransportControlUrl,
    this.manufacturer,
    this.modelName,
    this.modelNumber,
    this.iconUrl,
    this.renderingControlUrl,
    this.connectionManagerUrl,
    Map<String, Uri> eventSubUrls = const {},
  }) : eventSubUrls = Map.unmodifiable(eventSubUrls);

  /// Parses a device description document fetched from [location].
  ///
  /// Picks the MediaRenderer device (root or embedded; otherwise the first
  /// device offering AVTransport) and resolves relative URLs against
  /// `URLBase` when present, else against [location].
  ///
  /// Throws [DlnaProtocolException] for malformed XML or non-renderers.
  factory DlnaDevice.fromDescription(String xml, Uri location) {
    final XmlElement root;
    try {
      root = XmlDocument.parse(xml).rootElement;
    } on XmlException catch (e) {
      throw DlnaProtocolException(
        'Malformed device description: ${e.message}',
        uri: location,
      );
    }
    final urlBase = root.childText('URLBase');
    final base = (urlBase == null ? null : Uri.tryParse(urlBase)) ?? location;
    Uri? resolve(String? ref) {
      final parsed = ref == null ? null : Uri.tryParse(ref);
      return parsed == null ? null : base.resolveUri(parsed);
    }

    final devices = root.descendantsNamed('device').toList();
    final device =
        devices.where(_isMediaRenderer).firstOrNull ??
        devices.where((d) => _service(d, _avTransport) != null).firstOrNull;
    final avTransport = device == null ? null : _service(device, _avTransport);
    final avControl = resolve(avTransport?.childText('controlURL'));
    final udn = device?.childText('UDN');
    if (device == null || avControl == null || udn == null) {
      throw DlnaProtocolException('Not a DLNA media renderer', uri: location);
    }
    final events = <String, Uri>{};
    for (final service in _services(device)) {
      final type = service.childText('serviceType');
      final url = resolve(service.childText('eventSubURL'));
      if (type != null && url != null) events[type] = url;
    }
    final icon = _bestIcon(device) ?? _bestIcon(root.childNamed('device'));
    return DlnaDevice(
      udn: udn,
      friendlyName:
          device.childText('friendlyName') ??
          device.childText('modelName') ??
          location.host,
      location: location,
      avTransportControlUrl: avControl,
      manufacturer: device.childText('manufacturer'),
      modelName: device.childText('modelName'),
      modelNumber: device.childText('modelNumber'),
      iconUrl: resolve(icon?.childText('url')),
      renderingControlUrl: resolve(
        _service(device, ':service:RenderingControl:')?.childText('controlURL'),
      ),
      connectionManagerUrl: resolve(
        _service(
          device,
          ':service:ConnectionManager:',
        )?.childText('controlURL'),
      ),
      eventSubUrls: events,
    );
  }

  /// Restores a device saved with [toJson].
  ///
  /// Throws [FormatException] when [json] is not a saved device.
  factory DlnaDevice.fromJson(Map<String, Object?> json) {
    String? str(String key) => switch (json[key]) {
      final String s => s,
      null => null,
      final other => throw FormatException('"$key" is not a string', other),
    };
    String req(String key) =>
        str(key) ?? (throw FormatException('Missing "$key"', json));
    Uri? uri(String key) {
      final s = str(key);
      return s == null ? null : Uri.parse(s);
    }

    final events = json['eventSubUrls'] ?? const <String, Object?>{};
    if (events is! Map) {
      throw FormatException('"eventSubUrls" is not a map', events);
    }
    return DlnaDevice(
      udn: req('udn'),
      friendlyName: req('friendlyName'),
      location: Uri.parse(req('location')),
      avTransportControlUrl: Uri.parse(req('avTransportControlUrl')),
      manufacturer: str('manufacturer'),
      modelName: str('modelName'),
      modelNumber: str('modelNumber'),
      iconUrl: uri('iconUrl'),
      renderingControlUrl: uri('renderingControlUrl'),
      connectionManagerUrl: uri('connectionManagerUrl'),
      eventSubUrls: {
        for (final MapEntry(:key, :value) in events.entries)
          if (key is String && value is String) key: Uri.parse(value),
      },
    );
  }

  /// Unique device name, e.g. `uuid:2fcbf741-…`. Stable across reboots and
  /// IP changes; use it as the key for remembered devices.
  final String udn;

  /// User-visible name, e.g. `[TV] Samsung 5 Series (43)`.
  final String friendlyName;

  /// URL of the device description (the SSDP `LOCATION`).
  final Uri location;

  /// `manufacturer`, e.g. `Samsung Electronics`.
  final String? manufacturer;

  /// `modelName`, e.g. `UE43T5300`.
  final String? modelName;

  /// `modelNumber` (Samsung reports `AllShare1.0`).
  final String? modelNumber;

  /// Best icon (PNG preferred, then largest), if the device lists any.
  final Uri? iconUrl;

  /// AVTransport control URL (always present on a renderer).
  final Uri avTransportControlUrl;

  /// RenderingControl control URL (volume/mute), if offered.
  final Uri? renderingControlUrl;

  /// ConnectionManager control URL (GetProtocolInfo), if offered.
  final Uri? connectionManagerUrl;

  /// GENA event subscription URLs keyed by service type.
  final Map<String, Uri> eventSubUrls;

  /// True for Samsung TVs (enables the Samsung subtitle extensions).
  bool get isSamsung =>
      (manufacturer ?? '').toLowerCase().contains('samsung') ||
      friendlyName.toLowerCase().contains('samsung');

  /// JSON-encodable form; see [DlnaDevice.fromJson].
  Map<String, Object?> toJson() => {
    'udn': udn,
    'friendlyName': friendlyName,
    'location': '$location',
    'manufacturer': manufacturer,
    'modelName': modelName,
    'modelNumber': modelNumber,
    'iconUrl': iconUrl?.toString(),
    'avTransportControlUrl': '$avTransportControlUrl',
    'renderingControlUrl': renderingControlUrl?.toString(),
    'connectionManagerUrl': connectionManagerUrl?.toString(),
    'eventSubUrls': {for (final e in eventSubUrls.entries) e.key: '${e.value}'},
  };

  @override
  bool operator ==(Object other) =>
      other is DlnaDevice &&
      other.udn == udn &&
      other.friendlyName == friendlyName &&
      other.location == location &&
      other.manufacturer == manufacturer &&
      other.modelName == modelName &&
      other.modelNumber == modelNumber &&
      other.iconUrl == iconUrl &&
      other.avTransportControlUrl == avTransportControlUrl &&
      other.renderingControlUrl == renderingControlUrl &&
      other.connectionManagerUrl == connectionManagerUrl &&
      other.eventSubUrls.length == eventSubUrls.length &&
      eventSubUrls.entries.every((e) => other.eventSubUrls[e.key] == e.value);

  @override
  int get hashCode => Object.hash(
    udn,
    friendlyName,
    location,
    manufacturer,
    modelName,
    modelNumber,
    iconUrl,
    avTransportControlUrl,
    renderingControlUrl,
    connectionManagerUrl,
    Object.hashAllUnordered(
      eventSubUrls.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );

  @override
  String toString() =>
      'DlnaDevice($friendlyName, $udn, ${modelName ?? '?'}, $location)';
}

const _avTransport = ':service:AVTransport:';

bool _isMediaRenderer(XmlElement device) =>
    (device.childText('deviceType') ?? '').contains(':device:MediaRenderer:');

Iterable<XmlElement> _services(XmlElement device) =>
    device.childNamed('serviceList')?.childrenNamed('service') ?? const [];

XmlElement? _service(XmlElement device, String typeFragment) =>
    _services(device)
        .where((s) => (s.childText('serviceType') ?? '').contains(typeFragment))
        .firstOrNull;

XmlElement? _bestIcon(XmlElement? device) {
  final icons =
      device?.childNamed('iconList')?.childrenNamed('icon').toList() ?? [];
  if (icons.isEmpty) return null;
  int score(XmlElement icon) =>
      (icon.childText('mimetype') == 'image/png' ? 100000 : 0) +
      (int.tryParse(icon.childText('width') ?? '') ?? 0);
  return icons.reduce((a, b) => score(b) > score(a) ? b : a);
}
