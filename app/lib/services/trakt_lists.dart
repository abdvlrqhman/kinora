part of 'trakt.dart';

/// One of your own Trakt lists. [privacy]: private, link, friends or
/// public.
typedef TraktList = ({int id, String name, String privacy, int count});

/// Your Trakt numbers: all time, and this year from your history.
typedef TraktStats = ({
  int minutes,
  int movies,
  int episodes,
  int shows,
  int yearMinutes,
  int yearPlays,
  List<({MetaPreview show, int episodes})> topShows,
  List<({String genre, double share})> topGenres,
});

/// Your Trakt lists and stats (signed in only). Lists are read, made,
/// renamed and deleted straight away, never queued: a change you make
/// either happens or tells you why not.
extension TraktLists on TraktSync {
  Future<List<TraktList>> myLists() async {
    final (status, body) = await _call('GET', '/users/me/lists');
    _ok(status);
    return [
      for (final l
          in (body as List? ?? const []).whereType<Map<String, Object?>>())
        ?_listOf(l),
    ];
  }

  Future<TraktList> createList(
    String name, {
    String privacy = 'private',
  }) async {
    final (status, body) = await _call(
      'POST',
      '/users/me/lists',
      body: {'name': name, 'privacy': privacy},
    );
    _ok(status, limit: 'lists');
    return _listOf(body) ?? (id: 0, name: name, privacy: privacy, count: 0);
  }

  Future<void> updateList(
    int id, {
    required String name,
    required String privacy,
  }) async {
    final (status, _) = await _call(
      'PUT',
      '/users/me/lists/$id',
      body: {'name': name, 'privacy': privacy},
    );
    _ok(status);
  }

  Future<void> deleteList(int id) async {
    final (status, _) = await _call('DELETE', '/users/me/lists/$id');
    _ok(status);
  }

  /// The movies and shows on list [id], in its order.
  Future<List<MetaPreview>> listItems(int id) async {
    // (Seasons, episodes and people on it are left out.)
    final (status, body) = await _call('GET', '/users/me/lists/$id/items');
    _ok(status);
    return [
      for (final item
          in (body as List? ?? const []).whereType<Map<String, Object?>>())
        if (item['type'] == 'movie')
          ...TraktSync.picks([item['movie']], 'movie')
        else if (item['type'] == 'show')
          ...TraktSync.picks([item['show']], 'series'),
    ];
  }

  Future<void> addToList(int id, MetaPreview m) => _items(id, m, remove: false);

  Future<void> removeFromList(int id, MetaPreview m) =>
      _items(id, m, remove: true);

  Future<void> _items(int id, MetaPreview m, {required bool remove}) async {
    final (status, _) = await _call(
      'POST',
      '/users/me/lists/$id/items${remove ? '/remove' : ''}',
      body: {
        m.type == 'movie' ? 'movies' : 'shows': [
          {
            'ids': {'imdb': m.id},
          },
        ],
      },
    );
    _ok(status, limit: 'titles on a list');
  }

  /// Which of [lists] have the title [imdb] on them.
  Future<Set<int>> listsWith(String imdb, List<TraktList> lists) async {
    final found = await Future.wait([
      for (final l in lists)
        listItems(l.id)
            .then((items) => items.any((m) => m.id == imdb) ? l.id : null),
    ]);
    return {...found.nonNulls};
  }

