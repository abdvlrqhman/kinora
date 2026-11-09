import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stremio/stremio.dart';

import '../../core/db/database.dart';
import '../../core/format.dart';
import '../../services/library.dart';
import '../../services/play_request.dart';
import '../../services/resolver.dart';
import '../../services/tmdb.dart';
import '../../ui/widgets/media.dart';

typedef TitleKey = ({String type, String id});

/// A title's details arranged for the page: seasons in order (specials
/// last), episodes per season, and the episode order for "next up".
final class TitleModel {
  TitleModel(this.meta) {
    final sorted = [...meta.videos]
      ..sort((a, b) {
        final s = (a.season ?? 0).compareTo(b.season ?? 0);
        return s != 0 ? s : (a.episode ?? 0).compareTo(b.episode ?? 0);
      });
    for (final e in sorted) {
      (bySeason[e.season ?? 0] ??= []).add(e);
    }
    seasons = [
      ...bySeason.keys.where((s) => s > 0),
      if (bySeason.containsKey(0)) 0,
    ];
    final regular = sorted.where((e) => (e.season ?? 0) > 0).toList();
    order = regular.isEmpty ? sorted : regular;
  }

  final MetaDetail meta;
  final Map<int, List<Episode>> bySeason = {};
  late final List<int> seasons;

  /// Watch order, specials left out (unless there's nothing else).
  late final List<Episode> order;

  bool get isSeries => meta.videos.isNotEmpty && meta.type != 'movie';

  /// The player's type: anime and channels play as series.
  String get playType => isSeries ? 'series' : 'movie';

  PlayRequest request({Episode? episode, Duration? startAt}) => PlayRequest(
    type: playType,
    mediaId: meta.id,
    videoId: episode?.id ?? meta.id,
    title: meta.name,
    episodeTitle: episode?.title,
    season: episode?.season,
    episode: episode?.episode,
    poster: meta.poster,
    background: meta.background,
    logo: meta.logo,
    still: episode?.thumbnail,
    startAt: startAt,
  );

  VideoRef video([Episode? episode]) => VideoRef(
    type: playType,
    mediaId: meta.id,
    videoId: episode?.id ?? meta.id,
    season: episode?.season,
    episode: episode?.episode,
    runtimeMinutes: runtimeMinutes(meta.runtime),
  );
}

/// What the primary button plays: the movie, or the next episode.
final class NextUp {
  const NextUp({
    required this.label,
    this.episode,
    this.startAt,
    this.resume = false,
  });

  /// "Play", "Resume", "Play S1 E3", "Resume S1 E3".
  final String label;

  /// Null for movies.
  final Episode? episode;
  final Duration? startAt;
  final bool resume;
}

bool _started(WatchProgressData? p) =>
    p != null && !p.completed && p.positionMs > 0;

/// Whether [e] has aired by [now] (unknown dates count as aired).
bool aired(Episode e, DateTime now) =>
    e.released == null || !e.released!.isAfter(now);

/// The next aired, unwatched episode after [videoId] in watching order.
Episode? episodeAfter(
  TitleModel t,
  String videoId,
  Map<String, WatchProgressData> progress,
  DateTime now,
) {
  final order = t.order;
  final i = order.indexWhere((e) => e.id == videoId);
  // A special isn't in the order: then the first episode not watched yet.
  // (An id the show doesn't have says nothing.)
  if (i < 0 && !t.meta.videos.any((v) => v.id == videoId)) return null;
  return order
      .skip(i + 1)
      .where((e) => aired(e, now) && !(progress[e.id]?.completed ?? false))
      .firstOrNull;
}

/// Resume what's half watched, else the next unwatched episode after the
/// last one watched, else start over.
NextUp nextUp(
  TitleModel t,
  Map<String, WatchProgressData> progress,
  DateTime now,
) {
  NextUp at(Episode? e) {
    final p = progress[e?.id ?? t.meta.id];
    final name = e == null
        ? ''
        : ' ${Fmt.episode(e.season ?? 0, e.episode ?? 0)}';
    if (_started(p)) {
      return NextUp(
        label: 'Resume$name',
        episode: e,
        startAt: Duration(milliseconds: p!.positionMs),
        resume: true,
      );
    }
    // A finished video starts from the top, not from the credits.
    return NextUp(
      label: 'Play$name',
      episode: e,
      startAt: (p?.completed ?? false) ? Duration.zero : null,
    );
  }

  if (!t.isSeries) return at(null);
  final order = t.order;
  Episode first() =>
      order.firstWhere((e) => aired(e, now), orElse: () => order.first);
  WatchProgressData? last;
  Episode? lastEpisode;
  for (final e in t.meta.videos) {
    final p = progress[e.id];
    if (p != null && (last == null || p.updatedAt.isAfter(last.updatedAt))) {
      last = p;
      lastEpisode = e;
    }
  }
  if (lastEpisode == null) return at(first());
  if (_started(last)) return at(lastEpisode);
  return at(episodeAfter(t, lastEpisode.id, progress, now) ?? first());
}

/// The title page's model, derived synchronously from its details.
final titleProvider = Provider.autoDispose
    .family<AsyncValue<TitleModel>, TitleKey>(
      (ref, key) => ref.watch(richMetaProvider(key)).whenData(TitleModel.new),
    );

/// The primary button's target; null until progress has loaded.
final nextUpProvider = Provider.autoDispose.family<NextUp?, TitleKey>((
  ref,
  key,
) {
  final t = ref.watch(titleProvider(key)).value;
  if (t == null) return null;
  final p = ref.watch(mediaProgressProvider(t.meta.id));
  final progress = p.value ?? (p.hasError ? const {} : null);
  return progress == null ? null : nextUp(t, progress, DateTime.now());
});

/// Versions grouped by resolution, best quality first.
final class VersionGroups {
  const VersionGroups(this.all, this.byResolution, this.message);

  final List<ResolvedRelease> all;
  final List<(String, List<ResolvedRelease>)> byResolution;

  /// Why there are none, from the resolver.
  final String? message;
}

const _resolutionRank = {
  '4K': 0,
  '2160p': 0,
  '1440p': 1,
  '1080p': 2,
  '720p': 3,
  '576p': 4,
  '480p': 5,
};

VersionGroups groupVersions(ResolveResult r) {
  final map = <String, List<ResolvedRelease>>{};
  for (final v in r.releases) {
    (map[v.resolution ?? 'Other'] ??= []).add(v);
  }
  final keys = map.keys.toList()
    ..sort(
      (a, b) => (_resolutionRank[a] ?? 9).compareTo(_resolutionRank[b] ?? 9),
    );
  return VersionGroups(r.releases, [
    for (final k in keys) (k, map[k]!),
  ], r.message);
}

/// The version sheet's data for one video.
final versionGroupsProvider = Provider.autoDispose
    .family<AsyncValue<VersionGroups>, VideoRef>(
      (ref, video) => ref.watch(resolveProvider(video)).whenData(groupVersions),
    );

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "Mar 4" this year, "Mar 4, 2024" otherwise.
String shortDate(DateTime date, DateTime now) {
  final d = date.toLocal();
  final day = '${_months[d.month - 1]} ${d.day}';
  return d.year == now.year ? day : '$day, ${d.year}';
}
