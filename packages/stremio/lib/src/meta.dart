import 'json.dart';

/// A catalog item (Meta Preview Object).
class MetaPreview {
  /// Creates a preview.
  const MetaPreview({
    required this.id,
    required this.type,
    required this.name,
    this.poster,
    this.posterShape,
    this.background,
    this.logo,
    this.description,
    this.releaseInfo,
    this.imdbRating,
    this.genres = const [],
    this.links = const [],
    this.trailerYouTubeIds = const [],
  });

  /// Parses a Meta Preview Object; throws `AddonResponseException` when
  /// `id`, `type` or `name` is missing.
  factory MetaPreview.fromJson(Object? value) {
    final json = jsonObject(value, 'meta');
    return MetaPreview(
      id: requireString(json, 'id', 'meta'),
      type: requireString(json, 'type', 'meta'),
      name: requireString(json, 'name', 'meta'),
      poster: readString(json, 'poster'),
      posterShape: readString(json, 'posterShape'),
      background: readString(json, 'background'),
      logo: readString(json, 'logo'),
      description: readString(json, 'description'),
      releaseInfo: readString(json, 'releaseInfo'),
      imdbRating: readString(json, 'imdbRating'),
      genres: _genres(json),
      links: List.unmodifiable(
        readObjects(json, 'links').map(MetaLink._parse).nonNulls,
      ),
      trailerYouTubeIds: _trailers(json),
    );
  }

  /// Universal id, e.g. `tt0903747` or `kitsu:1`.
  final String id;

  /// Content type, e.g. `movie`, `series`, `anime`.
  final String type;

  /// Title.
  final String name;

  /// Poster image URL.
  final String? poster;

  /// `poster`, `square` or `landscape`; null means `poster`.
  final String? posterShape;

  /// Background image URL.
  final String? background;

  /// Logo image URL.
  final String? logo;

  /// Synopsis.
  final String? description;

  /// Year or year range, e.g. `2008–2013`.
  final String? releaseInfo;

  /// IMDb rating as sent (`"9.5"`).
  final String? imdbRating;

  /// Genre names.
  final List<String> genres;

  /// Meta links (genres, cast, IMDb, ...).
  final List<MetaLink> links;

  /// YouTube ids of trailers, from both `trailers` and `trailerStreams`.
  final List<String> trailerYouTubeIds;

  @override
  bool operator ==(Object other) =>
      other is MetaPreview &&
      other.runtimeType == runtimeType &&
      other.id == id &&
      other.type == type &&
      other.name == name &&
      other.poster == poster &&
      other.posterShape == posterShape &&
      other.background == background &&
      other.logo == logo &&
      other.description == description &&
      other.releaseInfo == releaseInfo &&
      other.imdbRating == imdbRating &&
      listEquals(other.genres, genres) &&
      listEquals(other.links, links) &&
      listEquals(other.trailerYouTubeIds, trailerYouTubeIds);

  @override
  int get hashCode => Object.hash(
    id,
    type,
    name,
    poster,
    posterShape,
    background,
    logo,
    description,
    releaseInfo,
    imdbRating,
    Object.hashAll(genres),
    Object.hashAll(links),
    Object.hashAll(trailerYouTubeIds),
  );

  @override
  String toString() => 'MetaPreview($type $id "$name")';
}

/// Full metadata for one item (Meta Object), as returned by `/meta`.
final class MetaDetail extends MetaPreview {
  /// Creates a detail object.
  const MetaDetail({
    required super.id,
    required super.type,
    required super.name,
    super.poster,
    super.posterShape,
    super.background,
    super.logo,
    super.description,
    super.releaseInfo,
    super.imdbRating,
    super.genres,
    super.links,
    super.trailerYouTubeIds,
    this.videos = const [],
    this.cast = const [],
    this.director = const [],
    this.runtime,
    this.released,
    this.defaultVideoId,
  });

  /// Parses a Meta Object (the value of `meta` in a `/meta` response).
  factory MetaDetail.fromJson(Object? value) {
    final p = MetaPreview.fromJson(value);
    final json = value! as JsonMap;
    final hints = json['behaviorHints'] is Map<String, Object?>
        ? json['behaviorHints']! as JsonMap
        : const <String, Object?>{};
    return MetaDetail(
      id: p.id,
      type: p.type,
      name: p.name,
      poster: p.poster,
      posterShape: p.posterShape,
      background: p.background,
      logo: p.logo,
      description: p.description,
      releaseInfo: p.releaseInfo,
      imdbRating: p.imdbRating,
      genres: p.genres,
      links: p.links,
      trailerYouTubeIds: p.trailerYouTubeIds,
      videos: List.unmodifiable(
        readObjects(json, 'videos').map(Episode._parse).nonNulls,
      ),
      cast: readStrings(json, 'cast'),
      director: readStrings(json, 'director'),
      runtime: readString(json, 'runtime'),
      released: readDate(json, 'released'),
      defaultVideoId: readString(hints, 'defaultVideoId'),
    );
  }

