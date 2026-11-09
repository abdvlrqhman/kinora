import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kinora_engine/kinora_engine.dart';
import 'package:swarm/swarm.dart';

import '../core/log.dart';
import 'engine_service.dart';
import 'play_request.dart';
import 'resolver.dart';

/// Where the player reads from.
final class PlaybackSource {
  const PlaybackSource({
    required this.uri,
    required this.kind,
    this.headers = const {},
    this.release,
    this.infoHash,
    this.streamToken,
    this.fileName,
    this.sizeBytes,
  });

  final Uri uri;
  final PlaybackKind kind;
  final Map<String, String> headers;
  final ResolvedRelease? release;

  /// Torrent streams: for buffer stats, cleanup and "Keep it".
  final String? infoHash;
  final String? streamToken;
  final String? fileName;
  final int? sizeBytes;
}

enum PlaybackKind { local, direct, torrent }

/// Progress while a source is being prepared, in the viewer's words.
sealed class PrepareStatus {
  const PrepareStatus();
}

final class Resolving extends PrepareStatus {
  const Resolving();
}

final class FindingPeers extends PrepareStatus {
  const FindingPeers({required this.peers, required this.seeds});
  final int peers;
  final int seeds;
}

final class TryingNext extends PrepareStatus {
  const TryingNext(this.reason);
  final String reason;
}

/// Thrown when nothing could be played; [message] is user-facing.
final class PlaybackException implements Exception {
  const PlaybackException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Turns a [PlayRequest] into a [PlaybackSource]: offline file, direct link,
/// debrid URL or a torrent stream through the engine. When a torrent finds
/// no peers in time it moves on to the next-best release.
final class PlaybackService {
  PlaybackService(this._ref);
  final Ref _ref;

  static const metadataTimeout = Duration(seconds: 25);

  Future<PlaybackSource> prepare(
    PlayRequest request, {
    void Function(PrepareStatus)? onStatus,
    Future<void>? cancel,
    int? runtimeMinutes,
  }) async {
    if (request.localFile != null && File(request.localFile!).existsSync()) {
      return PlaybackSource(
        uri: Uri.file(request.localFile!),
        kind: PlaybackKind.local,
      );
    }
    final link = request.videoId;
    if (link.startsWith('magnet:')) {
      final magnet = Magnet.parse(link);
      final ih = magnet.infoHash;
      if (ih == null)
        throw const PlaybackException(
          'This link only has a v2 hash, which isn’t supported yet.',
        );
      return _torrent(
        infoHash: ih,
        name: magnet.name,
        trackers: magnet.trackers,
        fileIndex: null,
        request: request,
        runtimeMinutes: runtimeMinutes,
        onStatus: onStatus,
      );
    }
    if (link.startsWith('http://') || link.startsWith('https://')) {
      return PlaybackSource(uri: Uri.parse(link), kind: PlaybackKind.direct);
    }

    onStatus?.call(const Resolving());
    final result = await _ref.read(
      resolveProvider(
        VideoRef(
          type: request.type,
          mediaId: request.mediaId,
          videoId: request.videoId,
          season: request.season,
          episode: request.episode,
          runtimeMinutes: runtimeMinutes,
        ),
      ).future,
    );
    final ordered = [...result.releases];
    if (request.candidateId != null) {
      final i = ordered.indexWhere((r) => r.candidateId == request.candidateId);
      if (i > 0) ordered.insert(0, ordered.removeAt(i));
    }
    if (ordered.isEmpty) {
      throw PlaybackException(
        result.message ?? 'No version of this is available right now.',
      );
    }
    Object? lastError;
    for (final release in ordered.take(4)) {
      if (cancel != null && await _isDone(cancel))
        throw const PlaybackException('Cancelled.');
      try {
        return await _fromRelease(release, request, runtimeMinutes, onStatus);
      } on PlaybackException catch (e) {
        lastError = e;
        Log.w('playback', '${release.releaseName}: ${e.message}');
        onStatus?.call(TryingNext(e.message));
      }
    }
    throw PlaybackException(
      lastError is PlaybackException
          ? '${lastError.message} Choose another version to try again.'
          : 'None of the versions could start.',
    );
  }

