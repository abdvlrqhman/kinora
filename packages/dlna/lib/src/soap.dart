import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import 'errors.dart';
import 'http_util.dart';
import 'xml_util.dart';

/// UPnP service types used by the renderer. Version 1 is always used:
/// UPnP requires devices to accept control points of lower versions.
abstract final class UpnpService {
  static const avTransport = 'urn:schemas-upnp-org:service:AVTransport:1';
  static const renderingControl =
      'urn:schemas-upnp-org:service:RenderingControl:1';
  static const connectionManager =
      'urn:schemas-upnp-org:service:ConnectionManager:1';
}

/// Builds a SOAP 1.1 envelope invoking [action] of [serviceType] with [args]
/// (sent in the given order; values are XML-escaped).
String buildSoapEnvelope(
  String serviceType,
  String action,
  Map<String, String> args,
) {
  final body = StringBuffer();
  args.forEach(
    (name, value) => body.write('<$name>${escapeXml(value)}</$name>'),
  );
  return '<?xml version="1.0" encoding="utf-8"?>\n'
      '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
      's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
      '<s:Body><u:$action xmlns:u="$serviceType">$body</u:$action></s:Body>'
      '</s:Envelope>';
}

/// Extracts the `<UPnPError>` of a SOAP fault body, or null when [body] is
/// not a UPnP fault.
DlnaSoapFault? parseSoapFault(String action, String body) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(body);
  } on XmlException {
    return null;
  }
  final error = doc.rootElement.descendantsNamed('UPnPError').firstOrNull;
  final code = int.tryParse(error?.childText('errorCode') ?? '');
  if (code == null) return null;
  return DlnaSoapFault(
    action: action,
    errorCode: code,
    errorDescription: error!.childText('errorDescription'),
  );
}

/// Extracts the out-arguments of `<u:{action}Response>` by local name.
Map<String, String> parseSoapResponse(String action, String body, Uri uri) {
  final XmlElement? response;
  try {
    response = XmlDocument.parse(body).rootElement
        .descendantsNamed('${action}Response')
        .firstOrNull;
  } on XmlException catch (e) {
    throw DlnaProtocolException(
      'Malformed $action response: ${e.message}',
      uri: uri,
    );
  }
  if (response == null) {
    throw DlnaProtocolException('No ${action}Response element', uri: uri);
  }
  return {for (final e in response.childElements) e.name.local: e.innerText};
}

/// Minimal UPnP control client: POSTs a SOAP action and returns its
/// out-arguments, throwing [DlnaSoapFault] for UPnP errors.
final class SoapClient {
  SoapClient(this._client, {required this.timeout});

  final http.Client _client;

  /// Timeout of each action.
  final Duration timeout;

  /// Invokes [action] on [controlUrl].
  Future<Map<String, String>> call(
    Uri controlUrl,
    String serviceType,
    String action,
    Map<String, String> args,
  ) async {
    final response = await sendHttp(
      _client,
      'POST',
      controlUrl,
      timeout: timeout,
      headers: {
        'Content-Type': 'text/xml; charset="utf-8"',
        'SOAPACTION': '"$serviceType#$action"',
      },
      body: buildSoapEnvelope(serviceType, action, args),
    );
    final text = bodyText(response);
    if (response.statusCode == 200) {
      return parseSoapResponse(action, text, controlUrl);
    }
    throw parseSoapFault(action, text) ??
        DlnaHttpException(
          '$action: ${response.reasonPhrase ?? 'error'}',
          statusCode: response.statusCode,
          uri: controlUrl,
        );
  }
}
