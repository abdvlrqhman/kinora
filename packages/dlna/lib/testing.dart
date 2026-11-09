/// Test doubles of a Samsung TV for this package's tests and the app's
/// end-to-end test: a DMR (description + SOAP) and an SSDP responder.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dlna/src/xml_util.dart';
import 'package:xml/xml.dart';

const samsungUdn = 'uuid:2fcbf741-f7a9-4041-bfc5-a08e4b09cd66';

/// Device description in the structure a Samsung Tizen TV serves on
/// `:9197/dmr` (reconstructed from published captures of 2018+ Tizen TVs:
/// pnpx/df/sec extras, `dlna:X_DLNADOC` declared inline, root-relative URLs).
const samsungDescription =
    '''<?xml version="1.0"?>
<root xmlns='urn:schemas-upnp-org:device-1-0' xmlns:pnpx="http://schemas.microsoft.com/windows/pnpx/2005/11" xmlns:df="http://schemas.microsoft.com/windows/2008/09/devicefoundation" xmlns:sec="http://www.sec.co.kr/dlna">
\t<specVersion>
\t\t<major>1</major>
\t\t<minor>0</minor>
\t</specVersion>
\t<device>
\t\t<deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>
\t\t<pnpx:X_compatibleId>MS_DigitalMediaDeviceClass_DMR_V001</pnpx:X_compatibleId>
\t\t<pnpx:X_deviceCategory>MediaDevices</pnpx:X_deviceCategory>
\t\t<pnpx:X_hardwareId>VEN_0105&amp;DEV_VD0001</pnpx:X_hardwareId>
\t\t<df:X_deviceCategory>Display.TV.LCD Multimedia.DMR</df:X_deviceCategory>
\t\t<dlna:X_DLNADOC xmlns:dlna="urn:schemas-dlna-org:device-1-0">DMR-1.50</dlna:X_DLNADOC>
\t\t<friendlyName>[TV] Samsung 5 Series (43)</friendlyName>
\t\t<manufacturer>Samsung Electronics</manufacturer>
\t\t<manufacturerURL>http://www.samsung.com/sec</manufacturerURL>
\t\t<modelDescription>Samsung TV DMR</modelDescription>
\t\t<modelName>UE43T5300</modelName>
\t\t<modelNumber>AllShare1.0</modelNumber>
\t\t<modelURL>http://www.samsung.com/sec</modelURL>
\t\t<serialNumber>20090804RCR</serialNumber>
\t\t<UDN>$samsungUdn</UDN>
\t\t<sec:deviceID>DMR1234567890</sec:deviceID>
\t\t<iconList>
\t\t\t<icon><mimetype>image/jpeg</mimetype><width>48</width><height>48</height><depth>24</depth><url>/dmr/icon_SML.jpg</url></icon>
\t\t\t<icon><mimetype>image/jpeg</mimetype><width>120</width><height>120</height><depth>24</depth><url>/dmr/icon_LRG.jpg</url></icon>
\t\t\t<icon><mimetype>image/png</mimetype><width>48</width><height>48</height><depth>24</depth><url>/dmr/icon_SML.png</url></icon>
\t\t\t<icon><mimetype>image/png</mimetype><width>120</width><height>120</height><depth>24</depth><url>/dmr/icon_LRG.png</url></icon>
\t\t</iconList>
\t\t<serviceList>
\t\t\t<service>
\t\t\t\t<serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType>
\t\t\t\t<serviceId>urn:upnp-org:serviceId:RenderingControl</serviceId>
\t\t\t\t<SCPDURL>/RenderingControl_1.xml</SCPDURL>
\t\t\t\t<controlURL>/upnp/control/RenderingControl1</controlURL>
\t\t\t\t<eventSubURL>/upnp/event/RenderingControl1</eventSubURL>
\t\t\t</service>
\t\t\t<service>
\t\t\t\t<serviceType>urn:schemas-upnp-org:service:ConnectionManager:1</serviceType>
\t\t\t\t<serviceId>urn:upnp-org:serviceId:ConnectionManager</serviceId>
\t\t\t\t<SCPDURL>/ConnectionManager_1.xml</SCPDURL>
\t\t\t\t<controlURL>/upnp/control/ConnectionManager1</controlURL>
\t\t\t\t<eventSubURL>/upnp/event/ConnectionManager1</eventSubURL>
\t\t\t</service>
\t\t\t<service>
\t\t\t\t<serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
\t\t\t\t<serviceId>urn:upnp-org:serviceId:AVTransport</serviceId>
\t\t\t\t<SCPDURL>/AVTransport_1.xml</SCPDURL>
\t\t\t\t<controlURL>/upnp/control/AVTransport1</controlURL>
\t\t\t\t<eventSubURL>/upnp/event/AVTransport1</eventSubURL>
\t\t\t</service>
\t\t</serviceList>
\t\t<sec:ProductCap>Tizen,Y2020,WebURIPlayable,NavigateInPause,ScreenMirroringP2PMAC=f4:7d:ef:00:00:00,vdProductType=TV,OCF=1</sec:ProductCap>
\t</device>
</root>''';

