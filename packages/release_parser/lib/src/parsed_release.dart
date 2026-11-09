import 'enums.dart';

/// Everything that could be read from one release name (and, for addon
/// streams, from the addon's emoji metadata lines).
///
/// Immutable; collections are unmodifiable. Unknown values are `null`,
/// empty, `false` or the enum's `unknown` member.
final class ParsedRelease {
  /// Creates a parsed release. Normally produced by `parseRelease` or
  /// `parseAddonStream`; public so tests and callers can build fixtures.
  ParsedRelease({
    required this.raw,
    this.title = '',
    this.year,
    List<int> seasons = const [],
    List<int> episodes = const [],
    this.absoluteEpisode,
    this.isSeasonPack = false,
    this.isCompleteSeries = false,
    this.resolution = Resolution.unknown,
    this.source = Source.unknown,
    this.videoCodec = VideoCodec.unknown,
    this.bitDepth,
    Set<HdrFormat> hdr = const {},
    List<AudioCodec> audioCodecs = const [],
    this.atmos = false,
    this.channels,
    Set<String> languages = const {},
    Set<String> subtitleLanguages = const {},
    this.multiAudio = false,
    this.dualAudio = false,
    this.dubbed = false,
    this.hardcodedSubs = false,
    this.group,
    this.proper = false,
    this.repack = false,
    this.extended = false,
    this.imax = false,
    this.threeD = false,
    this.container,
    this.sizeBytes,
    this.seeders,
    this.provider,
    this.debridCached,
  }) : seasons = List.unmodifiable(seasons),
       episodes = List.unmodifiable(episodes),
       hdr = Set.unmodifiable(hdr),
       audioCodecs = List.unmodifiable(audioCodecs),
       languages = Set.unmodifiable(languages),
       subtitleLanguages = Set.unmodifiable(subtitleLanguages);

  /// The exact text that was parsed.
  final String raw;

  /// Cleaned title (separators normalised, tags removed). May be empty.
  final String title;

  /// Release year, if one was found outside the title.
  final int? year;

  /// Seasons covered, ascending. Empty for movies and absolute-numbered anime.
  final List<int> seasons;

  /// Episodes covered, ascending. With an empty [seasons] these are absolute
  /// (anime) numbers.
  final List<int> episodes;

  /// Absolute episode number for single anime episodes (`Title - 1071`).
  final int? absoluteEpisode;

  /// True when whole season(s) are included (`S01`, `S01-S03`, anime batch).
  final bool isSeasonPack;

  /// True for "complete series" style packs.
  final bool isCompleteSeries;

  /// Vertical resolution.
  final Resolution resolution;

  /// Capture / rip source.
  final Source source;

  /// Video codec.
  final VideoCodec videoCodec;

  /// Colour bit depth (8, 10 or 12) when stated.
  final int? bitDepth;

  /// HDR formats present. Empty for SDR / unknown.
  final Set<HdrFormat> hdr;

  /// Audio codecs in the order they appear in the name (first = main track).
  final List<AudioCodec> audioCodecs;

  /// True when Dolby Atmos is mentioned.
  final bool atmos;

  /// Main audio channel layout, e.g. `5.1`, `7.1`, `2.0`.
  final String? channels;

  /// Audio languages as ISO 639-1 codes.
  final Set<String> languages;

  /// Subtitle languages mentioned in the name (`ESub`, `VOSTFR`, `KORSUB`).
  final Set<String> subtitleLanguages;

  /// "MULTi" / "Multi Audio": several audio languages.
  final bool multiAudio;

  /// "Dual Audio": two audio languages (usually original + dub).
  final bool dualAudio;

  /// Dubbed audio ("DUBBED", "Dublado", "ITA DUB").
  final bool dubbed;

  /// Subtitles burned into the picture (HC, KORSUB, HARDSUB).
  final bool hardcodedSubs;

  /// Release group, e.g. `FLUX` or `SubsPlease`.
  final String? group;

  /// PROPER release (fixes a previous release by another group).
  final bool proper;

  /// REPACK / RERIP (fixes the group's own previous release).
  final bool repack;

  /// Extended / longer cut.
  final bool extended;

  /// IMAX version.
  final bool imax;

  /// Stereoscopic 3D (3D, HSBS, HOU).
  final bool threeD;

  /// Lower-case file extension (`mkv`, `mp4`, `avi`, `ts`, ...) when present.
  final String? container;

  /// Size in bytes from addon metadata (`💾 1.2 GB`, `Size: 1.2GB`).
  final int? sizeBytes;

