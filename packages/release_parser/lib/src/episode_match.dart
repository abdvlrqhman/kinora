import 'parsed_release.dart';

/// Whether release [r] contains episode [episode] of season [season].
///
/// True for the exact episode, multi-episode files (`S01E01-E03`), season
/// packs and season ranges containing [season], and complete-series packs
/// without season numbers. Absolute-numbered anime (`Title - 1071`) matches
/// [absoluteEpisode] when given, otherwise only season 1 by episode number.
///
/// False when the name carries no season/episode information at all; use
/// [ParsedRelease.hasEpisodeInfo] to tell "unknown" from "wrong".
bool coversEpisode(
  ParsedRelease r, {
  required int season,
  required int episode,
  int? absoluteEpisode,
}) {
  if (r.seasons.isNotEmpty) {
    if (!r.seasons.contains(season)) return false;
    return r.episodes.isEmpty || r.episodes.contains(episode);
  }
  if (r.episodes.isNotEmpty) {
    return (absoluteEpisode != null && r.episodes.contains(absoluteEpisode)) ||
        (season == 1 && r.episodes.contains(episode));
  }
  return r.isCompleteSeries;
}
