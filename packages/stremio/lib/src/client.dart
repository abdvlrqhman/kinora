import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'addon.dart';
import 'cache.dart';
import 'errors.dart';
import 'json.dart';
import 'manifest.dart';
import 'meta.dart';
import 'stream.dart';
import 'subtitle.dart';

/// Default `User-Agent` sent to addons.
const kinoraUserAgent = 'Kinora/0.1.0';

// Some addons sit behind bot filters that reject unknown agents with 403.
const _browserUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

/// HTTP client for the Stremio addon protocol.
///
/// Every request has a per-attempt [timeout], is retried with exponential
/// backoff on HTTP 429/5xx and timeouts (at most [maxRetries] times), is
/// retried once with a browser `User-Agent` on HTTP 403, and can be
/// cancelled by completing the optional `cancel` future. All failures are
/// thrown as [StremioException] subtypes.
final class AddonClient {
  /// Creates a client. Pass [httpClient] to share a connection pool or to
  /// test with `MockClient`; a client created here is closed by [close].
  AddonClient({
    http.Client? httpClient,
    this.userAgent = kinoraUserAgent,
    this.timeout = const Duration(seconds: 10),
    this.maxRetries = 2,
    this.retryDelay = const Duration(milliseconds: 500),
    this.maxRetryDelay = const Duration(seconds: 4),
    this.cache,
  }) : _http = httpClient ?? http.Client(),
       _ownsHttp = httpClient == null;

  final http.Client _http;
  final bool _ownsHttp;

  /// `User-Agent` header, e.g. `Kinora/1.2.0`.
  final String userAgent;

  /// Limit for one HTTP attempt (connect + full body).
  final Duration timeout;

  /// Extra attempts after a 429/5xx answer or a timeout.
  final int maxRetries;

  /// First backoff delay; doubles per retry.
  final Duration retryDelay;

  /// Upper bound for one backoff delay (also caps `Retry-After`).
  final Duration maxRetryDelay;

  /// Optional response cache.
  final ResponseCache? cache;

  /// Downloads and parses the manifest at [url] (any form accepted by
  /// [parseAddonUrl]).
  Future<Addon> fetchManifest(Uri url, {Future<void>? cancel}) async {
    final manifestUrl = parseAddonUrl(url.toString());
    final manifest = await _fetch(
      'manifest',
      manifestUrl,
      cancel,
      (json, _) => AddonManifest.fromJson(json),
    );
    return Addon(transportUrl: manifestUrl, manifest: manifest);
  }

  /// Items of catalog [catalogId] of [type]. [extra] (e.g. `search`,
  /// `genre`, `skip`) is sent as `/catalog/{type}/{id}/{k=v&…}.json`.
  /// Items without `id`/`type`/`name` are skipped.
  Future<List<MetaPreview>> catalog(
    Addon addon,
    String type,
    String catalogId, {
    Map<String, String> extra = const {},
    Future<void>? cancel,
  }) => _fetch(
    'catalog',
    addon.resourceUrl('catalog', type, catalogId, extra: extra),
    cancel,
    (json, _) => _list(json, 'metas', _tryPreview),
    notFound: const [],
  );

  /// Full metadata for [id].
  Future<MetaDetail> meta(
    Addon addon,
    String type,
    String id, {
    Future<void>? cancel,
  }) => _fetch(
    'meta',
    addon.resourceUrl('meta', type, id),
    cancel,
    (json, _) => MetaDetail.fromJson(jsonObject(json, 'response')['meta']),
  );

  /// Streams for video [id] (e.g. `tt0903747:1:1`).
  ///
  /// Throws [DebridKeyRejectedException] when the addon only returned
  /// "invalid key" placeholders; mixed placeholders are dropped.
  Future<List<StreamItem>> streams(
    Addon addon,
    String type,
    String id, {
    Future<void>? cancel,
  }) => _fetch('stream', addon.resourceUrl('stream', type, id), cancel, (
    json,
    uri,
  ) {
    final items = _list(json, 'streams', StreamItem.tryParse);
    final real = items.where((s) => !isDebridKeyRejection(s)).toList();
    if (real.isEmpty && items.isNotEmpty) {
      final first = items.first;
      throw DebridKeyRejectedException(
        first.text ?? first.name ?? 'debrid key rejected',
        uri: uri,
      );
    }
    return real.length == items.length ? items : List.unmodifiable(real);
  }, notFound: const []);

  /// Subtitles for video [id]; the optional file details help the addon
  /// match exactly.
  Future<List<SubtitleItem>> subtitles(
    Addon addon,
    String type,
    String id, {
    String? videoHash,
    int? videoSize,
    String? filename,
    Future<void>? cancel,
  }) => _fetch(
    'subtitles',
    addon.resourceUrl(
      'subtitles',
      type,
      id,
      extra: {
        'videoHash': ?videoHash,
        if (videoSize != null) 'videoSize': '$videoSize',
        'filename': ?filename,
      },
    ),
    cancel,
    (json, _) => _list(json, 'subtitles', SubtitleItem.tryParse),
    notFound: const [],
  );