  /// Seeders from addon metadata (`👤 12`, `Seeders: 12`).
  final int? seeders;

  /// Indexer / tracker / site from addon metadata (`⚙️ ThePirateBay`).
  final String? provider;

  /// Debrid cache state shown by the addon: `true` for `[RD+]` / `⚡`,
  /// `false` for `[RD download]` / `⬇️` / `⏳`, `null` when not shown.
  final bool? debridCached;

  /// Short quality label such as `1080p WEB-DL` or `4K REMUX` (may be empty).
  String get quality => [
    if (resolution != Resolution.unknown) resolution.label,
    if (source != Source.unknown) source.label,
  ].join(' ');

  /// True when any season or episode number was found.
  bool get hasEpisodeInfo =>
      seasons.isNotEmpty || episodes.isNotEmpty || isCompleteSeries;

  /// True for 10-bit or higher video. HDR always implies 10-bit.
  bool get isTenBit => (bitDepth ?? 8) >= 10 || hdr.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ParsedRelease &&
          other.raw == raw &&
          other.title == title &&
          other.year == year &&
          _listEq(other.seasons, seasons) &&
          _listEq(other.episodes, episodes) &&
          other.absoluteEpisode == absoluteEpisode &&
          other.isSeasonPack == isSeasonPack &&
          other.isCompleteSeries == isCompleteSeries &&
          other.resolution == resolution &&
          other.source == source &&
          other.videoCodec == videoCodec &&
          other.bitDepth == bitDepth &&
          _setEq(other.hdr, hdr) &&
          _listEq(other.audioCodecs, audioCodecs) &&
          other.atmos == atmos &&
          other.channels == channels &&
          _setEq(other.languages, languages) &&
          _setEq(other.subtitleLanguages, subtitleLanguages) &&
          other.multiAudio == multiAudio &&
          other.dualAudio == dualAudio &&
          other.dubbed == dubbed &&
          other.hardcodedSubs == hardcodedSubs &&
          other.group == group &&
          other.proper == proper &&
          other.repack == repack &&
          other.extended == extended &&
          other.imax == imax &&
          other.threeD == threeD &&
          other.container == container &&
          other.sizeBytes == sizeBytes &&
          other.seeders == seeders &&
          other.provider == provider &&
          other.debridCached == debridCached;

  @override
  int get hashCode => Object.hashAll([
    raw,
    title,
    year,
    Object.hashAll(seasons),
    Object.hashAll(episodes),
    absoluteEpisode,
    resolution,
    source,
    videoCodec,
    bitDepth,
    Object.hashAllUnordered(hdr),
    Object.hashAll(audioCodecs),
    channels,
    Object.hashAllUnordered(languages),
    group,
    container,
    sizeBytes,
    seeders,
    provider,
    debridCached,
  ]);

  @override
  String toString() {
    final parts = <String>[
      '"$title"',
      if (year != null) '$year',
      if (seasons.isNotEmpty) 'S${seasons.join(',')}',
      if (episodes.isNotEmpty) 'E${episodes.join(',')}',
      if (absoluteEpisode != null) 'abs $absoluteEpisode',
      if (isSeasonPack) 'pack',
      if (isCompleteSeries) 'complete',
      if (quality.isNotEmpty) quality,
      if (videoCodec != VideoCodec.unknown) videoCodec.label,
      if (bitDepth != null) '${bitDepth}bit',
      ...hdr.map((h) => h.label),
      ...audioCodecs.map((a) => a.label),
      if (atmos) 'Atmos',
      ?channels,
      if (languages.isNotEmpty) 'lang ${languages.join('+')}',
      if (subtitleLanguages.isNotEmpty) 'subs ${subtitleLanguages.join('+')}',
      if (multiAudio) 'multi',
      if (dualAudio) 'dual',
      if (dubbed) 'dub',
      if (hardcodedSubs) 'HC',
      if (proper) 'PROPER',
      if (repack) 'REPACK',
      if (extended) 'EXTENDED',
      if (imax) 'IMAX',
      if (threeD) '3D',
      if (group != null) '-$group',
      if (container != null) '.$container',
      if (sizeBytes != null) '${sizeBytes}B',
      if (seeders != null) '$seeders seeds',
      if (provider != null) 'via $provider',
      if (debridCached != null) debridCached! ? 'cached' : 'uncached',
    ];
    return 'ParsedRelease(${parts.join(' ')})';
  }
}

bool _listEq<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _setEq<T>(Set<T> a, Set<T> b) => a.length == b.length && a.containsAll(b);
