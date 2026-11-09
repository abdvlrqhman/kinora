import 'dart:typed_data';

import 'package:collection/collection.dart';

import 'cancel.dart';
import 'language.dart';

const _eq = DeepCollectionEquality();

/// Subtitle file formats this package reads.
enum SubtitleFormat {
  srt('srt'),
  webvtt('vtt'),
  ass('ass'),
  ssa('ssa'),
  microDvd('sub'),
  mpl2('txt');

  const SubtitleFormat(this.extension);

  /// Usual file extension, without the dot.
  final String extension;

  /// Guesses the format from a file name or extension (`x.srt`, `vtt`).
  static SubtitleFormat? fromName(String? name) {
    if (name == null) return null;
    final ext = name.toLowerCase().split('.').last.trim();
    return switch (ext) {
      'srt' => srt,
      'vtt' || 'webvtt' => webvtt,
      'ass' => ass,
      'ssa' => ssa,
      'sub' => microDvd,
      'mpl' || 'mpl2' => mpl2,
      _ => null,
    };
  }
}

/// What a provider can do; used by the UI and the orchestrator.
enum ProviderCapability {
  /// Exact matches by OpenSubtitles file hash.
  hashSearch,

  /// Search by IMDb id.
  imdbSearch,

  /// Search by TMDB id.
  tmdbSearch,

  /// Search by Kitsu id (anime).
  kitsuSearch,

  /// Search by title text.
  textSearch,

  /// Movies are supported.
  movieSupport,

  /// TV episodes are supported.
  tvSupport,

  /// Only anime is covered.
  animeOnly,

  /// Results come from other providers (dedupe against them).
  aggregator,
}

/// Movie or a single TV episode.
enum MediaType { movie, episode }

/// What to search subtitles for.
final class SubtitleQuery {
  /// Creates a query. For episodes [imdbId]/[tmdbId] are the *show's* ids.
  const SubtitleQuery({
    required this.type,
    this.imdbId,
    this.tmdbId,
    this.kitsuId,
    this.title,
    this.year,
    this.season,
    this.episode,
    this.languages = const [],
    this.releaseNames = const [],
    this.fileHash,
    this.fileSize,
    this.fps,
    this.durationSec,
  });

  final MediaType type;

  /// IMDb id with `tt` prefix, e.g. `tt0903747` (the show for episodes).
  final String? imdbId;
  final int? tmdbId;
  final int? kitsuId;
  final String? title;
  final int? year;
  final int? season;
  final int? episode;

  /// Wanted languages in preference order.
  final List<Language> languages;

  /// Candidate release names on screen (first = the one being played).
  final List<String> releaseNames;

  /// OpenSubtitles hash of the file being played (16 lowercase hex).
  final String? fileHash;
  final int? fileSize;
  final double? fps;
  final int? durationSec;

  bool get isEpisode => type == MediaType.episode;

  /// IMDb id as a number (`tt0903747` -> 903747), or null.
  int? get imdbNumber =>
      imdbId == null ? null : int.tryParse(imdbId!.replaceFirst('tt', ''));

  @override
  bool operator ==(Object other) =>
      other is SubtitleQuery &&
      other.type == type &&
      other.imdbId == imdbId &&
      other.tmdbId == tmdbId &&
      other.kitsuId == kitsuId &&
      other.title == title &&
      other.year == year &&
      other.season == season &&
      other.episode == episode &&
      _eq.equals(other.languages, languages) &&
      _eq.equals(other.releaseNames, releaseNames) &&
      other.fileHash == fileHash &&
      other.fileSize == fileSize &&
      other.fps == fps &&
      other.durationSec == durationSec;

  @override
  int get hashCode => Object.hash(
    type,
    imdbId,
    tmdbId,
    kitsuId,
    title,
    year,
    season,
    episode,
    _eq.hash(languages),
    _eq.hash(releaseNames),
    fileHash,
    fileSize,
    fps,
    durationSec,
  );

  @override
  String toString() =>
      'SubtitleQuery(${type.name} ${imdbId ?? tmdbId ?? kitsuId ?? title}'
      '${isEpisode ? ' S${season}E$episode' : ''}'
      ' ${languages.map((l) => l.code).join(',')})';
}

/// One subtitle offered by a provider.
final class SubtitleResult {
  const SubtitleResult({
    required this.providerId,
    required this.id,
    required this.language,
    this.releaseNames = const [],
    this.fileName,
    this.hearingImpaired = false,
    this.forced = false,
    this.machineTranslated = false,
    this.fps,
    this.rating,
    this.downloads,
    this.uploadDate,
    this.format,
    this.matchedHash,
    this.comments,
    this.season,
    this.episodeFrom,
    this.episodeTo,
    this.isSeasonPack = false,
    this.payload = const {},
  });

  /// Provider id (see `SubtitleProvider.id`).
  final String providerId;

  /// Provider-native subtitle id.
  final String id;
  final Language language;

  /// Release names the subtitle was made for.
  final List<String> releaseNames;

  /// Original subtitle file name, when known.
  final String? fileName;
  final bool hearingImpaired;

  /// Only foreign-language parts are subtitled.
  final bool forced;

  /// Machine or AI translated.
  final bool machineTranslated;
  final double? fps;

  /// 0..10 when known.
  final double? rating;
  final int? downloads;
  final DateTime? uploadDate;
  final SubtitleFormat? format;

  /// The query file hash this result matched, when matched by hash.
  final String? matchedHash;
  final String? comments;

