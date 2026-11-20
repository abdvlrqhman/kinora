import 'package:flutter_test/flutter_test.dart';
import 'package:kinora/services/notices_plan.dart';
import 'package:stremio/stremio.dart';

AirDate ep(
  int season,
  int episode,
  DateTime airsAt, {
  String show = 'Harbor Lights',
  String id = 'tt200',
  bool precise = true,
  String? type,
  String? title,
}) => (
  showId: id,
  show: show,
  season: season,
  episode: episode,
  title: title,
  airsAt: airsAt,
  precise: precise,
  type: type,
);

void main() {
  // A Wednesday, 2 PM local.
  final now = DateTime(2026, 11, 18, 14);
  DateTime local(int day, int hour, [int minute = 0]) =>
      DateTime(2026, 11, day, hour, minute);

  test('an episode: an hour after it airs, by show and episode', () {
    final plan = planNotices(
      now: now,
      episodes: [ep(2, 4, local(19, 15), title: 'The Long Light')],
    );
    expect(plan.single.at, local(19, 16));
    expect(plan.single.title, 'Harbor Lights');
    expect(plan.single.body, 'S2 E4 “The Long Light” aired.');
    expect(plan.single.open, '/title/series/tt200');
    expect(plan.single.id, noticeId('ep:tt200:2026-11-19'));
  });

  test('never at night: moved to 9 AM', () {
    expect(outsideQuietHours(local(19, 23, 30)), local(20, 9));
    expect(outsideQuietHours(local(20, 2)), local(20, 9));
    expect(outsideQuietHours(local(20, 21, 59)), local(20, 21, 59));
    final plan = planNotices(now: now, episodes: [ep(1, 3, local(19, 22))]);
    expect(plan.single.at, local(20, 9));
  });

  test('quiet hours of your choice, or none', () {
    DateTime q(DateTime t, int from, int to) =>
        outsideQuietHours(t, from: from, to: to);
    expect(q(local(19, 23, 30), 23, 8), local(20, 8));
    expect(q(local(19, 22, 30), 23, 8), local(19, 22, 30));
    expect(q(local(20, 3), 0, 10), local(20, 10));
    expect(q(local(19, 23), 0, 10), local(19, 23));
    expect(q(local(20, 3), 0, 0), local(20, 3));
  });

  test('premieres and finales only: the rest stay quiet', () {
    final plan = planNotices(
      now: now,
      everyEpisode: false,
      episodes: [
        ep(2, 1, local(19, 15), id: 'tt1', type: 'season_premiere'),
        ep(
          1,
          4,
          local(20, 15),
          id: 'tt2',
          show: 'North Wind',
          type: 'standard',
        ),
        ep(
          3,
          10,
          local(21, 15),
          id: 'tt3',
          show: 'Salt Roads',
          type: 'season_finale',
        ),
        ep(1, 1, local(22, 15), id: 'tt4', show: 'Paper Moons', precise: false),
        ep(1, 2, local(23, 15), id: 'tt5', show: 'Glass', precise: false),
      ],
    );
    expect(plan.map((p) => p.key.split(':')[1]), ['tt1', 'tt3', 'tt4']);
  });

  test('new seasons can be left untold', () {
    expect(
      planNotices(
        now: now,
        seasons: false,
        episodes: [ep(3, 1, DateTime(2027, 3, 4, 21))],
      ),
      isEmpty,
    );
  });

  test('a day-only date is told late in the morning, US time', () {
    final day = DateTime.utc(2026, 11, 20, 5); // midnight US Eastern
    final plan = planNotices(
      now: now,
      episodes: [ep(1, 5, day, precise: false)],
    );
    expect(
      plan.single.at,
      outsideQuietHours(day.add(const Duration(hours: 4)).toLocal()),
    );
  });

  test('the kind of episode shapes the words', () {
    String body(
      String? type, {
      int season = 2,
      int episode = 5,
      bool precise = true,
    }) => planNotices(
      now: now,
      episodes: [
        ep(season, episode, local(19, 15), type: type, precise: precise),
      ],
    ).single.body;
    String title(
      String? type, {
      int season = 2,
      int episode = 5,
      bool precise = true,
    }) => planNotices(
      now: now,
      episodes: [
        ep(season, episode, local(19, 15), type: type, precise: precise),
      ],
    ).single.title;
    expect(title('season_premiere', episode: 1), 'Harbor Lights is back');
    expect(body('season_premiere', episode: 1), 'Season 2 premiered: S2 E1.');
    expect(body('season_finale'), 'Season finale aired: S2 E5.');
    expect(body('mid_season_finale'), 'Mid-season finale aired: S2 E5.');
    expect(body('series_finale'), 'Series finale aired: S2 E5.');
    expect(title('mid_season_premiere'), 'Harbor Lights is back');
    expect(
      body('series_premiere', season: 1, episode: 1),
      'Premiered: S1 E1 aired.',
    );
    // Without Trakt's types: a first episode is still a premiere, but no
    // episode is called a finale.
    expect(title(null, episode: 1, precise: false), 'Harbor Lights is back');
    expect(body(null, episode: 10, precise: false), 'S2 E10 aired.');
  });

  test('a whole season at once is one notice', () {
    final plan = planNotices(
      now: now,
      episodes: [for (var e = 1; e <= 8; e++) ep(2, e, local(20, 10))],
    );
    expect(plan.single.title, 'Harbor Lights is back');
    expect(plan.single.body, 'All 8 episodes of Season 2 aired.');
  });

  test('some episodes the same day: one notice, with the finale named', () {
    final plan = planNotices(
      now: now,
      episodes: [
        ep(2, 1, local(1, 10)),
        ep(2, 7, local(20, 10)),
        ep(2, 8, local(20, 10), type: 'season_finale'),
      ],
    );
    expect(
      plan.single.body,
      '2 new episodes aired, S2 E7 to S2 E8, with the finale.',
    );
  });

  test('two shows, two days: four notices, soonest first', () {
    final plan = planNotices(
      now: now,
      episodes: [
        ep(1, 2, local(26, 15)),
        ep(1, 1, local(19, 15)),
        ep(3, 1, local(20, 15), id: 'tt300', show: 'North Wind'),
        ep(3, 2, local(27, 15), id: 'tt300', show: 'North Wind'),
      ],
    );
    expect(plan.map((p) => p.at.day), [19, 20, 26, 27]);
  });

  test('already aired, or beyond two weeks: not planned', () {
    expect(planNotices(now: now, episodes: [ep(1, 1, local(18, 12))]), isEmpty);
    expect(
      planNotices(
        now: now,
        episodes: [ep(1, 2, now.add(const Duration(days: 20)))],
      ),
      isEmpty,
    );
  });

  test('a new season announced months ahead: said once', () {
    final premiere = DateTime(2027, 3, 4, 21);
    final plan = planNotices(now: now, episodes: [ep(3, 1, premiere)]);
    expect(plan.single.key, 'season:tt200:3');
    expect(plan.single.body, 'Season 3 starts March 4, 2027.');
    expect(plan.single.at, now.add(const Duration(minutes: 1)));
    expect(
      planNotices(
        now: now,
        episodes: [ep(3, 1, premiere)],
        announced: {'season:tt200:3'},
      ),
      isEmpty,
    );
  });

  test('one pick a week, Friday at 7 PM, never the same title twice', () {
    const picks = [
      MetaPreview(
        id: 'tt901',
        type: 'series',
        name: 'Salt Roads',
        releaseInfo: '2024',
      ),
      MetaPreview(id: 'tt902', type: 'movie', name: 'Paper Moons'),
    ];
    final plan = planNotices(now: now, episodes: const [], picks: picks);
    expect(plan.single.at, local(20, 19));
    expect(plan.single.title, 'Picked for you');
    expect(plan.single.body, 'Salt Roads (2024)');
    expect(plan.single.open, '/title/series/tt901');
    final next = planNotices(
      now: local(20, 20), // Friday evening, after 7
      episodes: const [],
      picks: picks,
      picked: {'tt901'},
    );
    expect(next.single.at, local(27, 19));
    expect(next.single.body, 'Paper Moons');
  });

  test('a busy day is one notice, when the last show is out', () {
    final plan = planNotices(
      now: now,
      episodes: [
        ep(1, 3, local(19, 15), id: 'tt1', show: 'Harbor Lights'),
        ep(2, 1, local(19, 16), id: 'tt2', show: 'North Wind'),
        ep(1, 7, local(19, 18), id: 'tt3', show: 'Salt Roads'),
        ep(4, 2, local(19, 20), id: 'tt4', show: 'Paper Moons'),
      ],
    );
    expect(plan.single.title, 'New episodes');
    expect(plan.single.body, 'Harbor Lights, North Wind and 2 more aired.');
    expect(plan.single.at, local(19, 21));
    expect(plan.single.open, '/');
  });

  test('two shows from the night, both at 9 AM: one notice', () {
    final plan = planNotices(
      now: now,
      episodes: [
        ep(1, 3, local(19, 2), id: 'tt1', show: 'Harbor Lights'),
        ep(
          2,
          1,
          local(19, 4),
          id: 'tt2',
          show: 'North Wind',
          type: 'season_premiere',
        ),
      ],
    );
    expect(plan.single.at, local(19, 9));
    expect(plan.single.body, 'Harbor Lights and North Wind aired.');
  });

  /// Plans every 30 minutes for [days], as Kinora does (opening, syncs),
  /// keeping what's scheduled in line, and returns what went out.
  List<ScheduledNotice> run({
    required int days,
    List<AirDate> episodes = const [],
    List<MetaPreview> picks = const [],
  }) {
    var scheduled = <int, ScheduledNotice>{};
    final told = <String>{}, picked = <String>{};
    DateTime? announced;
    final sent = <ScheduledNotice>[];
    for (
      var t = now;
      t.isBefore(now.add(Duration(days: days)));
      t = t.add(const Duration(minutes: 30))
    ) {
      sent.addAll(scheduled.values.where((n) => !n.at.isAfter(t)));
      final plan = planNotices(
        now: t,
        episodes: episodes,
        announced: told,
        lastAnnounced: announced,
        picks: picks,
        picked: picked,
      );
      final r = reconcile(before: scheduled, plan: plan, now: t);
      scheduled = r.after;
      picked.addAll(r.sentPicks);
      for (final p in plan.where((p) => p.key.startsWith('season:'))) {
        told.add(p.key);
        announced = p.at;
      }
    }
    return sent;
  }

  test('picks queued by 0.3.2 are cancelled, and their titles kept', () {
    // 0.3.2 stored [key, at] (no open) and keyed picks by title.
    final queued = <int, ScheduledNotice>{
      for (final id in ['tt901', 'tt902', 'tt903'])
        noticeId('pick:$id'): (key: 'pick:$id', at: local(27, 19), open: ''),
    };
    final plan = planNotices(
      now: now,
      episodes: const [],
      picks: const [MetaPreview(id: 'tt904', type: 'movie', name: 'New')],
      picked: {'tt901', 'tt902', 'tt903'},
    );
    final r = reconcile(before: queued, plan: plan, now: now);
    expect(r.cancel.toSet(), queued.keys.toSet());
    expect(r.after.values.single.key, startsWith('pick:2026-'));
    expect(r.after.values.single.open, '/title/movie/tt904');
    expect(r.sentPicks, isEmpty);
  });

  test('planning again and again: one pick a week, never the same title', () {
    final sent = run(
      days: 15,
      picks: const [
        MetaPreview(id: 'tt901', type: 'series', name: 'Salt Roads'),
        MetaPreview(id: 'tt902', type: 'movie', name: 'Paper Moons'),
        MetaPreview(id: 'tt903', type: 'movie', name: 'Glass Harbor'),
      ],
    );
    expect(sent.map((n) => n.at), [local(20, 19), local(27, 19)]);
    expect(sent.map((n) => n.open), [
      '/title/series/tt901',
      '/title/movie/tt902',
    ]);
  });

  test('new seasons announced: each once, one a day at most', () {
    final premiere = DateTime(2027, 3, 4, 21);
    final sent = run(
      days: 5,
      episodes: [
        ep(2, 1, premiere, id: 'tt1', show: 'Harbor Lights'),
        ep(3, 1, premiere, id: 'tt2', show: 'North Wind'),
        ep(4, 1, premiere, id: 'tt3', show: 'Salt Roads'),
      ],
    );
    expect(sent.map((n) => n.key).toSet(), hasLength(3));
    expect(sent, hasLength(3));
    for (var i = 1; i < sent.length; i++) {
      expect(
        sent[i].at.difference(sent[i - 1].at),
        greaterThanOrEqualTo(const Duration(hours: 24)),
      );
    }
  });

  test('a busy fortnight: never two notices at once', () {
    final sent = run(
      days: 14,
      episodes: [
        for (var d = 0; d < 14; d++)
          for (var s = 0; s < 4; s++)
            ep(1, d + 1, local(19 + d, 1 + s * 5), id: 'tt$s', show: 'Show $s'),
      ],
      picks: const [
        MetaPreview(id: 'tt901', type: 'series', name: 'Salt Roads'),
      ],
    );
    final times = sent.map((n) => n.at).toList();
    expect(times.toSet(), hasLength(times.length));
  });
}
