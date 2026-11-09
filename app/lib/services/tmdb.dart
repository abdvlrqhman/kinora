import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:stremio/stremio.dart';

import '../app/providers.dart';
import '../core/log.dart';
import 'sources.dart';

/// Secure-storage id of the user's TMDB key (none by default).
const tmdbKeyId = 'tmdb';

const _api = 'https://api.themoviedb.org/3';
const _img = 'https://image.tmdb.org/t/p';

/// A person in the cast, with their photo when TMDB has one.
typedef TmdbPerson = ({String name, String? role, String? photo});

/// A title TMDB recommends; opened by resolving its IMDb id on tap.
typedef TmdbSimilar = ({
  int id,
  String type,
  String name,
  String? poster,
  String? year,
});

/// What TMDB adds to a title.
final class TmdbTitle {
  const TmdbTitle({
    required this.id,
    required this.series,
    this.tagline,
    this.overview,
    this.backdrop,
    this.poster,
    this.logo,
    this.certification,
    this.trailers = const [],
    this.genres = const [],
    this.cast = const [],
    this.directors = const [],
    this.similar = const [],
    this.runtimeMinutes,
    this.episodes = const {},
  });

  final int id;
  final bool series;
  final String? tagline;
  final String? overview;
  final String? backdrop;
  final String? poster;
  final String? logo;

  /// Age rating in the US ("TV-MA", "PG-13").
  final String? certification;
  final List<String> trailers;
  final List<String> genres;
  final List<TmdbPerson> cast;
  final List<String> directors;
  final List<TmdbSimilar> similar;
  final int? runtimeMinutes;

  /// "season:episode" → TMDB's episode (still, overview, air date).
  final Map<String, Episode> episodes;
}

/// The key wasn't accepted.
final class TmdbKeyRejected implements Exception {
  const TmdbKeyRejected();
}

/// TMDB's API with the user's key: a v3 API key, or a v4 read access token
/// (a long token starting with "eyJ").
final class TmdbClient {
  TmdbClient(this.key, this._http);

  final String key;
  final http.Client _http;

  bool get _bearer => key.startsWith('eyJ');

  Future<Map<String, Object?>> _get(
    String path, [
    Map<String, String> query = const {},
  ]) async {
    final uri = Uri.parse('$_api$path')
        .replace(queryParameters: {...query, if (!_bearer) 'api_key': key});
    final res = await _http
        .get(
          uri,
          headers: {
            'accept': 'application/json',
            if (_bearer) 'authorization': 'Bearer $key',
          },
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode == 401) throw const TmdbKeyRejected();
    if (res.statusCode != 200) {
      throw http.ClientException('TMDB ${res.statusCode}', uri);
    }
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, Object?>;
  }

  /// Checks the key (throws [TmdbKeyRejected] when it's wrong).
  Future<void> verify() => _get('/configuration');

  /// TMDB's details for an IMDb id, or null when TMDB doesn't know it.
  Future<TmdbTitle?> title(String imdbId, {required bool series}) async {
    final found = await _get('/find/$imdbId', {'external_source': 'imdb_id'});
    List<Object?> list(String k) => found[k] as List<Object?>? ?? const [];
    final first = [
      ...list(series ? 'tv_results' : 'movie_results'),
      ...list(series ? 'movie_results' : 'tv_results'),
    ].whereType<Map<String, Object?>>().firstOrNull;
    if (first == null) return null;
    final isTv = list('tv_results').contains(first);
    final kind = isTv ? 'tv' : 'movie';
    final id = (first['id']! as num).toInt();
    final d = await _get('/$kind/$id', {
      'language': 'en-US',
      'include_image_language': 'en,null',
      'append_to_response':
          'credits,videos,images,recommendations,'
          '${isTv ? 'content_ratings' : 'release_dates'}',
    });
    final episodes = isTv
        ? await _episodes(id, (d['number_of_seasons'] as num?)?.toInt() ?? 0)
        : const <String, Episode>{};
    return parseTitle(d, isTv: isTv, episodes: episodes);
  }

