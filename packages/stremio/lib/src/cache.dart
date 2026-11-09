import 'dart:collection';

/// Small in-memory TTL cache for addon responses, keyed by request URL.
///
/// Stores parsed (immutable) results. When full, the oldest entry is evicted.
final class ResponseCache {
  /// Creates a cache. [streamTtl] is capped at 5 minutes because stream
  /// links (debrid URLs, seed counts) go stale quickly.
  ResponseCache({
    DateTime Function()? clock,
    this.maxEntries = 256,
    this.manifestTtl = const Duration(hours: 6),
    this.metaTtl = const Duration(hours: 1),
    this.catalogTtl = const Duration(minutes: 15),
    this.subtitlesTtl = const Duration(minutes: 30),
    Duration streamTtl = const Duration(minutes: 2),
  }) : _clock = clock ?? DateTime.now,
       streamTtl = streamTtl > _maxStreamTtl ? _maxStreamTtl : streamTtl;

  static const _maxStreamTtl = Duration(minutes: 5);

  final DateTime Function() _clock;
  final _entries = LinkedHashMap<String, (DateTime, Object)>();

  /// Maximum number of cached responses.
  final int maxEntries;

  /// Lifetime of manifests.
  final Duration manifestTtl;

  /// Lifetime of `/meta` responses.
  final Duration metaTtl;

  /// Lifetime of `/catalog` responses.
  final Duration catalogTtl;

  /// Lifetime of `/subtitles` responses.
  final Duration subtitlesTtl;

  /// Lifetime of `/stream` responses (at most 5 minutes).
  final Duration streamTtl;

  /// TTL for an addon [resource] name, or for `manifest`.
  Duration ttlFor(String resource) => switch (resource) {
    'manifest' => manifestTtl,
    'meta' => metaTtl,
    'catalog' => catalogTtl,
    'stream' => streamTtl,
    'subtitles' => subtitlesTtl,
    _ => Duration.zero,
  };

  /// The live value for [key], or null.
  T? get<T extends Object>(String key) {
    final entry = _entries[key];
    if (entry == null) return null;
    if (!_clock().isBefore(entry.$1)) {
      _entries.remove(key);
      return null;
    }
    final value = entry.$2;
    return value is T ? value : null;
  }

  /// Stores [value] for [ttl]; a zero TTL stores nothing.
  void put(String key, Object value, Duration ttl) {
    if (ttl <= Duration.zero || maxEntries <= 0) return;
    _entries
      ..remove(key)
      ..[key] = (_clock().add(ttl), value);
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  /// Drops every entry.
  void clear() => _entries.clear();

  /// Number of entries (including expired ones not yet evicted).
  int get length => _entries.length;
}
