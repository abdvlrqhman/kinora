import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:background_downloader/background_downloader.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kinora_engine/kinora_engine.dart';
import 'package:path/path.dart' as p;

import '../app/providers.dart';
import '../core/db/database.dart';
import '../core/format.dart';
import '../core/log.dart';
import '../core/paths.dart';
import '../core/settings.dart';
import '../features/downloads/storage.dart' show freeBytes;
import 'background.dart';
import 'downloads.dart';
import 'engine_service.dart';
import 'play_request.dart';
import 'playback.dart';
import 'resolver.dart';
import 'subtitles_service.dart';

/// Downloads movies and episodes (torrents through the engine, debrid links
/// through the OS background transfer service), keeps them going in the
/// background, restores them after a restart, and adopts streams that
/// finished downloading while being watched.
///
/// Torrent downloads only ever *claim* their own file (see
/// [EngineService.claim]): episodes of one season pack, streams and
/// downloads share a torrent without starving or deleting each other, and
/// each row completes when its own file is complete.
final class DownloadsService implements DownloadActions {
  DownloadsService(this._ref);

  final Ref _ref;
  StreamSubscription<EngineEvent>? _events;
  StreamSubscription<TaskUpdate>? _http;
  StreamSubscription<List<ConnectivityResult>>? _net;
  Timer? _poll;

  /// Pauses Wi-Fi-only downloads once Wi-Fi has been gone for a while.
  Timer? _offWifi;

  /// Torrents moving into a download's folder: the rows of the same torrent
  /// that start meanwhile take that folder, not the one being left.
  final _movingTo = <String, String>{};
  bool _onWifi = true;
  bool _started = false;
  bool _disposed = false;

  /// False once the app (or a test) disposed the service: async work that
  /// was already running stops at its next step.
  bool get _alive => !_disposed && _ref.mounted;

  /// Videos whose download is being set up right now (double taps).
  final _starting = <String>{};

  AppDatabase get _db => _ref.read(databaseProvider);
  AppPaths get _paths => _ref.read(pathsProvider);
  AppSettings get _settings => _ref.read(settingsProvider);
  EngineService get _engines => _ref.read(engineServiceProvider);

  static String _owner(String id) => 'dl:$id';