  /// Every episode, 20 seasons per request (TMDB's append limit).
  Future<Map<String, Episode>> _episodes(int id, int seasons) async {
    final out = <String, Episode>{};
    for (var from = 1; from <= seasons; from += 20) {
      final to = (from + 19).clamp(from, seasons);
      final d = await _get('/tv/$id', {
        'language': 'en-US',
        'append_to_response': [for (var s = from; s <= to; s++) 'season/$s']
            .join(','),
      });
      for (var s = from; s <= to; s++) {
        final season = d['season/$s'];
        if (season is! Map<String, Object?>) continue;
        for (final e
            in (season['episodes'] as List<Object?>? ?? const [])
                .whereType<Map<String, Object?>>()) {
          final n = (e['episode_number'] as num?)?.toInt();
          if (n == null) continue;
          out['$s:$n'] = Episode(
            id: '$s:$n',
            season: s,
            episode: n,
            title: e['name'] as String?,
            overview: _text(e['overview']),
            thumbnail: _image('w300', e['still_path']),
            released: DateTime.tryParse(e['air_date'] as String? ?? ''),
          );
        }
      }
    }
    return out;
  }

  /// The IMDb id for a TMDB title (to open a recommendation).
  Future<String?> imdbId(int id, String type) async {
    final d = await _get(
      '/${type == 'movie' ? 'movie' : 'tv'}/$id/external_ids',
    );
    final v = d['imdb_id'];
    return v is String && v.startsWith('tt') ? v : null;
  }
}

String? _text(Object? v) =>
    v is String && v.trim().isNotEmpty ? v.trim() : null;

String? _image(String size, Object? path) =>
    path is String && path.isNotEmpty ? '$_img/$size$path' : null;

/// Parses TMDB's details response (with its appended parts).
TmdbTitle parseTitle(
  Map<String, Object?> d, {
  required bool isTv,
  Map<String, Episode> episodes = const {},
}) {
  List<Map<String, Object?>> list(Object? v) =>
      (v as List<Object?>? ?? const [])
          .whereType<Map<String, Object?>>()
          .toList();
  Map<String, Object?> obj(Object? v) =>
      v is Map<String, Object?> ? v : const {};

  // Logos: English first, then language-free; PNG only (no SVG decoder).
  final logos =
      list(obj(d['images'])['logos'])
          .where((l) => (l['file_path'] as String? ?? '').endsWith('.png'))
          .toList()
        ..sort(
          (a, b) => (a['iso_639_1'] == 'en' ? 0 : 1).compareTo(
            b['iso_639_1'] == 'en' ? 0 : 1,
          ),
        );
  final videos =
      list(obj(d['videos'])['results'])
          .where((v) => v['site'] == 'YouTube' && v['type'] == 'Trailer')
          .toList()
        ..sort(
          (a, b) =>
              (b['official'] == true ? 1 : 0) - (a['official'] == true ? 1 : 0),
        );
  String? certification;
  if (isTv) {
    certification = list(obj(d['content_ratings'])['results'])
        .where((r) => r['iso_3166_1'] == 'US')
        .map((r) => _text(r['rating']))
        .nonNulls
        .firstOrNull;
  } else {
    for (final r in list(obj(d['release_dates'])['results'])) {
      if (r['iso_3166_1'] != 'US') continue;
      certification = list(r['release_dates'])
          .map((x) => _text(x['certification']))
          .nonNulls
          .firstOrNull;
    }
  }
  final credits = obj(d['credits']);
  final runtime = isTv
      ? (d['episode_run_time'] as List<Object?>? ?? const [])
            .whereType<num>()
            .firstOrNull
      : d['runtime'] as num?;
  return TmdbTitle(
    id: (d['id']! as num).toInt(),
    series: isTv,
    tagline: _text(d['tagline']),
    overview: _text(d['overview']),
    backdrop: _image('w1280', d['backdrop_path']),
    poster: _image('w500', d['poster_path']),
    logo: _image('w500', logos.firstOrNull?['file_path']),
    certification: certification,
    trailers: [for (final v in videos) ?(v['key'] as String?)],
    genres: [for (final g in list(d['genres'])) ?(g['name'] as String?)],
    cast: [
      for (final c in list(credits['cast']).take(15))
        if (c['name'] case final String name)
          (
            name: name,
            role: _text(c['character']),
            photo: _image('w185', c['profile_path']),
          ),
    ],
    directors: isTv
        ? [for (final c in list(d['created_by'])) ?(c['name'] as String?)]
        : [
            for (final c in list(credits['crew']))
              if (c['job'] == 'Director') ?(c['name'] as String?),
          ],
    similar: [
      for (final r in list(obj(d['recommendations'])['results']).take(20))
        if (r['id'] case final num id)
          (
            id: id.toInt(),
            type: (r['media_type'] ?? (isTv ? 'tv' : 'movie')) == 'tv'
                ? 'series'
                : 'movie',
            name: (r['title'] ?? r['name'] ?? '') as String,
            poster: _image('w342', r['poster_path']),
            year: ((r['release_date'] ?? r['first_air_date']) as String? ?? '')
                .split('-')
                .first,
          ),
    ],
    runtimeMinutes: runtime?.toInt(),
    episodes: episodes,
  );
}

