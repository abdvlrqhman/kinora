import 'dart:async';

import 'addon.dart';
import 'client.dart';
import 'errors.dart';
import 'json.dart';
import 'meta.dart';
import 'stream.dart';
import 'subtitle.dart';

/// What one addon returned for an aggregated request.
final class AddonResult<T> {
  /// Creates a result.
  const AddonResult({
    required this.addon,
    required this.items,
    required this.elapsed,
    this.error,
  });

  /// The addon that answered.
  final Addon addon;

  /// Items it returned; empty on error.
  final List<T> items;

  /// Why it failed, or null on success.
  final StremioException? error;

  /// Time from request start to answer or failure.
  final Duration elapsed;

  /// Whether the addon answered successfully.
  bool get isSuccess => error == null;

  @override
  bool operator ==(Object other) =>
      other is AddonResult<T> &&
      other.addon == addon &&
      listEquals(other.items, items) &&
      other.error == error &&
      other.elapsed == elapsed;

  @override
  int get hashCode => Object.hash(addon, Object.hashAll(items), error, elapsed);

  @override
  String toString() =>
      'AddonResult(${addon.manifest.name}, ${items.length} items'
      '${error == null ? '' : ', $error'}, ${elapsed.inMilliseconds} ms)';
}

/// Rolling health of one addon, for a settings screen.
final class AddonHealth {
  /// Creates a health record.
  const AddonHealth({
    this.lastLatency,
    this.consecutiveFailures = 0,
    this.lastError,
    this.lastCheckedAt,
  });

  /// Latency of the most recent request (success or failure).
  final Duration? lastLatency;

  /// Failures since the last success.
  final int consecutiveFailures;

  /// Most recent error (kept after a later success).
  final StremioException? lastError;

  /// When the most recent request finished.
  final DateTime? lastCheckedAt;

  /// Whether the most recent request succeeded.
  bool get isHealthy => consecutiveFailures == 0;

  @override
  bool operator ==(Object other) =>
      other is AddonHealth &&
      other.lastLatency == lastLatency &&
      other.consecutiveFailures == consecutiveFailures &&
      other.lastError == lastError &&
      other.lastCheckedAt == lastCheckedAt;

  @override
  int get hashCode =>
      Object.hash(lastLatency, consecutiveFailures, lastError, lastCheckedAt);

  @override
  String toString() =>
      'AddonHealth(${lastLatency?.inMilliseconds} ms, '
      'failures: $consecutiveFailures, lastError: $lastError)';
}

/// An aggregated request in flight.
final class AggregatedQuery<T> {
  AggregatedQuery._(this.results, this.merged);

  /// One event per queried addon, in arrival order; closes when all have
  /// answered, failed or timed out. Single-subscription; events are buffered
  /// until listened to.
  final Stream<AddonResult<T>> results;

  /// Every addon's items merged and de-duplicated, in addon order.
  /// Never completes with an error.
  final Future<List<T>> merged;
}

