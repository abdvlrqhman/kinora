import 'dart:convert';

import 'package:dlna/dlna.dart';
import 'package:test/test.dart';

import 'support/fake_samsung_dmr.dart';

void main() {
  final location = Uri.parse('http://192.168.1.50:9197/dmr');

  test('parses a Samsung Tizen description', () {
    final d = DlnaDevice.fromDescription(samsungDescription, location);
    expect(d.udn, samsungUdn);
    expect(d.friendlyName, '[TV] Samsung 5 Series (43)');
    expect(d.manufacturer, 'Samsung Electronics');
    expect(d.modelName, 'UE43T5300');
    expect(d.modelNumber, 'AllShare1.0');
    expect(d.isSamsung, isTrue);
    expect(d.location, location);
    expect(d.iconUrl, Uri.parse('http://192.168.1.50:9197/dmr/icon_LRG.png'));
    expect(
      d.avTransportControlUrl,
      Uri.parse('http://192.168.1.50:9197/upnp/control/AVTransport1'),
    );
    expect(
      d.renderingControlUrl,
      Uri.parse('http://192.168.1.50:9197/upnp/control/RenderingControl1'),
    );
    expect(
      d.connectionManagerUrl,
      Uri.parse('http://192.168.1.50:9197/upnp/control/ConnectionManager1'),
    );
    expect(d.eventSubUrls, {
      'urn:schemas-upnp-org:service:RenderingControl:1': Uri.parse(
        'http://192.168.1.50:9197/upnp/event/RenderingControl1',
      ),
      'urn:schemas-upnp-org:service:ConnectionManager:1': Uri.parse(
        'http://192.168.1.50:9197/upnp/event/ConnectionManager1',
      ),
      'urn:schemas-upnp-org:service:AVTransport:1': Uri.parse(
        'http://192.168.1.50:9197/upnp/event/AVTransport1',
      ),
    });
  });

  test('embedded renderer, URLBase and path-relative URLs', () {
    // Shaped like a 2011 Samsung AllShare description: relative SCPD/control
    // URLs without a leading slash, here inside an embedded device.
    const xml = '''<?xml version="1.0"?>
<root xmlns="urn:schemas-upnp-org:device-1-0">
  <URLBase>http://10.0.0.7:52235/dmr/</URLBase>
  <device>
    <deviceType>urn:schemas-upnp-org:device:Basic:1</deviceType>
    <friendlyName>Root</friendlyName>
    <UDN>uuid:root</UDN>
    <iconList><icon><mimetype>image/jpeg</mimetype><width>48</width><url>icon_SML.jpg</url></icon></iconList>
    <deviceList>
      <device>
        <deviceType>urn:schemas-upnp-org:device:MediaRenderer:2</deviceType>
        <friendlyName>[TV]UE55D8000</friendlyName>
        <manufacturer>Samsung Electronics</manufacturer>
        <modelName>UE55D8000</modelName>
        <UDN>uuid:e56fe598-c88b-5646-d1e2-75e44f14395b</UDN>
        <serviceList>
          <service>
            <serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
            <controlURL>upnp/control/AVTransport1</controlURL>
            <eventSubURL>upnp/event/AVTransport1</eventSubURL>
          </service>
        </serviceList>
      </device>
    </deviceList>
  </device>
</root>''';
    final d = DlnaDevice.fromDescription(
      xml,
      Uri.parse('http://10.0.0.7:52235/dmr/SamsungMRDesc.xml'),
    );
    expect(d.udn, 'uuid:e56fe598-c88b-5646-d1e2-75e44f14395b');
    expect(d.friendlyName, '[TV]UE55D8000');
    expect(
      d.avTransportControlUrl,
      Uri.parse('http://10.0.0.7:52235/dmr/upnp/control/AVTransport1'),
    );
    expect(d.iconUrl, Uri.parse('http://10.0.0.7:52235/dmr/icon_SML.jpg'));
    expect(d.renderingControlUrl, isNull);
    expect(d.connectionManagerUrl, isNull);
  });

  test('non-renderers and malformed XML are rejected', () {
    expect(
      () => DlnaDevice.fromDescription(
        '<root><device><deviceType>urn:dial-multiscreen-org:device:dial:1</deviceType>'
        '<UDN>uuid:x</UDN></device></root>',
        location,
      ),
      throwsA(isA<DlnaProtocolException>()),
    );
    expect(
      () => DlnaDevice.fromDescription('<root><device>', location),
      throwsA(isA<DlnaProtocolException>()),
    );
  });

  test('JSON round trip, equality and toString', () {
    final d = DlnaDevice.fromDescription(samsungDescription, location);
    final restored = DlnaDevice.fromJson(
      jsonDecode(jsonEncode(d.toJson())) as Map<String, Object?>,
    );
    expect(restored, d);
    expect(restored.hashCode, d.hashCode);
    expect('$d', contains('[TV] Samsung 5 Series (43)'));
    expect(
      () => DlnaDevice.fromJson({'udn': 'uuid:x'}),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => DlnaDevice.fromJson({...d.toJson(), 'udn': 3}),
      throwsA(isA<FormatException>()),
    );
  });
}
