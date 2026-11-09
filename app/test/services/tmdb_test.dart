import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kinora/services/tmdb.dart';
import 'package:stremio/stremio.dart';

final _details = <String, Object?>{
  'id': 1405,
  'tagline': 'Everyone has a dark side.',
  'overview': 'A blood spatter analyst.',
  'backdrop_path': '/b.jpg',
  'poster_path': '/p.jpg',
  'episode_run_time': [52],
  'genres': [
    {'name': 'Crime'},
  ],
  'created_by': [
    {'name': 'James Manos Jr.'},
  ],
  'images': {
    'logos': [
      {'file_path': '/fr.png', 'iso_639_1': 'fr'},
      {'file_path': '/en.svg', 'iso_639_1': 'en'},
      {'file_path': '/en.png', 'iso_639_1': 'en'},
    ],
  },
  'videos': {
    'results': [
      {'site': 'YouTube', 'type': 'Teaser', 'key': 'tease'},
      {'site': 'YouTube', 'type': 'Trailer', 'key': 'fan', 'official': false},
      {'site': 'YouTube', 'type': 'Trailer', 'key': 'real', 'official': true},
    ],
  },
  'content_ratings': {
    'results': [
      {'iso_3166_1': 'DE', 'rating': '16'},
      {'iso_3166_1': 'US', 'rating': 'TV-MA'},
    ],
  },
  'credits': {
    'cast': [
      {
        'name': 'Michael C. Hall',
        'character': 'Dexter',
        'profile_path': '/m.jpg',
      },
      {'name': 'No Photo', 'character': ''},
    ],
  },
  'recommendations': {
    'results': [
      {
        'id': 1,
        'name': 'Hannibal',
        'media_type': 'tv',
        'first_air_date': '2013-04-04',
      },
      {
        'id': 2,
        'title': 'Se7en',
        'media_type': 'movie',
        'release_date': '1995-09-22',
      },
    ],
  },
};

void main() {
  test('parses what TMDB adds', () {
    final t = parseTitle(_details, isTv: true);
    expect(t.tagline, 'Everyone has a dark side.');
    expect(t.logo, endsWith('/w500/en.png'), reason: 'English PNG first');
    expect(t.trailers.first, 'real', reason: 'official trailer first');
    expect(t.trailers, isNot(contains('tease')));
    expect(t.certification, 'TV-MA');
    expect(t.cast.first.photo, endsWith('/w185/m.jpg'));
    expect(t.cast.last.role, isNull);
    expect(t.directors, ['James Manos Jr.']);
    expect(t.similar.map((s) => (s.type, s.year)), [
      ('series', '2013'),
      ('movie', '1995'),
    ]);
    expect(t.runtimeMinutes, 52);
  });

  test('fills only what the source left empty', () {
    const t = TmdbTitle(
      id: 1,
      series: true,
      logo: 'L',
      backdrop: 'B',
      overview: 'TMDB overview',
      trailers: ['tr'],
      cast: [(name: 'A', role: null, photo: null)],
      episodes: {
        '1:1': Episode(
          id: '1:1',
          title: 'Pilot',
          thumbnail: 'S',
          overview: 'O',
        ),
        '1:2': Episode(id: '1:2', title: 'Crocodile', thumbnail: 'S2'),
      },
    );
    final merged = withTmdb(
      const MetaDetail(
        id: 'tt1',
        type: 'series',
        name: 'Show',
        background: 'source-bg',
        videos: [
          Episode(id: 'tt1:1:1', season: 1, episode: 1, title: 'Episode 1'),
          Episode(
            id: 'tt1:1:2',
            season: 1,
            episode: 2,
            title: 'Their title',
            thumbnail: 'theirs',
          ),
        ],
      ),
      t,
    );
    expect(merged.background, 'source-bg');
    expect(merged.logo, 'L');
    expect(merged.description, 'TMDB overview');
    expect(merged.trailerYouTubeIds, ['tr']);
    expect(merged.cast, ['A']);
    expect(merged.videos.first.title, 'Pilot');
    expect(merged.videos.first.thumbnail, 'S');
    expect(merged.videos.last.title, 'Their title');
    expect(merged.videos.last.thumbnail, 'theirs');
  });

  test('a v3 key goes in the query, a v4 token in the header', () async {
    final seen = <http.Request>[];
    final client = MockClient((r) async {
      seen.add(r);
      return http.Response(jsonEncode(<String, Object?>{}), 200);
    });
    await TmdbClient('abc123', client).verify();
    await TmdbClient('eyJtoken', client).verify();
    expect(seen.first.url.queryParameters['api_key'], 'abc123');
    expect(seen.first.headers['authorization'], isNull);
    expect(seen.last.url.queryParameters.containsKey('api_key'), isFalse);
    expect(seen.last.headers['authorization'], 'Bearer eyJtoken');
    final rejected = MockClient((_) async => http.Response('{}', 401));
    expect(
      TmdbClient('bad', rejected).verify(),
      throwsA(isA<TmdbKeyRejected>()),
    );
  });
}
