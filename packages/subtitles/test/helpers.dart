import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Bytes of `test/fixtures/<path>`.
Uint8List fixtureBytes(String path) =>
    File('test/fixtures/$path').readAsBytesSync();

/// Text of `test/fixtures/<path>`.
String fixture(String path) => File('test/fixtures/$path').readAsStringSync();

/// Decoded JSON of `test/fixtures/<path>`.
Object? fixtureJson(String path) => jsonDecode(fixture(path));

/// A recorded request.
typedef Seen = ({
  String method,
  Uri url,
  Map<String, String> headers,
  String body,
});

/// MockClient that answers via [handler] and records every request in [seen].
MockClient recordingClient(
  List<Seen> seen,
  Future<http.Response> Function(http.Request req) handler,
) => MockClient((req) {
  seen.add((
    method: req.method,
    url: req.url,
    headers: req.headers,
    body: req.body,
  ));
  return handler(req);
});

http.Response jsonResponse(
  Object? body, {
  int status = 200,
  Map<String, String> headers = const {},
}) => http.Response.bytes(
  utf8.encode(body is String ? body : jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json; charset=utf-8', ...headers},
);

Future<void> noSleep(Duration _) async {}
