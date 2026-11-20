import 'package:stremio/stremio.dart';

/// One episode of a followed show, as the planner sees it.
typedef AirDate = ({
  String showId,
  String show,
  int season,
  int episode,
  String? title,

  /// When it airs. [precise]: the real time (Trakt); else only the day
  /// (Cinemeta: midnight US Eastern).
  DateTime airsAt,
  bool precise,

  /// Trakt's episode type ("season_finale"…), when known.
  String? type,
});

/// A notification to show at [at] (local time). [open] is the app path a
/// tap goes to.
final class PlannedNotice {
  const PlannedNotice({
    required this.key,
    required this.at,
    required this.title,
    required this.body,
    required this.open,
  });

  /// Stable per event: the same event keeps the same id across plans.
  final String key;
  final DateTime at;
  final String title;
  final String body;
  final String open;

  int get id => noticeId(key);

  @override
  String toString() => 'PlannedNotice($key, $at, $title: $body)';
}

/// A stable 31-bit id for [key] (FNV-1a).
int noticeId(String key) {
  var h = 0x811c9dc5;
  for (final c in key.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0xffffffff;
  }
  return h & 0x7fffffff;
}

/// Never between 10 PM and 9 AM: moved to 9 AM.
DateTime outsideQuietHours(DateTime t) => t.hour >= 22
    ? DateTime(t.year, t.month, t.day + 1, 9)
    : t.hour < 9
    ? DateTime(t.year, t.month, t.day, 9)
    : t;

/// When to tell the viewer [e] aired: an hour after a precise time (the
/// first versions turn up), late morning US time on a day-only date.
DateTime noticeTime(AirDate e) => outsideQuietHours(
  e.airsAt.add(Duration(hours: e.precise ? 1 : 4)).toLocal(),
);

/// What to notify about, from [now]:
///
/// * [episodes] of followed shows airing within [horizon]: one notice per
///   show and day ("S2 E4 aired", "is back: Season 2 premiered", "Season
///   finale aired", "All 8 episodes of Season 2 aired");
/// * a new season announced further out: once per season (keys in
///   [announced]), one a plan, at least a day after [lastAnnounced];
/// * with [picks], one "Picked for you" a week, Friday 7 PM, never a title
///   already sent ([picked] ids). Its key is the week's, so planning again
///   replaces it instead of adding another.
///
/// More than two shows on a day (or two at the same minute, as the night's
/// episodes at 9 AM) become one notice. Finales come from Trakt's episode
/// types only (a day-only list can't tell the last episode announced from
/// the last one). At most [max] notices (iPhone keeps 64), soonest first.
List<PlannedNotice> planNotices({
  required DateTime now,
  required List<AirDate> episodes,
  Set<String> announced = const {},
  DateTime? lastAnnounced,
  List<MetaPreview> picks = const [],
  Set<String> picked = const {},
  Duration horizon = const Duration(days: 14),
  int max = 40,
}) {
  final shows = <PlannedNotice>[];
  final until = now.add(horizon);

  // Episodes, grouped per show and local day.
  final groups = <String, List<AirDate>>{};
  for (final e in episodes) {
    if (e.season <= 0) continue; // specials
    final at = noticeTime(e);
    if (!at.isAfter(now) || at.isAfter(until)) continue;
    final day = '${at.year}-${at.month}-${at.day}';
    (groups['ep:${e.showId}:$day'] ??= []).add(e);
  }
  for (final MapEntry(key: key, value: eps) in groups.entries) {
    eps.sort(
      (a, b) => a.season != b.season
          ? a.season.compareTo(b.season)
          : a.episode.compareTo(b.episode),
    );
    final first = eps.first;
    final at = eps.map(noticeTime).reduce((a, b) => a.isAfter(b) ? a : b);
    final (title, body) = eps.length == 1
        ? _one(first)
        : _many(first.show, eps, episodes);
    shows.add(
      PlannedNotice(
        key: key,
        at: at,
        title: title,
        body: body,
        open: '/title/series/${first.showId}',
      ),
    );
  }

  final out = _bundled(shows);

  // A new season announced beyond the horizon: the soonest one not said
  // yet, a day after the last.
  AirDate? season;
  for (final e in episodes) {
    if (e.episode != 1 || e.season <= 1) continue;
    if (!e.airsAt.isAfter(until)) continue;
    if (e.airsAt.isAfter(now.add(const Duration(days: 365)))) continue;
    if (announced.contains('season:${e.showId}:${e.season}')) continue;
    if (season == null || e.airsAt.isBefore(season.airsAt)) season = e;
  }
  if (season != null) {
    var at = now.add(const Duration(minutes: 1));
    final after = lastAnnounced?.add(const Duration(days: 1));
    if (after != null && after.isAfter(at)) at = after;
    out.add(
      PlannedNotice(
        key: 'season:${season.showId}:${season.season}',
        at: outsideQuietHours(at),
        title: season.show,
        body:
            'Season ${season.season} starts '
            '${_date(season.airsAt.toLocal(), now)}.',
        open: '/title/series/${season.showId}',
      ),
    );
  }

  // One pick a week.
  final pick = picks.where((p) => !picked.contains(p.id)).firstOrNull;
  if (pick != null) {
    var friday = DateTime(
      now.year,
      now.month,
      now.day + (DateTime.friday - now.weekday) % 7,
      19,
    );
    if (!friday.isAfter(now)) friday = friday.add(const Duration(days: 7));
    out.add(
      PlannedNotice(
        key: 'pick:${friday.year}-${friday.month}-${friday.day}',
        at: friday,
        title: 'Picked for you',
        body: [
          pick.name,
          if (pick.releaseInfo case final y? when y.isNotEmpty) '($y)',
        ].join(' '),
        open: '/title/${pick.type}/${pick.id}',
      ),
    );
  }

  out.sort((a, b) => a.at.compareTo(b.at));
  return out.take(max).toList();
}