/// GetProtocolInfo Sink in the style of a Samsung Tizen TV (abridged).
const samsungSink =
    'http-get:*:video/x-matroska:*,http-get:*:video/x-mkv:*,'
    'http-get:*:video/mp4:*,'
    'http-get:*:video/mp4:DLNA.ORG_PN=AVC_MP4_HP_HD_AAC,'
    'http-get:*:video/mp4:DLNA.ORG_PN=HEVC_MP4_MP_L41_AAC,'
    'http-get:*:video/vnd.dlna.mpeg-tts:DLNA.ORG_PN=AVC_TS_HD_24_AC3_T,'
    'http-get:*:video/mpeg:DLNA.ORG_PN=MPEG_TS_HD_NA,'
    'http-get:*:video/x-msvideo:*,http-get:*:video/avi:*,'
    'http-get:*:video/quicktime:*,'
    'http-get:*:audio/mpeg:DLNA.ORG_PN=MP3,'
    'http-get:*:audio/mp4:DLNA.ORG_PN=AAC_ISO_320,'
    'http-get:*:image/jpeg:DLNA.ORG_PN=JPEG_LRG,'
    'http-get:*:text/srt:*,http-get:*:smi/caption:*';

/// A recorded SOAP request.
final class SoapCall {
  SoapCall(this.path, this.soapAction, this.action, this.args, this.body);
  final String path;
  final String? soapAction;
  final String action;
  final Map<String, String> args;
  final String body;

  @override
  String toString() => '$action$args';
}

/// In-process fake of a Samsung DMR: serves the description on `/dmr` and
/// AVTransport/RenderingControl/ConnectionManager SOAP endpoints with a tiny
/// state machine. Queue UPnP faults per action in [faults].
final class FakeSamsungDmr {
  FakeSamsungDmr._(this._server) {
    _server.listen(_handle);
  }

  /// Listens on 127.0.0.1:[port] (any free port by default; a real Tizen
  /// TV uses 9197). With [pullOnPlay], Play makes it fetch the media (and
  /// the `CaptionInfo.sec` subtitles) the way a TV does.
  static Future<FakeSamsungDmr> start({
    int port = 0,
    bool pullOnPlay = false,
  }) async => FakeSamsungDmr._(
    await HttpServer.bind(InternetAddress.loopbackIPv4, port),
  )..pullOnPlay = pullOnPlay;

  bool pullOnPlay = false;

  /// What the TV fetched on Play: the media's response headers and bytes,
  /// and the subtitle text named by its `CaptionInfo.sec` header.
  HttpHeaders? pulledHeaders;
  final pulled = BytesBuilder(copy: false);
  String? pulledCaption;
  Object? pullError;
  Future<void>? _pull;

  /// Completes when the fetch started by the last Play has finished.
  Future<void> get pulling => _pull ?? Future.value();

  final HttpServer _server;
  final calls = <SoapCall>[];

  /// action -> UPnP error codes to answer with, consumed one per call.
  final faults = <String, List<int>>{};

  /// Delay before answering any request (to test timeouts).
  Duration delay = Duration.zero;

  /// Drops this many of the next control requests without an answer (the
  /// connection closes, as a TV's dead keep-alive connection does).
  int dropConnections = 0;

  /// The `Connection` header of the last control request.
  String? lastConnection;

