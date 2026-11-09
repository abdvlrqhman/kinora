import 'package:release_parser/release_parser.dart';

import 'equality.dart';

/// Live swarm numbers from a tracker scrape (BEP 15).
final class SwarmHealth {
  /// Creates a scrape result.
  const SwarmHealth({
    required this.seeders,
    required this.leechers,
    required this.measuredAt,
  });

  /// Peers with the whole torrent.
  final int seeders;

  /// Peers still downloading.
  final int leechers;

  /// When the scrape was taken. The ranker trusts it as given; drop stale
  /// scrapes before ranking.
  final DateTime measuredAt;

  List<Object?> get _fields => [seeders, leechers, measuredAt];

  @override
  bool operator ==(Object other) =>
      other is SwarmHealth && deepEquals(_fields, other._fields);

  @override
  int get hashCode => deepHash(_fields);

  @override
  String toString() =>
      'SwarmHealth($seeders seeders, $leechers leechers @ ${measuredAt.toIso8601String()})';
}

/// One playable source for the movie / episode being ranked.
final class Candidate {
  /// Creates a candidate. [subtitleFit] is copied and made unmodifiable.
  Candidate({
    required this.id,
    required this.release,
    required this.addonId,
    this.sizeBytes,
    this.addonSeeders,
    this.live,
    this.isDirectUrl = false,
    this.isDebridCached = false,
    this.fileIndex,
    Map<String, double> subtitleFit = const {},
  }) : subtitleFit = Map.unmodifiable(subtitleFit);

  /// Stable id (e.g. infohash + file index); breaks score ties.
  final String id;

  /// Parsed name / addon text.
  final ParsedRelease release;

  /// Addon that returned it.
  final String addonId;

  /// File size in bytes; falls back to [ParsedRelease.sizeBytes].
  final int? sizeBytes;

  /// Seeders reported by the addon (often stale); falls back to
  /// [ParsedRelease.seeders].
  final int? addonSeeders;

  /// Live tracker scrape, preferred over [addonSeeders].
  final SwarmHealth? live;

  /// Plain HTTP(S) stream (no swarm needed).
  final bool isDirectUrl;

  /// Already cached on the user's debrid service. `ParsedRelease.debridCached`
  /// (`[RD+]`, `⚡`) counts too.
  final bool isDebridCached;

  /// File inside a multi-file torrent, when known.
  final int? fileIndex;

  /// ISO 639-1 code → best subtitle match (0..1) for this exact release.
  final Map<String, double> subtitleFit;

  List<Object?> get _fields => [
    id,
    release,
    addonId,
    sizeBytes,
    addonSeeders,
    live,
    isDirectUrl,
    isDebridCached,
    fileIndex,
    subtitleFit,
  ];

  @override
  bool operator ==(Object other) =>
      other is Candidate && deepEquals(_fields, other._fields);

  @override
  int get hashCode => deepHash(_fields);

  @override
  String toString() => 'Candidate($id, ${release.raw}, via $addonId)';
}

/// What a screen can decode and display. Empty [audio] / [containers] mean
/// "anything".
final class DeviceCaps {
  /// Creates device capabilities; collections are copied.
  DeviceCaps({
    this.h265 = true,
    this.h265TenBit = true,
    this.av1 = false,
    this.dolbyVision = false,
    this.hdr10 = false,
    this.maxResolution = Resolution.p2160,
    Set<AudioCodec> audio = const {},
    Set<String> containers = const {},
  }) : audio = Set.unmodifiable(audio),
       containers = Set.unmodifiable(containers);

  /// Decodes 8-bit HEVC.
  final bool h265;

  /// Decodes 10-bit HEVC (also required for HDR).
  final bool h265TenBit;

  /// Decodes AV1.
  final bool av1;

  /// Displays Dolby Vision (needed for DV-only releases).
  final bool dolbyVision;

  /// Displays HDR10.
  final bool hdr10;

  /// Largest resolution it can decode.
  final Resolution maxResolution;

  /// Audio codecs it plays; empty = all.
  final Set<AudioCodec> audio;

