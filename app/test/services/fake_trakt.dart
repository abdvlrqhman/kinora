import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A small stand-in for api.trakt.tv: what it holds, and what it was sent.
final class FakeTrakt {
  final calls = <String>[];
  final bodies = <String, Object?>{};
  final queries = <String, String>{};
  var pendingPolls = 1;
  var access = 'a1';
  var expireOnce = false;
  var refuseRefresh = false;
  var refresh = 'r1';
  var renewals = 0;

  /// How long a sign-in lasts (Trakt's: a day), and a renewed one.
  var lifetime = const Duration(days: 1);
  var renewed = const Duration(days: 1);
  var watchedShows = <Object?>[];
  var playback = <Object?>[];
  var watchlistShows = <Object?>[];
  var ratedShows = <Object?>[];
  var activities = 'v1';

  late final client = MockClient((r) async {
    final path = r.url.path;
    final key = '${r.method} $path';
    calls.add(key);
    queries[key] = r.url.query;
    if (r.body.isNotEmpty) bodies[key] = jsonDecode(r.body);
    http.Response json(Object? body, [int status = 200]) =>
        http.Response(jsonEncode(body), status);
    if (path.startsWith('/oauth/')) {
      return switch (path) {
        '/oauth/device/code' => json({
          'device_code': 'dev',
          'user_code': 'AB12CD',
          'verification_url': 'https://trakt.tv/activate',
          'expires_in': 600,
          'interval': 0,
        }),
        '/oauth/device/token' when pendingPolls-- > 0 => http.Response('', 400),
        '/oauth/device/token' => json(_tokens('a1', 'r1', lifetime)),
        '/oauth/token' when refuseRefresh => json({
          'error': 'invalid_grant',
        }, 400),
        // Like Trakt: each refresh token works once.
        '/oauth/token'
            when (jsonDecode(r.body) as Map)['refresh_token'] != refresh =>
          json({'error': 'invalid_grant'}, 400),
        '/oauth/token' => json(
          _tokens(
            access = 'a${++renewals + 1}',
            refresh = 'r${renewals + 1}',
            renewed,
          ),
        ),
        _ => json({}),
      };
    }
    if (r.headers['authorization'] != 'Bearer $access' || expireOnce) {
      expireOnce = false;
      return http.Response('', 401);
    }
    if (_lists(r, path, json) case final res?) return res;
    return switch (key) {
      'GET /users/settings' => json({
        'user': {'username': 'abd'},
      }),
      'GET /sync/last_activities' => json({
        'episodes': {'watched_at': activities, 'paused_at': activities},
        'movies': {'watched_at': 'm', 'paused_at': 'm', 'watchlisted_at': 'm'},
        'shows': {'watchlisted_at': activities, 'rated_at': activities},
        'watchlist': {'updated_at': activities},
      }),
      'GET /sync/watched/shows' => json(watchedShows),
      'GET /sync/watched/movies' => json([]),
      'GET /sync/playback' => json(playback),
      'GET /sync/watchlist/movies' => json([]),
      'GET /sync/watchlist/shows' => json(watchlistShows),
      'GET /sync/ratings/movies' => json([]),
      'GET /sync/ratings/shows' => json(ratedShows),
      'GET /movies/trending' => json([
        {
          'watchers': 12,
          'movie': {
            'title': 'Paper Moons',
            'year': 2024,
            'ids': {'imdb': 'tt902'},
          },
        },
      ]),
      'GET /search/person' => json([
        {
          'type': 'person',
          'person': {
            'name': 'Ada Reyes',
            'ids': {'slug': 'ada-reyes', 'trakt': 7},
            'images': {
              'headshot': ['media.trakt.tv/people/7/medium/headshot.webp'],
            },
          },
        },
      ]),
      'GET /people/ada-reyes/movies' => json({
        'cast': [
          {
            'characters': ['Mira'],
            'movie': {
              'title': 'Old Light',
              'year': 2012,
              'ids': {'imdb': 'tt1'},
            },
          },
        ],
        'crew': {
          'directing': [
            {
              'jobs': ['Director'],
              'movie': {
                'title': 'New Light',
                'year': 2024,
                'ids': {'imdb': 'tt2'},
              },
            },
          ],
        },
      }),
      'GET /people/ada-reyes/shows' => json({
        'cast': [
          {
            'characters': ['Herself'],
            'show': {
              'title': 'Harbor Lights',
              'year': 2020,
              'ids': {'imdb': 'tt3'},
            },
          },
        ],
        'crew': <String, Object?>{},
      }),
      'GET /genres/movies' => json([
        {'name': 'Science Fiction', 'slug': 'science-fiction'},
      ]),
      'GET /shows/tt200/seasons/1/episodes/2' => json({
        'ids': {'trakt': 42},
      }),
      _ => json({}, 201),
    };
  });

