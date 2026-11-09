/// Everything the player needs to start one movie or episode.
final class PlayRequest {
  const PlayRequest({
    required this.type,
    required this.mediaId,
    required this.videoId,
    required this.title,
    this.episodeTitle,
    this.season,
    this.episode,
    this.poster,
    this.background,
    this.logo,
    this.still,
    this.startAt,
    this.candidateId,
    this.localFile,
  });

  /// Stremio type: `movie` or `series` (anime uses `series`).
  final String type;

  /// Title id (`tt…`, `kitsu:…`).
  final String mediaId;

  /// Movie id or episode id (`tt…:1:2`).
  final String videoId;
  final String title;
  final String? episodeTitle;
  final int? season;
  final int? episode;
  final String? poster;
  final String? background;
  final String? logo;
  final String? still;

  /// Resume point; null = from the remembered position.
  final Duration? startAt;

  /// A specific release picked by the user; null = the best one.
  final String? candidateId;

  /// A finished download to play offline.
  final String? localFile;

  bool get isEpisode => season != null && episode != null;

  /// "S1 E3 · Title" style label without dots: "S1 E3  Title".
  String get label => isEpisode ? 'S$season E$episode' : title;

  PlayRequest copyWith({
    String? videoId,
    String? episodeTitle,
    int? season,
    int? episode,
    String? still,
    Duration? startAt,
    String? candidateId,
    String? localFile,
    bool clearCandidate = false,
    bool clearLocal = false,
  }) => PlayRequest(
    type: type,
    mediaId: mediaId,
    videoId: videoId ?? this.videoId,
    title: title,
    episodeTitle: episodeTitle ?? this.episodeTitle,
    season: season ?? this.season,
    episode: episode ?? this.episode,
    poster: poster,
    background: background,
    logo: logo,
    still: still ?? this.still,
    startAt: startAt ?? this.startAt,
    candidateId: clearCandidate ? null : candidateId ?? this.candidateId,
    localFile: clearLocal ? null : localFile ?? this.localFile,
  );
}
