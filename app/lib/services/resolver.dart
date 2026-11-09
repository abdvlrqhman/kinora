import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ranking/ranking.dart';
import 'package:release_parser/release_parser.dart';
import 'package:stremio/stremio.dart';
import 'package:swarm/swarm.dart';

import '../app/providers.dart';
import '../core/log.dart';
import 'engine_service.dart';
import 'sources.dart';

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
    this.noStreamSource = false,
  });

  /// Ranked, best first. Empty when nothing playable was found.
  final List<ResolvedRelease> releases;
  final int rejectedCount;
  final int sourcesAsked;
  final int sourcesFailed;

  /// Plain-English note when [releases] is empty ("Add a source…").
  final String? message;

  /// No installed source provides streams (only catalogs/subtitles): the fix
  /// is adding one, not retrying.
  final bool noStreamSource;

  ResolvedRelease? get best => releases.isEmpty ? null : releases.first;
}

/// What this phone decodes well through the player (mpv).
final phoneCaps = DeviceCaps(
  h265: true,
  h265TenBit: true,
  av1: true,
  // mpv renders Dolby Vision profile 5 with wrong colors; hybrids keep HDR10.
  dolbyVision: false,
  hdr10: true,
);

/// Samsung 5 Series Full HD (Tizen) as a cast target; see packages/dlna
/// CastProfile.samsungFullHdTizen for the sources.
final samsungFullHdCaps = DeviceCaps(
  h265: true,
  h265TenBit: true,
  av1: false,
  dolbyVision: false,
  hdr10: false,
  maxResolution: Resolution.p1080,
  audio: {AudioCodec.aac, AudioCodec.ac3, AudioCodec.eac3, AudioCodec.mp3},
  containers: {'mkv', 'mp4', 'ts', 'm2ts'},
);

/// Set while a TV is the playback target (the cast service updates it).
final castTargetCapsProvider =
    NotifierProvider<ValueNotifierOf<DeviceCaps?>, DeviceCaps?>(
      () => ValueNotifierOf(null),
    );

/// Recent stream download speed (bytes/s), used to avoid files that can't
/// stream smoothly. The player updates it.
final bandwidthEstimateProvider =
    NotifierProvider<ValueNotifierOf<double?>, double?>(
      () => ValueNotifierOf(null),
    );

/// A provider value set from outside (cast target, measured speed).
class ValueNotifierOf<T> extends Notifier<T> {
  ValueNotifierOf(this._initial);
  final T _initial;

  @override
  T build() => _initial;

  // ignore: use_setters_to_change_properties
  void set(T value) => state = value;
}

/// Subtitle fit per candidate: candidate id → language → 0..1. The
/// subtitles service overrides this; by default nothing is known.
final subtitleFitProvider =
    Provider<
      Future<Map<String, Map<String, double>>> Function(
        VideoRef,
        Map<String, String>,
      )
    >(
      (ref) =>
          (video, releaseNames) async => const {},
    );

/// True on mobile data (ranking then prefers smaller files).
final onCellularProvider = StreamProvider<bool>(
  (ref) => Connectivity().onConnectivityChanged.map(
    (r) =>
        r.contains(ConnectivityResult.mobile) &&
        !r.contains(ConnectivityResult.wifi) &&
        !r.contains(ConnectivityResult.ethernet),
  ),
);

/// Live seeders/leechers for info-hashes (BEP 15 UDP scrape, ~2.5 s).
typedef SwarmLookup = Future<Map<String, SwarmStats>> Function(
  List<String> infoHashes,
  Set<Uri> extraTrackers,
);

final swarmLookupProvider = Provider<SwarmLookup>((ref) {
  final scraper = TrackerScraper(
    httpClient: ref.watch(httpClientProvider),
    userAgent: 'Kinora/$kinoraVersion',
  );
  return (hashes, extra) async {
    final trackers = await ref.read(trackerListProvider).load();
    return scraper.scrape(
      hashes,
      trackers: [
        ...trackers.take(20),
        ...extra.where((t) => t.scheme == 'udp').take(10),
      ],
    );
  };
});

