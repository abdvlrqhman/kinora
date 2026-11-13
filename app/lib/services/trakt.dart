import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../app/providers.dart';
import '../core/db/database.dart';
import '../core/log.dart';
import 'sources.dart';

/// Kinora's Trakt app, set at build time. Device sign-in needs only this
/// public id: Trakt asks mobile and desktop apps not to carry a secret.
const _clientId = String.fromEnvironment('TRAKT_CLIENT_ID');

final class TraktConfig {
  const TraktConfig({required this.clientId, this.api = _api});
  static const _api = 'https://api.trakt.tv';

  final String clientId;
  final String api;
}

/// Null when this build has no Trakt app (then Settings says so).
final traktConfigProvider = Provider<TraktConfig?>(
  (_) => _clientId.isEmpty ? null : const TraktConfig(clientId: _clientId),
);

/// A code for the user to approve at trakt.tv.
final class TraktCode {
  const TraktCode({
    required this.deviceCode,
    required this.userCode,
    required this.url,
    required this.expiresAt,
    required this.interval,
  });
  final String deviceCode;
  final String userCode;
  final String url;
  final DateTime expiresAt;
  final Duration interval;
}

/// How the approval at trakt.tv ended.
enum TraktSignIn { approved, denied, expired, failed }

final class _Tokens {
  const _Tokens(this.access, this.refresh, this.expiresAt);

  factory _Tokens.fromResponse(Map<String, Object?> j) => _Tokens(
    j['access_token']! as String,
    j['refresh_token']! as String,
    DateTime.fromMillisecondsSinceEpoch(
      ((j['created_at']! as num) + (j['expires_in']! as num)).toInt() * 1000,
    ),
  );

  factory _Tokens.fromJson(Map<String, Object?> j) => _Tokens(
    j['a']! as String,
    j['r']! as String,
    DateTime.parse(j['e']! as String),
  );

  final String access;
  final String refresh;
  final DateTime expiresAt;

  Map<String, Object?> toJson() => {
    'a': access,
    'r': refresh,
    'e': expiresAt.toIso8601String(),
  };
}

/// Trakt sync: an optional sign-in that keeps what you watched, where you
/// stopped and My List in step with your Trakt account (and so with other
/// devices and apps). Changes wait in a queue while offline. Only titles
/// with an IMDb id (Cinemeta's) are synced.
final class TraktSync extends ChangeNotifier {
  TraktSync(this._ref);

  final Ref _ref;
  static const _tokensKey = 'trakt.tokens';
  static const _userKey = 'trakt.user';
  static const _queueKey = 'trakt.queue';
  static const _activitiesKey = 'trakt.activities';
  static const _syncedKey = 'trakt.synced';

  /// The signed-in Trakt user, null when signed out.
  String? user;
  bool syncing = false;
  DateTime? lastSync;

  /// Why the last sync or sign-in didn't go through, for Settings.
  String? note;

  /// What the last sync brought in: watched, resume points, My List.
  ({int watched, int resume, int listed})? brought;
  int _watched = 0, _resume = 0, _listed = 0;

  _Tokens? _tokens;
  bool _loaded = false;
  Timer? _flushSoon;
  Future<void> _work = Future.value();
  final _episodeIds = <String, int>{};

  /// Tests and screen renders: signed in as [name], last synced [at].
  @visibleForTesting
  void debugSignedIn(
    String name, {
    DateTime? at,
    ({int watched, int resume, int listed})? brought,
  }) {
    _loaded = true;
    _tokens = _Tokens('test', 'test', DateTime(2100));
    user = name;
    lastSync = at;
    this.brought = brought;
    notifyListeners();
  }

  TraktConfig? get _config => _ref.read(traktConfigProvider);
  AppDatabase get _db => _ref.read(databaseProvider);
  http.Client get _http => _ref.read(httpClientProvider);
  bool get available => _config != null;
  bool get signedIn => user != null && _tokens != null;

  // ------------------------------------------------------------- startup --

