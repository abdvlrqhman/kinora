import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stremio/stremio.dart';

/// Identifies one movie or episode to resolve.
final class VideoRef {
  const VideoRef({
    required this.type,
    required this.mediaId,
    required this.videoId,
    this.season,
    this.episode,
    this.runtimeMinutes,
  });

  final String type;
  final String mediaId;
  final String videoId;
  final int? season;
  final int? episode;
  final int? runtimeMinutes;

  @override
  bool operator ==(Object other) =>
      other is VideoRef && other.videoId == videoId && other.type == type;

  @override
  int get hashCode => Object.hash(type, videoId);
}

/// One playable version of a video, explained in plain words.
final class ResolvedRelease {
  const ResolvedRelease({
    required this.candidateId,
    required this.releaseName,
    required this.headline,
    required this.reasons,
    required this.warnings,
    required this.score,
    this.sizeBytes,
    this.seeders,
    this.instant = false,
    this.resolution,
    this.source,
    this.addonName,
    this.stream,
    this.fileIndex,
  });

  final String candidateId;

  /// Raw release name ("Show.S01E02.1080p.WEB-DL.DDP5.1-GRP").
  final String releaseName;

  /// Short summary for under a Play button ("1080p WEB-DL, 214 seeds").
  final String headline;

  /// Why it ranks where it does ("Arabic subtitles match", "Plays on TV").
  final List<String> reasons;

  /// Things to know ("Few seeds", "DTS audio won't play on TV").
  final List<String> warnings;
  final double score;
  final int? sizeBytes;
  final int? seeders;

  /// Debrid-cached or direct link: starts immediately.
  final bool instant;

  /// e.g. "1080p", "4K".
  final String? resolution;

  /// e.g. "WEB-DL", "BluRay".
  final String? source;
  final String? addonName;

  /// The addon stream behind this release (torrent hash, URL, trackers).
  final StreamItem? stream;

  /// File inside the torrent, when known.
  final int? fileIndex;
}

/// Releases for one video, best first.
final class ResolveResult {
  const ResolveResult({
    required this.releases,
    this.rejectedCount = 0,
    this.sourcesAsked = 0,
    this.sourcesFailed = 0,
    this.message,
  });

  /// Ranked, best first. Empty when nothing playable was found.
  final List<ResolvedRelease> releases;
  final int rejectedCount;
  final int sourcesAsked;
  final int sourcesFailed;

  /// Plain-English note when [releases] is empty ("Add a source…").
  final String? message;

  ResolvedRelease? get best => releases.isEmpty ? null : releases.first;
}

// shortcut: stub until the ranking pipeline lands; returns no releases.
final resolveProvider = FutureProvider.autoDispose
    .family<ResolveResult, VideoRef>(
      (ref, video) async => const ResolveResult(
        releases: [],
        message: 'Add a source to find versions.',
      ),
    );
