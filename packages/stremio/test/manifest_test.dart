import 'package:stremio/stremio.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('AddonManifest.fromJson', () {
    test('Cinemeta: string resources, catalogs with extras', () {
      final m = AddonManifest.fromJson(fixture('cinemeta_manifest.json'));
      expect(m.id, 'com.linvo.cinemeta');
      expect(m.version, '3.0.14');
      expect(m.name, 'Cinemeta');
      expect(m.types, ['movie', 'series']);
      expect(m.idPrefixes, ['tt']);
      expect(m.resources.map((r) => r.name), [
        'catalog',
        'meta',
        'addon_catalog',
      ]);
      // String resources inherit manifest types and prefixes.
      expect(m.resources[1].types, ['movie', 'series']);
      expect(m.resources[1].idPrefixes, ['tt']);

      final top = m.catalog('movie', 'top')!;
      expect(top.name, 'Popular');
      expect(top.supportsExtra('search'), isTrue);
      expect(top.supportsExtra('skip'), isTrue);
      expect(top.extra.first.options, contains('Sci-Fi'));
      expect(top.requiredExtras, isEmpty);

      final year = m.catalog('movie', 'year')!;
      expect(year.requiredExtras.map((e) => e.name), ['genre']);
      final lastVideos = m.catalog('series', 'last-videos')!;
      expect(lastVideos.extra.single.optionsLimit, 100);
      expect(lastVideos.extra.single.isRequired, isTrue);
      expect(m.adult, isFalse);
    });

    test('Kitsu: logo, background and anime prefixes', () {
      final m = AddonManifest.fromJson(fixture('kitsu_manifest.json'));
      expect(m.id, 'community.anime.kitsu');
      expect(m.logo, startsWith('https://'));
      expect(m.background, startsWith('https://'));
      expect(m.idPrefixes, ['kitsu', 'mal', 'anilist', 'anidb']);
      expect(m.catalogs, hasLength(6));
      expect(m.catalog('anime', 'kitsu-anime-trending')!.extra, isEmpty);
      expect(
        m.catalog('anime', 'kitsu-anime-list')!.supportsExtra('search'),
        isTrue,
      );
    });

    test('OpenSubtitles v3: subtitles only', () {
      final m = AddonManifest.fromJson(fixture('opensubtitles_manifest.json'));
      expect(m.resources.single.name, 'subtitles');
      expect(m.catalogs, isEmpty);
      expect(m.description, 'OpenSubtitles v3 Addon for Stremio');
    });

    test('object resources, legacy extras and behaviorHints', () {
      final m = AddonManifest.fromJson({
        'id': 'org.example.torrents',
        'version': '1.2.3',
        'name': 'Example',
        'types': ['movie', 'series', 'anime'],
        'idPrefixes': ['tt'],
        'resources': [
          'catalog',
          {
            'name': 'stream',
            'types': ['movie', 'series'],
            'idPrefixes': ['tt', 'kitsu:'],
          },
          {
            'name': 'meta',
            'types': ['anime'],
          },
          {'types': <Object?>[]},
          42,
        ],
        'catalogs': [
          {
            'type': 'movie',
            'id': 'search-only',
            'extraSupported': ['search', 'skip'],
            'extraRequired': ['search'],
          },
          {'type': 'movie'},
        ],
        'behaviorHints': {
          'adult': false,
          'p2p': true,
          'configurable': true,
          'configurationRequired': true,
        },
      });
      expect(m.resources, hasLength(3), reason: 'invalid entries skipped');
      expect(m.resources[1].idPrefixes, ['tt', 'kitsu:']);
      // Object form without idPrefixes matches every id.
      expect(m.resources[2].idPrefixes, isNull);
      final c = m.catalogs.single;
      expect(c.extra.map((e) => (e.name, e.isRequired)), [
        ('search', true),
        ('skip', false),
      ]);
      expect(m.p2p, isTrue);
      expect(m.configurable, isTrue);
      expect(m.configurationRequired, isTrue);
    });

    test('missing id or non-object throws AddonResponseException', () {
      expect(
        () => AddonManifest.fromJson({'name': 'x'}),
        throwsA(isA<AddonResponseException>()),
      );
      expect(
        () => AddonManifest.fromJson(<Object?>[]),
        throwsA(isA<AddonResponseException>()),
      );
    });

    test('value equality', () {
      final a = AddonManifest.fromJson(fixture('cinemeta_manifest.json'));
      final b = AddonManifest.fromJson(fixture('cinemeta_manifest.json'));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(AddonManifest.fromJson(fixture('kitsu_manifest.json'))));
      expect(a.toString(), contains('com.linvo.cinemeta'));
    });
  });

  group('Addon.supports', () {
    final cinemeta = fixtureAddon(
      'cinemeta_manifest.json',
      'https://v3-cinemeta.strem.io/manifest.json',
    );
    final kitsu = fixtureAddon(
      'kitsu_manifest.json',
      'https://anime-kitsu.strem.fun/manifest.json',
    );
    final subs = fixtureAddon(
      'opensubtitles_manifest.json',
      'https://opensubtitles-v3.strem.io/manifest.json',
    );

    test('meta honors types and idPrefixes', () {
      expect(cinemeta.supports('meta', 'series', 'tt0903747'), isTrue);
      expect(cinemeta.supports('meta', 'series', 'kitsu:1'), isFalse);
      expect(cinemeta.supports('meta', 'anime', 'tt0903747'), isFalse);
      expect(kitsu.supports('meta', 'series', 'kitsu:1'), isTrue);
      expect(kitsu.supports('meta', 'anime', 'mal:1'), isTrue);
    });

    test('unsupported resource', () {
      expect(cinemeta.supports('stream', 'movie', 'tt1254207'), isFalse);
      expect(subs.supports('subtitles', 'series', 'tt0903747:1:1'), isTrue);
      expect(subs.supports('subtitles', 'series', 'kitsu:1:1'), isFalse);
    });

    test('catalog checks declared catalogs, not prefixes', () {
      expect(cinemeta.supports('catalog', 'movie', 'top'), isTrue);
      expect(cinemeta.supports('catalog', 'movie', 'nope'), isFalse);
      expect(kitsu.supports('catalog', 'anime', 'kitsu-anime-airing'), isTrue);
    });

    test('per-resource object form', () {
      final addon = Addon(
        transportUrl: parseAddonUrl('https://example.org'),
        manifest: AddonManifest.fromJson({
          'id': 'x',
          'name': 'x',
          'version': '1.0.0',
          'types': ['movie'],
          'idPrefixes': ['tt'],
          'resources': [
            {
              'name': 'stream',
              'types': ['series'],
              'idPrefixes': ['kitsu:'],
            },
            {
              'name': 'meta',
              'types': ['movie'],
            },
          ],
        }),
      );
      expect(addon.supports('stream', 'series', 'kitsu:1:1'), isTrue);
      expect(addon.supports('stream', 'series', 'tt1:1:1'), isFalse);
      expect(addon.supports('stream', 'movie', 'kitsu:1'), isFalse);
      expect(addon.supports('meta', 'movie', 'anything'), isTrue);
    });
  });
}
