import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinora/features/calendar/calendar_screen.dart';
import 'package:kinora/services/followed.dart';
import 'package:kinora/services/notices_plan.dart';

import '../harness.dart';

AirDate ep(
  int season,
  int episode,
  DateTime at, {
  String id = 'tt200',
  String show = 'Harbor Lights',
  String? type,
  bool precise = true,
  String? title,
}) => (
  showId: id,
  show: show,
  season: season,
  episode: episode,
  title: title,
  airsAt: at,
  precise: precise,
  type: type,
);

void main() {
  final now = DateTime(2026, 11, 18, 14); // a Wednesday

  test('days read like people say them', () {
    DateTime d(int day, [int month = 11, int year = 2026]) =>
        DateTime(year, month, day);
    expect(dayLabel(d(18), now), 'Today');
    expect(dayLabel(d(19), now), 'Tomorrow');
    expect(dayLabel(d(17), now), 'Yesterday');
    expect(dayLabel(d(21), now), 'Saturday');
    expect(dayLabel(d(25), now), 'Nov 25');
    expect(dayLabel(d(4, 3, 2027), now), 'Mar 4, 2027');
  });

  test('episodes by local day, in order', () {
    final days = byDay([
      ep(1, 3, DateTime(2026, 11, 20, 21)),
      ep(1, 2, DateTime(2026, 11, 19, 21)),
      ep(2, 1, DateTime(2026, 11, 19, 22), id: 'tt300', show: 'North Wind'),
    ]);
    expect(days.map((d) => d.$1.day), [19, 20]);
    expect(days.first.$2.map((e) => e.show), ['Harbor Lights', 'North Wind']);
  });

  test('premieres and finales get a badge, plain episodes don\'t', () {
    final at = DateTime(2026, 11, 19);
    expect(
      episodeKind(ep(2, 1, at, type: 'season_premiere')),
      'Season premiere',
    );
    expect(episodeKind(ep(2, 10, at, type: 'season_finale')), 'Season finale');
    expect(episodeKind(ep(1, 1, at, precise: false)), 'Premiere');
    expect(episodeKind(ep(3, 1, at, precise: false)), 'Season premiere');
    expect(episodeKind(ep(2, 4, at, type: 'standard')), isNull);
  });

  testScreen('the calendar lists days and opens a show', (tester) async {
    final soon = DateTime.now().add(const Duration(days: 1));
    final nav = await pumpScreen(
      tester,
      const CalendarScreen(),
      db: testDb(),
      overrides: [
        upcomingProvider.overrideWith(
          (ref) async => [
            ep(2, 1, soon, type: 'season_premiere', title: 'The Return'),
          ],
        ),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.text('Tomorrow'), findsOneWidget);
    expect(find.text('Season premiere'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel(RegExp('^Harbor Lights, S2 E1')));
    await tester.pumpAndSettle();
    expect(nav.locations.last, '/title/series/tt200');
  });

  testScreen('nothing coming up: says how to fill it', (tester) async {
    await pumpScreen(
      tester,
      const CalendarScreen(),
      db: testDb(),
      overrides: [upcomingProvider.overrideWith((ref) async => const [])],
    );
    await tester.pumpAndSettle();
    expect(find.text('Nothing coming up'), findsOneWidget);
    expect(find.byType(CalendarRow), findsNothing);
  });
}
