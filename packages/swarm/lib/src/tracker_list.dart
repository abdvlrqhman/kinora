import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Built-in fallback: the long-lived head of ngosang/trackerslist
/// `trackers_best.txt` (snapshot 2026-11-09), used when nothing better is
/// available.
final List<Uri> defaultTrackers = List.unmodifiable(
  normalizeTrackers(const [
    'udp://tracker.opentrackr.org:1337/announce',
    'udp://open.stealth.si:80/announce',
    'udp://tracker.torrent.eu.org:451/announce',
    'udp://open.demonii.com:1337/announce',
    'udp://open.tracker.cl:1337/announce',
    'udp://tracker.qu.ax:6969/announce',
    'udp://explodie.org:6969/announce',
    'udp://tracker-udp.gbitt.info:80/announce',
    'udp://tracker.theoks.net:6969/announce',
    'udp://tracker2.dler.org:80/announce',
    'http://tracker.dler.org:6969/announce',
    'http://tracker.renfei.net:8080/announce',
  ]),
);

/// Parses, normalizes and de-duplicates tracker URLs.
///
/// Accepts list-file lines (blank lines and `#` comments are skipped) and
/// Stremio `tracker:<url>` sources. Keeps `udp://host:port` and http(s)
/// trackers; drops anything else (e.g. `wss://`, `dht:`).
List<Uri> normalizeTrackers(Iterable<String> urls) {
  final seen = <String>{};
  final out = <Uri>[];
  for (final raw in urls) {
    var text = raw.trim();
    if (text.startsWith('tracker:')) text = text.substring('tracker:'.length);
    if (text.isEmpty || text.startsWith('#')) continue;
    final uri = Uri.tryParse(text)?.removeFragment();
    if (uri == null || uri.host.isEmpty) continue;
    final ok = switch (uri.scheme) {
      'udp' => uri.hasPort && uri.port > 0,
      'http' || 'https' => true,
      _ => false,
    };
    if (ok && seen.add(uri.toString())) out.add(uri);
  }
  return out;
}

/// A public best-trackers list, cached on disk.
///
/// [load] returns the cache while it is younger than [maxAge], otherwise
/// downloads [source]; offline it falls back to the (stale) cache and then
/// to [defaultTrackers]. It never throws.
final class TrackerList {
  /// Creates a list. [cacheFile] is optional; without it every [load]
  /// downloads.
  TrackerList({
    http.Client? httpClient,
    Uri? source,
    this.cacheFile,
    this.maxAge = const Duration(hours: 24),
    this.fetchTimeout = const Duration(seconds: 10),
    this.userAgent = 'Kinora/0.1.0',
    DateTime Function()? clock,
  }) : source = source ?? defaultSource,
       _http = httpClient ?? http.Client(),
       _ownsHttp = httpClient == null,
       _clock = clock ?? DateTime.now;

  /// ngosang/trackerslist `trackers_best.txt`.
  static final Uri defaultSource = Uri.parse(
    'https://raw.githubusercontent.com/ngosang/trackerslist/master/trackers_best.txt',
  );

  final http.Client _http;
  final bool _ownsHttp;
  final DateTime Function() _clock;

  /// Where the list is downloaded from.
  final Uri source;

  /// Cache location (one URL per line).
  final File? cacheFile;

  /// How long the cache counts as fresh.
  final Duration maxAge;

  /// Limit for the download.
  final Duration fetchTimeout;

  /// `User-Agent` for the download.
  final String userAgent;

  /// The tracker list; [forceRefresh] skips a fresh cache.
  Future<List<Uri>> load({bool forceRefresh = false}) async {
    final file = cacheFile;
    var cached = const <Uri>[];
    var fresh = false;
    if (file != null && file.existsSync()) {
      try {
        cached = normalizeTrackers(
          LineSplitter.split(await file.readAsString()),
        );
        fresh = _clock().difference(file.lastModifiedSync()) < maxAge;
      } on FileSystemException {
        cached = const [];
      } on FormatException {
        cached = const [];
      }
    }
    if (fresh && !forceRefresh && cached.isNotEmpty) return cached;
    try {
      final res = await _http
          .get(source, headers: {'User-Agent': userAgent})
          .timeout(fetchTimeout);
      if (res.statusCode == 200) {
        final list = normalizeTrackers(
          LineSplitter.split(utf8.decode(res.bodyBytes, allowMalformed: true)),
        );
        if (list.isNotEmpty) {
          if (file != null) await _write(file, list);
          return List.unmodifiable(list);
        }
      }
    } on Exception {
      // Offline or blocked: fall back below.
    }
    return cached.isNotEmpty ? List.unmodifiable(cached) : defaultTrackers;
  }

  /// Closes the HTTP client if this instance created it.
  void close() {
    if (_ownsHttp) _http.close();
  }

  Future<void> _write(File file, List<Uri> list) async {
    try {
      await file.parent.create(recursive: true);
      // Write-then-rename so a crash never leaves a half-written cache.
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString('${list.join('\n')}\n', flush: true);
      await tmp.rename(file.path);
    } on FileSystemException {
      // The cache is best-effort.
    }
  }
}
