import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kinora/services/skip_times.dart';

import '../features/harness.dart';

Duration s(num seconds) => Duration(milliseconds: (seconds * 1000).round());

void main() {
  test('AniSkip: openings and endings as segments', () {
    final segs = parseAniSkip({
      'found': true,
      'results': [
        {
          'interval': {'startTime': 52, 'endTime': 142.256},
          'skipType': 'op',
        },
        {
          'interval': {'startTime': 1474, 'endTime': 1582},
          'skipType': 'ed',
        },
        {
          'interval': {'startTime': 0, 'endTime': 30},
          'skipType': 'other',
        },
      ],
    });
    expect(segs.map((x) => x.kind), [SegmentKind.intro, SegmentKind.credits]);
    expect(segs.first.end, s(142.256));
    expect(parseAniSkip({'found': false, 'results': <Object?>[]}), isEmpty);
  });

  test('TheIntroDB: no start is the beginning, no end is the end', () {
    final segs = parseIntroDb({
      'intro': [
        {'start_ms': null, 'end_ms': 38000},
      ],
      'credits': [
        {'start_ms': 3629912, 'end_ms': null},
      ],
    });
    expect(segs.first, (
      kind: SegmentKind.intro,
      start: Duration.zero,
      end: s(38),
    ));
    expect(segs.last.end, isNull);
  });

  test('anime ids: one entry for the season is sure, a split cour is not', () {
    final arm = [
      {'myanimelist': 16498, 'thetvdb-season': 1, 'media': 'TV'},
      {'myanimelist': 18397, 'thetvdb-season': 0, 'media': 'OVA'},
      {'myanimelist': 35760, 'thetvdb-season': 3, 'media': 'TV'},
      {'myanimelist': 38524, 'thetvdb-season': 3, 'media': 'TV'},
    ];
    expect(malFor(arm, season: 1), (16498, true));
    expect(malFor(arm, season: 3), (35760, false));
    expect(malFor(arm, season: 5), isNull);
    expect(malFor(const <Object?>[], season: 1), isNull);
  });

  group('what to skip', () {
    final d = s(1500);
    final segs = <Segment>[
      (kind: SegmentKind.intro, start: s(52), end: s(142)),
      (kind: SegmentKind.credits, start: s(1300), end: s(1390)), // more after
      (kind: SegmentKind.preview, start: s(1480), end: null), // to the end
    ];

    test('inside an intro: jump to its end', () {
      final x = skippableAt(segs, s(60), d);
      expect(x?.segment.kind, SegmentKind.intro);
      expect(x?.to, s(142));
      expect(skipLabel(x!.segment.kind), 'Skip intro');
    });

    test('credits followed by more are skipped, a tail to the end is not', () {
      expect(skippableAt(segs, s(1310), d)?.to, s(1390));
      expect(skippableAt(segs, s(1485), d), isNull);
    });

    test('not in the last 2 s of a stretch, not outside one', () {
      expect(skippableAt(segs, s(141), d), isNull);
      expect(skippableAt(segs, s(200), d), isNull);
    });
  });

  test(
    'looked up once: AniSkip for anime, TheIntroDB otherwise, remembered',
    () async {
      final db = testDb();
      final calls = <String>[];
      final client = MockClient((r) async {
        calls.add(r.url.host);
        return switch (r.url.host) {
          'arm.haglund.dev' when r.url.queryParameters['id'] == 'tt9817980' =>
            http.Response(
              jsonEncode([
                {'myanimelist': 37982, 'thetvdb-season': 1, 'media': 'TV'},
              ]),
              200,
            ),
          'arm.haglund.dev' => http.Response('[]', 200),
          'api.aniskip.com' => http.Response(
            jsonEncode({
              'found': true,
              'results': [
                {
                  'interval': {'startTime': 52, 'endTime': 142},
                  'skipType': 'op',
                },
              ],
            }),
            200,
          ),
          'api.theintrodb.org' => http.Response(
            jsonEncode({
              'intro': [
                {'start_ms': 30000, 'end_ms': 75000},
              ],
            }),
            200,
          ),
          _ => http.Response('', 404),
        };
      });
      final service = SkipTimesService(client, db);
      final anime = await service.lookUp(
        imdb: 'tt9817980',
        season: 1,
        episode: 5,
        duration: s(1420),
      );
      expect(anime.source, 'AniSkip');
      expect(anime.sure, isTrue);
      expect(anime.segments.single.start, s(52));
      final show = await service.lookUp(
        imdb: 'tt0944947',
        season: 1,
        episode: 1,
        duration: s(3700),
      );
      expect(show.source, 'TheIntroDB');
      calls.clear();
      final again = await service.lookUp(
        imdb: 'tt0944947',
        season: 1,
        episode: 1,
        duration: s(3700),
      );
      expect(again.segments, show.segments);
      expect(calls, isEmpty, reason: 'remembered');
    },
  );
}