  /// Episodes / channel videos; empty for movies (the video id is [id]).
  final List<Episode> videos;

  /// Cast names.
  final List<String> cast;

  /// Director names.
  final List<String> director;

  /// Human readable runtime, e.g. `49 min`.
  final String? runtime;

  /// First release date.
  final DateTime? released;

  /// `behaviorHints.defaultVideoId`: open this video's streams directly.
  final String? defaultVideoId;

  @override
  bool operator ==(Object other) =>
      super == other &&
      other is MetaDetail &&
      listEquals(other.videos, videos) &&
      listEquals(other.cast, cast) &&
      listEquals(other.director, director) &&
      other.runtime == runtime &&
      other.released == released &&
      other.defaultVideoId == defaultVideoId;

  @override
  int get hashCode => Object.hash(
    super.hashCode,
    Object.hashAll(videos),
    Object.hashAll(cast),
    Object.hashAll(director),
    runtime,
    released,
    defaultVideoId,
  );

  @override
  String toString() => 'MetaDetail($type $id "$name", ${videos.length} videos)';
}

/// One video of a series or channel (Video Object).
final class Episode {
  /// Creates an episode.
  const Episode({
    required this.id,
    this.title,
    this.season,
    this.episode,
    this.released,
    this.thumbnail,
    this.overview,
  });

  static Episode? _parse(JsonMap json) {
    final id = readString(json, 'id');
    if (id == null) return null;
    return Episode(
      id: id,
      // Cinemeta sends `name`/`number`/`firstAired` instead of the documented
      // `title`/`episode`/`released`.
      title: readString(json, 'title') ?? readString(json, 'name'),
      season: readInt(json, 'season'),
      episode: readInt(json, 'episode') ?? readInt(json, 'number'),
      released: readDate(json, 'released') ?? readDate(json, 'firstAired'),
      thumbnail: readString(json, 'thumbnail'),
      overview: readString(json, 'overview') ?? readString(json, 'description'),
    );
  }

  /// Video id to request streams with, e.g. `tt0903747:1:1`.
  final String id;

  /// Episode title.
  final String? title;

  /// Season number (0 is specials).
  final int? season;

  /// Episode number within the season.
  final int? episode;

  /// Air date; null when not announced.
  final DateTime? released;

  /// Thumbnail image URL.
  final String? thumbnail;

  /// Synopsis.
  final String? overview;

  @override
  bool operator ==(Object other) =>
      other is Episode &&
      other.id == id &&
      other.title == title &&
      other.season == season &&
      other.episode == episode &&
      other.released == released &&
      other.thumbnail == thumbnail &&
      other.overview == overview;

  @override
  int get hashCode =>
      Object.hash(id, title, season, episode, released, thumbnail, overview);

  @override
  String toString() => 'Episode($id S${season}E$episode "$title")';
}

/// A Meta Link object.
final class MetaLink {
  /// Creates a link.
  const MetaLink({
    required this.name,
    required this.category,
    required this.url,
  });

  static MetaLink? _parse(JsonMap json) {
    final name = readString(json, 'name');
    final category = readString(json, 'category');
    final url = readString(json, 'url');
    if (name == null || category == null || url == null) return null;
    return MetaLink(name: name, category: category, url: url);
  }

  /// Display text.
  final String name;

  /// Group, e.g. `Genres`, `Cast`, `imdb`.
  final String category;

  /// External URL or `stremio:///…` meta link.
  final String url;

  @override
  bool operator ==(Object other) =>
      other is MetaLink &&
      other.name == name &&
      other.category == category &&
      other.url == url;

  @override
  int get hashCode => Object.hash(name, category, url);

  @override
  String toString() => 'MetaLink($category: $name)';
}

List<String> _genres(JsonMap json) {
  final genres = readStrings(json, 'genres');
  return genres.isNotEmpty ? genres : readStrings(json, 'genre');
}

List<String> _trailers(JsonMap json) => List.unmodifiable({
  for (final t in readObjects(json, 'trailers'))
    if (readString(t, 'source') case final id?) id,
  for (final t in readObjects(json, 'trailerStreams'))
    if (readString(t, 'ytId') case final id?) id,
});