  /// Restores unfinished downloads and starts listening. Idempotent.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    await _repairRelativePaths();
    await _rebaseMovedPaths();
    _http = FileDownloader().updates.listen(
      (u) => _whileAlive(() => _onHttpUpdate(u)),
    );
    await FileDownloader().start();
    _net = Connectivity().onConnectivityChanged.listen(_onNetwork);
    final net = await Connectivity().checkConnectivity();
    // iOS can answer "none" before its network monitor has looked: that's
    // unknown, not "off Wi-Fi" (the first network event says for sure).
    _onWifi = net.every((r) => r == ConnectivityResult.none) || _isWifi(net);
    Log.i(
      'downloads',
      'network ${net.map((r) => r.name).join('+')}: '
          '${_onWifi ? 'Wi-Fi' : 'not Wi-Fi'}',
    );
    await _flushDeferred();
    // An HTTP row whose task the system no longer knows (killed between
    // saving the row and queuing it) would say "downloading" forever.
    final http =
        await (_db.select(_db.downloads)..where(
              (t) =>
                  t.kind.equals('http') &
                  t.state.isIn(['queued', 'downloading']),
            ))
            .get();
    for (final row in http) {
      if (await FileDownloader().taskForId(row.id) == null) {
        await _fail(row.id, 'The download was interrupted. Tap to try again.');
      }
    }
    final active =
        await (_db.select(_db.downloads)..where(
              (t) =>
                  t.kind.equals('torrent') &
                  t.state.isIn(['queued', 'downloading']),
            ))
            .get();
    for (final row in active) {
      if (_settings.wifiOnlyDownloads && !_onWifi) {
        await _update(
          row.id,
          const DownloadsCompanion(
            state: Value('paused'),
            error: Value('Waiting for Wi-Fi'),
          ),
        );
      } else if (row.infoHash == null) {
        // Killed while finding a version: start over.
        unawaited(_startDownload(row.id, _requestOf(row), row.directory));
      } else {
        unawaited(_reclaim(row));
      }
    }
  }

  // ------------------------------------------------------------- actions --

  @override
  Future<void> download(PlayRequest request) async {
    await start();
    if (!_starting.add(request.videoId)) return;
    try {
      final existing = await _rowForVideo(request.videoId);
      if (existing != null) {
        // A row waiting for Wi-Fi keeps waiting: asking again isn't consent
        // to use mobile data.
        if (existing.state == 'failed' ||
            (existing.state == 'paused' &&
                existing.error != 'Waiting for Wi-Fi'))
          await resume(existing.id);
        return;
      }
      final id = _newId();
      final dir = Directory(_folderFor(request));
      await dir.create(recursive: true);
      await _db
          .into(_db.downloads)
          .insert(
            DownloadsCompanion.insert(
              id: id,
              mediaId: request.mediaId,
              videoId: request.videoId,
              type: request.type,
              title: request.title,
              episodeTitle: Value(request.episodeTitle),
              season: Value(request.season),
              episode: Value(request.episode),
              poster: Value(request.poster),
              still: Value(request.still ?? request.background),
              releaseName: 'Finding the best version',
              kind: 'torrent',
              directory: dir.path,
              state: 'queued',
            ),
          );
      unawaited(_startDownload(id, request, dir.path));
    } finally {
      _starting.remove(request.videoId);
    }
  }

  Future<void> _startDownload(
    String id,
    PlayRequest request,
    String dir,
  ) async {
    try {
      final video = VideoRef(
        type: request.type,
        mediaId: request.mediaId,
        videoId: request.videoId,
        season: request.season,
        episode: request.episode,
      );
      final result = await _ref.read(resolveProvider(video).future);
      if (await _row(id) == null) return; // removed meanwhile
      final releases = [...result.releases];
      if (request.candidateId != null) {
        final i = releases.indexWhere(
          (r) => r.candidateId == request.candidateId,
        );
        if (i > 0) releases.insert(0, releases.removeAt(i));
      }
      final best = releases.firstOrNull;
      final stream = best?.stream;
      if (best == null || stream == null) {
        await _fail(
          id,
          result.message ?? 'No version is available to download right now.',
        );
        return;
      }
      // Free-space guard: the video plus room for the phone to breathe.
      final free = freeBytes(dir) ?? freeBytes(_paths.downloadsRoot.path);
      final size = best.sizeBytes;
      if (free != null && size != null && free < size + (512 << 20)) {
        await _fail(
          id,
          'Not enough space: this needs ${Fmt.bytes(size)}, ${Fmt.bytes(free)} is free.',
        );
        return;
      }
      // Paused while a version was being found: remember it, don't start.
      if ((await _row(id))?.state == 'paused') {
        await _update(
          id,
          DownloadsCompanion(
            releaseName: Value(best.releaseName),
            infoHash: Value(stream.infoHash?.toLowerCase()),
            fileIndex: Value(best.fileIndex ?? stream.fileIdx),
          ),
        );
        return;
      }
      if (stream.url != null && stream.infoHash == null) {
        await _startHttp(
          id,
          request,
          dir,
          best.releaseName,
          stream.url!,
          stream.filename,
        );
      } else if (stream.infoHash != null) {
        await _update(
          id,
          DownloadsCompanion(
            releaseName: Value(best.releaseName),
            infoHash: Value(stream.infoHash!.toLowerCase()),
            fileIndex: Value(best.fileIndex ?? stream.fileIdx),
          ),
        );
        if (_settings.wifiOnlyDownloads && !_onWifi) {
          await _update(
            id,
            const DownloadsCompanion(
              state: Value('paused'),
              error: Value('Waiting for Wi-Fi'),
            ),
          );
          return;
        }
        final row = await _row(id);
        if (row != null)
          await _reclaim(row, trackers: stream.trackers, request: request);
      } else {
        await _fail(id, 'This version can’t be downloaded.');
      }
    } on Object catch (e, st) {
      Log.e('downloads', 'start failed', e, st);
      await _fail(id, 'Download couldn’t start. Try again.');
    }
  }

  /// (Re)attaches a torrent row to the engine: adds the torrent, claims the
  /// row's file once metadata is known, and makes sure the data lives in
  /// the Downloads folder (never in the stream cache).
  Future<void> _reclaim(
    DownloadRow row, {
    List<String> trackers = const [],
    PlayRequest? request,
  }) async {
    final id = row.id;
    final ih = row.infoHash!;
    final owner = _owner(id);
    try {
      final engine = _engines.engine;
      final added = _engines.add(
        infoHash: ih,
        name: row.releaseName,
        trackers: trackers,
        savePath: row.directory,
        forDownload: true,
      );
      _engines.claim(added, owner, row.fileIndex ?? -1);
      await _update(
        id,
        const DownloadsCompanion(
          state: Value('downloading'),
          error: Value(null),
        ),
      );
      _ensurePolling();
      final asked = DateTime.now();
      final files = await engine.waitForFiles(
        added,
        timeout: const Duration(minutes: 3),
      );
      Log.i(
        'downloads',
        'details for ${_label(row)} in '
            '${DateTime.now().difference(asked).inMilliseconds} ms',
      );
      if (await _row(id) == null) {
        _retire(added, owner);
        return;
      }
      final file = pickFile(
        files,
        fileIndex: row.fileIndex,
        season: row.season,
        episode: row.episode,
      );
      if (file == null) {
        _retire(added, owner);
        await _fail(id, 'This version has no video file.');
        return;
      }
      _engines.claim(added, owner, file.index);
      // Data folder: ours, unless another download already owns this
      // torrent (one torrent can only live in one folder).
      final others =
          (await (_db.select(
            _db.downloads,
          )..where((t) => t.infoHash.equals(added))).get()).where(
            (r) => r.id != id,
          );
      var base = _movingTo[added] ?? engine.status(added)?.savePath ?? '';
      // Downloads live in Downloads: not in the stream buffer (a pack that
      // was streamed first), and never at a relative path.
      final misplaced =
          !p.isAbsolute(base) || EngineService.isStreamData(_paths, base);
      if (misplaced || (others.isEmpty && !p.equals(base, row.directory))) {
        if (!p.equals(base, row.directory)) {
          engine.moveStorage(added, row.directory);
          _movingTo[added] = row.directory;
        }
        base = row.directory;
      }
      final path = p.join(base, file.path);
      await _update(
        id,
        DownloadsCompanion(
          fileIndex: Value(file.index),
          filePath: Value(path),
          totalBytes: Value(file.size),
        ),
      );
      if (row.subtitlesJson == '[]') {
        unawaited(
          _saveSubtitles(id, request ?? _requestOf(row), row.releaseName, path),
        );
      }
    } on EngineException catch (e) {
      Log.w('downloads', 'engine: ${e.message}');
      _retire(ih, owner);
      await _fail(
        id,
        e.message.contains('metadata')
            ? 'No one is sharing this version right now. Try again later or choose another version.'
            : 'Download couldn’t start. Try again.',
      );
    }
  }

  Future<void> _startHttp(
    String id,
    PlayRequest request,
    String dir,
    String releaseName,
    String url,
    String? filename,
  ) async {
    final name = _safe(filename ?? p.basename(Uri.parse(url).path));
    final task = DownloadTask(
      taskId: id,
      url: url,
      filename: name.isEmpty ? '$id.mkv' : name,
      directory: dir,
      baseDirectory: BaseDirectory.root,
      updates: Updates.statusAndProgress,
      requiresWiFi: _settings.wifiOnlyDownloads,
      retries: 5,
      allowPause: true,
      priority: 0,
      displayName: request.isEpisode
          ? '${request.title} ${Fmt.episode(request.season!, request.episode!)}'
          : request.title,
    );
    final path = p.join(dir, task.filename);
    await _update(
      id,
      DownloadsCompanion(
        kind: const Value('http'),
        url: Value(url),
        releaseName: Value(releaseName),
        filePath: Value(path),
        state: const Value('downloading'),
      ),
    );
    if (!await FileDownloader().enqueue(task)) {
      await _fail(id, 'The download couldn’t be queued.');
      return;
    }
    unawaited(_saveSubtitles(id, request, releaseName, path));
  }

  @override
  Future<void> pause(String downloadId) async {
    final row = await _row(downloadId);
    if (row == null) return;
    if (row.kind == 'http') {
      final task = await FileDownloader().taskForId(downloadId);
      if (task is DownloadTask) await FileDownloader().pause(task);
    } else if (row.infoHash != null && _engines.isRunning) {
      // Pause this file only; others sharing the torrent keep going.
      if (!_engines.release(row.infoHash!, _owner(row.id))) {
        try {
          _engines.engine.pause(row.infoHash!);
        } on EngineException {
          // Not in the session.
        }
      }
    }
    await _update(
      downloadId,
      const DownloadsCompanion(state: Value('paused'), error: Value(null)),
    );
    await _refreshKeepAlive();
  }

  @override
  Future<void> resume(String downloadId) async {
    final row = await _row(downloadId);
    if (row == null) return;
    if (row.kind == 'http') {
      final task = await FileDownloader().taskForId(downloadId);
      if (task is DownloadTask && await FileDownloader().resume(task)) {
        await _update(
          downloadId,
          const DownloadsCompanion(
            state: Value('downloading'),
            error: Value(null),
          ),
        );
        return;
      }
    }
    if (row.infoHash != null) {
      await _reclaim(row);
      return;
    }
    // Never got a version: start over.
    await (_db.delete(
      _db.downloads,
    )..where((t) => t.id.equals(downloadId))).go();
    await download(_requestOf(row));
  }

  @override
  Future<void> remove(String downloadId) async {
    final row = await _row(downloadId);
    if (row == null) return;
    if (row.kind == 'http') await FileDownloader().cancelTaskWithId(downloadId);
    await (_db.delete(
      _db.downloads,
    )..where((t) => t.id.equals(downloadId))).go();
    final ih = row.infoHash;
    if (ih != null) _engines.release(ih, _owner(row.id));
    final shared = ih != null && _engines.isRunning && _engines.isClaimed(ih);
    if (shared) {
      // Others still use this torrent: drop the row now, delete the file
      // when the torrent retires (deleting now would fail their downloads).
      await _deferDelete(ih, row);
    } else {
      if (ih != null) _retire(ih, null);
      await _deleteFiles(row);
    }
    await _refreshKeepAlive();
  }

  static const _deferredKey = 'downloads.deferredDeletes';

  Future<void> _deferDelete(String ih, DownloadRow row) async {
    final all = await _readDeferred();
    (all[ih] ??= <String>[]).addAll([?row.filePath, ..._subtitlePaths(row)]);
    await _db
        .into(_db.keyValues)
        .insertOnConflictUpdate(
          KeyValue(key: _deferredKey, value: jsonEncode(all)),
        );
  }

  Future<Map<String, List<String>>> _readDeferred() async {
    final kv = await (_db.select(
      _db.keyValues,
    )..where((t) => t.key.equals(_deferredKey))).getSingleOrNull();
    if (kv == null) return {};
    try {
      return {
        for (final e in (jsonDecode(kv.value) as Map<String, Object?>).entries)
          e.key: [for (final v in e.value! as List<Object?>) '$v'],
      };
    } on FormatException {
      return {};
    }
  }

  /// Deletes files whose deletion waited for their torrent to retire (also
  /// at startup, before any of those torrents is added again).
  Future<void> _flushDeferred({String? onlyHash}) async {
    final all = await _readDeferred();
    if (all.isEmpty) return;
    for (final ih in [...all.keys]) {
      if (onlyHash != null && ih != onlyHash) continue;
      if (_engines.isRunning && _engines.isClaimed(ih)) continue;
      for (final path in all.remove(ih)!) {
        await _deleteIfExists(path);
      }
    }
    await _db
        .into(_db.keyValues)
        .insertOnConflictUpdate(
          KeyValue(key: _deferredKey, value: jsonEncode(all)),
        );
  }

  /// 0.1.13 and before could save a pack's later episodes with a path
  /// missing its folder: their files are in the download's folder.
  Future<void> _repairRelativePaths() async {
    for (final r in await _db.select(_db.downloads).get()) {
      final path = r.filePath;
      if (path == null || p.isAbsolute(path)) continue;
      Log.i('downloads', 'path repaired: ${_label(r)}');
      await _update(
        r.id,
        DownloadsCompanion(filePath: Value(p.join(r.directory, path))),
      );
    }
  }

  /// After an iOS update the files are where they were, under a new
  /// folder path: saved paths follow, so downloads keep playing offline.
  Future<void> _rebaseMovedPaths() async {
    if (!_paths.moved) return;
    String? moved(String? path) {
      if (path == null ||
          FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound) {
        return null;
      }
      return _paths.rebased(path);
    }

    for (final r in await _db.select(_db.downloads).get()) {
      final dir = moved(r.directory);
      final file = moved(r.filePath);
      String? subs;
      try {
        var changed = false;
        final list = jsonDecode(r.subtitlesJson) as List<Object?>;
        for (final e in list.whereType<Map<String, Object?>>()) {
          final to = moved(e['path'] as String?);
          if (to != null) {
            e['path'] = to;
            changed = true;
          }
        }
        if (changed) subs = jsonEncode(list);
      } on Object {
        subs = null; // unreadable: left as it is
      }
      if (dir == null && file == null && subs == null) continue;
      Log.i('downloads', 'paths moved with the app folder: ${r.title}');
      await _update(
        r.id,
        DownloadsCompanion(
          directory: dir == null ? const Value.absent() : Value(dir),
          filePath: file == null ? const Value.absent() : Value(file),
          subtitlesJson: subs == null ? const Value.absent() : Value(subs),
        ),
      );
    }
    // Deletions waiting for their torrent: the files moved with the folder.
    final deferred = await _readDeferred();
    var rebased = false;
    for (final paths in deferred.values) {
      for (var k = 0; k < paths.length; k++) {
        final to = moved(paths[k]);
        if (to != null) {
          paths[k] = to;
          rebased = true;
        }
      }
    }
    if (rebased) {
      await _db
          .into(_db.keyValues)
          .insertOnConflictUpdate(
            KeyValue(key: _deferredKey, value: jsonEncode(deferred)),
          );
    }
  }

  static List<String> _subtitlePaths(DownloadRow row) {
    try {
      return [
        for (final e in jsonDecode(row.subtitlesJson) as List<Object?>)
          if (e is Map<String, Object?> && e['path'] is String)
            e['path']! as String,
      ];
    } on FormatException {
      return const [];
    }
  }

  /// Deletes every download of a title (or one season of it).
  Future<void> removeTitle(String mediaId, {int? season}) async {
    final rows =
        await (_db.select(_db.downloads)..where(
              (t) =>
                  t.mediaId.equals(mediaId) &
                  (season == null
                      ? const Constant(true)
                      : t.season.equals(season)),
            ))
            .get();
    for (final r in rows) {
      await remove(r.id);
    }
  }

  // ------------------------------------------- completed streams → downloads --

  /// A stream reached 100%: keep it in Downloads instead of deleting it.
  Future<void> adoptCompletedStream(
    PlaybackSource source,
    PlayRequest request,
  ) => _whileAlive(() => _adopt(source, request));

  /// Runs [work]; failures after the service was disposed (app or test
  /// shutting down mid-operation) are expected and dropped.
  Future<void> _whileAlive(Future<void> Function() work) async {
    try {
      await work();
    } on Object {
      if (_alive) rethrow;
    }
  }

  Future<void> _adopt(PlaybackSource source, PlayRequest request) async {
    final ih = source.infoHash;
    if (ih == null ||
        request.videoId.startsWith('magnet:') ||
        request.videoId.startsWith('http'))
      return;
    if (await _rowForVideo(request.videoId) != null) return;
    final engine = _engines.engine;
    final files = engine.files(ih);
    final status = engine.status(ih);
    if (files == null || status == null) return;
    final file =
        files.where((f) => f.index == source.fileIndex).firstOrNull ??
        files.where((f) => p.basename(f.path) == source.fileName).firstOrNull;
    if (file == null) return;
    final id = _newId();
    final owner = _owner(id);
    _engines.claim(ih, owner, file.index);
    final others = await (_db.select(
      _db.downloads,
    )..where((t) => t.infoHash.equals(ih))).get();
    // One torrent lives in one folder: the first download's, once it owns it.
    final owned = others.where((r) => r.directory.isNotEmpty).firstOrNull;
    final dir = owned?.directory ?? _folderFor(request);
    await Directory(dir).create(recursive: true);
    if (!_alive) return;
    await _db
        .into(_db.downloads)
        .insert(
          DownloadsCompanion.insert(
            id: id,
            mediaId: request.mediaId,
            videoId: request.videoId,
            type: request.type,
            title: request.title,
            episodeTitle: Value(request.episodeTitle),
            season: Value(request.season),
            episode: Value(request.episode),
            poster: Value(request.poster),
            still: Value(request.still ?? request.background),
            releaseName:
                source.release?.releaseName ?? source.fileName ?? request.title,
            kind: 'torrent',
            infoHash: Value(ih),
            fileIndex: Value(file.index),
            directory: dir,
            filePath: Value(p.join(dir, file.path)),
            totalBytes: Value(file.size),
            doneBytes: Value(file.size),
            state: 'completed',
            completedAt: Value(DateTime.now()),
          ),
        );
    if (!p.equals(status.savePath, dir)) {
      final moved = Completer<bool>();
      final sub = engine.events.listen((e) {
        if (e is StorageMoved && e.infoHash == ih && !moved.isCompleted)
          moved.complete(true);
        if (e is StorageMoveFailed && e.infoHash == ih && !moved.isCompleted)
          moved.complete(false);
      });
      engine.moveStorage(ih, dir);
      // Same volume as the stream cache, so normally a rename; never delete
      // the user's data because a big copy is slow.
      final ok = await moved.future.timeout(
        const Duration(minutes: 30),
        onTimeout: () => false,
      );
      await sub.cancel();
      if (!_alive) return;
      if (!ok) {
        Log.w('downloads', 'keeping a finished stream failed for $ih');
        await _update(
          id,
          DownloadsCompanion(
            state: const Value('failed'),
            filePath: Value(p.join(status.savePath, file.path)),
            error: const Value(
              'Couldn’t move this episode into Downloads. It plays from where it is.',
            ),
          ),
        );
      }
    }
    Log.i(
      'downloads',
      'kept finished stream ${request.title} ${request.videoId}',
    );
    unawaited(
      _saveSubtitles(
        id,
        request,
        source.release?.releaseName ?? source.fileName ?? '',
        p.join(dir, file.path),
      ),
    );
    // The stream is over: its claim goes now, so the torrent can retire.
    if (source.owner != null) _engines.release(ih, source.owner!);
    _finishClaim(ih, owner);
  }

  // ------------------------------------------------------------ progress --

  void _ensurePolling() {
    _events ??= _engines.engine.events.listen(
      (e) => _whileAlive(() => _onEngineEvent(e)),
    );
    _poll ??= Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_whileAlive(_tick)),
    );
  }

  Future<void> _tick() async {
    if (!_alive) return;
    final rows =
        await (_db.select(_db.downloads)..where(
              (t) => t.kind.equals('torrent') & t.state.equals('downloading'),
            ))
            .get();
    if (rows.isEmpty) {
      _poll?.cancel();
      _poll = null;
      await _refreshKeepAlive();
      return;
    }
    final engine = _engines.engine;
    var done = 0, total = 0, rate = 0;
    final rates = <String>{};
    for (final r in rows) {
      final ih = r.infoHash;
      if (ih == null || r.fileIndex == null || r.totalBytes <= 0) continue;
      final fp = engine.fileProgress(ih);
      if (fp == null || r.fileIndex! >= fp.length) continue;
      final have = fp[r.fileIndex!];
      total += r.totalBytes;
      done += have;
      if (rates.add(ih)) rate += engine.status(ih)?.downloadRate ?? 0;
      if (have != r.doneBytes)
        await _update(r.id, DownloadsCompanion(doneBytes: Value(have)));
      if (have >= r.totalBytes) await _complete(r);
    }
    final progress = total == 0 ? null : done / total;
    await _markPending();
    await BackgroundKeeper.instance.hold(
      'downloads',
      title: rows.length == 1
          ? 'Downloading ${_label(rows.first)}'
          : 'Downloading ${rows.length} videos',
      text: progress == null
          ? 'Finding people sharing it'
          : '${(progress * 100).toStringAsFixed(0)}%  ${Fmt.speed(rate)}',
      progress: progress,
    );
  }

  Future<void> _onEngineEvent(EngineEvent e) async {
    if (!_alive) return;
    if (e is StorageMoved) {
      _movingTo.remove(e.infoHash);
    } else if (e is StorageMoveFailed && _movingTo.remove(e.infoHash) != null) {
      Log.w('downloads', 'moving ${e.infoHash} failed: ${e.message}');
      final rows = await (_db.select(
        _db.downloads,
      )..where((t) => t.infoHash.equals(e.infoHash))).get();
      for (final r in rows.where((r) => r.state != 'completed')) {
        await _fail(
          r.id,
          'Couldn’t move this into Downloads. Check free space, then tap to try again.',
        );
      }
    } else if (e is TorrentFinished) {
      // Finished means every *claimed* file is done; check each row's own.
      await _tick();
    } else if (e is TorrentFileError) {
      final rows = await (_db.select(
        _db.downloads,
      )..where((t) => t.infoHash.equals(e.infoHash))).get();
      for (final r in rows.where((r) => r.state != 'completed')) {
        await _fail(
          r.id,
          RegExp('space|ENOSPC', caseSensitive: false).hasMatch(e.message)
              ? 'Your device is out of space. Free some up, then tap to try again.'
              : 'Saving failed. Check free space, then tap to try again.',
        );
      }
    }
  }

  Future<void> _complete(DownloadRow r) async {
    await _update(
      r.id,
      DownloadsCompanion(
        state: const Value('completed'),
        doneBytes: Value(r.totalBytes),
        completedAt: Value(DateTime.now()),
        error: const Value(null),
      ),
    );
    Log.i('downloads', 'completed ${_label(r)}');
    if (r.infoHash != null) _finishClaim(r.infoHash!, _owner(r.id));
  }

  /// A finished download no longer needs the network: release its claim and,
  /// unless sharing is on, retire the torrent once nobody else uses it.
  void _finishClaim(String ih, String owner) {
    if (_settings.seedAfterDownload) return; // keep sharing
    if (!_engines.release(ih, owner)) {
      // Give a stream of the next episode in the same pack a moment.
      Timer(const Duration(seconds: 30), () => _retire(ih, null));
    }
  }

  /// Releases [owner] (if given) and removes the torrent when unclaimed,
  /// keeping finished files and deleting leftovers no download owns.
  void _retire(String ih, String? owner) {
    if (owner != null) _engines.release(ih, owner);
    if (!_engines.isRunning || _engines.isClaimed(ih)) return;
    final engine = _engines.engine;
    final status = engine.status(ih);
    if (status == null) return;
    final files = engine.files(ih);
    final progress = engine.fileProgress(ih);
    final savePath = status.savePath;
    _engines.removeIfUnclaimed(ih, deleteFiles: false);
    unawaited(() async {
      await _flushDeferred(onlyHash: ih);
      final owned = {
        for (final r in await (_db.select(
          _db.downloads,
        )..where((t) => t.infoHash.equals(ih))).get())
          ?r.filePath,
      };
      if (files != null) {
        for (final f in files) {
          final path = p.join(savePath, f.path);
          final partial =
              progress == null ||
              f.index >= progress.length ||
              progress[f.index] < f.size;
          if (!owned.contains(path) && partial) await _deleteIfExists(path);
        }
      }
      if (owned.isEmpty) await _deleteIfExists(p.join(savePath, '.$ih.parts'));
    }());
  }

  Future<void> _onHttpUpdate(TaskUpdate update) async {
    if (!_alive) return;
    final id = update.task.taskId;
    switch (update) {
      case TaskProgressUpdate(:final progress, :final expectedFileSize):
        if (progress >= 0 && expectedFileSize > 0) {
          await _update(
            id,
            DownloadsCompanion(
              totalBytes: Value(expectedFileSize),
              doneBytes: Value((progress * expectedFileSize).round()),
            ),
          );
        }
      case TaskStatusUpdate(:final status, :final exception):
        switch (status) {
          case TaskStatus.complete:
            final row = await _row(id);
            if (row != null) await _complete(row);
          case TaskStatus.failed || TaskStatus.notFound:
            Log.w(
              'downloads',
              'http download failed: ${exception?.description}',
            );
            final disk =
                exception is TaskFileSystemException ||
                RegExp(
                  'space|ENOSPC|disk',
                  caseSensitive: false,
                ).hasMatch(exception?.description ?? '');
            await _fail(
              id,
              disk
                  ? 'Your device is out of space. Free some up, then tap to try again.'
                  : 'The download link stopped working. Try another version.',
            );
          case TaskStatus.paused:
            await _update(id, const DownloadsCompanion(state: Value('paused')));
          case TaskStatus.waitingToRetry:
            await _update(
              id,
              const DownloadsCompanion(
                error: Value('Connection lost, retrying'),
              ),
            );
          case TaskStatus.running || TaskStatus.enqueued:
            await _update(
              id,
              const DownloadsCompanion(
                state: Value('downloading'),
                error: Value(null),
              ),
            );
          case TaskStatus.canceled:
        }
    }
  }

  // ------------------------------------------------------------- network --

  Future<void> _onNetwork(List<ConnectivityResult> r) async {
    final wifi = _isWifi(r);
    Log.i('downloads', 'network ${r.map((x) => x.name).join('+')}');
    if (wifi) {
      _offWifi?.cancel();
      _offWifi = null;
      await _setWifi(true);
    } else if (_onWifi && _offWifi == null) {
      // A Wi-Fi blip (roaming, a VPN reconnecting) doesn't pause anything.
      _offWifi = Timer(const Duration(seconds: 10), () {
        _offWifi = null;
        unawaited(_whileAlive(() => _setWifi(false)));
      });
    }
  }

  Future<void> _setWifi(bool wifi) async {
    if (wifi == _onWifi) return;
    _onWifi = wifi;
    Log.i(
      'downloads',
      wifi
          ? 'on Wi-Fi: resuming'
          : 'off Wi-Fi${_settings.wifiOnlyDownloads ? ': pausing (Wi-Fi only)' : ''}',
    );
    if (!_settings.wifiOnlyDownloads) return;
    final rows = await (_db.select(
      _db.downloads,
    )..where((t) => t.kind.equals('torrent'))).get();
    for (final row in rows) {
      if (!wifi && row.state == 'downloading') {
        await pause(row.id);
        await _update(
          row.id,
          const DownloadsCompanion(error: Value('Waiting for Wi-Fi')),
        );
      } else if (wifi &&
          row.state == 'paused' &&
          row.error == 'Waiting for Wi-Fi') {
        await resume(row.id);
      }
    }
  }

  static bool _isWifi(List<ConnectivityResult> r) =>
      r.contains(ConnectivityResult.wifi) ||
      r.contains(ConnectivityResult.ethernet);

  // ------------------------------------------------------------- helpers --

  int? _pendingMarked;
  Future<void> _pendingWrite = Future.value();

  /// How many torrent downloads are unfinished (downloading, queued or
  /// waiting for Wi-Fi), for Android's boot receiver
  /// (DownloadsBootReceiver.kt): after a restart it says they wait for
  /// Kinora to open, since torrents need the app running. One count, one
  /// write at a time.
  Future<void> _markPending() => _pendingWrite = _pendingWrite.then((_) async {
    try {
      final rows =
          await (_db.select(_db.downloads)..where(
                (t) =>
                    t.kind.equals('torrent') &
                    (t.state.isIn(['queued', 'downloading']) |
                        (t.state.equals('paused') &
                            t.error.equals('Waiting for Wi-Fi'))),
              ))
              .get();
      final count = rows.length;
      if (count == _pendingMarked) return;
      _pendingMarked = count;
      final f = File(p.join(_paths.support.path, 'pending_downloads'));
      if (count == 0) {
        if (f.existsSync()) await f.delete();
      } else {
        await f.writeAsString('$count');
      }
    } on Object catch (e) {
      Log.w('downloads', 'pending marker: $e');
    }
  });

  Future<void> _refreshKeepAlive() async {
    final rows = await (_db.select(
      _db.downloads,
    )..where((t) => t.kind.equals('torrent'))).get();
    final active = rows.where((r) => r.state == 'downloading').length;
    // Rows waiting for Wi-Fi keep the app alive too, or nothing would resume
    // them when Wi-Fi returns while Kinora is in the background.
    final waiting = rows
        .where((r) => r.state == 'paused' && r.error == 'Waiting for Wi-Fi')
        .length;
    await _markPending();
    if (active == 0 && waiting == 0) {
      await BackgroundKeeper.instance.drop('downloads');
    } else if (active == 0) {
      await BackgroundKeeper.instance.hold(
        'downloads',
        title: waiting == 1
            ? '1 download waiting for Wi-Fi'
            : '$waiting downloads waiting for Wi-Fi',
        text: 'They continue when you’re back on Wi-Fi.',
      );
    }
  }

  Future<void> _saveSubtitles(
    String id,
    PlayRequest request,
    String releaseName,
    String videoPath,
  ) async {
    try {
      final saved = await _ref
          .read(playerSubtitlesProvider)
          .saveForDownload(
            VideoRef(
              type: request.type,
              mediaId: request.mediaId,
              videoId: request.videoId,
              season: request.season,
              episode: request.episode,
            ),
            releaseName: releaseName,
            videoPath: videoPath,
          );
      if (saved.isNotEmpty && await _row(id) != null) {
        await _update(
          id,
          DownloadsCompanion(subtitlesJson: Value(jsonEncode(saved))),
        );
      }
    } on Object catch (e) {
      Log.w('downloads', 'subtitles for download failed: $e');
    }
  }

  Future<void> _deleteFiles(DownloadRow row) async {
    final path = row.filePath;
    if (path != null) await _deleteIfExists(path);
    try {
      for (final e in jsonDecode(row.subtitlesJson) as List<Object?>) {
        if (e is Map<String, Object?> && e['path'] is String)
          await _deleteIfExists(e['path']! as String);
      }
    } on FormatException {
      // No saved subtitles.
    }
    // Remove now-empty folders up to the Downloads root.
    var dir = path == null ? Directory(row.directory) : File(path).parent;
    final root = _paths.downloads.path;
    while (dir.path.startsWith(root) &&
        dir.path != root &&
        dir.existsSync() &&
        dir.listSync().isEmpty) {
      await dir.delete();
      dir = dir.parent;
    }
  }

  static Future<void> _deleteIfExists(String path) async {
    try {
      final f = File(path);
      if (f.existsSync()) await f.delete();
    } on FileSystemException catch (e) {
      Log.d('downloads', 'delete $path: $e');
    }
  }

  Future<DownloadRow?> _row(String id) => (_db.select(
    _db.downloads,
  )..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<DownloadRow?> _rowForVideo(String videoId) async => (await (_db.select(
    _db.downloads,
  )..where((t) => t.videoId.equals(videoId))).get()).firstOrNull;

  Future<void> _update(String id, DownloadsCompanion c) =>
      (_db.update(_db.downloads)..where((t) => t.id.equals(id))).write(c);

  Future<void> _fail(String id, String message) async {
    final row = await _row(id);
    Log.w('downloads', 'failed ${row == null ? id : _label(row)}: $message');
    await _update(
      id,
      DownloadsCompanion(state: const Value('failed'), error: Value(message)),
    );
    await _refreshKeepAlive();
  }

  String _folderFor(PlayRequest r) {
    final title = _safe(r.title);
    return r.isEpisode
        ? p.join(_paths.downloads.path, title, 'Season ${r.season}')
        : p.join(_paths.downloads.path, title);
  }

  static String _safe(String s) => s
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String _newId() {
    final r = Random.secure();
    return List.generate(
      16,
      (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  static String _label(DownloadRow r) => r.season != null && r.episode != null
      ? '${r.title} ${Fmt.episode(r.season!, r.episode!)}'
      : r.title;

  PlayRequest _requestOf(DownloadRow r) => PlayRequest(
    type: r.type,
    mediaId: r.mediaId,
    videoId: r.videoId,
    title: r.title,
    episodeTitle: r.episodeTitle,
    season: r.season,
    episode: r.episode,
    poster: r.poster,
    still: r.still,
  );

  void dispose() {
    _disposed = true;
    _poll?.cancel();
    unawaited(_events?.cancel());
    unawaited(_http?.cancel());
    unawaited(_net?.cancel());
    _offWifi?.cancel();
  }
}

final downloadsServiceProvider = Provider<DownloadsService>((ref) {
  final s = DownloadsService(ref);
  ref.onDispose(s.dispose);
  return s;
});