/// Fills what the source left empty with TMDB's details. The source's own
/// values win: TMDB only adds.
MetaDetail withTmdb(MetaDetail m, TmdbTitle t) {
  Episode fill(Episode e) {
    final x = t.episodes['${e.season}:${e.episode}'];
    if (x == null) return e;
    final generic =
        e.title == null || RegExp(r'^Episode \d+$').hasMatch(e.title!);
    return Episode(
      id: e.id,
      season: e.season,
      episode: e.episode,
      title: generic ? (x.title ?? e.title) : e.title,
      released: e.released ?? x.released,
      thumbnail: e.thumbnail ?? x.thumbnail,
      overview: (e.overview?.trim().isNotEmpty ?? false)
          ? e.overview
          : x.overview,
    );
  }

  return MetaDetail(
    id: m.id,
    type: m.type,
    name: m.name,
    poster: m.poster ?? t.poster,
    posterShape: m.posterShape,
    background: m.background ?? t.backdrop,
    logo: m.logo ?? t.logo,
    description: (m.description?.trim().isNotEmpty ?? false)
        ? m.description
        : t.overview,
    releaseInfo: m.releaseInfo,
    imdbRating: m.imdbRating,
    genres: m.genres.isEmpty ? t.genres : m.genres,
    links: m.links,
    trailerYouTubeIds: m.trailerYouTubeIds.isEmpty
        ? t.trailers
        : m.trailerYouTubeIds,
    videos: [for (final e in m.videos) fill(e)],
    cast: m.cast.isEmpty ? [for (final c in t.cast) c.name] : m.cast,
    director: m.director.isEmpty ? t.directors : m.director,
    runtime:
        m.runtime ??
        (t.runtimeMinutes == null ? null : '${t.runtimeMinutes} min'),
    released: m.released,
    defaultVideoId: m.defaultVideoId,
  );
}

/// The user's TMDB key, or null (TMDB is off).
final tmdbKeyProvider = FutureProvider<String?>((ref) async {
  try {
    final c = await ref.watch(secureKeysProvider).read(tmdbKeyId);
    return c.apiKey.isEmpty ? null : c.apiKey;
  } on Object catch (e) {
    Log.w('tmdb', 'key unavailable: $e');
    return null; // TMDB off; everything else works
  }
});

/// TMDB's details for a title; null without a key, for non-IMDb ids, when
/// TMDB doesn't know it, or when it can't be reached (the page works
/// without it).
final tmdbTitleProvider =
    FutureProvider.family<TmdbTitle?, ({String type, String id})>((
      ref,
      key,
    ) async {
      final apiKey = await ref.watch(tmdbKeyProvider.future);
      final imdb = key.id.split(':').first;
      if (apiKey == null || !imdb.startsWith('tt')) return null;
      try {
        return await TmdbClient(
          apiKey,
          ref.watch(httpClientProvider),
        ).title(imdb, series: key.type != 'movie');
      } on Object catch (e) {
        Log.w('tmdb', 'details for $imdb: $e');
        return null;
      }
    });

/// A title's details from its source, with TMDB's additions once they
/// arrive (the source's details show first; TMDB never delays them).
final richMetaProvider = Provider.autoDispose
    .family<AsyncValue<MetaDetail>, ({String type, String id})>((ref, key) {
      final extra = ref.watch(tmdbTitleProvider(key)).value;
      return ref
          .watch(metaProvider(key))
          .whenData((m) => extra == null ? m : withTmdb(m, extra));
    });
