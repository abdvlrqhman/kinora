import 'package:stremio/stremio.dart';
import 'package:test/test.dart';

import 'helpers.dart';

List<StreamItem> parseStreams(String name) => [
  for (final s
      in (fixture(name)! as Map<String, Object?>)['streams']! as List<Object?>)
    ?StreamItem.tryParse(s),
];

void main() {
  group('MetaDetail', () {
    test('Cinemeta series: videos with name/number quirks', () {
      final json =
          (fixture('cinemeta_meta_series.json')!
              as Map<String, Object?>)['meta'];
      final m = MetaDetail.fromJson(json);
      expect(m.id, 'tt0903747');
      expect(m.type, 'series');
      expect(m.name, 'Breaking Bad');
      expect(m.imdbRating, '9.5');
      expect(m.releaseInfo, '2008–2013');
      expect(m.runtime, '49 min');
      expect(m.genres, ['Crime', 'Drama', 'Thriller']);
      expect(m.cast, ['Bryan Cranston', 'Aaron Paul', 'Anna Gunn']);
      expect(m.director, isEmpty, reason: 'director: null');
      expect(m.defaultVideoId, isNull, reason: 'defaultVideoId: null');
      expect(m.logo, contains('/logo/'));
      expect(m.background, contains('/background/'));
      expect(m.trailerYouTubeIds, ['VFkjBy2b50Q']);
      expect(m.released, DateTime.utc(2008, 1, 20));
      expect(m.links.first.category, 'imdb');
      expect(m.videos, hasLength(5));
      final pilot = m.videos[1];
      expect(pilot.id, 'tt0903747:1:1');
      expect(pilot.title, 'Pilot');
      expect(pilot.season, 1);
      expect(pilot.episode, 1);
      expect(pilot.released, DateTime.utc(2008, 1, 21, 5));
      expect(
        pilot.thumbnail,
        'https://episodes.metahub.space/tt0903747/1/1/w780.jpg',
      );
      expect(pilot.overview, startsWith('When an unassuming'));
      expect(m.videos.first.season, 0, reason: 'specials kept');
      expect(m.videos.last.id, 'tt0903747:5:16');
    });

    test('Cinemeta movie', () {
      final m = MetaDetail.fromJson(
        (fixture('cinemeta_meta_movie.json')! as Map<String, Object?>)['meta'],
      );
      expect(m.videos, isEmpty);
      expect(m.cast, isEmpty, reason: 'cast: null');
      expect(m.director, ['Sacha Goedegebure']);
      expect(m.defaultVideoId, 'tt1254207');
      expect(m.trailerYouTubeIds, ['yUQM7H4Swgw']);
    });

    test('Kitsu series: absolute kitsu episode ids', () {
      final m = MetaDetail.fromJson(
        (fixture('kitsu_meta_series.json')! as Map<String, Object?>)['meta'],
      );
      expect(m.id, 'kitsu:1');
      expect(m.name, 'Cowboy Bebop');
      expect(m.videos.first.id, 'kitsu:1:1');
      expect(m.videos.first.title, 'Asteroid Blues');
      expect(m.videos.first.episode, 1);
      expect(m.trailerYouTubeIds, ['qig4KOK2R2g']);
    });

    test('equality and MetaPreview != MetaDetail', () {
      final json =
          (fixture('cinemeta_meta_movie.json')!
              as Map<String, Object?>)['meta'];
      expect(MetaDetail.fromJson(json), MetaDetail.fromJson(json));
      expect(
        MetaDetail.fromJson(json).hashCode,
        MetaDetail.fromJson(json).hashCode,
      );
      expect(MetaPreview.fromJson(json), isNot(MetaDetail.fromJson(json)));
      expect(MetaDetail.fromJson(json).toString(), contains('tt1254207'));
    });
  });

  group('MetaPreview', () {
    test('Cinemeta and Kitsu catalog items', () {
      final cinemeta =
          (fixture('cinemeta_catalog_top_movie.json')!
                  as Map<String, Object?>)['metas']!
              as List<Object?>;
      final p = MetaPreview.fromJson(cinemeta.first);
      expect(p.type, 'movie');
      expect(p.id, startsWith('tt'));
      expect(p.poster, startsWith('https://'));
      expect(p.genres, isNotEmpty);

      final kitsu =
          (fixture('kitsu_catalog.json')! as Map<String, Object?>)['metas']!
              as List<Object?>;
      final k = MetaPreview.fromJson(kitsu.first);
      expect(k.id, 'kitsu:7442');
      expect(k.name, 'Attack on Titan');
      expect(k.genres, isEmpty);
    });

    test('number imdbRating is stringified; missing name throws', () {
      expect(
        MetaPreview.fromJson({
          'id': 'x1',
          'type': 'movie',
          'name': 'X',
          'imdbRating': 7.5,
        }).imdbRating,
        '7.5',
      );
      expect(
        () => MetaPreview.fromJson({'id': 'x1', 'type': 'movie'}),
        throwsA(isA<AddonResponseException>()),
      );
    });
  });

  group('StreamItem', () {
    test('torrent stream fields', () {
      final s = parseStreams('torrent_streams_a.json');
      expect(s, hasLength(3));
      final first = s.first;
      expect(first.infoHash, '8e9f7a6b5c4d3e2f1a0b9c8d7e6f5a4b3c2d1e0f');
      expect(first.fileIdx, 0);
      expect(first.name, 'Torrentio\n1080p');
      expect(first.text, startsWith('Breaking.Bad.S01E01.1080p'));
      expect(first.bingeGroup, 'torrentio|1080p|BluRay|x265');
      expect(first.filename, endsWith('.mkv'));
      expect(first.sources, hasLength(3));
      expect(first.trackers, [
        'udp://tracker.opentrackr.org:1337/announce',
        'udp://open.stealth.si:80/announce',
      ]);
      expect(s[1].fileIdx, 3);
      expect(s[2].fileIdx, isNull);
      expect(s[2].sources, isEmpty);
    });

    test('entries without a source are skipped', () {
      final s = parseStreams('torrent_streams_b.json');
      expect(s, hasLength(2));
      expect(s.first.videoSize, 1299227607);
      expect(s.first.text, startsWith('Breaking.Bad.S01E01.1080p'));
    });

    test('url / ytId / externalUrl streams with proxy headers', () {
      final s = parseStreams('debrid_streams.json');
      final d = s.first;
      expect(d.url, startsWith('https://debrid.example/resolve/'));
      expect(d.infoHash, isNull);
      expect(d.notWebReady, isTrue);
      expect(d.videoSize, 10522669875);
      expect(d.videoHash, '8e245d9679d31e12');
      expect(d.proxyRequestHeaders, {
        'User-Agent': 'Stremio',
        'Referer': 'https://debrid.example/',
      });
      expect(d.proxyResponseHeaders, {'Content-Type': 'video/x-matroska'});
      expect(s[1].ytId, 'yUQM7H4Swgw');
      expect(s[2].externalUrl, 'https://www.example.com/watch/big-buck-bunny');
      expect(d, parseStreams('debrid_streams.json').first);
      expect(d.hashCode, parseStreams('debrid_streams.json').first.hashCode);
    });

    test('dedupeStreams merges trackers of identical torrents', () {
      final merged = dedupeStreams([
        ...parseStreams('torrent_streams_a.json'),
        ...parseStreams('torrent_streams_b.json'),
        ...parseStreams('debrid_streams.json'),
        ...parseStreams('debrid_streams.json'),
      ]);
      expect(merged, hasLength(3 + 1 + 3));
      final first = merged.first;
      expect(first.name, 'Torrentio\n1080p', reason: 'first occurrence wins');
      expect(first.sources, [
        'tracker:udp://tracker.opentrackr.org:1337/announce',
        'tracker:udp://open.stealth.si:80/announce',
        'dht:8e9f7a6b5c4d3e2f1a0b9c8d7e6f5a4b3c2d1e0f',
        'tracker:http://tracker.renfei.net:8080/announce',
      ]);
    });

    test('same hash, different fileIdx are different streams', () {
      const a = StreamItem(infoHash: 'aa', fileIdx: 1);
      const b = StreamItem(infoHash: 'aa', fileIdx: 2);
      expect(dedupeStreams([a, b, a]), [a, b]);
    });
  });

  group('isDebridKeyRejection', () {
    test('Torrentio failed_access placeholder', () {
      expect(
        parseStreams('debrid_key_rejected.json').every(isDebridKeyRejection),
        isTrue,
      );
    });

    test('invalid key / expired token text', () {
      expect(
        parseStreams('debrid_invalid_token.json').every(isDebridKeyRejection),
        isTrue,
      );
      for (final text in [
        'Invalid API key',
        'invalid apikey provided',
        'Error: invalid token',
        'Your API key is invalid',
        'Invalid AllDebrid API Key',
      ]) {
        expect(
          isDebridKeyRejection(
            StreamItem(description: text, url: 'https://x.example/e.mp4'),
          ),
          isTrue,
          reason: text,
        );
      }
    });

    test('real results are not flagged', () {
      expect(
        parseStreams('torrent_streams_a.json').any(isDebridKeyRejection),
        isFalse,
      );
      expect(
        parseStreams('debrid_streams.json').any(isDebridKeyRejection),
        isFalse,
      );
      // A torrent whose release name happens to say "invalid key".
      expect(
        isDebridKeyRejection(
          const StreamItem(title: 'The.Invalid.Key.2019.1080p', infoHash: 'ab'),
        ),
        isFalse,
      );
    });
  });

  group('SubtitleItem', () {
    test('OpenSubtitles v3 responses', () {
      final list =
          (fixture('opensubtitles_series.json')!
                  as Map<String, Object?>)['subtitles']!
              as List<Object?>;
      final s = SubtitleItem.tryParse(list.first)!;
      expect(s.id, '4290498');
      expect(s.lang, 'por');
      expect(s.url, startsWith('https://subs5.strem.io/'));
      expect(s.label, isNull);
      expect(s, SubtitleItem.tryParse(list.first));
    });

    test('missing url is rejected, missing id falls back to url', () {
      expect(SubtitleItem.tryParse({'lang': 'eng'}), isNull);
      expect(
        SubtitleItem.tryParse({'url': 'https://s/x.srt', 'lang': 'eng'})!.id,
        'https://s/x.srt',
      );
    });
  });

  group('VideoId', () {
    test('parses IMDb, Kitsu and TMDB forms', () {
      expect(VideoId.parse('tt0903747'), VideoId('tt0903747'));
      expect(
        VideoId.parse('tt0903747:1:2'),
        VideoId('tt0903747', season: 1, episode: 2),
      );
      expect(VideoId.parse('kitsu:1'), VideoId('kitsu:1'));
      expect(VideoId.parse('kitsu:123:5'), VideoId('kitsu:123', episode: 5));
      expect(
        VideoId.parse('tmdb:1396:5:16'),
        VideoId('tmdb:1396', season: 5, episode: 16),
      );
      expect(VideoId.parse('tmdb:1396'), VideoId('tmdb:1396'));
      expect(VideoId.parse('tt0903747:0:1').season, 0);
    });

    test('unknown shapes keep the whole id', () {
      const yt = 'yt_id:UCrDkAvwZum-UTjHmzDI2iIw:9bZkp7q19f0';
      expect(VideoId.parse(yt), VideoId(yt));
      expect(VideoId.parse('bbb1').isEpisode, isFalse);
      expect(VideoId.parse('tt1:1:2:3').metaId, 'tt1:1:2:3');
    });

    test('builds ids', () {
      expect(
        VideoId('tt0903747', season: 1, episode: 2).toString(),
        'tt0903747:1:2',
      );
      expect(VideoId('kitsu:1', episode: 5).toString(), 'kitsu:1:5');
      expect(VideoId('tt1254207').toString(), 'tt1254207');
      expect(() => VideoId('tt1', season: 1), throwsArgumentError);
      for (final id in ['tt0903747:1:1', 'kitsu:1:12', 'tmdb:1:2:3']) {
        expect(VideoId.parse(id).toString(), id);
      }
    });
  });
}
