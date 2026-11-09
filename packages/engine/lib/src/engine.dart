import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'bencode.dart';
import 'bindings.dart';
import 'models.dart';

/// A libtorrent session with a built-in HTTP streaming server.
///
/// All calls are synchronous and cheap (the native side caches status and
/// does slow work on its own threads). Create one per app; [dispose] saves
/// resume data and DHT state before shutting down.
final class KinoraEngine {
  KinoraEngine._(this._b, this._session);

  /// Starts a session. Throws [EngineException] when the native side refuses.
  factory KinoraEngine.start(EngineConfig config, {String? libraryPath}) {
    final b = EngineBindings(EngineBindings.open(libraryPath));
    final session = _withBytes(bencode(config.toMap()), (ptr, len) {
      final error = calloc<Pointer<Utf8>>();
      try {
        final s = b.sessionNew(ptr, len, error);
        if (s == nullptr) {
          throw EngineException(b.take(error.value) ?? 'session failed');
        }
        return s;
      } finally {
        calloc.free(error);
      }
    });
    return KinoraEngine._(b, session);
  }

  /// Native library version string.
  static String version({String? libraryPath}) {
    final b = EngineBindings(EngineBindings.open(libraryPath));
    return b.take(b.version()) ?? '';
  }

  final EngineBindings _b;
  Pointer<KnSession> _session;
  StreamController<EngineEvent>? _events;
  StreamController<List<TorrentStatus>>? _statuses;
  Timer? _eventTimer;
  Timer? _statusTimer;

  Pointer<KnSession> get _s {
    if (_session == nullptr) throw const EngineException('engine disposed');
    return _session;
  }

  /// Whether [dispose] ran.
  bool get isDisposed => _session == nullptr;

  /// Adds a torrent and returns its info-hash (idempotent for duplicates).
  String add(AddTorrent torrent) {
    final json = _withBytes(
      bencode(torrent.toMap()),
      (p, n) => _b.take(_b.add(_s, p, n)),
    );
    final map = _decodeObject(json);
    final ih = map['ih'];
    if (ih is String) return ih;
    throw EngineException(map['error']?.toString() ?? 'add failed');
  }

  /// Removes a torrent; [deleteFiles] also deletes its data.
  void remove(String infoHash, {bool deleteFiles = false}) => _check(
    _withStr(infoHash, (ih) => _b.remove(_s, ih, deleteFiles ? 1 : 0)),
  );

  /// Pauses gracefully and saves resume data.
  void pause(String infoHash) =>
      _check(_withStr(infoHash, (ih) => _b.pause(_s, ih)));

  /// Resumes a paused torrent.
  void resume(String infoHash) =>
      _check(_withStr(infoHash, (ih) => _b.resume(_s, ih)));

  /// Sets one priority (0 = skip … 7 = top) per file.
  void setFilePriorities(String infoHash, List<int> priorities) {
    final arr = calloc<Int32>(priorities.isEmpty ? 1 : priorities.length);
    try {
      for (var i = 0; i < priorities.length; i++) {
        arr[i] = priorities[i];
      }
      _check(
        _withStr(
          infoHash,
          (ih) => _b.setFilePriorities(_s, ih, arr, priorities.length),
        ),
      );
    } finally {
      calloc.free(arr);
    }
  }

  /// The torrent's files, or null until metadata arrives.
  List<TorrentFile>? files(String infoHash) {
    final json = _withStr(infoHash, (ih) => _b.take(_b.files(_s, ih)));
    if (json == null) return null;
    return [
      for (final f in jsonDecode(json) as List<Object?>)
        TorrentFile.fromJson(f! as Map<String, Object?>),
    ];
  }

  /// Latest status of every torrent.
  List<TorrentStatus> statuses() {
    final json = _b.take(_b.statusAll(_s));
    if (json == null) return const [];
    return [
      for (final s in jsonDecode(json) as List<Object?>)
        TorrentStatus.fromJson(s! as Map<String, Object?>),
    ];
  }

  /// Status of one torrent, if known.
  TorrentStatus? status(String infoHash) {
    for (final s in statuses()) {
      if (s.infoHash == infoHash) return s;
    }
    return null;
  }

  /// Events since the previous call. Prefer [events] unless polling yourself.
  List<EngineEvent> pollEvents() {
    final json = _b.take(_b.pollEvents(_s));
    if (json == null) return const [];
    return [
      for (final e in jsonDecode(json) as List<Object?>)
        EngineEvent.fromJson(e! as Map<String, Object?>),
    ];
  }

