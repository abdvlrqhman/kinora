import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kinora/app/providers.dart';
import 'package:kinora/core/settings.dart';
import 'package:kinora/services/resolver.dart';
import 'package:kinora/services/sources.dart';
import 'package:stremio/stremio.dart';
import 'package:swarm/swarm.dart';

String hash(int i) => i.toRadixString(16).padLeft(40, '0');

Map<String, Object?> torrent(int i, String title, {int? fileIdx}) => {
  'name': 'Test\n${title.contains('2160p') ? '4k' : '1080p'}',
  'title': '$title\n👤 ${10 * i} 💾 ${i + 1}.2 GB ⚙️ Test',
  'infoHash': hash(i),
  'fileIdx': ?fileIdx,
};

void main() {
  final addon = Addon(
    transportUrl: Uri.parse('https://addon.test/manifest.json'),
    manifest: AddonManifest.fromJson({
      'id': 'test.addon',
      'version': '1.0.0',
      'name': 'Test source',
      'resources': ['stream'],
      'types': ['series'],
      'idPrefixes': ['tt'],
    }),
  );

  ProviderContainer container({
    required List<Map<String, Object?>> streams,
    Map<String, SwarmStats> live = const {},
    AppSettings settings = const AppSettings(subtitleLanguages: ['ar', 'en']),
  }) {
    final c = ProviderContainer(
      overrides: [
        initialSettingsProvider.overrideWithValue(settings),
        enabledAddonsProvider.overrideWith((ref) async => [addon]),
        httpClientProvider.overrideWithValue(
          MockClient((req) async {
            expect(req.url.path, '/stream/series/tt0903747%3A1%3A2.json');
            // UTF-8 bytes: addon titles carry emoji.
            return http.Response.bytes(
              utf8.encode(jsonEncode({'streams': streams})),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        ),
        onCellularProvider.overrideWith((ref) => Stream.value(false)),
        swarmLookupProvider.overrideWithValue((hashes, extra) async => live),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  const ep = VideoRef(
    type: 'series',
    mediaId: 'tt0903747',
    videoId: 'tt0903747:1:2',
    season: 1,
    episode: 2,
    runtimeMinutes: 47,
  );

  test('ranks, rejects wrong episodes and explains the pick', () async {
    final c = container(
      streams: [
        torrent(1, 'Show.S01E02.1080p.WEB-DL.DDP5.1.H.264-GRP'),
        torrent(2, 'Show.S01E03.1080p.WEB-DL.DDP5.1.H.264-GRP'),
        torrent(3, 'Show.S01E02.720p.HDTV.x264-OLD'),
        torrent(4, 'Show.S01E02.CAM.x264'),
      ],
      live: {
        hash(1): const SwarmStats(
          seeders: 214,
          leechers: 30,
          completed: 900,
          sources: 3,
        ),
        hash(3): const SwarmStats(
          seeders: 2,
          leechers: 1,
          completed: 10,
          sources: 2,
        ),
      },
    );
    final result = await c.read(resolveProvider(ep).future);
    expect(
      result.best!.releaseName,
      'Show.S01E02.1080p.WEB-DL.DDP5.1.H.264-GRP',
    );
    expect(result.best!.headline, '1080p WEB-DL, 214 seeds');
    expect(result.best!.headline, isNot(contains('·')));
    expect(
      result.releases.any((r) => r.releaseName.contains('S01E03')),
      isFalse,
    );
    expect(result.rejectedCount, greaterThanOrEqualTo(1));
    expect(result.best!.stream!.infoHash, hash(1));
  });

  test('says what to do when nothing is found', () async {
    final c = container(streams: const []);
    final result = await c.read(resolveProvider(ep).future);
    expect(result.releases, isEmpty);
    expect(result.message, isNotNull);
  });

  test('no sources installed', () async {
    final c = ProviderContainer(
      overrides: [
        enabledAddonsProvider.overrideWith((ref) async => <Addon>[]),
        onCellularProvider.overrideWith((ref) => Stream.value(false)),
      ],
    );
    addTearDown(c.dispose);
    final result = await c.read(resolveProvider(ep).future);
    expect(result.message, contains('Add a source'));
  });
}
