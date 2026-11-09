import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'errors.dart';

/// Sends one HTTP request with a hard [timeout] covering connect, headers and
/// body. On timeout the request is aborted (clients supporting
/// [http.Abortable]) and a [DlnaUnreachableException] is thrown; network
/// failures are mapped to [DlnaUnreachableException] as well.
Future<http.Response> sendHttp(
  http.Client client,
  String method,
  Uri uri, {
  required Duration timeout,
  Map<String, String> headers = const {},
  String? body,
}) async {
  final abort = Completer<void>();
  final request = http.AbortableRequest(method, uri, abortTrigger: abort.future)
    ..followRedirects = false
    ..headers.addAll(headers);
  if (body != null) request.bodyBytes = utf8.encode(body);
  final response = client.send(request).then(http.Response.fromStream);
  try {
    return await response.timeout(
      timeout,
      onTimeout: () {
        abort.complete();
        response.ignore();
        throw TimeoutException(null, timeout);
      },
    );
  } on TimeoutException catch (e) {
    throw DlnaUnreachableException(
      'No answer within ${timeout.inMilliseconds} ms',
      uri: uri,
      cause: e,
      isTimeout: true,
    );
  } on http.ClientException catch (e) {
    throw DlnaUnreachableException(e.message, uri: uri, cause: e);
  } on IOException catch (e) {
    throw DlnaUnreachableException(e.toString(), uri: uri, cause: e);
  }
}

/// Decodes a response body as UTF-8 regardless of the declared charset
/// (UPnP mandates UTF-8; some devices mislabel it).
String bodyText(http.Response response) =>
    utf8.decode(response.bodyBytes, allowMalformed: true);