/// Resolves and ranks every version of one movie/episode. Cached for a few
/// minutes so the title page, player and Up Next share the work.
final resolveProvider = FutureProvider.autoDispose
    .family<ResolveResult, VideoRef>((ref, video) async {
      final keep = ref.keepAlive();
      final timer = Timer(const Duration(minutes: 4), keep.close);
      ref.onDispose(timer.cancel);
      try {
        final result = await _resolve(ref, video);
        // Only good answers are reused; "Try again" must really try again.
        if (result.releases.isEmpty || result.sourcesFailed > 0) keep.close();
        return result;
      } on Object {
        keep.close();
        rethrow;
      }
    });

Future<ResolveResult> _resolve(Ref ref, VideoRef video) async {
  final addons = await ref.watch(enabledAddonsProvider.future);
  final settings = ref.read(settingsProvider);
  final streamAddons = [
    for (final a in addons)
      if (a.supports('stream', video.type, video.videoId)) a,
  ];
  if (!addons.any(
    (a) => a.manifest.resources.any((res) => res.name == 'stream'),
  )) {
    return const ResolveResult(
      releases: [],
      noStreamSource: true,
      message: 'Your sources only list titles. Add a source that provides streams to play them.',
    );
  }
  if (streamAddons.isEmpty) {
    return const ResolveResult(
      releases: [],
      message: 'None of your sources offers versions of this.',
    );
  }

  // 1. Ask every source at once.
  final query = ref
      .read(aggregatorProvider)
      .streams(streamAddons, video.type, video.videoId);
  final perAddon = await query.results.toList();
  final failed = perAddon.where((r) => r.error != null).length;
  final rejection = perAddon
      .map((r) => r.error)
      .whereType<DebridKeyRejectedException>()
      .firstOrNull;

  // 2. Parse and dedupe.
  final byId =
      <String, ({StreamItem stream, ParsedRelease parsed, String addon})>{};
  for (final r in perAddon) {
    for (final s in r.items) {
      if (isDebridKeyRejection(s)) continue;
      final id = s.infoHash != null
          ? '${s.infoHash}:${s.fileIdx ?? -1}'
          : (s.url ?? s.externalUrl ?? s.title ?? '');
      if (id.isEmpty || byId.containsKey(id)) continue;
      final parsed = parseAddonStream(
        name: s.name,
        title: s.title,
        description: s.description,
        filename: s.filename,
      );
      byId[id] = (stream: s, parsed: parsed, addon: r.addon.manifest.name);
    }
  }
  if (byId.isEmpty) {
    return ResolveResult(
      releases: const [],
      sourcesAsked: streamAddons.length,
      sourcesFailed: failed,
      message: rejection != null
          ? 'Your debrid service rejected its key. Check it in Settings › Sources.'
          : failed == streamAddons.length
          ? 'Your sources didn’t answer. Check your connection and try again.'
          : 'No versions were found for this yet.',
    );
  }

  // 3. Live swarm health for the most promising torrents (≈2.5 s).
  final hashes = <String>[
    for (final e
        in (byId.values.where((v) => v.stream.infoHash != null).toList()..sort(
              (a, b) =>
                  (b.parsed.seeders ?? 0).compareTo(a.parsed.seeders ?? 0),
            ))
            .take(70))
      e.stream.infoHash!,
  ];
  var live = <String, SwarmStats>{};
  if (hashes.isNotEmpty) {
    try {
      live = await ref.read(swarmLookupProvider)(hashes, {
        for (final v in byId.values)
          for (final t in v.stream.trackers) ?Uri.tryParse(t),
      });
    } on Object catch (e) {
      Log.d('resolve', 'scrape failed: $e');
    }
  }

  // 4. Subtitle fit for each release in the user's languages.
  var fit = <String, Map<String, double>>{};
  if (settings.subtitleLanguages.isNotEmpty) {
    try {
      fit = await ref
          .read(subtitleFitProvider)(video, {
            for (final e in byId.entries)
              e.key: e.value.stream.filename ?? e.value.parsed.raw,
          })
          .timeout(const Duration(seconds: 6));
    } on Object catch (e) {
      Log.d('resolve', 'subtitle fit unavailable: $e');
    }
  }

  // 5. Rank.
  final now = DateTime.now();
  final candidates = [
    for (final e in byId.entries)
      Candidate(
        id: e.key,
        release: e.value.parsed,
        addonId: e.value.addon,
        sizeBytes: e.value.stream.videoSize ?? e.value.parsed.sizeBytes,
        addonSeeders: e.value.parsed.seeders,
        live: switch (live[e.value.stream.infoHash]) {
          final s? when s.sources > 0 => SwarmHealth(
            seeders: s.seeders,
            leechers: s.leechers,
            measuredAt: now,
          ),
          _ => null,
        },
        isDirectUrl:
            e.value.stream.url != null && e.value.stream.infoHash == null,
        isDebridCached: e.value.parsed.debridCached ?? false,
        fileIndex: e.value.stream.fileIdx,
        subtitleFit: fit[e.key] ?? const {},
      ),
  ];
  final prefs = RankPrefs(
    device: phoneCaps,
    audioLanguages: [
      for (final l in settings.audioLanguages)
        if (l != 'original') l,
    ],
    subtitleLanguages: settings.subtitleLanguages,
    maxResolution: _resolution(settings.maxResolution),
    castTarget: ref.read(castTargetCapsProvider),
    bandwidthBytesPerSec: ref.read(bandwidthEstimateProvider),
    runtimeMinutes: video.runtimeMinutes,
    dataSaver:
        settings.dataSaver || (ref.read(onCellularProvider).value ?? false),
  );
  final ranked = rank(
    candidates,
    prefs,
    episode: video.season != null && video.episode != null
        ? EpisodeRef(season: video.season!, episode: video.episode!)
        : null,
  );
  final kept = ranked.where((r) => !r.isRejected).toList();
  return ResolveResult(
    releases: [
      for (final r in kept) _toRelease(r, byId[r.candidate.id]!.stream),
    ],
    rejectedCount: ranked.length - kept.length,
    sourcesAsked: streamAddons.length,
    sourcesFailed: failed,
    message: kept.isEmpty
        ? 'The versions found are for other episodes or can’t play here.'
        : null,
  );
}