  /// Lower-case containers it plays (`mkv`, `mp4`, ...); empty = all.
  final Set<String> containers;

  List<Object?> get _fields => [
    h265,
    h265TenBit,
    av1,
    dolbyVision,
    hdr10,
    maxResolution,
    audio,
    containers,
  ];

  @override
  bool operator ==(Object other) =>
      other is DeviceCaps && deepEquals(_fields, other._fields);

  @override
  int get hashCode => deepHash(_fields);

  @override
  String toString() =>
      'DeviceCaps(hevc: $h265, hevc10: $h265TenBit, av1: $av1, dv: $dolbyVision, '
      'hdr10: $hdr10, max: ${maxResolution.label}, '
      'audio: ${audio.isEmpty ? 'any' : audio.map((a) => a.label).join('/')}, '
      'containers: ${containers.isEmpty ? 'any' : containers.join('/')})';
}

/// The user's preferences and context for one ranking.
final class RankPrefs {
  /// Creates preferences; lists are copied.
  RankPrefs({
    required this.device,
    List<String> audioLanguages = const [],
    List<String> subtitleLanguages = const [],
    this.maxResolution = Resolution.p2160,
    this.castTarget,
    this.bandwidthBytesPerSec,
    this.runtimeMinutes,
    this.dataSaver = false,
    this.originalLanguage,
  }) : audioLanguages = List.unmodifiable(audioLanguages),
       subtitleLanguages = List.unmodifiable(subtitleLanguages);

  /// Preferred audio languages, best first. Empty = original audio.
  final List<String> audioLanguages;

  /// Preferred subtitle languages, best first (first weighs most).
  final List<String> subtitleLanguages;

  /// Highest resolution the user wants.
  final Resolution maxResolution;

  /// This phone.
  final DeviceCaps device;

  /// The TV being cast to, if any.
  final DeviceCaps? castTarget;

  /// Measured download speed, if known.
  final double? bandwidthBytesPerSec;

  /// Runtime of the movie / episode, for bitrate checks.
  final int? runtimeMinutes;

  /// Prefer small files (≤ 720p, low bitrate).
  final bool dataSaver;

  /// Original audio language of the title (ISO 639-1), if known. Releases
  /// without language tags are assumed to carry it.
  final String? originalLanguage;

  List<Object?> get _fields => [
    audioLanguages,
    subtitleLanguages,
    maxResolution,
    device,
    castTarget,
    bandwidthBytesPerSec,
    runtimeMinutes,
    dataSaver,
    originalLanguage,
  ];

  @override
  bool operator ==(Object other) =>
      other is RankPrefs && deepEquals(_fields, other._fields);

  @override
  int get hashCode => deepHash(_fields);

  @override
  String toString() =>
      'RankPrefs(audio: $audioLanguages, subs: $subtitleLanguages, '
      'max: ${maxResolution.label}, cast: ${castTarget != null}, '
      'bandwidth: $bandwidthBytesPerSec, runtime: $runtimeMinutes, '
      'dataSaver: $dataSaver, original: $originalLanguage)';
}

/// The episode being ranked for (absent for movies).
final class EpisodeRef {
  /// Creates an episode reference.
  const EpisodeRef({
    required this.season,
    required this.episode,
    this.absolute,
  });

  /// Season number.
  final int season;

  /// Episode number within the season.
  final int episode;

  /// Absolute episode number (anime), if known.
  final int? absolute;

  @override
  bool operator ==(Object other) =>
      other is EpisodeRef &&
      other.season == season &&
      other.episode == episode &&
      other.absolute == absolute;

  @override
  int get hashCode => Object.hash(season, episode, absolute);

  @override
  String toString() =>
      'EpisodeRef(S${season}E$episode${absolute == null ? '' : ' #$absolute'})';
}

/// What a [RankReason] is about.
enum RankReasonKind {
  /// Resolution + source ("1080p WEB-DL").
  quality,

  /// Seeds, debrid cache or direct link.
  availability,

  /// Subtitle match in a preferred language.
  subtitles,