  /// `CurrentTransportStatus`: 'ERROR_OCCURRED' when the TV's player failed.
  String transportStatus = 'OK';

  String state = 'NO_MEDIA_PRESENT';
  String uri = '';
  int volume = 12;
  bool muted = false;
  String relTime = '0:00:00';
  String trackDuration = '0:00:00';
  int descriptionHits = 0;

  int get port => _server.port;
  Uri get location => Uri.parse('http://127.0.0.1:$port/dmr');
  List<String> get actions => [for (final c in calls) c.action];

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final body = await utf8.decodeStream(request);
    await Future<void>.delayed(delay);
    final response = request.response;
    if (request.method == 'GET' && request.uri.path == '/dmr') {
      descriptionHits++;
      response.headers.contentType = ContentType(
        'text',
        'xml',
        charset: 'utf-8',
      );
      response.write(samsungDescription);
      return response.close();
    }
    if (request.method != 'POST' ||
        !request.uri.path.startsWith('/upnp/control/')) {
      response.statusCode = 404;
      return response.close();
    }
    lastConnection = request.headers.value('connection');
    if (dropConnections > 0) {
      dropConnections--;
      (await response.detachSocket(writeHeaders: false)).destroy();
      return;
    }
    final element = XmlDocument.parse(body).rootElement
        .descendantsNamed('Body')
        .single
        .childElements
        .single;
    final action = element.name.local;
    final args = {
      for (final e in element.childElements) e.name.local: e.innerText,
    };
    calls.add(
      SoapCall(
        request.uri.path,
        request.headers.value('soapaction'),
        action,
        args,
        body,
      ),
    );
    final serviceType = element.getAttribute('xmlns:u')!;
    final queued = faults[action];
    if (queued != null && queued.isNotEmpty) {
      return _fault(response, queued.removeAt(0));
    }
    final out = _perform(action, args);
    if (out == null) return _fault(response, 401);
    response.headers.contentType = ContentType('text', 'xml', charset: 'utf-8');
    response.write(
      '<?xml version="1.0" encoding="utf-8"?>'
      '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
      's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body>'
      '<u:${action}Response xmlns:u="$serviceType">'
      '${out.entries.map((e) => '<${e.key}>${escapeXml(e.value)}</${e.key}>').join()}'
      '</u:${action}Response></s:Body></s:Envelope>',
    );
    await response.close();
  }

  Map<String, String>? _perform(String action, Map<String, String> args) {
    switch (action) {
      case 'SetAVTransportURI':
        uri = args['CurrentURI']!;
        state = 'STOPPED';
        return {};
      case 'Play':
        state = 'PLAYING';
        if (pullOnPlay && uri.isNotEmpty) _pull ??= _fetch(Uri.parse(uri));
        return {};
      case 'Pause':
        state = 'PAUSED_PLAYBACK';
        return {};
      case 'Stop':
        state = 'STOPPED';
        return {};
      case 'Seek':
        relTime = args['Target']!;
        return {};
      case 'GetTransportInfo':
        return {
          'CurrentTransportState': state,
          'CurrentTransportStatus': transportStatus,
          'CurrentSpeed': '1',
        };
      case 'GetPositionInfo':
        return {
          'Track': '1',
          'TrackDuration': trackDuration,
          'TrackMetaData': '',
          'TrackURI': uri,
          'RelTime': relTime,
          'AbsTime': 'NOT_IMPLEMENTED',
          'RelCount': '2147483647',
          'AbsCount': '2147483647',
        };
      case 'GetVolume':
        return {'CurrentVolume': '$volume'};
      case 'SetVolume':
        volume = int.parse(args['DesiredVolume']!);
        return {};
      case 'GetMute':
        return {'CurrentMute': muted ? '1' : '0'};
      case 'SetMute':
        muted = args['DesiredMute'] == '1';
        return {};
      case 'GetProtocolInfo':
        return {'Source': '', 'Sink': samsungSink};
    }
    return null;
  }

  Future<void> _fetch(Uri media) async {
    final client = HttpClient();
    try {
      // Headers a Samsung TV sends when it starts a DLNA stream.
      final req = await client.getUrl(media)
        ..headers.set('getcontentFeatures.dlna.org', '1')
        ..headers.set('getCaptionInfo.sec', '1')
        ..headers.set('transferMode.dlna.org', 'Streaming')
        ..headers.set(HttpHeaders.rangeHeader, 'bytes=0-');
      final res = await req.close();
      pulledHeaders = res.headers;
      await res.forEach(pulled.add);
      final caption = res.headers.value('CaptionInfo.sec');
      if (caption != null) {
        final c = await (await client.getUrl(Uri.parse(caption))).close();
        pulledCaption = await utf8.decodeStream(c);
      }
    } on Object catch (e) {
      pullError = e;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _fault(HttpResponse response, int code) {
    response
      ..statusCode = 500
      ..headers.contentType = ContentType('text', 'xml', charset: 'utf-8')
      ..write(soapFaultBody(code, 'Fake error $code'));
    return response.close();
  }
}

/// A SOAP fault body as Samsung TVs send it.
String soapFaultBody(int code, String description) =>
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
    's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">\n'
    '<s:Body>\n<s:Fault>\n<faultcode>s:Client</faultcode>\n'
    '<faultstring>UPnPError</faultstring>\n<detail>\n'
    '<UPnPError xmlns="urn:schemas-upnp-org:control-1-0">\n'
    '<errorCode>$code</errorCode>\n'
    '<errorDescription>$description</errorDescription>\n'
    '</UPnPError>\n</detail>\n</s:Fault>\n</s:Body>\n</s:Envelope>';

/// Fake SSDP responder on 127.0.0.1: answers M-SEARCH like a Samsung TV
/// (for `ssdp:all` also a rootdevice entry and a non-renderer DIAL device).
final class FakeSsdpResponder {
  FakeSsdpResponder._(this._socket, this.location) {
    _socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      for (var d = _socket.receive(); d != null; d = _socket.receive()) {
        _onDatagram(d);
      }
    });
  }

  static Future<FakeSsdpResponder> start(Uri location) async =>
      FakeSsdpResponder._(
        await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0),
        location,
      );

  final RawDatagramSocket _socket;
  final Uri location;
  final searches = <String>[];

  int get port => _socket.port;

  void close() => _socket.close();

  void _onDatagram(Datagram d) {
    final text = latin1.decode(d.data);
    if (!text.startsWith('M-SEARCH')) return;
    searches.add(text);
    final st = RegExp(
      r'^ST: *(.*)$',
      multiLine: true,
    ).firstMatch(text)!.group(1)!.trim();
    final replies = <(String, Uri)>[
      if (st == 'ssdp:all') ('upnp:rootdevice', location),
      if (st == 'ssdp:all' || st.contains('MediaRenderer'))
        ('urn:schemas-upnp-org:device:MediaRenderer:1', location),
      if (st == 'ssdp:all')
        (
          'urn:dial-multiscreen-org:device:dial:1',
          location.replace(path: '/dial'),
        ),
    ];
    for (final (target, loc) in replies) {
      _socket.send(
        latin1.encode(
          'HTTP/1.1 200 OK\r\n'
          'CACHE-CONTROL: max-age=1800\r\n'
          'EXT:\r\n'
          'LOCATION: $loc\r\n'
          'SERVER: SHP, UPnP/1.0, Samsung UPnP SDK/1.0\r\n'
          'ST: $target\r\n'
          'USN: $samsungUdn::$target\r\n'
          'Content-Length: 0\r\n\r\n',
        ),
        d.address,
        d.port,
      );
    }
  }
}

/// A NOTIFY datagram as a Samsung TV multicasts it.
List<int> samsungNotify(Uri location, {String nts = 'ssdp:alive'}) =>
    latin1.encode(
      'NOTIFY * HTTP/1.1\r\n'
      'HOST: 239.255.255.250:1900\r\n'
      'CACHE-CONTROL: max-age=1800\r\n'
      'LOCATION: $location\r\n'
      'NT: urn:schemas-upnp-org:device:MediaRenderer:1\r\n'
      'NTS: $nts\r\n'
      'SERVER: SHP, UPnP/1.0, Samsung UPnP SDK/1.0\r\n'
      'USN: $samsungUdn::urn:schemas-upnp-org:device:MediaRenderer:1\r\n'
      '\r\n',
    );