Resolution _resolution(int lines) => switch (lines) {
  >= 2160 => Resolution.p2160,
  >= 1440 => Resolution.p1440,
  >= 1080 => Resolution.p1080,
  >= 720 => Resolution.p720,
  _ => Resolution.p480,
};

ResolvedRelease _toRelease(RankedCandidate r, StreamItem stream) {
  final c = r.candidate;
  final p = c.release;
  final instant = c.isDebridCached || c.isDirectUrl;
  final seeds = c.live?.seeders ?? c.addonSeeders;
  final availability = instant
      ? 'Instant'
      : seeds == null
      ? null
      : seeds == 1
      ? '1 seed'
      : '$seeds seeds';
  final quality = p.quality.isEmpty ? 'Unknown quality' : p.quality;
  return ResolvedRelease(
    candidateId: c.id,
    releaseName: p.raw,
    headline: [quality, ?availability].join(', '),
    reasons: [
      for (final reason in r.reasons)
        if (reason.kind != RankReasonKind.quality &&
            reason.kind != RankReasonKind.availability)
          reason.label,
    ],
    warnings: [for (final w in r.warnings) w.label],
    score: r.score,
    sizeBytes: c.sizeBytes,
    seeders: seeds,
    instant: instant,
    resolution: p.resolution == Resolution.unknown ? null : p.resolution.label,
    source: p.source == Source.unknown ? null : p.source.label,
    addonName: c.addonId,
    stream: stream,
    fileIndex: c.fileIndex,
  );
}