/// Fans a request out to every addon that supports it, in parallel.
///
/// Slow addons never block the others: each gets [perAddonTimeout] (retries
/// included), after which its result carries an [AddonTimeoutException].
final class AddonAggregator {
  /// Creates an aggregator that sends requests through the given client.
  AddonAggregator(
    this._client, {
    this.perAddonTimeout = const Duration(seconds: 12),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AddonClient _client;
  final DateTime Function() _clock;
  final _health = <Uri, AddonHealth>{};

  /// Total time one addon may take, retries included.
  final Duration perAddonTimeout;

  /// Health per addon, keyed by [Addon.transportUrl].
  Map<Uri, AddonHealth> get health => Map.unmodifiable(_health);

  /// Streams for video [id] from every addon with a matching `stream`
  /// resource. Merged results are de-duplicated with [dedupeStreams].
  AggregatedQuery<StreamItem> streams(
    Iterable<Addon> addons,
    String type,
    String id, {
    Future<void>? cancel,
  }) => _run(
    addons.where((a) => a.supports('stream', type, id)),
    (a, c) => _client.streams(a, type, id, cancel: c),
    dedupeStreams,
    cancel,
  );

  /// Subtitles for video [id] from every addon with a matching `subtitles`
  /// resource, de-duplicated by URL.
  AggregatedQuery<SubtitleItem> subtitles(
    Iterable<Addon> addons,
    String type,
    String id, {
    String? videoHash,
    int? videoSize,
    String? filename,
    Future<void>? cancel,
  }) => _run(
    addons.where((a) => a.supports('subtitles', type, id)),
    (a, c) => _client.subtitles(
      a,
      type,
      id,
      videoHash: videoHash,
      videoSize: videoSize,
      filename: filename,
      cancel: c,
    ),
    (items) => _dedupeBy(items, (s) => s.url),
    cancel,
  );

  /// Searches every catalog of [type] that declares the `search` extra,
  /// de-duplicated by meta id.
  AggregatedQuery<MetaPreview> search(
    Iterable<Addon> addons,
    String type,
    String query, {
    Future<void>? cancel,
  }) {
    List<String> searchable(Addon a) => [
      for (final c in a.manifest.catalogs)
        if (c.type == type && c.supportsExtra('search')) c.id,
    ];
    return _run(
      addons.where((a) => searchable(a).isNotEmpty),
      (a, c) async => [
        for (final page in await Future.wait([
          for (final id in searchable(a))
            _client.catalog(a, type, id, extra: {'search': query}, cancel: c),
        ]))
          ...page,
      ],
      (items) => _dedupeBy(items, (m) => m.id),
      cancel,
    );
  }

  AggregatedQuery<T> _run<T>(
    Iterable<Addon> addons,
    Future<List<T>> Function(Addon addon, Future<void> cancel) fetch,
    List<T> Function(Iterable<T>) merge,
    Future<void>? cancel,
  ) {
    final controller = StreamController<AddonResult<T>>();
    final pending = [
      for (final addon in addons)
        _one(addon, fetch, cancel).then((r) {
          controller.add(r);
          return r;
        }),
    ];
    final merged = Future.wait(pending).then((results) {
      unawaited(controller.close());
      return merge(results.expand((r) => r.items));
    });
    return AggregatedQuery._(controller.stream, merged);
  }

  Future<AddonResult<T>> _one<T>(
    Addon addon,
    Future<List<T>> Function(Addon addon, Future<void> cancel) fetch,
    Future<void>? outerCancel,
  ) async {
    final stop = Completer<void>();
    var timedOut = false;
    var cancelled = false;
    final timer = Timer(perAddonTimeout, () {
      timedOut = true;
      if (!stop.isCompleted) stop.complete();
    });
    if (outerCancel != null) {
      unawaited(
        outerCancel.then(
          (_) {
            cancelled = true;
            if (!stop.isCompleted) stop.complete();
          },
          onError: (Object _) {
            cancelled = true;
            if (!stop.isCompleted) stop.complete();
          },
        ),
      );
    }
    final watch = Stopwatch()..start();
    List<T> items = const [];
    StremioException? error;
    try {
      items = await fetch(addon, stop.future);
    } on StremioException catch (e) {
      error = timedOut && !cancelled
          ? AddonTimeoutException(perAddonTimeout, uri: e.uri)
          : e;
    } on Object catch (e) {
      // A bug or a response shape the parsers did not foresee must not take
      // the whole aggregation down.
      error = AddonResponseException('unexpected failure: $e');
    } finally {
      timer.cancel();
      if (!stop.isCompleted) stop.complete();
    }
    final elapsed = watch.elapsed;
    if (!cancelled) {
      final previous = _health[addon.transportUrl] ?? const AddonHealth();
      _health[addon.transportUrl] = AddonHealth(
        lastLatency: elapsed,
        consecutiveFailures: error == null
            ? 0
            : previous.consecutiveFailures + 1,
        lastError: error ?? previous.lastError,
        lastCheckedAt: _clock(),
      );
    }
    return AddonResult(
      addon: addon,
      items: items,
      error: error,
      elapsed: elapsed,
    );
  }
}

List<T> _dedupeBy<T>(Iterable<T> items, String Function(T) key) {
  final seen = <String>{};
  return List.unmodifiable(items.where((i) => seen.add(key(i))));
}