  /// Your lists: id → (name, privacy, items as [type, imdb]).
  final lists =
      <int, ({String name, String privacy, List<(String, String)> items})>{};
  var listLimit = 5;
  var nextList = 100;
  var stats = <String, Object?>{};
  var history = <Object?>[];

  http.Response? _lists(
    http.Request r,
    String path,
    http.Response Function(Object?, [int]) json,
  ) {
    Map<String, Object?> listJson(int id) => {
      'name': lists[id]!.name,
      'privacy': lists[id]!.privacy,
      'item_count': lists[id]!.items.length,
      'ids': {'trakt': id, 'slug': 'l$id'},
    };
    final body = r.body.isEmpty
        ? const <String, Object?>{}
        : jsonDecode(r.body) as Map<String, Object?>;
    if (path == '/users/me/lists') {
      if (r.method == 'GET')
        return json([for (final id in lists.keys) listJson(id)]);
      if (lists.length >= listLimit) return json({}, 420);
      final id = nextList++;
      lists[id] = (
        name: body['name']! as String,
        privacy: body['privacy'] as String? ?? 'private',
        items: [],
      );
      return json(listJson(id), 201);
    }
    if (path == '/users/me/stats') return json(stats);
    if (path == '/sync/history') {
      final page = int.parse(r.url.queryParameters['page'] ?? '1');
      final limit = int.parse(r.url.queryParameters['limit'] ?? '10');
      return json(history.skip((page - 1) * limit).take(limit).toList());
    }
    final m = RegExp(r'^/users/me/lists/(\d+)(/items(/remove)?)?$')
        .firstMatch(path);
    if (m == null) return null;
    final id = int.parse(m[1]!);
    final list = lists[id];
    if (list == null) return json({}, 404);
    if (m[2] == null) {
      if (r.method == 'DELETE') {
        lists.remove(id);
        return http.Response('', 204);
      }
      lists[id] = (
        name: body['name'] as String? ?? list.name,
        privacy: body['privacy'] as String? ?? list.privacy,
        items: list.items,
      );
      return json(listJson(id));
    }
    if (r.method == 'GET') {
      return json([
        for (final (type, imdb) in list.items)
          {
            'type': type,
            type: {
              'title': 'T $imdb',
              'ids': {'imdb': imdb},
            },
          },
        {
          'type': 'person',
          'person': {'name': 'Someone'},
        },
      ]);
    }
    final added = [
      for (final (key, type) in [('movies', 'movie'), ('shows', 'show')])
        for (final e
            in (body[key] as List? ?? const []).cast<Map<String, Object?>>())
          (type, (e['ids']! as Map<String, Object?>)['imdb']! as String),
    ];
    if (m[3] != null) {
      list.items.removeWhere(added.contains);
      return json({'deleted': <String, Object?>{}});
    }
    list.items.addAll(added.where((a) => !list.items.contains(a)));
    return json({'added': <String, Object?>{}}, 201);
  }

  Map<String, Object?> _tokens(String a, String r, Duration life) => {
    'access_token': a,
    'refresh_token': r,
    'token_type': 'bearer',
    'expires_in': life.inSeconds - 1,
    'scope': 'public',
    'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
  };
}
