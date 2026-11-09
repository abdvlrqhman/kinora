import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../cancel.dart';
import '../errors.dart';
import '../language.dart';
import '../models.dart';
import '../provider_http.dart';

/// Default User-Agent (`App vX.Y`, the form OpenSubtitles requires).
const defaultUserAgent = 'Kinora v0.1.0';

/// Lenient JSON accessors: providers mix strings, numbers and nulls.
extension JsonRead on Map<String, Object?> {
  String? str(String key) {
    final v = this[key];
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  int? integer(String key) {
    final v = this[key];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '');
  }

  double? number(String key) {
    final v = this[key];
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '');
  }

  bool flag(String key) {
    final v = this[key];
    return v == true || v == 1 || v == 'true' || v == '1';
  }

  Map<String, Object?> obj(String key) {
    final v = this[key];
    return v is Map ? v.cast<String, Object?>() : const {};
  }

  List<Object?> list(String key) {
    final v = this[key];
    return v is List ? v.cast<Object?>() : const [];
  }

  DateTime? date(String key) => DateTime.tryParse(str(key) ?? '');
}

/// Casts a decoded JSON value to a map or throws.
Map<String, Object?> asJsonMap(Object? v, String providerId) {
  if (v is Map) return v.cast<String, Object?>();
  throw SubtitleResponseException(
    'expected a JSON object',
    providerId: providerId,
  );
}

/// Maps of objects inside a JSON list, skipping anything else.
Iterable<Map<String, Object?>> jsonObjects(Iterable<Object?> list) => list
    .whereType<Map<Object?, Object?>>()
    .map((m) => m.cast<String, Object?>());

/// FPS strings like "23.976", "N/A", "" -> number or null.
double? parseFps(Object? v) {
  final f = v is num ? v.toDouble() : double.tryParse('${v ?? ''}'.trim());
  return f == null || f <= 0 ? null : f;
}

/// Keeps results in [wanted] languages (all when [wanted] is empty).
bool wantedLanguage(Language language, List<Language> wanted) =>
    wanted.isEmpty || wanted.contains(language);

/// GET [url] and wrap the body as a [SubtitleDownload].
Future<SubtitleDownload> fetchFile(
  ProviderHttp http0,
  Uri url, {
  required String fallbackName,
  Map<String, String> headers = const {},
  SubtitleFormat? format,
  CancelToken? cancel,
}) async {
  final http.Response res = await http0.send(
    'GET',
    url,
    headers: headers,
    cancel: cancel,
  );
  final name =
      contentDispositionFileName(res.headers['content-disposition']) ??
      fallbackName;
  return SubtitleDownload(
    bytes: Uint8List.fromList(res.bodyBytes),
    fileName: name,
    format: format ?? SubtitleFormat.fromName(name),
  );
}
