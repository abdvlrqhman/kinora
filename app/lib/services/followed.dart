import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import 'notices_plan.dart';
import 'ratings.dart';
import 'sources.dart';
import 'trakt.dart';

/// Every episode of the shows the viewer follows: in My list or, with
/// [lately], watched in the last two months; never one rated Not for me.
/// Cinemeta's list (days only), with Trakt's real times and kinds when
/// signed in. At most 40 shows.
Future<List<AirDate>> followedEpisodes(Ref ref, {bool lately = true}) async {
  final db = ref.read(databaseProvider);
  final tastes = await ref.read(ratingsProvider).all();
  bool notForMe(String id) => (tastes[id]?.rating ?? 6) <= Taste.notForMe.trakt;
  final recent = DateTime.now().subtract(const Duration(days: 60));
  final listed = await db.select(db.libraryItems).get();
  final watched =
      await (db.select(db.watchProgress)..where(
            (t) => t.season.isNotNull() & t.updatedAt.isBiggerThanValue(recent),
          ))
          .get();
  final ids = {
    for (final i in listed)
      if (i.type == 'series') i.mediaId,
    if (lately)
      for (final w in watched) w.mediaId,
  }.where((id) => id.startsWith('tt') && !notForMe(id)).take(40).toSet();
  final precise = {
    for (final e in await ref.read(traktSyncProvider).calendar())
      '${e.showId}:${e.season}:${e.episode}': e,
  };
  final out = <AirDate>[];
  for (final id in ids) {
    try {
      final meta = await ref.read(
        metaProvider((type: 'series', id: id)).future,
      );
      for (final v in meta.videos) {
        final (season, episode, at) = (v.season, v.episode, v.released);
        if (season == null || episode == null || at == null) continue;
        out.add(
          precise.remove('$id:$season:$episode') ??
              (
                showId: id,
                show: meta.name,
                season: season,
                episode: episode,
                title: v.title,
                airsAt: at,
                precise: false,
                type: null,
              ),
        );
      }
    } on Object {
      // No details for this show: Trakt's times only.
    }
  }
  out.addAll(precise.values.where((e) => ids.contains(e.showId)));
  return out;
}

/// What airs next for the shows the viewer follows: from the start of
/// yesterday on, soonest first (the calendar and Home's Coming up).
final upcomingProvider = FutureProvider.autoDispose<List<AirDate>>((ref) async {
  final s = ref.watch(settingsProvider);
  final now = DateTime.now();
  final from = DateTime(now.year, now.month, now.day - 1);
  final all = await followedEpisodes(ref, lately: s.notifyWatchedLately);
  return [
    for (final e in all)
      if (e.season > 0 && !e.airsAt.toLocal().isBefore(from)) e,
  ]..sort((a, b) => a.airsAt.compareTo(b.airsAt));
});

/// [episodes] by local day: (day, that day's episodes), in order.
List<(DateTime, List<AirDate>)> byDay(List<AirDate> episodes) {
  final days = <DateTime, List<AirDate>>{};
  for (final e in episodes) {
    final t = e.airsAt.toLocal();
    (days[DateTime(t.year, t.month, t.day)] ??= []).add(e);
  }
  final keys = days.keys.toList()..sort();
  return [for (final d in keys) (d, days[d]!)];
}

/// "Today", "Tomorrow", "Yesterday", a weekday this week, else "Mar 4"
/// ("Mar 4, 2027" in another year).
String dayLabel(DateTime day, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final diff = DateTime(day.year, day.month, day.day).difference(today).inDays;
  const weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return switch (diff) {
    0 => 'Today',
    1 => 'Tomorrow',
    -1 => 'Yesterday',
    > 1 && < 7 => weekdays[day.weekday - 1],
    _ =>
      day.year == now.year
          ? '${months[day.month - 1]} ${day.day}'
          : '${months[day.month - 1]} ${day.day}, ${day.year}',
  };
}
