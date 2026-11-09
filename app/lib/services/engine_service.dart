import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:kinora_engine/kinora_engine.dart';
import 'package:swarm/swarm.dart';

import '../app/providers.dart';
import '../core/log.dart';
import '../core/paths.dart';
import '../core/settings.dart';

/// Owns the single torrent session. Starts on first use, applies settings
/// live, and keeps a daily-refreshed tracker list for every magnet.
final class EngineService {
  EngineService(this._paths, this._settings, this._trackerList);

  final AppPaths _paths;
  AppSettings _settings;
  final TrackerList _trackerList;
  KinoraEngine? _engine;
  List<String> _trackers = const [];
  StreamSubscription<EngineEvent>? _logSub;

  /// The running session (started on first access).
  KinoraEngine get engine => _engine ??= _start();

  bool get isRunning => _engine != null;

  KinoraEngine _start() {
    final e = KinoraEngine.start(_config(_settings));
    Log.i('engine', KinoraEngine.version());
    _logSub = e.events.listen((ev) {
      switch (ev) {
        case TorrentFailed(:final infoHash, :final message):
          Log.w('engine', 'torrent $infoHash failed: $message');
        case TorrentFileError(:final infoHash, :final message):
          Log.w('engine', 'disk error $infoHash: $message');
        case EngineLog(:final message):
          Log.d('engine', message);
        case MetadataReceived(:final infoHash):
          // Files are known now: only claimed ones may download.
          _applyPriorities(infoHash);
        default:
      }
    });
    unawaited(_loadTrackers());
    return e;
  }

  EngineConfig _config(AppSettings s) => EngineConfig(
    // One session per process: the UI can be recreated (Android) while the
    // foreground service keeps the process and its downloads alive.
    shared: true,
    // iOS: LSD/UPnP/NAT-PMP would raise the Local Network prompt on the
    // first stream, out of context. Casting asks for it when it's needed.
    lsd: !Platform.isIOS,
    upnp: !Platform.isIOS,
    natpmp: !Platform.isIOS,
    statePath: _paths.engineState.path,
    resumeDir: _paths.resume.path,
    userAgent: 'Kinora/$kinoraVersion',
    uploadRateLimit: s.uploadLimitKBps * 1024,
    downloadRateLimit: s.downloadLimitKBps * 1024,
    outgoingInterfaces: s.vpnInterface,
  );

  Future<void> _loadTrackers() async {
    try {
      final list = await _trackerList.load();
      _trackers = [for (final t in list) t.toString()];
      Log.i('engine', '${_trackers.length} trackers ready');
    } on Object catch (e) {
      Log.w('engine', 'tracker list unavailable: $e');
    }
  }

  /// Applies changed settings to a running session.
  void updateSettings(AppSettings s) {
    _settings = s;
    if (_engine != null) _engine!.apply(_config(s));
  }

  /// Adds a torrent for streaming (data in the stream cache) or downloading.
  String add({
    required String infoHash,
    String? name,
    List<String> trackers = const [],
    bool forDownload = false,
    String? savePath,
  }) {
    final magnet = Magnet(
      infoHash: infoHash,
      name: name,
      trackers: [
        ...{...trackers, ..._trackers},
      ],
    );
    final resume = File('${_paths.resume.path}/$infoHash.fastresume');
    final existed = engine.status(infoHash) != null;
    final ih = engine.add(
      AddTorrent.magnet(
        magnet.toUri().toString(),
        savePath:
            savePath ??
            (forDownload ? _paths.downloads.path : _paths.streams.path),
        resumePath: resume.existsSync() ? resume.path : null,
        name: name,
        // Nothing downloads until an owner claims its file (see [claim]).
        filePriorities: existed ? null : List.filled(1024, 0),
        // Not sharing while watching: a trickle keeps peers willing to send.
        uploadLimit: !forDownload && !_settings.seedWhileWatching
            ? 20 * 1024
            : null,
      ),
    );
    // Reusing a torrent someone paused (kept stream, paused download).
    if (engine.status(ih)?.paused ?? false) engine.resume(ih);
    if (existed) _applyPriorities(ih);
    return ih;
  }

  /// Deletes stream leftovers older than [keepHours] (all of them when 0),
  /// plus resume files that no download owns. Runs before the session
  /// starts; [downloadHashes] are never touched.
  static Future<void> cleanStreamCache(
    AppPaths paths, {
    required int keepHours,
    required Set<String> downloadHashes,
  }) async {
    final cutoff = DateTime.now().subtract(Duration(hours: keepHours));
    var removed = 0;
    for (final dir in [paths.streams, paths.resume]) {
      if (!dir.existsSync()) continue;
      for (final e in dir.listSync(followLinks: false)) {
        final name = e.uri.pathSegments.where((x) => x.isNotEmpty).last;
        if (dir.path == paths.resume.path) {
          final ih = name.split('.').first;
          if (downloadHashes.contains(ih)) continue;
        }
        try {
          if (keepHours == 0 || e.statSync().modified.isBefore(cutoff)) {
            e.deleteSync(recursive: true);
            removed++;
          }
        } on FileSystemException {
          // In use or already gone.
        }
      }
    }
    if (removed > 0) Log.i('engine', 'cleaned $removed old stream files');
  }

  // ------------------------------------------------------------ claims --

  /// Who needs which file of each torrent: info-hash → owner → file index
  /// (-1 = metadata only). File priorities are always the union, so streams
  /// and downloads of one season pack never starve each other, and a
  /// torrent is only removed once nobody owns it.
  final _claims = <String, Map<String, int>>{};

