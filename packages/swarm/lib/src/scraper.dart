import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'bencode.dart';
import 'info_hash.dart';
import 'tracker_list.dart';

/// Live swarm numbers for one torrent, merged over trackers.
final class SwarmStats {
  /// Creates stats.
  const SwarmStats({
    required this.seeders,
    required this.leechers,
    required this.completed,
    required this.sources,
  });

  /// Peers with the whole torrent (max over trackers).
  final int seeders;

  /// Peers still downloading (max over trackers).
  final int leechers;

  /// Completed downloads ever reported (max over trackers).
  final int completed;

  /// How many trackers answered for this torrent.
  final int sources;

  @override
  bool operator ==(Object other) =>
      other is SwarmStats &&
      other.seeders == seeders &&
      other.leechers == leechers &&
      other.completed == completed &&
      other.sources == sources;

  @override
  int get hashCode => Object.hash(seeders, leechers, completed, sources);

  @override
  String toString() =>
      'SwarmStats(seeders: $seeders, leechers: $leechers, '
      'completed: $completed, sources: $sources)';
}

/// Asks BitTorrent trackers how many peers torrents have right now.
///
/// UDP trackers use BEP 15 (connect, then scrape up to
/// [maxHashesPerPacket] hashes per packet, one retransmit, connection ids
/// reused for a minute). HTTP(S) trackers use the `/announce` → `/scrape`
/// convention with a bencoded answer. All trackers are queried at once and
/// whatever arrived by the deadline is returned.
final class TrackerScraper {
  /// Creates a scraper. [httpClient] is closed by [close] only if this
  /// instance created it.
  TrackerScraper({
    http.Client? httpClient,
    this.udpRetransmitAfter = const Duration(milliseconds: 1000),
    this.userAgent = 'Kinora/0.1.0',
    DateTime Function()? clock,
    Random? random,
  }) : _http = httpClient ?? http.Client(),
       _ownsHttp = httpClient == null,
       _clock = clock ?? DateTime.now,
       _random = random ?? Random();

  /// BEP 15 notes ~74 hashes fit one UDP packet.
  static const maxHashesPerPacket = 74;

  // BEP 15: a connection id may be used for one minute.
  static const _connectionIdLifetime = Duration(minutes: 1);

  final http.Client _http;
  final bool _ownsHttp;
  final DateTime Function() _clock;
  final Random _random;
  final _connections = <String, (int, DateTime)>{};

  /// Wait before resending an unanswered UDP packet (sent at most twice).
  final Duration udpRetransmitAfter;

  /// `User-Agent` for HTTP trackers.
  final String userAgent;

  /// Scrapes [infoHashes] (hex or base32) on [trackers] (default
  /// [defaultTrackers]).
  ///
  /// Returns at the latest after [timeout] or when [cancel] completes, with
  /// stats for every hash at least one tracker answered for, keyed by
  /// lowercase hex. Invalid hashes and unsupported tracker URLs are ignored.
  /// Never throws.
  Future<Map<String, SwarmStats>> scrape(
    Iterable<String> infoHashes, {
    List<Uri>? trackers,
    Duration timeout = const Duration(milliseconds: 2500),
    Future<void>? cancel,
  }) async {
    final hashes = {for (final h in infoHashes) ?normalizeInfoHash(h)}.toList();
    final targets = {...(trackers ?? defaultTrackers)};
    if (hashes.isEmpty || targets.isEmpty) return const {};
    final batches = [
      for (var i = 0; i < hashes.length; i += maxHashesPerPacket)
        hashes.sublist(i, min(i + maxHashesPerPacket, hashes.length)),
    ];
    final run = _Run();
    final deadline = Timer(timeout, run.finish);
    if (cancel != null) {
      unawaited(
        cancel.then((_) => run.finish(), onError: (Object _) => run.finish()),
      );
    }
    final work = Future.wait([
      for (final t in targets)
        _ignoreErrors(switch (t.scheme) {
          'udp' => _scrapeUdp(t, batches, run),
          'http' || 'https' => _scrapeHttp(t, batches, run),
          _ => Future<void>.value(),
        }),
    ]);
    await Future.any([work, run.stopped]);
    deadline.cancel();
    run.finish();
    return run.results();
  }

  /// Closes the HTTP client if this instance created it.
  void close() {
    if (_ownsHttp) _http.close();
  }