  /// Your numbers. This year's come from your history, at most 2,000
  /// plays (20 pages), and are kept for a day.
  Future<TraktStats> stats({DateTime? now}) async {
    final today = now ?? DateTime.now();
    final key = 'trakt.stats.${today.year}';
    if (await _kv(key) case final cached?) {
      final j = jsonDecode(cached) as Map<String, Object?>;
      if (DateTime.tryParse(j['at'] as String? ?? '') case final at?
          when today.difference(at) < const Duration(days: 1)) {
        return _statsOf(j);
      }
    }
    final (status, body) = await _call('GET', '/users/me/stats');
    _ok(status);
    final all = body is Map<String, Object?> ? body : const <String, Object?>{};
    int n(String group, String field) =>
        ((all[group] as Map<String, Object?>?)?[field] as num?)?.toInt() ?? 0;

    var yearMinutes = 0, yearPlays = 0;
    final shows = <String, ({MetaPreview show, int episodes})>{};
    final genres = <String, int>{};
    final start = DateTime.utc(today.year).toIso8601String();
    for (var page = 1; page <= 20; page++) {
      final (s, b) = await _call(
        'GET',
        '/sync/history?start_at=$start&extended=full&limit=100&page=$page',
      );
      if (s != 200 || b is! List || b.isEmpty) break;
      for (final play in b.whereType<Map<String, Object?>>()) {
        final movie = play['type'] == 'movie';
        final media =
            (play[movie ? 'movie' : 'show'] as Map<String, Object?>?) ??
            const {};
        final runtime = movie
            ? media['runtime']
            : (play['episode'] as Map<String, Object?>?)?['runtime'] ??
                  media['runtime'];
        yearPlays++;
        yearMinutes += (runtime as num?)?.toInt() ?? 0;
        for (final g
            in (media['genres'] as List? ?? const []).whereType<String>()) {
          genres[g] = (genres[g] ?? 0) + 1;
        }
        if (!movie) {
          if (TraktSync.picks([media], 'series').firstOrNull case final show?) {
            final had = shows[show.id];
            shows[show.id] = (show: show, episodes: (had?.episodes ?? 0) + 1);
          }
        }
      }
      if (b.length < 100) break;
    }
    final total = genres.values.fold(0, (a, b) => a + b);
    final stats = (
      minutes: n('movies', 'minutes') + n('episodes', 'minutes'),
      movies: n('movies', 'watched'),
      episodes: n('episodes', 'watched'),
      shows: n('shows', 'watched'),
      yearMinutes: yearMinutes,
      yearPlays: yearPlays,
      topShows:
          (shows.values.toList()
                ..sort((a, b) => b.episodes.compareTo(a.episodes)))
              .take(5)
              .toList(),
      topGenres: [
        for (final e
            in (genres.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value)))
                .take(5))
          (genre: e.key, share: total == 0 ? 0.0 : e.value / total),
      ],
    );
    await _setKv(
      key,
      jsonEncode({'at': today.toIso8601String(), ..._statsJson(stats)}),
    );
    return stats;
  }

  static Map<String, Object?> _statsJson(TraktStats s) => {
    'm': s.minutes,
    'mv': s.movies,
    'ep': s.episodes,
    'sh': s.shows,
    'ym': s.yearMinutes,
    'yp': s.yearPlays,
    'ts': [
      for (final t in s.topShows)
        [t.show.id, t.show.name, t.show.releaseInfo, t.episodes],
    ],
    'tg': [
      for (final g in s.topGenres) [g.genre, g.share],
    ],
  };

  static TraktStats _statsOf(Map<String, Object?> j) => (
    minutes: j['m'] as int? ?? 0,
    movies: j['mv'] as int? ?? 0,
    episodes: j['ep'] as int? ?? 0,
    shows: j['sh'] as int? ?? 0,
    yearMinutes: j['ym'] as int? ?? 0,
    yearPlays: j['yp'] as int? ?? 0,
    topShows: [
      for (final t in (j['ts'] as List? ?? const []).whereType<List<Object?>>())
        (
          show: MetaPreview(
            id: t[0]! as String,
            type: 'series',
            name: t[1] as String? ?? '',
            poster: 'https://images.metahub.space/poster/medium/${t[0]}/img',
            releaseInfo: t[2] as String?,
          ),
          episodes: t[3] as int? ?? 0,
        ),
    ],
    topGenres: [
      for (final g in (j['tg'] as List? ?? const []).whereType<List<Object?>>())
        (genre: g[0]! as String, share: (g[1] as num?)?.toDouble() ?? 0),
    ],
  );

  static TraktList? _listOf(Object? l) {
    if (l is! Map<String, Object?>) return null;
    final id = (l['ids'] as Map<String, Object?>?)?['trakt'];
    if (id is! int) return null;
    return (
      id: id,
      name: l['name'] as String? ?? '',
      privacy: l['privacy'] as String? ?? 'private',
      count: (l['item_count'] as num?)?.toInt() ?? 0,
    );
  }

  /// Trakt's answer as a plain sentence when it isn't a yes. 420: the
  /// free plan's limit on [limit].
  static void _ok(int status, {String limit = 'this'}) {
    if (status >= 200 && status < 300) return;
    throw StateError(switch (status) {
      420 =>
        'Your Trakt plan allows no more $limit. Remove some, or upgrade '
            'at trakt.tv.',
      401 || 403 => 'Sign in to Trakt again, then try once more.',
      404 => 'Trakt no longer has this. Pull to refresh.',
      429 => 'Trakt asked Kinora to slow down. Try again in a minute.',
      _ => 'Trakt didn’t take that (error $status). Try again later.',
    });
  }
}