  /// Broadcast stream of engine events (polled every 250 ms while listened).
  Stream<EngineEvent> get events {
    return (_events ??= StreamController<EngineEvent>.broadcast(
      onListen: () =>
          _eventTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
            if (isDisposed) return;
            for (final e in pollEvents()) {
              _events?.add(e);
            }
          }),
      onCancel: () => _eventTimer?.cancel(),
    )).stream;
  }

  /// Broadcast stream of all statuses (every [interval] while listened).
  Stream<List<TorrentStatus>> get statusStream {
    return (_statuses ??= StreamController<List<TorrentStatus>>.broadcast(
      onListen: () =>
          _statusTimer = Timer.periodic(const Duration(seconds: 1), (_) {
            if (!isDisposed) _statuses?.add(statuses());
          }),
      onCancel: () => _statusTimer?.cancel(),
    )).stream;
  }

  /// Waits until [infoHash] has metadata and returns its files.
  Future<List<TorrentFile>> waitForFiles(
    String infoHash, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final end = DateTime.now().add(timeout);
    while (true) {
      final f = files(infoHash);
      if (f != null) return f;
      if (DateTime.now().isAfter(end)) {
        throw const EngineException('timed out waiting for metadata');
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  /// Asks for fresh resume data (written to the resume dir).
  void saveResume(String infoHash) =>
      _check(_withStr(infoHash, (ih) => _b.saveResume(_s, ih)));

  /// Writes the DHT state file now.
  void saveState() => _b.sessionSaveState(_s);

  /// Applies runtime settings (rate limits, toggles).
  void apply(EngineConfig config) => _check(
    _withBytes(bencode(config.toMap()), (p, n) => _b.sessionApply(_s, p, n)),
  );

  /// Moves a torrent's data to [path]; a [StorageMoved] (or
  /// [StorageMoveFailed]) event follows. Open streams keep working.
  void moveStorage(String infoHash, String path) => _check(
    _withStr(
      infoHash,
      (ih) => _withStr(path, (p) => _b.moveStorage(_s, ih, p)),
    ),
  );

  /// Bytes on disk for each file (complete pieces only), or null before
  /// metadata. Lets several owners of one torrent (episodes of a season
  /// pack) track their own file.
  List<int>? fileProgress(String infoHash) {
    final json = _withStr(infoHash, (ih) => _b.take(_b.fileProgress(_s, ih)));
    if (json == null) return null;
    return [
      for (final v in jsonDecode(json) as List<Object?>) (v! as num).toInt(),
    ];
  }

  /// BitTorrent listen port (0 until listening).
  int get listenPort => _b.listenPort(_s);

  /// HTTP server port (starts the server).
  int get serverPort {
    final port = _b.serverPort(_s);
    if (port <= 0) throw const EngineException('stream server failed to start');
    return port;
  }

  /// Connects to a known peer.
  void connectPeer(String infoHash, String ip, int port) => _check(
    _withStr(
      infoHash,
      (ih) => _withStr(ip, (a) => _b.connectPeer(_s, ih, a, port)),
    ),
  );

  /// Opens an HTTP stream of [fileIndex].
  ///
  /// [bitrate] (bytes/s, e.g. size ÷ runtime) sizes the read-ahead window
  /// to [readaheadSecs] of playback.
  StreamHandle openStream(
    String infoHash,
    int fileIndex, {
    int? bitrate,
    int readaheadSecs = 90,
  }) {
    final opts = bencode({'bitrate': bitrate, 'readahead_secs': readaheadSecs});
    final json = _withStr(
      infoHash,
      (ih) => _withBytes(
        opts,
        (p, n) => _b.take(_b.streamOpen(_s, ih, fileIndex, p, n)),
      ),
    );
    final map = _decodeObject(json);
    final token = map['token'];
    if (token is! String) {
      throw EngineException(map['error']?.toString() ?? 'stream failed');
    }
    return StreamHandle(
      token: token,
      path: map['path']! as String,
      size: (map['size']! as num).toInt(),
      port: serverPort,
    );
  }

  /// Live buffer numbers for an open stream (null once closed).
  StreamStats? streamStats(String token) {
    final json = _withStr(token, (t) => _b.take(_b.streamStats(_s, t)));
    return json == null
        ? null
        : StreamStats.fromJson(jsonDecode(json) as Map<String, Object?>);
  }

  /// Closes a stream: in-flight reads stop, deadlines are dropped.
  void closeStream(String token) =>
      _withStr(token, (t) => _b.streamClose(_s, t));

  /// Exposes a local file (finished download, subtitle) over HTTP.
  ServedFile serveFile(String path, {String? mime}) {
    final json = _withStr(
      path,
      (p) => _withStr(mime ?? '', (m) => _b.take(_b.serveFile(_s, p, m))),
    );
    final map = _decodeObject(json);
    final token = map['token'];
    if (token is! String) {
      throw EngineException(map['error']?.toString() ?? 'serve failed');
    }
    return ServedFile(
      token: token,
      path: map['path']! as String,
      port: serverPort,
    );
  }

  /// Extra response headers for a stream or file route (e.g. DLNA).
  void setRouteHeaders(String token, Map<String, String> headers) => _check(
    _withStr(
      token,
      (t) =>
          _withBytes(bencode(headers), (p, n) => _b.routeHeaders(_s, t, p, n)),
    ),
  );

  /// Stops serving a route.
  void closeRoute(String token) => _withStr(token, (t) => _b.routeClose(_s, t));

  /// Saves resume data and DHT state, then shuts the session down.
  void dispose() {
    if (isDisposed) return;
    _eventTimer?.cancel();
    _statusTimer?.cancel();
    unawaited(_events?.close());
    unawaited(_statuses?.close());
    _b.sessionFree(_session);
    _session = nullptr;
  }

  // ------------------------------------------------------------- helpers --

  static T _withBytes<T>(Uint8List bytes, T Function(Pointer<Uint8>, int) f) {
    final ptr = malloc<Uint8>(bytes.isEmpty ? 1 : bytes.length);
    try {
      ptr.asTypedList(bytes.length).setAll(0, bytes);
      return f(ptr, bytes.length);
    } finally {
      malloc.free(ptr);
    }
  }

  static T _withStr<T>(String s, T Function(Pointer<Utf8>) f) {
    final ptr = s.toNativeUtf8();
    try {
      return f(ptr);
    } finally {
      malloc.free(ptr);
    }
  }

  static void _check(int rc) {
    if (rc != 0) throw EngineException('engine call failed ($rc)');
  }

  static Map<String, Object?> _decodeObject(String? json) {
    if (json == null) throw const EngineException('no response');
    return jsonDecode(json) as Map<String, Object?>;
  }
}
