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
final class DownloadsService implements DownloadActions {
  DownloadsService(this._ref);

  final Ref _ref;
  StreamSubscription<EngineEvent>? _events;
  StreamSubscription<TaskUpdate>? _http;
  StreamSubscription<List<ConnectivityResult>>? _net;
  Timer? _poll;
  bool _onWifi = true;
  bool _started = false;

  AppDatabase get _db => _ref.read(databaseProvider);
  AppPaths get _paths => _ref.read(pathsProvider);
  AppSettings get _settings => _ref.read(settingsProvider);
  EngineService get _engines => _ref.read(engineServiceProvider);

  /// Restores unfinished downloads and starts listening. Idempotent.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _http = FileDownloader().updates.listen(_onHttpUpdate);
    await FileDownloader().start();
    _net = Connectivity().onConnectivityChanged.listen(_onNetwork);
    _onWifi = _isWifi(await Connectivity().checkConnectivity());
    final active =
        await (_db.select(_db.downloads)..where(
              (t) =>
                  t.kind.equals('torrent') &
                  t.state.isIn(['queued', 'downloading']),
            ))
            .get();
    for (final row in active) {
      if (row.infoHash == null) continue;
      _engines.add(
        infoHash: row.infoHash!,
        name: row.releaseName,
        savePath: row.directory,
        forDownload: true,
      );
    }
    if (active.isNotEmpty) _ensurePolling();
  }

  // ---------------------------------------------------------- actions --

  @override
  Future<void> download(PlayRequest request) async {
    await start();
    final existing = await (_db.select(
      _db.downloads,
    )..where((t) => t.videoId.equals(request.videoId))).getSingleOrNull();
    if (existing != null) {
      if (existing.state == 'paused' || existing.state == 'failed')
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
        await _startTorrent(
          id,
          request,
          dir,
          best,
          stream.infoHash!,
          stream.trackers,
          best.fileIndex ?? stream.fileIdx,
        );
      } else {
        await _fail(id, 'This version can’t be downloaded.');
      }
    } on Object catch (e, st) {
      Log.e('downloads', 'start failed', e, st);
      await _fail(id, 'Download couldn’t start. Try again.');
    }
  }

  Future<void> _startTorrent(
    String id,
    PlayRequest request,
    String dir,
    ResolvedRelease release,
    String infoHash,
    List<String> trackers,
    int? fileIndex,
  ) async {
    if (_settings.wifiOnlyDownloads && !_onWifi) {
      await _update(
        id,
        DownloadsCompanion(
          releaseName: Value(release.releaseName),
          infoHash: Value(infoHash),
          fileIndex: Value(fileIndex),
          state: const Value('paused'),
          error: const Value('Waiting for Wi-Fi'),
        ),
      );
      return;
    }
    final engine = _engines.engine;
    final ih = _engines.add(
      infoHash: infoHash,
      name: release.releaseName,
      trackers: trackers,
      savePath: dir,
      forDownload: true,
    );
    await _update(
      id,
      DownloadsCompanion(
        releaseName: Value(release.releaseName),
        infoHash: Value(ih),
        fileIndex: Value(fileIndex),
        state: const Value('downloading'),
        error: const Value(null),
      ),
    );
    _ensurePolling();
    final files = await engine.waitForFiles(
      ih,
      timeout: const Duration(minutes: 3),
    );
    final file = pickFile(
      files,
      fileIndex: fileIndex,
      season: request.season,
      episode: request.episode,
    );
    if (file == null) {
      await _fail(id, 'This version has no video file.');
      return;
    }
    engine.setFilePriorities(ih, [
      for (final f in files) f.index == file.index ? 4 : 0,
    ]);
    final path = p.join(dir, file.path);
    await _update(
      id,
      DownloadsCompanion(
        fileIndex: Value(file.index),
        filePath: Value(path),
        totalBytes: Value(file.size),
      ),
    );
    unawaited(_saveSubtitles(id, request, release.releaseName, path));
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
      _engines.engine.pause(row.infoHash!);
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
      _engines.add(
        infoHash: row.infoHash!,
        name: row.releaseName,
        savePath: row.directory,
        forDownload: true,
      );
      _engines.engine.resume(row.infoHash!);
      await _update(
        downloadId,
        const DownloadsCompanion(
          state: Value('downloading'),
          error: Value(null),
        ),
      );
      _ensurePolling();
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
    if (row.kind == 'http') {
      await FileDownloader().cancelTaskWithId(downloadId);
    }
    if (row.infoHash != null &&
        _engines.isRunning &&
        _engines.engine.status(row.infoHash!) != null) {
      _engines.engine.remove(row.infoHash!, deleteFiles: true);
    }
    await _deleteFiles(row);
    await (_db.delete(
      _db.downloads,
    )..where((t) => t.id.equals(downloadId))).go();
    await _refreshKeepAlive();
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

  /// A stream reached 100%: move it into Downloads instead of deleting it.
  Future<void> adoptCompletedStream(
    PlaybackSource source,
    PlayRequest request,
  ) async {
    final ih = source.infoHash;
    if (ih == null || request.videoId.startsWith('magnet:')) return;
    final existing = await (_db.select(
      _db.downloads,
    )..where((t) => t.videoId.equals(request.videoId))).getSingleOrNull();
    if (existing != null) return;
    final engine = _engines.engine;
    final files = engine.files(ih);
    final status = engine.status(ih);
    if (files == null || status == null) return;
    final file =
        files.where((f) => p.basename(f.path) == source.fileName).firstOrNull ??
        files
            .where((f) => f.isVideo)
            .fold<TorrentFile?>(
              null,
              (a, b) => a == null || b.size > a.size ? b : a,
            );
    if (file == null) return;
    final dir = Directory(_folderFor(request))..createSync(recursive: true);
    final id = _newId();
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
            directory: dir.path,
            filePath: Value(p.join(dir.path, file.path)),
            totalBytes: Value(file.size),
            doneBytes: Value(file.size),
            state: 'completed',
            completedAt: Value(DateTime.now()),
          ),
        );
    final moved = Completer<bool>();
    final sub = engine.events.listen((e) {
      if (e is StorageMoved && e.infoHash == ih && !moved.isCompleted)
        moved.complete(true);
      if (e is StorageMoveFailed && e.infoHash == ih && !moved.isCompleted)
        moved.complete(false);
    });
    engine.moveStorage(ih, dir.path);
    final ok = await moved.future.timeout(
      const Duration(minutes: 2),
      onTimeout: () => false,
    );
    await sub.cancel();
    if (!ok) {
      Log.w('downloads', 'keeping a finished stream failed for $ih');
      await (_db.delete(_db.downloads)..where((t) => t.id.equals(id))).go();
      engine.remove(ih, deleteFiles: true);
      return;
    }
    if (!_settings.seedAfterDownload) engine.remove(ih);
    Log.i(
      'downloads',
      'kept finished stream ${request.title} ${request.videoId}',
    );
    unawaited(
      _saveSubtitles(
        id,
        request,
        source.release?.releaseName ?? source.fileName ?? '',
        p.join(dir.path, file.path),
      ),
    );
  }

  // ------------------------------------------------------------ progress --

  void _ensurePolling() {
    _events ??= _engines.engine.events.listen(_onEngineEvent);
    _poll ??= Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_tick()),
    );
  }

  Future<void> _tick() async {
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
    for (final r in rows) {
      final st = engine.status(r.infoHash ?? '');
      if (st == null) continue;
      total += st.totalWanted;
      done += st.totalWantedDone;
      rate += st.downloadRate;
      if (st.totalWantedDone != r.doneBytes ||
          (st.totalWanted > 0 && st.totalWanted != r.totalBytes)) {
        await _update(
          r.id,
          DownloadsCompanion(
            doneBytes: Value(st.totalWantedDone),
            totalBytes: Value(
              st.totalWanted > 0 ? st.totalWanted : r.totalBytes,
            ),
          ),
        );
      }
      if (st.isComplete && st.hasMetadata && st.totalWanted > 0)
        await _complete(r);
    }
    final progress = total == 0 ? null : done / total;
    await BackgroundKeeper.instance.keepAlive(
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
    if (e is TorrentFinished) {
      final rows = await (_db.select(
        _db.downloads,
      )..where((t) => t.infoHash.equals(e.infoHash))).get();
      for (final r in rows) {
        if (r.state != 'completed') await _complete(r);
      }
    } else if (e is TorrentFileError) {
      final rows = await (_db.select(
        _db.downloads,
      )..where((t) => t.infoHash.equals(e.infoHash))).get();
      for (final r in rows) {
        await _fail(
          r.id,
          e.message.contains('space')
              ? 'Your device is out of space.'
              : 'Saving failed: ${e.message}',
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
    if (!_settings.seedAfterDownload &&
        r.infoHash != null &&
        _engines.isRunning) {
      _engines.engine.remove(r.infoHash!); // stop sharing; files stay
    }
  }

  Future<void> _onHttpUpdate(TaskUpdate update) async {
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
            await _fail(
              id,
              exception?.description ??
                  'The download link stopped working. Try another version.',
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
    if (wifi == _onWifi) return;
    _onWifi = wifi;
    if (!_settings.wifiOnlyDownloads) return;
    final rows = await (_db.select(
      _db.downloads,
    )..where((t) => t.kind.equals('torrent'))).get();
    for (final row in rows) {
      if (!wifi && row.state == 'downloading') {
        if (row.infoHash != null && _engines.isRunning)
          _engines.engine.pause(row.infoHash!);
        await _update(
          row.id,
          const DownloadsCompanion(
            state: Value('paused'),
            error: Value('Waiting for Wi-Fi'),
          ),
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

  Future<void> _refreshKeepAlive() async {
    final active =
        await (_db.select(_db.downloads)..where(
              (t) => t.kind.equals('torrent') & t.state.equals('downloading'),
            ))
            .get();
    if (active.isEmpty) await BackgroundKeeper.instance.release();
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
      if (saved.isNotEmpty) {
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
    if (path != null) {
      final f = File(path);
      if (f.existsSync()) await f.delete();
    }
    for (final s in await savedDownloadSubtitles(_db, row.videoId)) {
      final f = File(s['path']!);
      if (f.existsSync()) await f.delete();
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

  Future<DownloadRow?> _row(String id) => (_db.select(
    _db.downloads,
  )..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> _update(String id, DownloadsCompanion c) =>
      (_db.update(_db.downloads)..where((t) => t.id.equals(id))).write(c);

  Future<void> _fail(String id, String message) async {
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
    _poll?.cancel();
    unawaited(_events?.cancel());
    unawaited(_http?.cancel());
    unawaited(_net?.cancel());
  }
}

final downloadsServiceProvider = Provider<DownloadsService>((ref) {
  final s = DownloadsService(ref);
  ref.onDispose(s.dispose);
  return s;
});
