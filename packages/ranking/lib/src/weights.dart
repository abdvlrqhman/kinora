import 'package:release_parser/release_parser.dart';

import 'equality.dart';

/// Every tunable number of the ranker, in one place.
///
/// A candidate's score is
/// `availability·A + quality·Q + audioLanguage·L + subtitles·S
///  + bonuses − penalties`, where A, Q, L, S are each 0..1:
///
/// * **A** (availability): 1 for debrid-cached / direct links, else
///   `ln(1+seeds) / ln(1+seedSaturation)` capped at 1, times [addonSeedTrust]
///   when the count comes from the addon instead of a live scrape.
/// * **Q** (quality): [resolutionShare] × resolution fit (1 at the target,
///   −[resolutionStepBelow] per rung below, −[resolutionStepAbove] per rung
///   above) + the rest × [sourceScores].
/// * **L** (audio language): [languageDecay] by position of the best matching
///   preferred language; [noAudioMatch] when none matches; [neutral] when
///   unknown.
/// * **S** (subtitles): max over preferred languages of
///   `languageDecay[i] × fit`, where embedded subtitles count as
///   [embeddedSubtitleFit].
final class RankWeights {
  /// Creates a weight set; the defaults are [standard].
  const RankWeights({
    this.availability = 0.35,
    this.quality = 0.30,
    this.audioLanguage = 0.15,
    this.subtitles = 0.15,
    this.seedSaturation = 100,
    this.addonSeedTrust = 0.85,
    this.unknownSeedsAvailability = 0.25,
    this.fewSeeds = 5,
    this.resolutionShare = 0.6,
    this.resolutionStepBelow = 0.25,
    this.resolutionStepAbove = 0.4,
    this.unknownResolutionFit = 0.4,
    this.sourceScores = const {
      Source.remux: 1.0,
      Source.bluray: 0.9,
      Source.webdl: 0.85,
      Source.webrip: 0.75,
      Source.hdrip: 0.6,
      Source.hdtv: 0.55,
      Source.unknown: 0.5,
      Source.dvd: 0.4,
      Source.screener: 0.2,
      Source.telecine: 0.15,
      Source.telesync: 0.1,
      Source.cam: 0.0,
    },
    this.languageDecay = const [1.0, 0.7, 0.5, 0.35],
    this.neutral = 0.5,
    this.noAudioMatch = 0.1,
    this.embeddedSubtitleFit = 0.9,
    this.subtitleMatchThreshold = 0.75,
    this.properBonus = 0.02,
    this.hdrBonus = 0.04,
    this.dolbyVisionBonus = 0.02,
    this.hdrOnSdrPenalty = 0.03,
    this.packPenalty = 0.05,
    this.episodeUnconfirmedPenalty = 0.05,
    this.unwantedHardsubPenalty = 0.08,
    this.streamHeadroom = 0.8,
    this.largeFilePenaltyPerExcess = 0.25,
    this.largeFileMaxPenalty = 0.25,
    this.minBytesPerSecond = const {
      Resolution.p480: 25000,
      Resolution.p576: 30000,
      Resolution.p720: 50000,
      Resolution.p1080: 100000,
      Resolution.p1440: 150000,
      Resolution.p2160: 250000,
      Resolution.p4320: 500000,
    },
    this.tinyFilePenalty = 0.15,
    this.dataSaverBytesPerSecond = 400000,
    this.dataSaverPenalty = 0.1,
    this.keptUnplayablePenalty = 0.5,
    this.keptPreReleasePenalty = 0.3,
  });

  /// The shipped weights.
  static const standard = RankWeights();

  /// Weight of A (swarm health / instant availability).
  final double availability;

  /// Weight of Q (resolution + source).
  final double quality;

  /// Weight of L (audio language).
  final double audioLanguage;

  /// Weight of S (subtitle fit).
  final double subtitles;

  /// Seeds at which availability saturates.
  final int seedSaturation;

