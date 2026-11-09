/// A Stremio video id split into the meta id and episode coordinates.
///
/// Forms:
/// * IMDb: `tt0903747` (movie), `tt0903747:1:2` (S01E02)
/// * prefixed: `tmdb:1396:1:2`, `kitsu:1` / `kitsu:1:5` (absolute
///   episode 5, no season), `mal:…`, `anilist:…`, `anidb:…`
///
/// Ids that do not fit (e.g. `yt_id:UC…:video`) parse to a [VideoId] whose
/// [metaId] is the whole id.
final class VideoId {
  /// Creates an id. [season] requires [episode].
  VideoId(this.metaId, {this.season, this.episode}) {
    if (metaId.isEmpty) throw ArgumentError.value(metaId, 'metaId');
    if (season != null && episode == null) {
      throw ArgumentError('season given without episode');
    }
  }

  /// Splits [id]; never throws for a non-empty id.
  factory VideoId.parse(String id) {
    final parts = id.split(':');
    final metaLength = RegExp(r'^tt\d+$').hasMatch(parts.first) ? 1 : 2;
    if (parts.length <= metaLength) return VideoId(id);
    final numbers = parts.skip(metaLength).map(int.tryParse).toList();
    if (numbers.length > 2 || numbers.any((n) => n == null || n < 0)) {
      return VideoId(id);
    }
    final metaId = parts.take(metaLength).join(':');
    return numbers.length == 1
        ? VideoId(metaId, episode: numbers[0])
        : VideoId(metaId, season: numbers[0], episode: numbers[1]);
  }

  /// Meta id: `tt0903747`, `kitsu:1`, `tmdb:1396`.
  final String metaId;

  /// Season number, if the id has one.
  final int? season;

  /// Episode number (absolute for Kitsu-style ids), if any.
  final int? episode;

  /// Whether this points at an episode rather than a whole title.
  bool get isEpisode => episode != null;

  /// The id string, e.g. `tt0903747:1:2`.
  @override
  String toString() => [metaId, ?season, ?episode].join(':');

  @override
  bool operator ==(Object other) =>
      other is VideoId &&
      other.metaId == metaId &&
      other.season == season &&
      other.episode == episode;

  @override
  int get hashCode => Object.hash(metaId, season, episode);
}
