import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

String hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// In-process BEP 15 tracker on a loopback UDP socket.
final class FakeUdpTracker {
  FakeUdpTracker._(this._socket, this.stats) {
    _socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      for (var d = _socket.receive(); d != null; d = _socket.receive()) {
        unawaited(_handle(d));
      }
    });
  }

  static Future<FakeUdpTracker> start(
    Map<String, (int seeders, int completed, int leechers)> stats, {
    InternetAddress? host,
  }) async => FakeUdpTracker._(
    await RawDatagramSocket.bind(host ?? InternetAddress.loopbackIPv4, 0),
    stats,
  );

  final RawDatagramSocket _socket;
  final Map<String, (int, int, int)> stats;
  static const _connectionId = 0x1122334455667788;

  int connects = 0;
  final scrapeBatchSizes = <int>[];

  /// Packets to ignore before answering (forces a retransmit).
  int dropFirst = 0;

  /// Never answer.
  bool silent = false;

  /// Send junk (short packet, unknown transaction id, other action) first.
  bool garbageFirst = false;

  /// Answer scrapes with an error (action 3).
  bool errorOnScrape = false;

  /// Answer scrapes with a connect-shaped reply for the right transaction.
  bool wrongActionOnScrape = false;

  /// Only return this many rows per scrape.
  int? truncateTo;

  Duration delay = Duration.zero;

  Uri get url => Uri.parse(
    _socket.address.type == InternetAddressType.IPv6
        ? 'udp://[${_socket.address.address}]:${_socket.port}/announce'
        : 'udp://${_socket.address.address}:${_socket.port}/announce',
  );

  void close() => _socket.close();

  Future<void> _handle(Datagram d) async {
    if (silent) return;
    if (dropFirst > 0) {
      dropFirst--;
      return;
    }
    final data = d.data;
    if (data.length < 16) return;
    final view = ByteData.sublistView(data);
    final action = view.getUint32(8);
    final tid = view.getUint32(12);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    void send(List<int> bytes) =>
        _socket.send(Uint8List.fromList(bytes), d.address, d.port);
    if (garbageFirst) {
      send([1, 2, 3]);
      send(_header(0, tid ^ 0xffff) + _int64(_connectionId));
    }
    if (action == 0 && view.getInt64(0) == 0x41727101980) {
      connects++;
      send(_header(0, tid) + _int64(_connectionId));
      return;
    }
    if (action != 2 || view.getInt64(0) != _connectionId) return;
    final count = (data.length - 16) ~/ 20;
    scrapeBatchSizes.add(count);
    if (errorOnScrape) {
      send(_header(3, tid) + utf8.encode('Connection ID missmatch.'));
      return;
    }
    if (wrongActionOnScrape) {
      send(_header(0, tid) + _int64(_connectionId));
      return;
    }
    final rows = <int>[];
    for (var i = 0; i < (truncateTo ?? count); i++) {
      final h = hex(data.sublist(16 + 20 * i, 36 + 20 * i));
      final (s, c, l) = stats[h] ?? (0, 0, 0);
      rows.addAll(_int32(s) + _int32(c) + _int32(l));
    }
    send(_header(2, tid) + rows);
  }

  static List<int> _header(int action, int tid) => _int32(action) + _int32(tid);

  static List<int> _int32(int v) =>
      (ByteData(4)..setUint32(0, v & 0xffffffff)).buffer.asUint8List();

  static List<int> _int64(int v) =>
      (ByteData(8)..setInt64(0, v)).buffer.asUint8List();
}

/// In-process HTTP tracker answering `/scrape` (and `/scrape.php`).
final class FakeHttpTracker {
  FakeHttpTracker._(this._server, this.stats) {
    _server.listen((request) async {
      requests.add(request.uri);
      final path = request.uri.path;
      if (!path.endsWith('/scrape') && !path.endsWith('/scrape.php')) {
        request.response.statusCode = 404;
        await request.response.close();
        return;
      }
      final hashes = [
        for (final pair in request.uri.query.split('&'))
          if (pair.startsWith('info_hash='))
            hex(_percentBytes(pair.substring(10))),
      ];
      final files = <List<int>, Object>{
        for (final h in hashes)
          if (stats[h] case (final s, final c, final l))
            _hexBytes(h): {'complete': s, 'downloaded': c, 'incomplete': l},
      };
      request.response.add(bencode({'files': files}));
      await request.response.close();
    });
  }

  static Future<FakeHttpTracker> start(
    Map<String, (int seeders, int completed, int leechers)> stats,
  ) async => FakeHttpTracker._(
    await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    stats,
  );

  final HttpServer _server;
  final Map<String, (int, int, int)> stats;
  final requests = <Uri>[];

  Uri announce([String path = '/announce']) =>
      Uri.parse('http://127.0.0.1:${_server.port}$path');

  Future<void> close() => _server.close(force: true);

  static List<int> _percentBytes(String s) {
    final out = <int>[];
    for (var i = 0; i < s.length; i++) {
      if (s[i] == '%') {
        out.add(int.parse(s.substring(i + 1, i + 3), radix: 16));
        i += 2;
      } else {
        out.add(s.codeUnitAt(i));
      }
    }
    return out;
  }

  static List<int> _hexBytes(String h) => [
    for (var i = 0; i < h.length; i += 2)
      int.parse(h.substring(i, i + 2), radix: 16),
  ];
}

/// Minimal bencode encoder for test fixtures. Dict keys may be strings or
/// raw byte lists.
List<int> bencode(Object value) => switch (value) {
  final int i => ascii.encode('i${i}e'),
  final String s => bencode(utf8.encode(s)),
  final List<int> b => [...ascii.encode('${b.length}:'), ...b],
  final List<Object> l => [
    ...ascii.encode('l'),
    for (final e in l) ...bencode(e),
    ...ascii.encode('e'),
  ],
  final Map<Object, Object> m => [
    ...ascii.encode('d'),
    for (final e in m.entries) ...[...bencode(e.key), ...bencode(e.value)],
    ...ascii.encode('e'),
  ],
  _ => throw ArgumentError.value(value),
};