  /// Closes the HTTP client if this instance created it.
  void close() {
    if (_ownsHttp) _http.close();
  }

  Future<T> _fetch<T extends Object>(
    String resource,
    Uri uri,
    Future<void>? cancel,
    T Function(Object? json, Uri uri) parse, {
    T? notFound,
  }) async {
    final key = uri.toString();
    final hit = cache?.get<T>(key);
    if (hit != null) return hit;
    final Object? json;
    try {
      json = await _getJson(uri, cancel);
    } on AddonHttpException catch (e) {
      // A 404 from a list resource means "nothing for this id".
      if (e.statusCode == 404 && notFound != null) return notFound;
      rethrow;
    }
    final T value;
    try {
      value = parse(json, uri);
    } on AddonResponseException catch (e) {
      throw AddonResponseException(e.message, uri: uri);
    }
    cache?.put(key, value, cache!.ttlFor(resource));
    return value;
  }

  Future<Object?> _getJson(Uri uri, Future<void>? cancel) async {
    var retries = 0;
    var browser = false;
    while (true) {
      final http.Response res;
      try {
        res = await _send(uri, browser ? _browserUserAgent : userAgent, cancel);
      } on AddonTimeoutException {
        if (retries >= maxRetries) rethrow;
        await _pause(_backoff(retries++, null), uri, cancel);
        continue;
      }
      final code = res.statusCode;
      if (code == 403 && !browser) {
        browser = true;
        continue;
      }
      if ((code == 429 || code >= 500) && retries < maxRetries) {
        await _pause(
          _backoff(retries++, res.headers['retry-after']),
          uri,
          cancel,
        );
        continue;
      }
      if (code < 200 || code >= 300) throw AddonHttpException(code, uri);
      try {
        return jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
      } on FormatException {
        throw AddonResponseException('invalid JSON', uri: uri);
      }
    }
  }

  Future<http.Response> _send(Uri uri, String ua, Future<void>? cancel) async {
    final abort = Completer<void>();
    var timedOut = false;
    final timer = Timer(timeout, () {
      timedOut = true;
      if (!abort.isCompleted) abort.complete();
    });
    if (cancel != null) {
      _whenDone(cancel, () {
        if (!abort.isCompleted) abort.complete();
      });
    }
    final request =
        http.AbortableRequest('GET', uri, abortTrigger: abort.future)
          ..headers['User-Agent'] = ua
          ..headers['Accept'] = 'application/json';
    try {
      // Racing the abort keeps timeouts working with clients that ignore
      // abortTrigger (e.g. MockClient).
      return await Future.any([
        _http.send(request).then(http.Response.fromStream),
        abort.future.then<http.Response>((_) => throw const _Aborted()),
      ]);
    } on _Aborted {
      throw _abortError(timedOut, uri);
    } on http.RequestAbortedException {
      throw _abortError(timedOut, uri);
    } on http.ClientException catch (e) {
      throw AddonNetworkException(e.message, uri: uri);
    } on Exception catch (e) {
      throw AddonNetworkException('$e', uri: uri);
    } finally {
      timer.cancel();
    }
  }

  StremioException _abortError(bool timedOut, Uri uri) => timedOut
      ? AddonTimeoutException(timeout, uri: uri)
      : AddonCancelledException(uri: uri);

  Duration _backoff(int retry, String? retryAfter) {
    final seconds = int.tryParse(retryAfter?.trim() ?? '');
    final wanted = seconds != null
        ? Duration(seconds: seconds)
        : retryDelay * (1 << retry);
    return wanted > maxRetryDelay ? maxRetryDelay : wanted;
  }

  Future<void> _pause(Duration delay, Uri uri, Future<void>? cancel) async {
    var cancelled = false;
    final done = Completer<void>();
    final timer = Timer(delay, () {
      if (!done.isCompleted) done.complete();
    });
    if (cancel != null) {
      _whenDone(cancel, () {
        cancelled = true;
        if (!done.isCompleted) done.complete();
      });
    }
    await done.future;
    timer.cancel();
    if (cancelled) throw AddonCancelledException(uri: uri);
  }
}

final class _Aborted implements Exception {
  const _Aborted();
}

void _whenDone(Future<void> future, void Function() callback) => unawaited(
  future.then((_) => callback(), onError: (Object _) => callback()),
);

List<T> _list<T>(Object? json, String key, T? Function(Object?) parse) {
  final value = jsonObject(json, 'response')[key];
  if (value == null) return const [];
  if (value is! List<Object?>) {
    throw AddonResponseException('"$key" is not a list');
  }
  return List<T>.unmodifiable(value.map(parse).nonNulls);
}

MetaPreview? _tryPreview(Object? json) {
  try {
    return MetaPreview.fromJson(json);
  } on AddonResponseException {
    return null;
  }
}