  Future<void> _scrapeUdp(
    Uri tracker,
    List<List<String>> batches,
    _Run run,
  ) async {
    if (!tracker.hasPort) return;
    final address = await _resolve(tracker.host);
    if (address == null || run.done) return;
    final socket = await RawDatagramSocket.bind(
      address.type == InternetAddressType.IPv6
          ? InternetAddress.anyIPv6
          : InternetAddress.anyIPv4,
      0,
    );
    final session = _UdpSession(
      socket,
      address,
      tracker.port,
      udpRetransmitAfter,
      _random,
    );
    if (!run.track(session.close)) return;
    try {
      final key = '${address.address}:${tracker.port}';
      final cached = _connections[key];
      final int connectionId;
      if (cached != null &&
          _clock().difference(cached.$2) < _connectionIdLifetime) {
        connectionId = cached.$1;
      } else {
        final at = _clock();
        connectionId = await session.connect();
        _connections[key] = (connectionId, at);
      }
      await Future.wait([
        for (final batch in batches)
          _ignoreErrors(() async {
            try {
              final rows = await session.scrape(connectionId, batch);
              for (var i = 0; i < rows.length; i++) {
                run.add(batch[i], rows[i].$1, rows[i].$3, rows[i].$2);
              }
            } on _TrackerError catch (e) {
              // An error reply may mean the connection id expired.
              if (e.fromTracker) _connections.remove(key);
              rethrow;
            }
          }()),
      ]);
    } finally {
      session.close();
    }
  }

  Future<void> _scrapeHttp(
    Uri tracker,
    List<List<String>> batches,
    _Run run,
  ) async {
    final segments = tracker.path.split('/');
    if (!segments.last.startsWith('announce')) return;
    segments.last = 'scrape${segments.last.substring('announce'.length)}';
    final base = tracker.replace(path: segments.join('/')).toString();
    await Future.wait([
      for (final batch in batches)
        _ignoreErrors(() async {
          final query = [
            for (final h in batch)
              'info_hash=${infoHashBytes(h).map((b) => '%${b.toRadixString(16).padLeft(2, '0')}').join()}',
          ].join('&');
          final request = http.AbortableRequest(
            'GET',
            Uri.parse('$base${base.contains('?') ? '&' : '?'}$query'),
            abortTrigger: run.stopped,
          )..headers['User-Agent'] = userAgent;
          final response = await http.Response.fromStream(
            await _http.send(request),
          );
          if (response.statusCode != 200) return;
          if (bdecode(response.bodyBytes) case {
            'files': final Map<String, Object> files,
          }) {
            for (final MapEntry(:key, :value) in files.entries) {
              final hash = toHex(latin1.encode(key));
              if (!batch.contains(hash) || value is! Map<String, Object>) {
                continue;
              }
              int field(String name) => switch (value[name]) {
                final int n when n > 0 => n,
                _ => 0,
              };
              run.add(
                hash,
                field('complete'),
                field('incomplete'),
                field('downloaded'),
              );
            }
          }
        }()),
    ]);
  }

  Future<InternetAddress?> _resolve(String host) async {
    final literal = InternetAddress.tryParse(host);
    if (literal != null) return literal;
    try {
      final all = await InternetAddress.lookup(host);
      return all.firstWhere(
        (a) => a.type == InternetAddressType.IPv4,
        orElse: () => all.first,
      );
    } on Exception {
      return null;
    }
  }
}

/// State of one [TrackerScraper.scrape] call.
final class _Run {
  final _stats = <String, (int, int, int, int)>{};
  final _closers = <void Function()>[];
  final _stopped = Completer<void>();

  bool get done => _stopped.isCompleted;

  Future<void> get stopped => _stopped.future;

  /// Registers a cleanup; runs it now and returns false if already done.
  bool track(void Function() close) {
    if (done) {
      close();
      return false;
    }
    _closers.add(close);
    return true;
  }

  void add(String hash, int seeders, int leechers, int completed) {
    if (done) return;
    final (s, l, c, n) = _stats[hash] ?? (0, 0, 0, 0);
    _stats[hash] = (
      max(s, seeders),
      max(l, leechers),
      max(c, completed),
      n + 1,
    );
  }

  void finish() {
    if (done) return;
    _stopped.complete();
    for (final close in _closers) {
      close();
    }
  }

