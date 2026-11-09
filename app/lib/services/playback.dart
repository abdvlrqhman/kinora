import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kinora_engine/kinora_engine.dart';
import 'package:swarm/swarm.dart';

import '../app/providers.dart';
import '../core/log.dart';
import 'downloads.dart';
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
    this.owner,
    this.fileIndex,
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

  /// Claim held on the torrent's file while this source is in use.
  final String? owner;
  final int? fileIndex;
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

/// Starting a specific version (named on the preparing screen).
final class Starting extends PrepareStatus {
  const Starting(this.release);
  final ResolvedRelease release;
}

final class TryingNext extends PrepareStatus {
  const TryingNext(this.reason);
  final String reason;
}

/// Thrown when nothing could be played; [message] is user-facing.
final class PlaybackException implements Exception {
  const PlaybackException(this.message, {this.noStreamSource = false});
  final String message;

  /// Nothing can play until a stream source is added.
  final bool noStreamSource;
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

  /// Versions that couldn't start during this session (skipped on retries).
  final failedCandidates = <String>{};

  /// Episodes whose unfinished download's torrent didn't start: versions
  /// are looked up for them instead.
  final failedDownloadTorrents = <String>{};

  Future<PlaybackSource> prepare(
    PlayRequest request, {
    void Function(PrepareStatus)? onStatus,
    Future<void>? cancel,
    int? runtimeMinutes,
    Set<String> skip = const {},
  }) async {
    if (request.localFile != null && File(request.localFile!).existsSync()) {
      return PlaybackSource(
        uri: Uri.file(request.localFile!),
        kind: PlaybackKind.local,
      );
    }
    final link = request.videoId;
    if (link.startsWith('magnet:')) {
      final magnet = Magnet.tryParse(link);
      if (magnet == null)
        throw const PlaybackException('This magnet link isn’t valid.');
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

    // Downloading this episode already: play that torrent, not another
    // version from the start (unless the viewer picked one).
    if (request.candidateId == null &&
        !failedDownloadTorrents.contains(request.videoId)) {
      final d = await unfinishedTorrentDownload(
        _ref.read(databaseProvider),
        request.videoId,
      );
      if (d != null) {
        try {
          return await _torrent(
            infoHash: d.infoHash!,
            name: d.releaseName,
            trackers: Magnet.tryParse(d.magnet ?? '')?.trackers ?? const [],
            fileIndex: d.fileIndex,
            request: request,
            runtimeMinutes: runtimeMinutes,
            onStatus: onStatus,
          );
        } on PlaybackException catch (e) {
          failedDownloadTorrents.add(request.videoId);
          Log.w('playback', 'the download’s torrent: ${e.message}');
        }
      }
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
    // A version the viewer picked is tried alone (and reported if dead);
    // otherwise versions that already failed this session are skipped.
    final picked = request.candidateId == null
        ? null
        : result.releases
              .where((r) => r.candidateId == request.candidateId)
              .firstOrNull;
    final ordered = picked != null
        ? [picked]
        : [
            for (final r in result.releases)
              if (!skip.contains(r.candidateId)) r,
          ];
    if (ordered.isEmpty) {
      throw PlaybackException(
        result.message ?? 'No version of this is available right now.',
        noStreamSource: result.noStreamSource,
      );
    }
    Object? lastError;
    for (final release in ordered.take(picked != null ? 1 : 4)) {
      if (cancel != null && await _isDone(cancel))
        throw const PlaybackException('Cancelled.');
      try {
        onStatus?.call(Starting(release));
        return await _fromRelease(release, request, runtimeMinutes, onStatus);
      } on PlaybackException catch (e) {
        lastError = e;
        failedCandidates.add(release.candidateId);
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
    final existed = engine.status(infoHash.toLowerCase()) != null;
    final ih = engineService.add(
      infoHash: infoHash,
      name: name,
      trackers: trackers,
    );
    final owner =
        'stream:${request.videoId}:${DateTime.now().microsecondsSinceEpoch}';
    // Keep it warm while metadata arrives; nothing downloads yet.
    engineService.claim(ih, owner, -1);
    try {
      final deadline = DateTime.now().add(
        release?.seeders == 0 ? const Duration(seconds: 10) : metadataTimeout,
      );
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
      engineService.claim(ih, owner, file.index);
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
        owner: owner,
        fileIndex: file.index,
      );
    } on Object {
      // Don't leave a torrent we started running for nobody.
      engineService.release(ih, owner);
      if (!existed) engineService.removeIfUnclaimed(ih, deleteFiles: true);
      rethrow;
    }
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
