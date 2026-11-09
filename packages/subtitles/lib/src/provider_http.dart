import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io' show HttpDate, HttpException;
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import 'cancel.dart';
import 'errors.dart';

/// Returns the current time; injectable for tests.
typedef Clock = DateTime Function();

/// Waits for a duration; injectable so tests don't sleep.
typedef Sleep = Future<void> Function(Duration);

Future<void> _realSleep(Duration d) => Future<void>.delayed(d);

/// Shared HTTP plumbing for one provider: per-request timeout, bounded
/// retries with exponential backoff on 429/5xx/network errors, Retry-After,
/// a per-provider concurrency limit and minimum spacing, and cancellation.
final class ProviderHttp {
  ProviderHttp({
    required this.providerId,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
    this.maxRetries = 2,
    this.maxConcurrent = 4,
    this.minInterval = Duration.zero,
    this.maxRetryWait = const Duration(seconds: 20),
    Clock? clock,
    Sleep? sleep,
  }) : _client = client ?? http.Client(),
       clock = clock ?? DateTime.now,
       _sleep = sleep ?? _realSleep;

  final String providerId;
  final http.Client _client;

  /// Deadline for one request (connect + full body).
  final Duration timeout;

  /// Extra attempts after the first on 429/5xx/network errors.
  final int maxRetries;

  /// Requests in flight at once for this provider.
  final int maxConcurrent;

  /// Minimum gap between request starts (provider rate limits).
  final Duration minInterval;

  /// Longer Retry-After waits fail fast with [SubtitleRateLimitException].
  final Duration maxRetryWait;

  final Clock clock;
  final Sleep _sleep;

  int _active = 0;
  final Queue<Completer<void>> _waiters = Queue();
  DateTime? _nextStart;
  DateTime? _blockedUntil;

  /// Sends a request and returns the successful (2xx) response, or one whose
  /// status is in [passStatuses] (for provider-specific error bodies).
  ///
  /// Throws a [SubtitleException] for every failure. [body] may be a String,
  /// bytes, or a JSON-encodable map (sent as JSON).
  Future<http.Response> send(
    String method,
    Uri url, {
    Map<String, String> headers = const {},
    Object? body,
    CancelToken? cancel,
    Set<int> passStatuses = const {},
  }) async {
    for (var attempt = 0; ; attempt++) {
      cancel?.throwIfCancelled(providerId: providerId);
      Duration? wait;
      try {
        final res = await _guarded(
          () => _once(method, url, headers, body, cancel),
        );
        if ((res.statusCode >= 200 && res.statusCode < 300) ||
            passStatuses.contains(res.statusCode)) {
          return res;
        }
        final retryable = res.statusCode == 429 || res.statusCode >= 500;
        if (!retryable || attempt >= maxRetries) throw _statusError(res);
        if (res.statusCode == 429) {
          wait = retryAfter(res) ?? _backoff(attempt);
          if (wait > maxRetryWait) {
            _blockedUntil = clock().add(wait);
            throw _statusError(res);
          }
        }
      } on SubtitleNetworkException {
        if (attempt >= maxRetries || (cancel?.isCancelled ?? false)) rethrow;
      }
      await _cancellableSleep(wait ?? _backoff(attempt), cancel);
    }
  }

  /// [send] and decode the body as JSON.
  Future<Object?> json(
    String method,
    Uri url, {
    Map<String, String> headers = const {},
    Object? body,
    CancelToken? cancel,
  }) async {
    final res = await send(
      method,
      url,
      headers: {'Accept': 'application/json', ...headers},
      body: body,
      cancel: cancel,
    );
    return decodeJson(res);
  }

  /// Decodes a JSON body or throws [SubtitleResponseException].
  Object? decodeJson(http.Response res) {
    try {
      return jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
    } on FormatException {
      throw SubtitleResponseException(
        'invalid JSON from ${res.request?.url.host}',
        providerId: providerId,
      );
    }
  }

  /// Closes the underlying client.
  void close() => _client.close();

  Duration _backoff(int attempt) =>
      Duration(milliseconds: math.min(8000, 500 * (1 << attempt)));

  /// Parses Retry-After (seconds or HTTP date) and common rate-limit headers.
  Duration? retryAfter(http.Response res) {
    final h = res.headers;
    final ra = h['retry-after'];
    if (ra != null) {
      final secs = double.tryParse(ra.trim());
      if (secs != null) return Duration(milliseconds: (secs * 1000).ceil());
      try {
        final d = HttpDate.parse(ra).difference(clock());
        return d.isNegative ? Duration.zero : d;
      } on FormatException {
        // fall through to other headers
      } on HttpException {
        // fall through
      }
    }
    for (final name in const ['x-ratelimit-reset-after', 'ratelimit-reset']) {
      final secs = double.tryParse(h[name]?.trim() ?? '');
      if (secs != null) return Duration(milliseconds: (secs * 1000).ceil());
    }
    // SubSource puts it in the JSON body: {"retryAfter": 12}.
    final inBody = RegExp(
      r'"retry_?after"\s*:\s*"?(\d+(?:\.\d+)?)',
      caseSensitive: false,
    ).firstMatch(utf8.decode(res.bodyBytes, allowMalformed: true));
    final secs = double.tryParse(inBody?.group(1) ?? '');
    return secs == null ? null : Duration(milliseconds: (secs * 1000).ceil());
  }