  /// Season/episode range the provider says this covers (metadata, optional).
  final int? season;
  final int? episodeFrom;
  final int? episodeTo;

  /// The provider says this is a whole-season pack.
  final bool isSeasonPack;

  /// Provider-specific data needed to download (never contains API keys).
  final Map<String, Object?> payload;

  /// Whether this result matched the queried file hash.
  bool get matchedByHash => matchedHash != null;

  /// Stable key across runs: `providerId:id`.
  String get key => '$providerId:$id';

  /// Every name worth parsing for release info (release names + file name).
  List<String> get names => [...releaseNames, ?fileName];

  SubtitleResult copyWith({String? matchedHash, Language? language}) =>
      SubtitleResult(
        providerId: providerId,
        id: id,
        language: language ?? this.language,
        releaseNames: releaseNames,
        fileName: fileName,
        hearingImpaired: hearingImpaired,
        forced: forced,
        machineTranslated: machineTranslated,
        fps: fps,
        rating: rating,
        downloads: downloads,
        uploadDate: uploadDate,
        format: format,
        matchedHash: matchedHash ?? this.matchedHash,
        comments: comments,
        season: season,
        episodeFrom: episodeFrom,
        episodeTo: episodeTo,
        isSeasonPack: isSeasonPack,
        payload: payload,
      );

  @override
  bool operator ==(Object other) =>
      other is SubtitleResult &&
      other.providerId == providerId &&
      other.id == id &&
      other.language == language &&
      _eq.equals(other.releaseNames, releaseNames) &&
      other.fileName == fileName &&
      other.hearingImpaired == hearingImpaired &&
      other.forced == forced &&
      other.machineTranslated == machineTranslated &&
      other.fps == fps &&
      other.rating == rating &&
      other.downloads == downloads &&
      other.uploadDate == uploadDate &&
      other.format == format &&
      other.matchedHash == matchedHash &&
      other.comments == comments &&
      other.season == season &&
      other.episodeFrom == episodeFrom &&
      other.episodeTo == episodeTo &&
      other.isSeasonPack == isSeasonPack &&
      _eq.equals(other.payload, payload);

  @override
  int get hashCode => Object.hashAll([
    providerId,
    id,
    language,
    _eq.hash(releaseNames),
    fileName,
    hearingImpaired,
    forced,
    machineTranslated,
    fps,
    rating,
    downloads,
    uploadDate,
    format,
    matchedHash,
    comments,
    season,
    episodeFrom,
    episodeTo,
    isSeasonPack,
    _eq.hash(payload),
  ]);

  @override
  String toString() =>
      'SubtitleResult($key ${language.code} '
      '"${releaseNames.firstOrNull ?? fileName ?? ''}"'
      '${hearingImpaired ? ' HI' : ''}${forced ? ' forced' : ''}'
      '${machineTranslated ? ' MT' : ''}${matchedByHash ? ' hash' : ''})';
}

/// Raw bytes as served by a provider (may be a ZIP; see `extractSubtitle`).
final class SubtitleDownload {
  const SubtitleDownload({
    required this.bytes,
    required this.fileName,
    this.format,
  });

  final Uint8List bytes;
  final String fileName;

  /// Format when known from the provider or file name; null for archives.
  final SubtitleFormat? format;

  @override
  bool operator ==(Object other) =>
      other is SubtitleDownload &&
      other.fileName == fileName &&
      other.format == format &&
      _eq.equals(other.bytes, bytes);

  @override
  int get hashCode => Object.hash(fileName, format, _eq.hash(bytes));

  @override
  String toString() =>
      'SubtitleDownload($fileName, ${bytes.length} B, ${format?.name})';
}

/// User preferences used for ranking (never hard filters).
final class SubtitlePrefs {
  const SubtitlePrefs({
    this.languages = const [],
    this.preferHearingImpaired = false,
    this.forcedOnly = false,
  });

  /// Preferred languages, most wanted first.
  final List<Language> languages;
  final bool preferHearingImpaired;

  /// Prefer forced (foreign-parts-only) subtitles, e.g. audio already matches.
  final bool forcedOnly;

  @override
  bool operator ==(Object other) =>
      other is SubtitlePrefs &&
      _eq.equals(other.languages, languages) &&
      other.preferHearingImpaired == preferHearingImpaired &&
      other.forcedOnly == forcedOnly;

  @override
  int get hashCode =>
      Object.hash(_eq.hash(languages), preferHearingImpaired, forcedOnly);

  @override
  String toString() =>
      'SubtitlePrefs(${languages.map((l) => l.code).join(',')}'
      '${preferHearingImpaired ? ' HI' : ''}${forcedOnly ? ' forced' : ''})';
}

/// A subtitle source. Implementations take credentials from the caller.
abstract interface class SubtitleProvider {
  /// Stable id, e.g. `opensubtitles`, `subdl`, `stremio:<host>`.
  String get id;

  /// Name for the UI.
  String get displayName;

  /// Whether an API key is needed (the user enters it in Settings).
  bool get requiresKey;

  Set<ProviderCapability> get capabilities;

  /// Finds subtitles for [query] in `query.languages`.
  Future<List<SubtitleResult>> search(
    SubtitleQuery query, {
    CancelToken? cancel,
  });

  /// Downloads the raw file (subtitle or archive) for [result].
  Future<SubtitleDownload> download(
    SubtitleResult result, {
    CancelToken? cancel,
  });
}