  /// [owner] needs [fileIndex] of [infoHash] (-1: just keep it warm).
  void claim(String infoHash, String owner, int fileIndex) {
    Log.d('engine', 'claim ${_short(infoHash)} $owner file $fileIndex');
    (_claims[infoHash] ??= {})[owner] = fileIndex;
    _applyPriorities(infoHash);
  }

  /// [owner] no longer needs [infoHash]. Returns whether anyone still does.
  bool release(String infoHash, String owner) {
    Log.d('engine', 'release ${_short(infoHash)} $owner');
    final m = _claims[infoHash];
    m?.remove(owner);
    if (m != null && m.isEmpty) _claims.remove(infoHash);
    _applyPriorities(infoHash);
    return isClaimed(infoHash);
  }

  bool isClaimed(String infoHash) => _claims[infoHash]?.isNotEmpty ?? false;

  /// Owners currently holding [infoHash] (for diagnostics and tests).
  Map<String, int> claimsOf(String infoHash) =>
      Map.unmodifiable(_claims[infoHash] ?? const {});

  void _applyPriorities(String infoHash) {
    final e = _engine;
    // Not status(): it's empty for a fresh magnet until metadata or the
    // first status update, exactly when the early priorities matter.
    if (e == null) return;
    final files = e.files(infoHash);
    final wanted = {
      for (final i in _claims[infoHash]?.values ?? const <int>[]) i,
    };
    if (files == null) {
      // No metadata yet. Hand libtorrent the claimed files now (it keeps
      // them for when the file list arrives): otherwise the torrent looks
      // finished for a moment once metadata is in, and seeds drop a peer
      // that says it wants nothing.
      // Nothing claimed (metadata only, or released): all off. Files past
      // the list stay off as well (the engine adds magnets that way).
      final top = wanted.fold(-1, (a, b) => b > a ? b : a);
      Log.d('engine', 'priorities ${_short(infoHash)}: files $wanted, early');
      try {
        e.setFilePriorities(infoHash, [
          for (var i = 0; i < (top < 1024 ? 1024 : top + 1); i++)
            wanted.contains(i) ? 4 : 0,
        ]);
      } on EngineException catch (err) {
        Log.d('engine', 'priorities for $infoHash: $err');
      }
      return;
    }
    Log.d(
      'engine',
      'priorities ${_short(infoHash)}: files $wanted of ${files.length}',
    );
    try {
      e.setFilePriorities(infoHash, [
        for (final f in files) wanted.contains(f.index) ? 4 : 0,
      ]);
    } on EngineException catch (err) {
      Log.d('engine', 'priorities for $infoHash: $err');
    }
  }

  /// Removes [infoHash] if nobody claims it. [deleteFiles] for stream
  /// leftovers; downloads keep their files.
  void removeIfUnclaimed(String infoHash, {required bool deleteFiles}) {
    final e = _engine;
    if (e == null || isClaimed(infoHash) || e.status(infoHash) == null) return;
    try {
      e.remove(infoHash, deleteFiles: deleteFiles);
    } on EngineException catch (err) {
      Log.d('engine', 'remove $infoHash: $err');
    }
  }

  /// Clears the stream buffer safely: unclaimed stream torrents go (with
  /// their data); data of claimed ones (playing, prefetched) stays.
  Future<void> clearStreamCache() async {
    final streams = _paths.streams.path;
    final keep = <String>{};
    final e = _engine;
    if (e != null) {
      for (final st in e.statuses()) {
        if (!p.equals(streams, st.savePath) &&
            !p.isWithin(streams, st.savePath))
          continue;
        if (isClaimed(st.infoHash)) {
          for (final f in e.files(st.infoHash) ?? const <TorrentFile>[]) {
            keep.add(p.join(st.savePath, f.path.split('/').first));
          }
        } else {
          removeIfUnclaimed(st.infoHash, deleteFiles: true);
        }
      }
    }
    final dir = Directory(streams);
    if (!dir.existsSync()) return;
    for (final f in dir.listSync(followLinks: false)) {
      if (keep.contains(f.path)) continue;
      try {
        f.deleteSync(recursive: true);
      } on FileSystemException {
        // In use; the next launch cleans it.
      }
    }
  }

  /// Saves resume data and the DHT table (call when backgrounded).
  void checkpoint() {
    final e = _engine;
    if (e == null) return;
    for (final s in e.statuses()) {
      e.saveResume(s.infoHash);
    }
    e.saveState();
  }

  void dispose() {
    unawaited(_logSub?.cancel());
    _engine?.dispose();
    _engine = null;
  }
}

final trackerListProvider = Provider<TrackerList>(
  (ref) => TrackerList(
    httpClient: ref.watch(httpClientProvider),
    cacheFile: ref.watch(pathsProvider).trackers,
    userAgent: 'Kinora/$kinoraVersion',
  ),
);

final engineServiceProvider = Provider<EngineService>((ref) {
  final service = EngineService(
    ref.watch(pathsProvider),
    ref.read(settingsProvider),
    ref.watch(trackerListProvider),
  );
  ref.listen(settingsProvider, (_, next) => service.updateSettings(next));
  ref.onDispose(service.dispose);
  return service;
});

String _short(String infoHash) =>
    infoHash.length > 6 ? infoHash.substring(0, 6) : infoHash;