  /// Multiplier for addon-reported (possibly stale) seed counts.
  final double addonSeedTrust;

  /// Availability when no seed count is known at all.
  final double unknownSeedsAvailability;

  /// Below this many seeds a "Few seeds" warning is shown.
  final int fewSeeds;

  /// Share of Q given to resolution (the rest goes to source).
  final double resolutionShare;

  /// Resolution fit lost per rung below the target (480→720→1080→4K→8K).
  final double resolutionStepBelow;

  /// Resolution fit lost per rung above the target.
  final double resolutionStepAbove;

  /// Resolution fit when the name has no resolution.
  final double unknownResolutionFit;

  /// Source quality, 0..1.
  final Map<Source, double> sourceScores;

  /// Weight by preference position (first language weighs most).
  final List<double> languageDecay;

  /// Score used when a component can't be judged.
  final double neutral;

  /// Audio score when no preferred language is present.
  final double noAudioMatch;

  /// Subtitle fit credited to subtitles named in the release itself.
  final double embeddedSubtitleFit;

  /// Fit from which a "subtitles match" reason is shown.
  final double subtitleMatchThreshold;

  /// Bonus for PROPER / REPACK.
  final double properBonus;

  /// Bonus for HDR on an HDR screen.
  final double hdrBonus;

  /// Extra bonus for Dolby Vision on a DV screen.
  final double dolbyVisionBonus;

  /// Penalty for HDR on a non-HDR screen (washed-out tone mapping).
  final double hdrOnSdrPenalty;

  /// Penalty for packs when streaming from the swarm (slower start).
  final double packPenalty;

  /// Penalty when an episode request gets a name without episode numbers.
  final double episodeUnconfirmedPenalty;

  /// Penalty for burned-in subtitles not in the first subtitle language.
  final double unwantedHardsubPenalty;

  /// Share of the bandwidth a stream may use before it counts as too big.
  final double streamHeadroom;

  /// Penalty per 1× of bitrate above `bandwidth × streamHeadroom`.
  final double largeFilePenaltyPerExcess;

  /// Cap for the too-big penalty.
  final double largeFileMaxPenalty;

  /// Bitrates (bytes/s) below which a file is suspiciously small.
  final Map<Resolution, int> minBytesPerSecond;

  /// Penalty for a suspiciously small file.
  final double tinyFilePenalty;

  /// Bitrate above which data saver penalises a file.
  final double dataSaverBytesPerSecond;

  /// Penalty for heavy files in data-saver mode.
  final double dataSaverPenalty;

  /// Penalty for an unplayable candidate kept because nothing else plays.
  final double keptUnplayablePenalty;

  /// Penalty for a CAM/TS kept because nothing else exists.
  final double keptPreReleasePenalty;

  List<Object?> get _fields => [
    availability, quality, audioLanguage, subtitles, seedSaturation, //
    addonSeedTrust, unknownSeedsAvailability, fewSeeds, resolutionShare,
    resolutionStepBelow, resolutionStepAbove, unknownResolutionFit,
    sourceScores, languageDecay, neutral, noAudioMatch, embeddedSubtitleFit,
    subtitleMatchThreshold, properBonus, hdrBonus, dolbyVisionBonus,
    hdrOnSdrPenalty, packPenalty, episodeUnconfirmedPenalty,
    unwantedHardsubPenalty, streamHeadroom, largeFilePenaltyPerExcess,
    largeFileMaxPenalty, minBytesPerSecond, tinyFilePenalty,
    dataSaverBytesPerSecond, dataSaverPenalty, keptUnplayablePenalty,
    keptPreReleasePenalty,
  ];

  @override
  bool operator ==(Object other) =>
      other is RankWeights && deepEquals(_fields, other._fields);

  @override
  int get hashCode => deepHash(_fields);

  @override
  String toString() =>
      'RankWeights(A $availability, Q $quality, L $audioLanguage, S $subtitles)';
}