  /// Audio in a preferred language.
  audioLanguage,

  /// Plays on the cast target.
  castable,

  /// HDR / Dolby Vision on a capable screen.
  hdr,

  /// PROPER / REPACK fix.
  fix,
}

/// A positive point shown to the user.
final class RankReason {
  /// Creates a reason.
  const RankReason(this.kind, this.label);

  /// Category.
  final RankReasonKind kind;

  /// Short plain-English label, e.g. `214 seeds`.
  final String label;

  @override
  bool operator ==(Object other) =>
      other is RankReason && other.kind == kind && other.label == label;

  @override
  int get hashCode => Object.hash(kind, label);

  @override
  String toString() => label;
}

/// What a [RankWarning] is about.
enum RankWarningKind {
  /// 1–4 seeds.
  fewSeeds,

  /// Zero seeds.
  noSeeds,

  /// No seed count anywhere.
  unknownSeeds,

  /// CAM / TS / TC / SCR.
  preRelease,

  /// This device can't decode or display it.
  unplayableOnDevice,

  /// The cast target can't play it.
  unplayableOnTv,

  /// Bitrate exceeds the connection.
  largeForConnection,

  /// Far too small for its resolution and runtime (likely fake or broken).
  tinyFile,

  /// Heavy file while data saver is on.
  dataHeavy,

  /// Season / series pack: slower to start.
  pack,

  /// Name has no season / episode numbers.
  episodeUnconfirmed,

  /// Audio is a dub the user didn't ask for.
  dubbed,

  /// Subtitles burned into the picture.
  hardcodedSubs,

  /// HDR on a screen without HDR.
  hdrOnSdr,
}

/// A caveat shown to the user.
final class RankWarning {
  /// Creates a warning.
  const RankWarning(this.kind, this.label);

  /// Category.
  final RankWarningKind kind;

  /// Short plain-English label, e.g. `DTS audio won't play on TV`.
  final String label;

  @override
  bool operator ==(Object other) =>
      other is RankWarning && other.kind == kind && other.label == label;

  @override
  int get hashCode => Object.hash(kind, label);

  @override
  String toString() => label;
}

/// Why a candidate was dropped.
enum RejectReason {
  /// Doesn't contain the requested season / episode.
  wrongEpisode,

  /// Cinema recording while proper releases exist.
  preRelease,

  /// This device can't play it while others can.
  unplayableOnDevice,

  /// The cast target can't play it while others can.
  unplayableOnTv,
}

/// A candidate with its score and explanation.
final class RankedCandidate {
  /// Creates a ranked candidate; lists are copied.
  RankedCandidate({
    required this.candidate,
    required this.score,
    List<RankReason> reasons = const [],
    List<RankWarning> warnings = const [],
    this.rejected,
  }) : reasons = List.unmodifiable(reasons),
       warnings = List.unmodifiable(warnings);

  /// The input candidate.
  final Candidate candidate;

  /// Higher is better. Comparable only within one `rank` call.
  final double score;

  /// What speaks for it, most important first.
  final List<RankReason> reasons;

  /// Caveats.
  final List<RankWarning> warnings;

  /// Set when the candidate should be hidden from "Best".
  final RejectReason? rejected;

  /// Whether [rejected] is set.
  bool get isRejected => rejected != null;

  /// One-line summary: `1080p WEB-DL · 214 seeds · Arabic subtitles match`.
  String get summary => reasons.map((r) => r.label).join(' · ');

  List<Object?> get _fields => [candidate, score, reasons, warnings, rejected];

  @override
  bool operator ==(Object other) =>
      other is RankedCandidate && deepEquals(_fields, other._fields);

  @override
  int get hashCode => deepHash(_fields);

  @override
  String toString() =>
      'RankedCandidate(${candidate.id}, ${score.toStringAsFixed(3)}, '
      '[$summary]${warnings.isEmpty ? '' : ' warn: ${warnings.join('; ')}'}'
      '${rejected == null ? '' : ' rejected: ${rejected!.name}'})';
}
