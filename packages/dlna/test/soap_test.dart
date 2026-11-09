import 'package:dlna/dlna.dart';
import 'package:dlna/src/didl.dart';
import 'package:dlna/src/soap.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/fake_samsung_dmr.dart';

void main() {
  test('Play envelope golden', () {
    expect(
      buildSoapEnvelope(UpnpService.avTransport, 'Play', {
        'InstanceID': '0',
        'Speed': '1',
      }),
      '<?xml version="1.0" encoding="utf-8"?>\n'
      '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
      's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body>'
      '<u:Play xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">'
      '<InstanceID>0</InstanceID><Speed>1</Speed></u:Play>'
      '</s:Body></s:Envelope>',
    );
  });

  test('SetAVTransportURI with Samsung captions golden (DIDL escaped twice)', () {
    final media = Uri.parse(
      'http://192.168.1.20:8090/s/abc/Show%20S01E01.mkv?t=1&q=2',
    );
    final srt = Uri.parse('http://192.168.1.20:8090/sub/7.srt?lang=ar&v=1');
    final didl = buildVideoDidl(
      media: media,
      title: 'Tom & Jerry <S01E01> "Pilot"',
      mimeType: 'video/x-matroska',
      sizeBytes: 1234567890,
      duration: const Duration(minutes: 42, seconds: 10, milliseconds: 5),
      subtitleSrt: srt,
      posterUrl: Uri.parse('https://image.tmdb.org/t/p/w500/a.jpg'),
    );
    const expectedDidl =
        '<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" '
        'xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" '
        'xmlns:sec="http://www.sec.co.kr/">'
        '<item id="0" parentID="-1" restricted="1">'
        '<dc:title>Tom &amp; Jerry &lt;S01E01&gt; &quot;Pilot&quot;</dc:title>'
        '<upnp:class>object.item.videoItem</upnp:class>'
        '<upnp:albumArtURI>https://image.tmdb.org/t/p/w500/a.jpg</upnp:albumArtURI>'
        '<res protocolInfo="http-get:*:video/x-matroska:DLNA.ORG_OP=01;DLNA.ORG_CI=0;'
        'DLNA.ORG_FLAGS=01700000000000000000000000000000" size="1234567890" '
        'duration="0:42:10.005">'
        'http://192.168.1.20:8090/s/abc/Show%20S01E01.mkv?t=1&amp;q=2</res>'
        '<sec:CaptionInfoEx sec:type="srt">http://192.168.1.20:8090/sub/7.srt?lang=ar&amp;v=1</sec:CaptionInfoEx>'
        '<sec:CaptionInfo sec:type="srt">http://192.168.1.20:8090/sub/7.srt?lang=ar&amp;v=1</sec:CaptionInfo>'
        '</item></DIDL-Lite>';
    expect(didl, expectedDidl);

    final envelope = buildSoapEnvelope(
      UpnpService.avTransport,
      'SetAVTransportURI',
      {'InstanceID': '0', 'CurrentURI': '$media', 'CurrentURIMetaData': didl},
    );
    expect(
      envelope,
      '<?xml version="1.0" encoding="utf-8"?>\n'
      '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
      's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body>'
      '<u:SetAVTransportURI xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">'
      '<InstanceID>0</InstanceID>'
      '<CurrentURI>http://192.168.1.20:8090/s/abc/Show%20S01E01.mkv?t=1&amp;q=2</CurrentURI>'
      '<CurrentURIMetaData>&lt;DIDL-Lite xmlns=&quot;urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/&quot; '
      'xmlns:dc=&quot;http://purl.org/dc/elements/1.1/&quot; '
      'xmlns:upnp=&quot;urn:schemas-upnp-org:metadata-1-0/upnp/&quot; '
      'xmlns:sec=&quot;http://www.sec.co.kr/&quot;&gt;'
      '&lt;item id=&quot;0&quot; parentID=&quot;-1&quot; restricted=&quot;1&quot;&gt;'
      '&lt;dc:title&gt;Tom &amp;amp; Jerry &amp;lt;S01E01&amp;gt; &amp;quot;Pilot&amp;quot;&lt;/dc:title&gt;'
      '&lt;upnp:class&gt;object.item.videoItem&lt;/upnp:class&gt;'
      '&lt;upnp:albumArtURI&gt;https://image.tmdb.org/t/p/w500/a.jpg&lt;/upnp:albumArtURI&gt;'
      '&lt;res protocolInfo=&quot;http-get:*:video/x-matroska:DLNA.ORG_OP=01;DLNA.ORG_CI=0;'
      'DLNA.ORG_FLAGS=01700000000000000000000000000000&quot; size=&quot;1234567890&quot; '
      'duration=&quot;0:42:10.005&quot;&gt;'
      'http://192.168.1.20:8090/s/abc/Show%20S01E01.mkv?t=1&amp;amp;q=2&lt;/res&gt;'
      '&lt;sec:CaptionInfoEx sec:type=&quot;srt&quot;&gt;http://192.168.1.20:8090/sub/7.srt?lang=ar&amp;amp;v=1&lt;/sec:CaptionInfoEx&gt;'
      '&lt;sec:CaptionInfo sec:type=&quot;srt&quot;&gt;http://192.168.1.20:8090/sub/7.srt?lang=ar&amp;amp;v=1&lt;/sec:CaptionInfo&gt;'
      '&lt;/item&gt;&lt;/DIDL-Lite&gt;</CurrentURIMetaData>'
      '</u:SetAVTransportURI></s:Body></s:Envelope>',
    );

    // Unescaping the SOAP argument yields well-formed DIDL with the
    // original title and URLs.
    final arg = XmlDocument.parse(envelope).rootElement.innerText;
    expect(arg, contains(expectedDidl));
    final item = XmlDocument.parse(expectedDidl)
        .rootElement
        .childElements
        .single;
    expect(
      item.getElement('dc:title')!.innerText,
      'Tom & Jerry <S01E01> "Pilot"',
    );
    expect(item.getElement('sec:CaptionInfoEx')!.innerText, '$srt');
  });

  test('minimal DIDL drops optional metadata', () {
    expect(
      buildVideoDidl(
        media: Uri.parse('http://h/v.mp4'),
        title: 'T',
        mimeType: 'video/mp4',
        sizeBytes: 1,
        duration: const Duration(seconds: 1),
        subtitleSrt: Uri.parse('http://h/s.srt'),
        posterUrl: Uri.parse('http://h/p.jpg'),
        minimal: true,
      ),
      '<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" '
      'xmlns:dc="http://purl.org/dc/elements/1.1/" '
      'xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">'
      '<item id="0" parentID="-1" restricted="1"><dc:title>T</dc:title>'
      '<upnp:class>object.item.videoItem</upnp:class>'
      '<res protocolInfo="http-get:*:video/mp4:*">http://h/v.mp4</res>'
      '</item></DIDL-Lite>',
    );
  });

  test('control characters are dropped from metadata', () {
    final didl = buildVideoDidl(
      media: Uri.parse('http://h/v.mp4'),
      title: 'Bad\u0001Title',
      mimeType: 'video/mp4',
    );
    expect(didl, contains('<dc:title>BadTitle</dc:title>'));
    expect(() => XmlDocument.parse(didl), returnsNormally);
  });

  group('faults', () {
    test('parses a UPnPError', () {
      final fault = parseSoapFault(
        'Seek',
        soapFaultBody(710, 'Seek mode not supported'),
      )!;
      expect(fault.action, 'Seek');
      expect(fault.errorCode, DlnaSoapFault.seekModeNotSupported);
      expect(fault.errorDescription, 'Seek mode not supported');
      expect('$fault', contains('710'));
    });

    test('UPnPError without description', () {
      final fault = parseSoapFault(
        'Play',
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><s:Fault>'
            '<detail><UPnPError><errorCode> 701 </errorCode></UPnPError></detail>'
            '</s:Fault></s:Body></s:Envelope>',
      )!;
      expect(fault.errorCode, 701);
      expect(fault.errorDescription, isNull);
    });

    test('non-UPnP bodies are not faults', () {
      expect(parseSoapFault('Play', '<html>Internal error</html>'), isNull);
      expect(parseSoapFault('Play', 'not xml <'), isNull);
    });
  });

  test('response out-arguments by local name', () {
    expect(
      parseSoapResponse(
        'GetVolume',
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>'
            '<m:GetVolumeResponse xmlns:m="urn:schemas-upnp-org:service:RenderingControl:1">'
            '<CurrentVolume>17</CurrentVolume></m:GetVolumeResponse></s:Body></s:Envelope>',
        Uri.parse('http://h/'),
      ),
      {'CurrentVolume': '17'},
    );
    expect(
      () => parseSoapResponse('GetVolume', '<a/>', Uri.parse('http://h/')),
      throwsA(isA<DlnaProtocolException>()),
    );
  });

  test('dlnaStreamHeaders', () {
    expect(dlnaStreamHeaders(mimeType: 'video/x-matroska'), {
      'Content-Type': 'video/x-matroska',
      'Accept-Ranges': 'bytes',
      'contentFeatures.dlna.org': 'DLNA.ORG_OP=01;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01700000000000000000000000000000',
      'transferMode.dlna.org': 'Streaming',
    });
    expect(
      dlnaStreamHeaders(
        mimeType: 'video/mp4',
        captionSrt: Uri.parse('http://192.168.1.20:8090/sub/7.srt'),
      )['CaptionInfo.sec'],
      'http://192.168.1.20:8090/sub/7.srt',
    );
  });
}