  /// Loads the sign-in and syncs (at launch and when Kinora comes back).
  Future<void> start() async {
    await _load();
    if (signedIn) await syncNow();
  }

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    final keys = _ref.read(secureKeysProvider);
    final raw = await keys.readSecret(_tokensKey);
    if (raw != null) {
      _tokens = _Tokens.fromJson(jsonDecode(raw) as Map<String, Object?>);
      user = await keys.readSecret(_userKey);
    }
    final synced = await _kv(_syncedKey);
    lastSync = synced == null ? null : DateTime.tryParse(synced);
    notifyListeners();
  }

  // ------------------------------------------------------------- sign-in --

  /// Starts a sign-in: a code to approve at trakt.tv.
  Future<TraktCode> startSignIn() async {
    final c = _config!;
    final res = await _http.post(
      Uri.parse('${c.api}/oauth/device/code'),
      headers: _headers(),
      body: jsonEncode({'client_id': c.clientId}),
    );
    if (res.statusCode != 200) {
      throw StateError('Trakt answered ${res.statusCode}');
    }
    final j = jsonDecode(res.body) as Map<String, Object?>;
    return TraktCode(
      deviceCode: j['device_code']! as String,
      userCode: j['user_code']! as String,
      url: j['verification_url']! as String,
      expiresAt: DateTime.now().add(
        Duration(seconds: (j['expires_in']! as num).toInt()),
      ),
      interval: Duration(seconds: (j['interval']! as num).toInt()),
    );
  }

  /// Waits (polling at Trakt's pace) until the code is approved, denied or
  /// expired, or [cancelled] returns true. Approved: signed in; the first
  /// [syncNow] then merges both ways.
  Future<TraktSignIn> finishSignIn(
    TraktCode code, {
    bool Function()? cancelled,
  }) async {
    final c = _config!;
    var wait = code.interval;
    while (DateTime.now().isBefore(code.expiresAt)) {
      await Future<void>.delayed(wait);
      if (cancelled?.call() ?? false) return TraktSignIn.failed;
      final http.Response res;
      try {
        res = await _http.post(
          Uri.parse('${c.api}/oauth/device/token'),
          headers: _headers(),
          body: jsonEncode({'code': code.deviceCode, 'client_id': c.clientId}),
        );
      } on Object catch (e) {
        Log.d('trakt', 'poll: $e');
        continue; // a network blip: keep waiting
      }
      switch (res.statusCode) {
        case 200:
          await _signedIn(
            _Tokens.fromResponse(jsonDecode(res.body) as Map<String, Object?>),
          );
          return TraktSignIn.approved;
        case 400:
          continue; // not approved yet
        case 429:
          wait += const Duration(seconds: 1);
        case 410:
          return TraktSignIn.expired;
        case 418:
          return TraktSignIn.denied;
        default:
          Log.w('trakt', 'sign-in: ${res.statusCode}');
          return TraktSignIn.failed;
      }
    }
    return TraktSignIn.expired;
  }

  Future<void> _signedIn(_Tokens t) async {
    await _saveTokens(t);
    final (status, body) = await _call('GET', '/users/settings');
    String? name;
    if (status == 200) {
      final u = (body! as Map<String, Object?>)['user'];
      if (u is Map<String, Object?>) name = u['username'] as String?;
    }
    user = name ?? 'you';
    await _ref.read(secureKeysProvider).writeSecret(_userKey, user);
    await _setKv(_activitiesKey, null); // a first sync: merge both ways
    note = null;
    notifyListeners();
    Log.i('trakt', 'signed in');
  }

  Future<void> signOut() async {
    final t = _tokens;
    final c = _config;
    if (t != null && c != null) {
      try {
        await _http.post(
          Uri.parse('${c.api}/oauth/revoke'),
          headers: _headers(),
          body: jsonEncode({'token': t.access, 'client_id': c.clientId}),
        );
      } on Object catch (e) {
        Log.d('trakt', 'revoke: $e');
      }
    }
    await _forget();
    Log.i('trakt', 'signed out');
  }

  Future<void> _forget() async {
    final keys = _ref.read(secureKeysProvider);
    await keys.writeSecret(_tokensKey, null);
    await keys.writeSecret(_userKey, null);
    for (final k in [_queueKey, _activitiesKey, _syncedKey]) {
      await _setKv(k, null);
    }
    _tokens = null;
    user = null;
    lastSync = null;
    notifyListeners();
  }

  // --------------------------------------------------- local → Trakt -----

  /// A video's progress was saved (playing, finished, marked watched or
  /// not): queued for Trakt. [unwatched] when a watched mark was removed.
  void progressSaved(WatchProgressData r, {bool unwatched = false}) {
    if (!signedIn || !r.mediaId.startsWith('tt')) return;
    final pct = r.durationMs > 0 ? r.positionMs * 100 / r.durationMs : 0.0;
    if (!unwatched && !r.completed && pct < 1) return;
    unawaited(
      _enqueue({
        'k': unwatched
            ? 'unwatch'
            : r.completed
            ? 'stop'
            : 'pause',
        'v': r.videoId,
        'm': r.mediaId,
        't': r.season == null ? 'movie' : 'episode',
        's': r.season,
        'e': r.episode,
        // Finished counts as watched on Trakt above 80%.
        'p': r.completed ? (pct < 90 ? 90.0 : pct.clamp(0, 100)) : pct,
      }, soon: r.completed || unwatched),
    );
  }

  /// A title was added to or removed from My List.
  void listChanged(String mediaId, String type, {required bool added}) {
    if (!signedIn || !mediaId.startsWith('tt')) return;
    unawaited(
      _enqueue({
        'k': added ? 'list+' : 'list-',
        'm': mediaId,
        't': type == 'movie' ? 'movie' : 'show',
      }, soon: true),
    );
  }

  /// Queues [op], replacing a queued one about the same video or title.
  Future<void> _enqueue(Map<String, Object?> op, {required bool soon}) =>
      _serial(() async {
        final q = await _queue();
        String key(Map<String, Object?> o) =>
            (o['k']! as String).startsWith('list')
            ? 'm${o['m']}'
            : 'v${o['v']}';
        q.removeWhere((o) => key(o) == key(op));
        q.add(op);
        await _setKv(_queueKey, jsonEncode(q));
        _flushSoon?.cancel();
        // Progress while playing waits until it settles; the rest goes now.
        _flushSoon = Timer(
          soon ? const Duration(seconds: 2) : const Duration(seconds: 20),
          () => unawaited(_serial(_flush)),
        );
      });

  /// Sends queued changes in order, one per second (Trakt's write limit).
  /// Stops at a network error (kept for later); drops changes Trakt
  /// refuses for good.
  Future<void> _flush() async {
    if (!signedIn) return;
    final q = await _queue();
    while (q.isNotEmpty) {
      final op = q.first;
      final int status;
      try {
        status = await _send(op);
      } on Object catch (e) {
        Log.d('trakt', 'send: $e');
        break; // offline: later
      }
      if (status == 429 || status >= 500) break;
      if (status == 420) {
        note = 'Your Trakt list is full (free accounts keep 250 titles).';
      } else if (status >= 400 && status != 409 && status != 422) {
        Log.w('trakt', '${op['k']} refused: $status');
      }
      q.removeAt(0);
      await _setKv(_queueKey, jsonEncode(q));
      if (q.isNotEmpty) await Future<void>.delayed(const Duration(seconds: 1));
    }
  }

  Future<int> _send(Map<String, Object?> op) async {
    final k = op['k']! as String;
    final imdb = op['m']! as String;
    final movie = op['t'] == 'movie';
    switch (k) {
      case 'pause' || 'stop':
        final Map<String, Object?> item;
        if (movie) {
          item = {
            'movie': {
              'ids': {'imdb': imdb},
            },
          };
        } else {
          final id = await _episodeId(imdb, op['s']! as int, op['e']! as int);
          if (id == null) return 404;
          item = {
            'episode': {
              'ids': {'trakt': id},
            },
          };
        }
        return (await _call(
          'POST',
          '/scrobble/$k',
          body: {...item, 'progress': op['p']},
        )).$1;
      case 'unwatch':
        return (await _call(
          'POST',
          '/sync/history/remove',
          body: movie
              ? {
                  'movies': [
                    {
                      'ids': {'imdb': imdb},
                    },
                  ],
                }
              : _showEpisodes(imdb, [(op['s']! as int, op['e']! as int, null)]),
        )).$1;
      case 'list+' || 'list-':
        return (await _call(
          'POST',
          k == 'list+' ? '/sync/watchlist' : '/sync/watchlist/remove',
          body: {
            op['t'] == 'movie' ? 'movies' : 'shows': [
              {
                'ids': {'imdb': imdb},
              },
            ],
          },
        )).$1;
    }
    return 400;
  }

  /// Trakt's id for an episode (scrobbles name episodes by id).
  Future<int?> _episodeId(String show, int season, int episode) async {
    final key = '$show:$season:$episode';
    final known = _episodeIds[key];
    if (known != null) return known;
    final (status, body) = await _call(
      'GET',
      '/shows/$show/seasons/$season/episodes/$episode',
    );
    if (status != 200) return null;
    final id =
        ((body! as Map<String, Object?>)['ids']
                as Map<String, Object?>?)?['trakt']
            as int?;
    if (id != null) _episodeIds[key] = id;
    return id;
  }

  static Map<String, Object?> _showEpisodes(
    String imdb,
    List<(int, int, String?)> episodes,
  ) {
    final seasons = <int, List<Map<String, Object?>>>{};
    for (final (s, e, at) in episodes) {
      (seasons[s] ??= []).add({'number': e, 'watched_at': ?at});
    }
    return {
      'shows': [
        {
          'ids': {'imdb': imdb},
          'seasons': [
            for (final MapEntry(key: s, value: eps) in seasons.entries)
              {'number': s, 'episodes': eps},
          ],
        },
      ],
    };
  }

  // --------------------------------------------------- Trakt → local -----

  /// Sends queued changes, then brings in what changed on Trakt. The first
  /// sync after signing in also sends what this phone already had.
  Future<void> syncNow() => _serial(() async {
    await _load();
    if (!signedIn || syncing) return;
    syncing = true;
    _watched = _resume = _listed = 0;
    notifyListeners();
    try {
      final before = await _kv(_activitiesKey);
      final first = before == null;
      if (first) await _sendEverything();
      await _flush();
      final (status, body) = await _call('GET', '/sync/last_activities');
      if (status != 200) throw StateError('last activities: $status');
      final now = body! as Map<String, Object?>;
      final was = first
          ? const <String, Object?>{}
          : jsonDecode(before) as Map<String, Object?>;
      String? at(Map<String, Object?> j, String group, String field) =>
          (j[group] as Map<String, Object?>?)?[field] as String?;
      bool changed(String group, String field) =>
          first || at(now, group, field) != at(was, group, field);
      if (changed('episodes', 'watched_at') ||
          changed('movies', 'watched_at')) {
        await _pullWatched();
      }
      if (changed('episodes', 'paused_at') || changed('movies', 'paused_at')) {
        await _pullPlayback();
      }
      if (changed('watchlist', 'updated_at') ||
          changed('movies', 'watchlisted_at') ||
          changed('shows', 'watchlisted_at')) {
        await _pullWatchlist(merge: first);
      }
      await _setKv(_activitiesKey, jsonEncode(now));
      brought = (watched: _watched, resume: _resume, listed: _listed);
      lastSync = DateTime.now();
      await _setKv(_syncedKey, lastSync!.toIso8601String());
      note = null;
      Log.i('trakt', 'synced${first ? ' (first)' : ''}');
    } on Object catch (e) {
      Log.w('trakt', 'sync: $e');
      note ??= 'Couldn’t reach Trakt. Kinora tries again later.';
    } finally {
      syncing = false;
      notifyListeners();
    }
  });

  /// After signing in: what this phone watched and listed goes to Trakt.
  Future<void> _sendEverything() async {
    final rows = await _db.select(_db.watchProgress).get();
    final shows = <String, List<(int, int, String?)>>{};
    final movies = <Map<String, Object?>>[];
    for (final r in rows.where((r) => r.completed)) {
      if (!r.mediaId.startsWith('tt')) continue;
      final at = r.updatedAt.toUtc().toIso8601String();
      if (r.season == null) {
        movies.add({
          'ids': {'imdb': r.mediaId},
          'watched_at': at,
        });
      } else if (r.episode != null) {
        (shows[r.mediaId] ??= []).add((r.season!, r.episode!, at));
      }
    }
    if (movies.isNotEmpty || shows.isNotEmpty) {
      await _call(
        'POST',
        '/sync/history',
        body: {
          'movies': movies,
          'shows': [
            for (final MapEntry(key: imdb, value: eps) in shows.entries)
              ...(_showEpisodes(imdb, eps)['shows']! as List<Object?>),
          ],
        },
      );
    }
    final list = await _db.select(_db.libraryItems).get();
    final listed = list.where((i) => i.mediaId.startsWith('tt'));
    if (listed.isNotEmpty) {
      await _call(
        'POST',
        '/sync/watchlist',
        body: {
          'movies': [
            for (final i in listed.where((i) => i.type == 'movie'))
              {
                'ids': {'imdb': i.mediaId},
              },
          ],
          'shows': [
            for (final i in listed.where((i) => i.type != 'movie'))
              {
                'ids': {'imdb': i.mediaId},
              },
          ],
        },
      );
    }
    // Where you stopped, for the last month's unfinished videos.
    final recent = DateTime.now().subtract(const Duration(days: 30));
    for (final r in rows.where(
      (r) => !r.completed && r.updatedAt.isAfter(recent),
    )) {
      progressSaved(r);
    }
  }

  /// Watched episodes and movies: Trakt's newer marks become watched here.
  Future<void> _pullWatched() async {
    final watched = <(String, String, String, int?, int?, DateTime)>[];
    for (final type in ['shows', 'movies']) {
      final (status, body) = await _call('GET', '/sync/watched/$type');
      if (status != 200) continue;
      for (final item
          in (body! as List<Object?>).cast<Map<String, Object?>>()) {
        final media =
            (item[type == 'shows' ? 'show' : 'movie']
                as Map<String, Object?>?) ??
            const {};
        final imdb =
            (media['ids'] as Map<String, Object?>?)?['imdb'] as String?;
        final title = media['title'] as String? ?? '';
        if (imdb == null) continue;
        if (type == 'movies') {
          final at = DateTime.tryParse(
            item['last_watched_at'] as String? ?? '',
          );
          if (at != null) watched.add((imdb, imdb, title, null, null, at));
          continue;
        }
        for (final s
            in (item['seasons'] as List<Object?>? ?? const [])
                .cast<Map<String, Object?>>()) {
          for (final e
              in (s['episodes'] as List<Object?>? ?? const [])
                  .cast<Map<String, Object?>>()) {
            final at = DateTime.tryParse(e['last_watched_at'] as String? ?? '');
            final sn = s['number'] as int?, en = e['number'] as int?;
            if (at == null || sn == null || en == null) continue;
            watched.add(('$imdb:$sn:$en', imdb, title, sn, en, at));
          }
        }
      }
    }
    await _db.transaction(() async {
      for (final (videoId, imdb, title, s, e, at) in watched) {
        final mine = await (_db.select(
          _db.watchProgress,
        )..where((t) => t.videoId.equals(videoId))).getSingleOrNull();
        if (mine != null && (mine.completed || mine.updatedAt.isAfter(at))) {
          continue;
        }
        _watched++;
        await _db
            .into(_db.watchProgress)
            .insertOnConflictUpdate(
              WatchProgressCompanion.insert(
                videoId: videoId,
                mediaId: imdb,
                type: s == null ? 'movie' : 'series',
                name: mine?.name ?? title,
                episodeTitle: Value(mine?.episodeTitle),
                season: Value(s),
                episode: Value(e),
                positionMs: mine?.durationMs ?? 1,
                durationMs: mine?.durationMs ?? 1,
                completed: const Value(true),
                poster: Value(mine?.poster),
                still: Value(mine?.still),
                updatedAt: Value(at),
              ),
            );
      }
    });
  }

  /// Where you stopped elsewhere: newer than here, it's resumed from there.
  Future<void> _pullPlayback() async {
    final (status, body) = await _call('GET', '/sync/playback?extended=full');
    if (status != 200) return;
    await _db.transaction(() async {
      for (final item
          in (body! as List<Object?>).cast<Map<String, Object?>>()) {
        final movie = item['type'] == 'movie';
        final media =
            (item[movie ? 'movie' : 'show'] as Map<String, Object?>?) ??
            const {};
        final ep = item['episode'] as Map<String, Object?>?;
        final imdb =
            (media['ids'] as Map<String, Object?>?)?['imdb'] as String?;
        final at = DateTime.tryParse(item['paused_at'] as String? ?? '');
        final pct = (item['progress'] as num?)?.toDouble();
        if (imdb == null || at == null || pct == null) continue;
        if (!movie && (ep?['season'] == null || ep?['number'] == null)) {
          continue;
        }
        final s = movie ? null : ep!['season']! as int;
        final e = movie ? null : ep!['number']! as int;
        final videoId = movie ? imdb : '$imdb:$s:$e';
        final mine = await (_db.select(
          _db.watchProgress,
        )..where((t) => t.videoId.equals(videoId))).getSingleOrNull();
        if (mine != null && mine.updatedAt.isAfter(at)) continue;
        final runtime = ((movie ? media : ep)?['runtime'] as num?)?.toInt();
        final duration = (mine?.durationMs ?? 0) > 1
            ? mine!.durationMs
            : (runtime ?? 0) * 60000;
        if (duration <= 0) continue; // no length: nowhere to resume
        _resume++;
        await _db
            .into(_db.watchProgress)
            .insertOnConflictUpdate(
              WatchProgressCompanion.insert(
                videoId: videoId,
                mediaId: imdb,
                type: movie ? 'movie' : 'series',
                name: mine?.name ?? media['title'] as String? ?? '',
                episodeTitle: Value(
                  mine?.episodeTitle ?? ep?['title'] as String?,
                ),
                season: Value(s),
                episode: Value(e),
                positionMs: (duration * pct / 100).round(),
                durationMs: duration,
                completed: const Value(false),
                poster: Value(mine?.poster),
                still: Value(mine?.still),
                updatedAt: Value(at),
              ),
            );
      }
    });
  }

  /// My List follows Trakt's watchlist (the first time: both together).
  Future<void> _pullWatchlist({required bool merge}) async {
    final theirs = <String, (String, String)>{};
    for (final type in ['movies', 'shows']) {
      final (status, body) = await _call('GET', '/sync/watchlist/$type');
      if (status != 200) return; // half a list would remove the rest
      for (final item
          in (body! as List<Object?>).cast<Map<String, Object?>>()) {
        final media =
            (item[type == 'movies' ? 'movie' : 'show']
                as Map<String, Object?>?) ??
            const {};
        final imdb =
            (media['ids'] as Map<String, Object?>?)?['imdb'] as String?;
        if (imdb == null) continue;
        theirs[imdb] = (
          type == 'movies' ? 'movie' : 'series',
          media['title'] as String? ?? '',
        );
      }
    }
    final mine = await _db.select(_db.libraryItems).get();
    final added = <String>[];
    await _db.transaction(() async {
      if (!merge) {
        for (final i in mine) {
          if (i.mediaId.startsWith('tt') && !theirs.containsKey(i.mediaId)) {
            await (_db.delete(
              _db.libraryItems,
            )..where((t) => t.mediaId.equals(i.mediaId))).go();
          }
        }
      }
      final have = {for (final i in mine) i.mediaId};
      for (final MapEntry(key: imdb, value: (type, name)) in theirs.entries) {
        if (have.contains(imdb)) continue;
        await _db
            .into(_db.libraryItems)
            .insert(
              LibraryItemsCompanion.insert(
                mediaId: imdb,
                type: type,
                name: name,
              ),
            );
        added.add(imdb);
        _listed++;
      }
    });
    unawaited(_fillArtwork(added.take(40).toList()));
  }

  /// Posters for titles that came from Trakt (best effort).
  Future<void> _fillArtwork(List<String> ids) async {
    for (final id in ids) {
      final row = await (_db.select(
        _db.libraryItems,
      )..where((t) => t.mediaId.equals(id))).getSingleOrNull();
      if (row == null) continue;
      try {
        final meta = await _ref.read(
          metaProvider((type: row.type, id: id)).future,
        );
        await (_db.update(
          _db.libraryItems,
        )..where((t) => t.mediaId.equals(id))).write(
          LibraryItemsCompanion(
            poster: Value(meta.poster),
            background: Value(meta.background),
          ),
        );
      } on Object {
        // No details: the title shows by name.
      }
    }
  }

  // ---------------------------------------------------------------- HTTP --

  Map<String, String> _headers([String? token]) => {
    'Content-Type': 'application/json',
    'trakt-api-version': '2',
    'trakt-api-key': _config?.clientId ?? '',
    'User-Agent': 'Kinora/$kinoraVersion',
    'Authorization': ?(token == null ? null : 'Bearer $token'),
  };

  /// One API call with the user's sign-in, refreshed when needed. Returns
  /// the status and the decoded body.
  Future<(int, Object?)> _call(
    String method,
    String path, {
    Object? body,
  }) async {
    for (var attempt = 0; ; attempt++) {
      final token = await _access();
      if (token == null) return (401, null);
      final req = http.Request(method, Uri.parse('${_config!.api}$path'))
        ..headers.addAll(_headers(token));
      if (body != null) req.body = jsonEncode(body);
      final res = await http.Response.fromStream(
        await _http.send(req).timeout(const Duration(seconds: 30)),
      );
      if (res.statusCode == 401 && attempt == 0 && await _refresh()) continue;
      Object? decoded;
      if (res.body.isNotEmpty) {
        try {
          decoded = jsonDecode(res.body);
        } on FormatException {
          decoded = null;
        }
      }
      return (res.statusCode, decoded);
    }
  }

  /// The access token, renewed a day before it runs out.
  Future<String?> _access() async {
    final t = _tokens;
    if (t == null) return null;
    if (t.expiresAt.difference(DateTime.now()) < const Duration(days: 1)) {
      await _refresh();
    }
    return _tokens?.access;
  }

  /// Trakt's refresh tokens work once: the new pair is saved straight
  /// away. A refused refresh signs out (the user signs in again).
  Future<bool> _refresh() async {
    final t = _tokens;
    final c = _config;
    if (t == null || c == null) return false;
    try {
      final res = await _http.post(
        Uri.parse('${c.api}/oauth/token'),
        headers: _headers(),
        body: jsonEncode({
          'refresh_token': t.refresh,
          'client_id': c.clientId,
          'redirect_uri': 'urn:ietf:wg:oauth:2.0:oob',
          'grant_type': 'refresh_token',
        }),
      );
      if (res.statusCode == 200) {
        await _saveTokens(
          _Tokens.fromResponse(jsonDecode(res.body) as Map<String, Object?>),
        );
        return true;
      }
      if (res.statusCode == 400 || res.statusCode == 401) {
        Log.w('trakt', 'sign-in expired');
        await _forget();
        note = 'Trakt signed you out. Sign in again to keep syncing.';
        notifyListeners();
      }
    } on Object catch (e) {
      Log.d('trakt', 'refresh: $e');
    }
    return false;
  }

  Future<void> _saveTokens(_Tokens t) async {
    _tokens = t;
    await _ref
        .read(secureKeysProvider)
        .writeSecret(_tokensKey, jsonEncode(t.toJson()));
  }

  // ------------------------------------------------------------- storage --

  Future<List<Map<String, Object?>>> _queue() async {
    final raw = await _kv(_queueKey);
    if (raw == null) return [];
    return (jsonDecode(raw) as List<Object?>).cast<Map<String, Object?>>();
  }

  Future<String?> _kv(String key) async => (await (_db.select(
    _db.keyValues,
  )..where((t) => t.key.equals(key))).getSingleOrNull())?.value;

  Future<void> _setKv(String key, String? value) => value == null
      ? (_db.delete(_db.keyValues)..where((t) => t.key.equals(key))).go()
      : _db
            .into(_db.keyValues)
            .insertOnConflictUpdate(KeyValue(key: key, value: value));

  /// One sync or queue change at a time.
  Future<void> _serial(Future<void> Function() work) {
    final next = _work.then((_) => work());
    _work = next.catchError((Object _) {});
    return next;
  }

  @override
  void dispose() {
    _flushSoon?.cancel();
    super.dispose();
  }
}

final traktSyncProvider = Provider<TraktSync>((ref) {
  final s = TraktSync(ref);
  ref.onDispose(s.dispose);
  return s;
});
