import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../app/providers.dart';
import '../core/db/database.dart';
import '../core/log.dart';

enum SegmentKind { intro, recap, credits, preview }

/// A stretch of a video worth skipping. [end] null: to the end.
typedef Segment = ({SegmentKind kind, Duration start, Duration? end});

/// Where a video's intro, recap, credits and preview are, from online
/// timestamps, and whether they can be trusted to skip without asking
/// ([sure]: the match to this exact video is certain).
typedef SkipTimes = ({List<Segment> segments, bool sure, String source});

const noSkipTimes = (segments: <Segment>[], sure: false, source: '');

/// The MyAnimeList id for [season] of an anime from ARM's IMDb mapping:
/// (id, sure). Not sure when a season maps to several entries (a split
/// cour), whose episode numbers don't line up with the season's.
(int, bool)? malFor(Object? arm, {int? season}) {
  if (arm is! List || arm.isEmpty) return null;
  final entries = arm.whereType<Map<String, Object?>>().toList();
  final tv = entries
      .where((e) => e['myanimelist'] is int && e['media'] != 'OVA')
      .where(
        (e) =>
            season == null ||
            e['thetvdb-season'] == season ||
            e['themoviedb-season'] == season,
      )
      .toList();
  if (tv.isEmpty) return null;
  return (tv.first['myanimelist']! as int, tv.length == 1);
}

/// AniSkip's answer as segments (op → intro, ed → credits).
List<Segment> parseAniSkip(Object? body) {
  if (body is! Map<String, Object?> || body['found'] != true) return const [];
  return [
    for (final r
        in (body['results'] as List? ?? const [])
            .whereType<Map<String, Object?>>())
      if (r['interval'] case {
        'startTime': final num start,
        'endTime': final num end,
      })
        if (switch (r['skipType']) {
              'op' || 'mixed-op' => SegmentKind.intro,
              'ed' || 'mixed-ed' => SegmentKind.credits,
              'recap' => SegmentKind.recap,
              _ => null,
            }
            case final kind?)
          (
            kind: kind,
            start: Duration(milliseconds: (start * 1000).round()),
            end: Duration(milliseconds: (end * 1000).round()),
          ),
  ];
}

/// TheIntroDB's answer as segments (start null: from the beginning; end
/// null: to the end).
List<Segment> parseIntroDb(Object? body) {
  if (body is! Map<String, Object?>) return const [];
  return [
    for (final (key, kind) in [
      ('intro', SegmentKind.intro),
      ('recap', SegmentKind.recap),
      ('credits', SegmentKind.credits),
      ('preview', SegmentKind.preview),
    ])
      for (final s
          in (body[key] as List? ?? const []).whereType<Map<String, Object?>>())
        if ((s['start_ms'] as num?, s['end_ms'] as num?)
            case (final start, final end) when start != null || end != null)
          (
            kind: kind,
            start: Duration(milliseconds: (start ?? 0).round()),
            end: end == null ? null : Duration(milliseconds: end.round()),
          ),
  ];
}

/// Asks AniSkip (anime, through ARM's id mapping) and TheIntroDB (shows
/// and movies) where a video's intro and credits are. Remembered for a
/// week (a miss for a day).
final class SkipTimesService {
  SkipTimesService(this._http, this._db);
  final http.Client _http;
  final AppDatabase _db;

  static const _timeout = Duration(seconds: 8);

  Future<SkipTimes> lookUp({
    required String imdb,
    int? season,
    int? episode,
    required Duration duration,
  }) async {
    if (!imdb.startsWith('tt') || duration <= Duration.zero) {
      return noSkipTimes;
    }
    final key =
        'skip:$imdb:${season ?? ''}:${episode ?? ''}:'
        '${duration.inSeconds ~/ 2}';
    if (await _cached(key) case final hit?) return hit;
    var found = noSkipTimes;
    try {
      found = await _anime(imdb, season, episode, duration) ?? found;
      if (found.segments.isEmpty) {
        found = await _introDb(imdb, season, episode, duration) ?? found;
      }
    } on Object catch (e) {
      Log.d('skip', 'look up $imdb: $e');
      return noSkipTimes; // offline: ask again next time
    }
    await _remember(key, found);
    return found;
  }