  SubtitleException _statusError(http.Response res) {
    final code = res.statusCode;
    final detail = _snippet(res);
    return switch (code) {
      401 ||
      403 => SubtitleAuthException('HTTP $code$detail', providerId: providerId),
      429 => SubtitleRateLimitException(
        'HTTP 429$detail',
        providerId: providerId,
        retryAfter: retryAfter(res),
      ),
      _ => SubtitleHttpException(
        'HTTP $code$detail',
        providerId: providerId,
        statusCode: code,
      ),
    };
  }

  String _snippet(http.Response res) {
    final text = utf8.decode(res.bodyBytes, allowMalformed: true).trim();
    if (text.isEmpty || text.startsWith('<')) return '';
    // Some providers echo the key in URLs (SubDL); keep it out of messages.
    final safe = text.replaceAllMapped(
      RegExp(r'((?:api_?key|key|token|tok)=)[^&\s"]+', caseSensitive: false),
      (m) => '${m[1]}***',
    );
    return ': ${safe.length > 200 ? '${safe.substring(0, 200)}…' : safe}';
  }

  Future<T> _guarded<T>(Future<T> Function() run) async {
    final blocked = _blockedUntil;
    if (blocked != null && blocked.isAfter(clock())) {
      throw SubtitleRateLimitException(
        'rate limited',
        providerId: providerId,
        retryAfter: blocked.difference(clock()),
      );
    }
    if (_active >= maxConcurrent) {
      final c = Completer<void>();
      _waiters.add(c);
      await c.future;
    }
    _active++;
    try {
      if (minInterval > Duration.zero) {
        final now = clock();
        final next = _nextStart;
        _nextStart = (next != null && next.isAfter(now) ? next : now).add(
          minInterval,
        );
        if (next != null && next.isAfter(now)) {
          await _sleep(next.difference(now));
        }
      }
      return await run();
    } finally {
      _active--;
      if (_waiters.isNotEmpty) _waiters.removeFirst().complete();
    }
  }

  Future<http.Response> _once(
    String method,
    Uri url,
    Map<String, String> headers,
    Object? body,
    CancelToken? cancel,
  ) async {
    final abort = Completer<void>();
    var timedOut = false;
    final timer = Timer(timeout, () {
      timedOut = true;
      if (!abort.isCompleted) abort.complete();
    });
    unawaited(
      cancel?.whenCancelled.then((_) {
        if (!abort.isCompleted) abort.complete();
      }),
    );
    final req = http.AbortableRequest(method, url, abortTrigger: abort.future)
      ..headers.addAll(headers);
    if (body is String) {
      req.body = body;
    } else if (body is List<int>) {
      req.bodyBytes = body;
    } else if (body != null) {
      req.headers.putIfAbsent('Content-Type', () => 'application/json');
      req.body = jsonEncode(body);
    }
    try {
      final run = _client.send(req).then(http.Response.fromStream);
      return await Future.any([
        run,
        abort.future.then<http.Response>((_) => throw const _Aborted()),
      ]);
    } on _Aborted {
      if (timedOut) {
        throw SubtitleNetworkException(
          'timed out after ${timeout.inSeconds}s: ${url.host}',
          providerId: providerId,
          isTimeout: true,
        );
      }
      throw SubtitleCancelledException(providerId: providerId);
    } on http.RequestAbortedException {
      if (timedOut) {
        throw SubtitleNetworkException(
          'timed out: ${url.host}',
          providerId: providerId,
          isTimeout: true,
        );
      }
      throw SubtitleCancelledException(providerId: providerId);
    } on http.ClientException catch (e) {
      throw SubtitleNetworkException(
        '${url.host}: ${e.message}',
        providerId: providerId,
      );
    } on SubtitleException {
      rethrow;
    } on Exception catch (e) {
      // SocketException, HandshakeException, TlsException ...
      throw SubtitleNetworkException(
        '${url.host}: ${e.runtimeType}',
        providerId: providerId,
      );
    } finally {
      timer.cancel();
    }
  }

  Future<void> _cancellableSleep(Duration d, CancelToken? cancel) async {
    if (cancel == null) return _sleep(d);
    await Future.any([_sleep(d), cancel.whenCancelled]);
    cancel.throwIfCancelled(providerId: providerId);
  }
}

final class _Aborted implements Exception {
  const _Aborted();
}

/// Reads a `filename=` from a Content-Disposition header.
String? contentDispositionFileName(String? header) {
  if (header == null) return null;
  final star = RegExp(
    r"filename\*\s*=\s*[^']*'[^']*'([^;]+)",
    caseSensitive: false,
  ).firstMatch(header);
  if (star != null) return Uri.decodeComponent(star.group(1)!.trim());
  final plain = RegExp(
    r'filename\s*=\s*"?([^";]+)"?',
    caseSensitive: false,
  ).firstMatch(header);
  return plain?.group(1)?.trim();
}