/// More than two shows on one day, or two at the same minute: one notice,
/// when the last of them is out, opening Home.
List<PlannedNotice> _bundled(List<PlannedNotice> shows) {
  final byDay = <String, List<PlannedNotice>>{};
  for (final n in shows) {
    (byDay['${n.at.year}-${n.at.month}-${n.at.day}'] ??= []).add(n);
  }
  return [
    for (final MapEntry(key: day, value: ns) in byDay.entries)
      if (ns.length > 2 ||
          (ns.length == 2 && ns[0].at.difference(ns[1].at).inMinutes == 0))
        PlannedNotice(
          key: 'eps:$day',
          at: ns.map((n) => n.at).reduce((a, b) => a.isAfter(b) ? a : b),
          title: 'New episodes',
          body: ns.length == 2
              ? '${_titleOf(ns[0])} and ${_titleOf(ns[1])} aired.'
              : '${_titleOf(ns[0])}, ${_titleOf(ns[1])} and '
                    '${ns.length - 2} more aired.',
          open: '/',
        )
      else
        ...ns,
  ];
}

/// The show a single-show notice is about ("X is back" → "X").
String _titleOf(PlannedNotice n) => n.title.endsWith(' is back')
    ? n.title.substring(0, n.title.length - ' is back'.length)
    : n.title;

/// What was scheduled: its key, when, and what a tap opens.
typedef ScheduledNotice = ({String key, DateTime at, String open});

/// Brings what's scheduled ([before], by id) in line with [plan] at [now]:
/// what to cancel, what's scheduled after, and the titles of picks that
/// went out (never picked again). A season notice stays until it's out
/// ([keepSeasons]); everything else follows the plan.
({List<int> cancel, Map<int, ScheduledNotice> after, Set<String> sentPicks})
reconcile({
  required Map<int, ScheduledNotice> before,
  required List<PlannedNotice> plan,
  required DateTime now,
  bool keepSeasons = true,
}) {
  final after = <int, ScheduledNotice>{
    for (final p in plan) p.id: (key: p.key, at: p.at, open: p.open),
  };
  final cancel = <int>[];
  final sentPicks = <String>{};
  for (final MapEntry(key: id, value: n) in before.entries) {
    if (!n.at.isAfter(now)) {
      if (n.key.startsWith('pick:') && n.open.isNotEmpty) {
        sentPicks.add(n.open.split('/').last);
      }
    } else if (!after.containsKey(id)) {
      if (keepSeasons && n.key.startsWith('season:')) {
        after[id] = n;
      } else {
        cancel.add(id);
      }
    }
  }
  return (cancel: cancel, after: after, sentPicks: sentPicks);
}

(String, String) _one(AirDate e) {
  final ep = 'S${e.season} E${e.episode}';
  final named = e.title == null || e.title!.isEmpty ? ep : '$ep “${e.title}”';
  return switch (e.type) {
    'series_premiere' => (e.show, 'Premiered: $named aired.'),
    'season_premiere' => (
      '${e.show} is back',
      'Season ${e.season} premiered: $named.',
    ),
    'mid_season_premiere' => ('${e.show} is back', '$named aired.'),
    'season_finale' => (e.show, 'Season finale aired: $named.'),
    'mid_season_finale' => (e.show, 'Mid-season finale aired: $named.'),
    'series_finale' => (e.show, 'Series finale aired: $named.'),
    // Day-only lists: a first episode is still a premiere.
    null when e.episode == 1 && e.season == 1 => (
      e.show,
      'Premiered: $named aired.',
    ),
    null when e.episode == 1 => (
      '${e.show} is back',
      'Season ${e.season} premiered: $named.',
    ),
    _ => (e.show, '$named aired.'),
  };
}

(String, String) _many(String show, List<AirDate> eps, List<AirDate> all) {
  final season = eps.first.season;
  final sameSeason = eps.every((e) => e.season == season);
  final inSeason = all
      .where((e) => e.showId == eps.first.showId && e.season == season)
      .length;
  if (sameSeason && eps.length == inSeason) {
    return (
      season == 1 ? show : '$show is back',
      'All ${eps.length} episodes of Season $season aired.',
    );
  }
  final last = eps.last;
  final finale = eps.any(
    (e) => e.type == 'season_finale' || e.type == 'series_finale',
  );
  return (
    show,
    '${eps.length} new episodes aired, '
        'S${eps.first.season} E${eps.first.episode} to '
        'S${last.season} E${last.episode}${finale ? ', with the finale' : ''}.',
  );
}

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// "March 4" this year, "March 4, 2027" otherwise.
String _date(DateTime d, DateTime now) {
  final day = '${_months[d.month - 1]} ${d.day}';
  return d.year == now.year ? day : '$day, ${d.year}';
}