  Map<String, SwarmStats> results() => Map.unmodifiable({
    for (final MapEntry(:key, value: (s, l, c, n)) in _stats.entries)
      key: SwarmStats(seeders: s, leechers: l, completed: c, sources: n),
  });
}

final class _TrackerError implements Exception {
  const _TrackerError(this.message, {this.fromTracker = false});

  final String message;

  /// The tracker itself sent an error reply (action 3).
  final bool fromTracker;

  @override
  String toString() => 'tracker error: $message';
}

/// One UDP socket talking BEP 15 to one tracker. Replies are matched to
/// requests by transaction id; stray, foreign and short packets are dropped.
final class _UdpSession {
  _UdpSession(
    this._socket,
    this._address,
    this._port,
    this._retransmit,
    this._random,
  ) {
    _subscription = _socket.listen(_onEvent, onError: (Object _) {});
  }

  static const _protocolId = 0x41727101980;
  static const _connect = 0;
  static const _scrape = 2;
  static const _error = 3;

  final RawDatagramSocket _socket;
  final InternetAddress _address;
  final int _port;
  final Duration _retransmit;
  final Random _random;
  final _pending = <int, Completer<Uint8List>>{};
  late final StreamSubscription<RawSocketEvent> _subscription;
  var _closed = false;

  void _onEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    for (var d = _socket.receive(); d != null; d = _socket.receive()) {
      if (d.port != _port || d.address.address != _address.address) continue;
      if (d.data.length < 8) continue;
      final tid = ByteData.sublistView(d.data).getUint32(4);
      _pending.remove(tid)?.complete(d.data);
    }
  }

  Future<int> connect() async {
    final reply = await _request(
      _connect,
      16,
      (tid) =>
          (ByteData(16)
                ..setInt64(0, _protocolId)
                ..setUint32(8, _connect)
                ..setUint32(12, tid))
              .buffer
              .asUint8List(),
    );
    return ByteData.sublistView(reply).getInt64(8);
  }

  /// Rows of (seeders, completed, leechers) in [hashes] order; may be
  /// shorter than [hashes] if the tracker truncated its reply.
  Future<List<(int, int, int)>> scrape(
    int connectionId,
    List<String> hashes,
  ) async {
    final reply = await _request(_scrape, 8, (tid) {
      final packet = ByteData(16 + 20 * hashes.length)
        ..setInt64(0, connectionId)
        ..setUint32(8, _scrape)
        ..setUint32(12, tid);
      final bytes = packet.buffer.asUint8List();
      for (var i = 0; i < hashes.length; i++) {
        bytes.setAll(16 + 20 * i, infoHashBytes(hashes[i]));
      }
      return bytes;
    });
    final view = ByteData.sublistView(reply);
    final rows = min((reply.length - 8) ~/ 12, hashes.length);
    return [
      for (var i = 0; i < rows; i++)
        (
          max(0, view.getInt32(8 + 12 * i)),
          max(0, view.getInt32(12 + 12 * i)),
          max(0, view.getInt32(16 + 12 * i)),
        ),
    ];
  }

  Future<Uint8List> _request(
    int action,
    int minLength,
    Uint8List Function(int tid) build,
  ) async {
    if (_closed) throw const _TrackerError('closed');
    var tid = _random.nextInt(1 << 32);
    while (_pending.containsKey(tid)) {
      tid = _random.nextInt(1 << 32);
    }
    final packet = build(tid);
    final reply = Completer<Uint8List>();
    _pending[tid] = reply;
    try {
      for (var attempt = 0; ; attempt++) {
        _socket.send(packet, _address, _port);
        try {
          final data = await reply.future.timeout(_retransmit);
          final got = ByteData.sublistView(data).getUint32(0);
          if (got == _error) {
            throw _TrackerError(
              utf8.decode(data.sublist(8), allowMalformed: true),
              fromTracker: true,
            );
          }
          if (got != action || data.length < minLength) {
            throw const _TrackerError('malformed reply');
          }
          return data;
        } on TimeoutException {
          if (attempt >= 1) throw const _TrackerError('no reply');
        }
      }
    } finally {
      _pending.remove(tid);
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    for (final c in _pending.values) {
      c.completeError(const _TrackerError('closed'));
    }
    _pending.clear();
    unawaited(_subscription.cancel());
    _socket.close();
  }
}

Future<void> _ignoreErrors(Future<void> future) =>
    future.then((_) {}, onError: (Object _) {});