  Future<Object?> _get(String url) async {
    final res = await _http.get(Uri.parse(url)).timeout(_timeout);
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) throw StateError('HTTP ${res.statusCode}');
    return jsonDecode(res.body);
  }

  Future<SkipTimes?> _anime(
    String imdb,
    int? season,
    int? episode,
    Duration duration,
  ) async {
    final mal = malFor(
      await _get('https://arm.haglund.dev/api/v2/imdb?id=$imdb'),
      season: season,
    );
    if (mal == null) return null;
    final (id, sure) = mal;
    // AniSkip keeps only times recorded on a video this long.
    final body = await _get(
      'https://api.aniskip.com/v2/skip-times/$id/${episode ?? 1}'
      '?types=op&types=ed&types=mixed-op&types=mixed-ed&types=recap'
      '&episodeLength=${duration.inSeconds}',
    );
    return (segments: parseAniSkip(body), sure: sure, source: 'AniSkip');
  }

  Future<SkipTimes?> _introDb(
    String imdb,
    int? season,
    int? episode,
    Duration duration,
  ) async {
    final body = await _get(
      'https://api.theintrodb.org/v4/media?imdb_id=$imdb'
      '${season != null && episode != null ? '&season=$season&episode=$episode' : ''}'
      '&duration_ms=${duration.inMilliseconds}',
    );
    return (segments: parseIntroDb(body), sure: true, source: 'TheIntroDB');
  }

  Future<SkipTimes?> _cached(String key) async {
    final row = await (_db.select(
      _db.keyValues,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    if (row == null) return null;
    try {
      final j = jsonDecode(row.value) as Map<String, Object?>;
      final at = DateTime.parse(j['at']! as String);
      final list = (j['s']! as List).cast<List<Object?>>();
      final age = DateTime.now().difference(at);
      if (age >
          (list.isEmpty ? const Duration(days: 1) : const Duration(days: 7))) {
        return null;
      }
      return (
        segments: [
          for (final [kind, start, end] in list)
            (
              kind: SegmentKind.values.byName(kind! as String),
              start: Duration(milliseconds: start! as int),
              end: end == null ? null : Duration(milliseconds: end as int),
            ),
        ],
        sure: j['sure'] == true,
        source: j['src'] as String? ?? '',
      );
    } on Object {
      return null;
    }
  }

  Future<void> _remember(String key, SkipTimes t) => _db
      .into(_db.keyValues)
      .insertOnConflictUpdate(
        KeyValuesCompanion.insert(
          key: key,
          value: jsonEncode({
            'at': DateTime.now().toIso8601String(),
            'sure': t.sure,
            'src': t.source,
            's': [
              for (final s in t.segments)
                [s.kind.name, s.start.inMilliseconds, s.end?.inMilliseconds],
            ],
          }),
        ),
      );
}

final skipTimesProvider = Provider(
  (ref) => SkipTimesService(
    ref.watch(httpClientProvider),
    ref.watch(databaseProvider),
  ),
);

/// What can be skipped at [pos] and where to: intros, recaps, and credits
/// or previews followed by more of the video (a scene after the credits).
/// Credits that run to the end are left to Up next. Stretches under 5 s
/// aren't worth a jump.
({Segment segment, Duration to})? skippableAt(
  List<Segment> segments,
  Duration pos,
  Duration duration,
) {
  for (final s in segments) {
    final end = s.end ?? duration;
    if (pos < s.start || pos >= end - const Duration(seconds: 2)) continue;
    if (end - s.start < const Duration(seconds: 5)) continue;
    final tail = s.kind == SegmentKind.credits || s.kind == SegmentKind.preview;
    if (tail && duration - end < const Duration(seconds: 15)) continue;
    return (segment: s, to: end);
  }
  return null;
}

/// The button's words for skipping [kind].
String skipLabel(SegmentKind kind) => switch (kind) {
  SegmentKind.intro => 'Skip intro',
  SegmentKind.recap => 'Skip recap',
  SegmentKind.credits => 'Skip credits',
  SegmentKind.preview => 'Skip preview',
};
