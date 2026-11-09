import 'package:stremio/stremio.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('parseAddonUrl', () {
    test('https manifest URL is kept', () {
      expect(
        parseAddonUrl('https://v3-cinemeta.strem.io/manifest.json').toString(),
        'https://v3-cinemeta.strem.io/manifest.json',
      );
    });

    test('stremio:// becomes https://', () {
      expect(
        parseAddonUrl('stremio://opensubtitles-v3.strem.io/manifest.json')
            .toString(),
        'https://opensubtitles-v3.strem.io/manifest.json',
      );
    });

    test('base URLs, trailing slashes, whitespace and bare hosts', () {
      for (final input in [
        'https://anime-kitsu.strem.fun',
        'https://anime-kitsu.strem.fun/',
        '  https://anime-kitsu.strem.fun//  ',
        'anime-kitsu.strem.fun',
        'STREMIO://anime-kitsu.strem.fun/manifest.json',
      ]) {
        expect(
          parseAddonUrl(input).toString(),
          'https://anime-kitsu.strem.fun/manifest.json',
          reason: input,
        );
      }
    });

    test('config segments are preserved', () {
      const encoded =
          'https://addon.example/%7B%22debrid%22%3A%22rd%22%2C%22q%22%3A%5B1%5D%7D/manifest.json';
      expect(parseAddonUrl(encoded).toString(), encoded);
      expect(
        parseAddonUrl(
          'stremio://addon.example/eyJrZXkiOiJ2YWx1ZSJ9==/sub%2Fpath',
        ).toString(),
        'https://addon.example/eyJrZXkiOiJ2YWx1ZSJ9==/sub%2Fpath/manifest.json',
      );
      // `|` is illegal in a URL path and gets percent-encoded, as browsers do.
      expect(
        parseAddonUrl(
          'https://addon.example/providers=yts,eztv|qualityfilter=480p',
        ).toString(),
        'https://addon.example/providers=yts,eztv%7Cqualityfilter=480p/manifest.json',
      );
    });

    test('http, ports and query are kept', () {
      expect(
        parseAddonUrl('http://192.168.1.10:7000/cfg?x=1').toString(),
        'http://192.168.1.10:7000/cfg/manifest.json?x=1',
      );
    });

    test('rejects junk with InvalidAddonUrlException', () {
      for (final input in [
        '',
        '   ',
        'ftp://x.org/manifest.json',
        'https://',
      ]) {
        expect(
          () => parseAddonUrl(input),
          throwsA(isA<InvalidAddonUrlException>()),
          reason: input,
        );
      }
    });
  });

  group('Addon.resourceUrl', () {
    final addon = streamAddon(
      'https://addon.example/%7B%22k%22%3A1%7D/manifest.json',
    );

    test('encodes id like encodeURIComponent and keeps config', () {
      expect(
        addon.resourceUrl('stream', 'series', 'tt0903747:1:1').toString(),
        'https://addon.example/%7B%22k%22%3A1%7D/stream/series/tt0903747%3A1%3A1.json',
      );
    });

    test('extras as k=v&k2=v2 with encoded values', () {
      expect(
        addon
            .resourceUrl(
              'catalog',
              'movie',
              'top',
              extra: {'search': 'the matrix & co', 'skip': '100'},
            )
            .toString(),
        'https://addon.example/%7B%22k%22%3A1%7D/catalog/movie/top/search=the%20matrix%20%26%20co&skip=100.json',
      );
    });

    test('query of the transport URL is appended', () {
      final a = streamAddon('https://addon.example/manifest.json?token=abc');
      expect(
        a.resourceUrl('stream', 'movie', 'tt1').toString(),
        'https://addon.example/stream/movie/tt1.json?token=abc',
      );
    });
  });
}
