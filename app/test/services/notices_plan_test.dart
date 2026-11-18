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
      picked: {'pick:tt901'},
    );
    expect(next.single.at, local(27, 19));
    expect(next.single.body, 'Paper Moons');
  });

  test('at most 40, soonest first', () {
    final plan = planNotices(
      now: now,
      episodes: [
        for (var i = 0; i < 60; i++)
          ep(1, 1 + i ~/ 6, local(19 + i % 6, 15), id: 'tt$i', show: 'Show $i'),
      ],
    );
    expect(plan, hasLength(40));
    expect(plan.first.at.isAfter(plan.last.at), isFalse);
  });
}