  Future<PlaybackSource> _fromRelease(
    ResolvedRelease release,
    PlayRequest request,
    int? runtimeMinutes,
    void Function(PrepareStatus)? onStatus,
  ) async {
    final stream = release.stream;
    if (stream == null)
      throw const PlaybackException('This version has no link.');
    if (stream.url != null) {
      return PlaybackSource(
        uri: Uri.parse(stream.url!),
        kind: PlaybackKind.direct,
        headers: stream.proxyRequestHeaders,
        release: release,
        fileName: stream.filename,
        sizeBytes: stream.videoSize,
      );
    }
    final ih = stream.infoHash;
    if (ih == null)
      throw const PlaybackException('This version can’t be played here.');
    return _torrent(
      infoHash: ih,
      name: stream.filename ?? release.releaseName,
      trackers: stream.trackers.map((u) => u.toString()).toList(),
      fileIndex: release.fileIndex ?? stream.fileIdx,
      request: request,
      runtimeMinutes: runtimeMinutes,
      onStatus: onStatus,
      release: release,
    );
  }

  Future<PlaybackSource> _torrent({
    required String infoHash,
    required String? name,
    required List<String> trackers,
    required int? fileIndex,
    required PlayRequest request,
    required int? runtimeMinutes,
    void Function(PrepareStatus)? onStatus,
    ResolvedRelease? release,
  }) async {
    final engineService = _ref.read(engineServiceProvider);
    final engine = engineService.engine;
    final ih = engineService.add(
      infoHash: infoHash,
      name: name,
      trackers: trackers,
    );
    final deadline = DateTime.now().add(metadataTimeout);
    List<TorrentFile>? files;
    while ((files = engine.files(ih)) == null) {
      final st = engine.status(ih);
      onStatus?.call(
        FindingPeers(peers: st?.numPeers ?? 0, seeds: st?.numSeeds ?? 0),
      );
      if (DateTime.now().isAfter(deadline)) {
        throw const PlaybackException(
          'No one is sharing this version right now.',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    final file = pickFile(
      files!,
      fileIndex: fileIndex,
      season: request.season,
      episode: request.episode,
    );
    if (file == null)
      throw const PlaybackException('This version has no video file.');
    // Only the chosen file downloads (packs!), the rest stay untouched.
    engine.setFilePriorities(ih, [
      for (final f in files) f.index == file.index ? 4 : 0,
    ]);
    final bitrate = runtimeMinutes != null && runtimeMinutes > 0
        ? file.size ~/ (runtimeMinutes * 60)
        : null;
    final handle = engine.openStream(ih, file.index, bitrate: bitrate);
    return PlaybackSource(
      uri: handle.uri(),
      kind: PlaybackKind.torrent,
      release: release,
      infoHash: ih,
      streamToken: handle.token,
      fileName: file.name,
      sizeBytes: file.size,
    );
  }

  static Future<bool> _isDone(Future<void> f) async {
    var done = false;
    await Future.any([f.then((_) => done = true), Future<void>.value()]);
    return done;
  }
}

/// Chooses the file to play: the addon's index when valid, else the file
/// matching SxxEyy, else the largest video (samples excluded).
TorrentFile? pickFile(
  List<TorrentFile> files, {
  int? fileIndex,
  int? season,
  int? episode,
}) {
  final videos = files.where((f) => f.isVideo).toList();
  if (fileIndex != null) {
    for (final f in files) {
      if (f.index == fileIndex && !f.isPad) return f;
    }
  }
  if (videos.isEmpty) return null;
  if (season != null && episode != null) {
    final pattern = RegExp(
      '(s0*$season[ ._-]*e0*$episode(?!\\d))|(\\b0*${season}x0*$episode(?!\\d))|([ ._-]e0*$episode(?!\\d))',
      caseSensitive: false,
    );
    final matches = videos.where((f) => pattern.hasMatch(f.name)).toList()
      ..sort((a, b) => b.size.compareTo(a.size));
    if (matches.isNotEmpty) return matches.first;
  }
  videos.sort((a, b) => b.size.compareTo(a.size));
  return videos.first;
}

final playbackServiceProvider = Provider<PlaybackService>(PlaybackService.new);
