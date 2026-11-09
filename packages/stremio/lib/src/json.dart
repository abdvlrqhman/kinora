// Lenient readers for addon JSON. Real addons send nulls, numbers as
// strings and strings as numbers, so every reader tolerates the wrong type
// and returns null/empty instead of throwing.

import 'errors.dart';

/// Decoded JSON object.
typedef JsonMap = Map<String, Object?>;

/// Returns [value] as a JSON object or throws [AddonResponseException].
JsonMap jsonObject(Object? value, String what) {
  if (value is Map<String, Object?>) return value;
  throw AddonResponseException('$what is not a JSON object');
}

/// Non-empty string (numbers are stringified), else null.
String? readString(JsonMap json, String key) => switch (json[key]) {
  final String s when s.trim().isNotEmpty => s,
  final num n => n.toString(),
  _ => null,
};

/// Required non-empty string, else [AddonResponseException].
String requireString(JsonMap json, String key, String what) =>
    readString(json, key) ??
    (throw AddonResponseException('$what has no "$key"'));

/// Integer from an int, a whole double or a numeric string.
int? readInt(JsonMap json, String key) => switch (json[key]) {
  final int i => i,
  final double d when d.isFinite => d.toInt(),
  final String s => int.tryParse(s.trim()),
  _ => null,
};

/// `true` only for JSON true or the string "true".
bool readBool(JsonMap json, String key) {
  final v = json[key];
  return v == true || v == 'true';
}

/// List of non-empty strings; a single string becomes a one-element list.
List<String> readStrings(JsonMap json, String key) => switch (json[key]) {
  final String s when s.isNotEmpty => List.unmodifiable([s]),
  final List<Object?> l => List.unmodifiable([
    for (final e in l)
      if (e is String && e.isNotEmpty) e,
  ]),
  _ => const [],
};

/// Like [readStrings] but null when the key is absent or not a list.
List<String>? readStringsOrNull(JsonMap json, String key) =>
    json[key] is List<Object?> ? readStrings(json, key) : null;

/// The JSON objects inside a list, skipping anything else.
List<JsonMap> readObjects(JsonMap json, String key) => switch (json[key]) {
  final List<Object?> l => [
    for (final e in l)
      if (e is Map<String, Object?>) e,
  ],
  _ => const [],
};

/// ISO 8601 date, else null.
DateTime? readDate(JsonMap json, String key) => switch (json[key]) {
  final String s => DateTime.tryParse(s),
  _ => null,
};

/// String-to-string map (non-string values are dropped).
Map<String, String> readStringMap(Object? value) => switch (value) {
  final Map<String, Object?> m => Map.unmodifiable({
    for (final e in m.entries)
      if (e.value is String) e.key: e.value! as String,
  }),
  _ => const {},
};

/// Element-wise list equality.
bool listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Entry-wise map equality.
bool mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    if (!b.containsKey(e.key) || b[e.key] != e.value) return false;
  }
  return true;
}

/// Hash consistent with [mapEquals].
int mapHash<K, V>(Map<K, V> m) =>
    Object.hashAllUnordered(m.entries.map((e) => Object.hash(e.key, e.value)));
