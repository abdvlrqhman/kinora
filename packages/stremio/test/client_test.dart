import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stremio/stremio.dart';
import 'package:test/test.dart';

import 'helpers.dart';

http.Response json(String fixtureName, {int status = 200}) =>
    http.Response.bytes(
      utf8.encode(fixtureText(fixtureName)),
      status,
      headers: {'content-type': 'application/json'},
    );

AddonClient client(
  MockClientHandler handler, {
  Duration timeout = const Duration(seconds: 5),
  int maxRetries = 2,
  ResponseCache? cache,
}) => AddonClient(
  httpClient: MockClient(handler),
  timeout: timeout,
  maxRetries: maxRetries,
  retryDelay: Duration.zero,
  cache: cache,
);

void main() {
  final cinemeta = fixtureAddon(
    'cinemeta_manifest.json',
    'https://v3-cinemeta.strem.io/manifest.json',
  );
  final torrents = streamAddon('https://torrents.example/cfg=1');

  group('requests', () {
    test('fetchManifest normalizes the URL and sends Kinora UA', () async {
      final seen = <http.Request>[];
      final c = client((r) async {
        seen.add(r);
        return json('cinemeta_manifest.json');
      });
      final addon = await c.fetchManifest(
        Uri.parse('stremio://v3-cinemeta.strem.io'),
      );
      expect(
        addon.transportUrl.toString(),
        'https://v3-cinemeta.strem.io/manifest.json',
      );
      expect(addon.manifest.name, 'Cinemeta');
      expect(seen.single.url, addon.transportUrl);
      expect(seen.single.headers['User-Agent'], 'Kinora/0.1.0');
      expect(seen.single.headers['Accept'], 'application/json');
    });

    test('catalog with search extra', () async {
      Uri? url;
      final c = client((r) async {
        url = r.url;
        return json('cinemeta_search_series.json');
      });
      final items = await c.catalog(
        cinemeta,
        'series',
        'top',
        extra: {'search': 'breaking bad'},
      );
      expect(
        url.toString(),
        'https://v3-cinemeta.strem.io/catalog/series/top/search=breaking%20bad.json',
      );
      expect(items.first.id, 'tt0903747');
      expect(items.first.name, 'Breaking Bad');
    });

    test('meta', () async {
      final c = client((r) async => json('cinemeta_meta_series.json'));
      final m = await c.meta(cinemeta, 'series', 'tt0903747');
      expect(m.videos, hasLength(5));
    });

    test('meta: null is a typed error', () async {
      final c = client((r) async => http.Response('{"meta":null}', 200));
      await expectLater(
        c.meta(cinemeta, 'series', 'tt0'),
        throwsA(
          isA<AddonResponseException>().having(
            (e) => e.uri.toString(),
            'uri',
            'https://v3-cinemeta.strem.io/meta/series/tt0.json',
          ),
        ),
      );
    });

    test('streams decode UTF-8 without charset header', () async {
      final c = client(
        (r) async => http.Response.bytes(
          utf8.encode(fixtureText('torrent_streams_a.json')),
          200,
        ),
      );
      final s = await c.streams(torrents, 'series', 'tt0903747:1:1');
      expect(s.first.title, contains('👤 152'));
    });

    test('subtitles send videoHash/videoSize/filename as extras', () async {
      Uri? url;
      final subs = fixtureAddon(
        'opensubtitles_manifest.json',
        'https://opensubtitles-v3.strem.io/manifest.json',
      );
      final c = client((r) async {
        url = r.url;
        return json('opensubtitles_series.json');
      });
      final list = await c.subtitles(
        subs,
        'series',
        'tt0903747:1:1',
        videoHash: '8e245d9679d31e12',
        videoSize: 1234567890,
        filename: 'Breaking Bad S01E01.mkv',
      );
      expect(
        url.toString(),
        'https://opensubtitles-v3.strem.io/subtitles/series/tt0903747%3A1%3A1/'
        'videoHash=8e245d9679d31e12&videoSize=1234567890&'
        'filename=Breaking%20Bad%20S01E01.mkv.json',
      );
      expect(list, hasLength(5));
    });

    test('404 on list resources means empty, on meta an error', () async {
      final c = client((r) async => http.Response('Not found', 404));
      expect(await c.streams(torrents, 'movie', 'tt1'), isEmpty);
      expect(await c.catalog(cinemeta, 'movie', 'top'), isEmpty);
      await expectLater(
        c.meta(cinemeta, 'movie', 'tt1'),
        throwsA(
          isA<AddonHttpException>().having((e) => e.statusCode, 'code', 404),
        ),
      );
    });

    test('invalid JSON and wrong shapes are AddonResponseException', () async {
      final bad = client((r) async => http.Response('<html>oops</html>', 200));
      await expectLater(
        bad.streams(torrents, 'movie', 'tt1'),
        throwsA(isA<AddonResponseException>()),
      );
      final shape = client((r) async => http.Response('{"streams":{}}', 200));
      await expectLater(
        shape.streams(torrents, 'movie', 'tt1'),
        throwsA(isA<AddonResponseException>()),
      );
      final empty = client((r) async => http.Response('{}', 200));
      expect(await empty.streams(torrents, 'movie', 'tt1'), isEmpty);
    });
  });

  group('debrid key detection', () {
    test('only placeholders -> DebridKeyRejectedException', () async {
      for (final f in [
        'debrid_key_rejected.json',
        'debrid_invalid_token.json',
      ]) {
        final c = client((r) async => json(f));
        await expectLater(
          c.streams(torrents, 'movie', 'tt1254207'),
          throwsA(isA<DebridKeyRejectedException>()),
          reason: f,
        );
      }
    });

    test('placeholders mixed with real results are dropped', () async {
      final body = {
        'streams': [
          ...(fixture('debrid_key_rejected.json')!
                  as Map<String, Object?>)['streams']!
              as List<Object?>,
          ...(fixture('torrent_streams_a.json')!
                  as Map<String, Object?>)['streams']!
              as List<Object?>,
        ],
      };
      final c = client(
        (r) async => http.Response.bytes(utf8.encode(jsonEncode(body)), 200),
      );
      final s = await c.streams(torrents, 'movie', 'tt1');
      expect(s, hasLength(3));
      expect(s.any(isDebridKeyRejection), isFalse);
    });
  });

  group('retries', () {
    test('403 is retried once with a browser User-Agent', () async {
      final agents = <String?>[];
      final c = client((r) async {
        agents.add(r.headers['User-Agent']);
        return r.headers['User-Agent']!.startsWith('Kinora')
            ? http.Response('Forbidden', 403)
            : json('torrent_streams_a.json');
      });
      final s = await c.streams(torrents, 'movie', 'tt1');
      expect(s, hasLength(3));
      expect(agents, hasLength(2));
      expect(agents.last, startsWith('Mozilla/5.0'));
    });

    test('403 twice gives AddonHttpException', () async {
      var calls = 0;
      final c = client((r) async {
        calls++;
        return http.Response('Forbidden', 403);
      });
      await expectLater(
        c.streams(torrents, 'movie', 'tt1'),
        throwsA(
          isA<AddonHttpException>().having((e) => e.statusCode, 'code', 403),
        ),
      );
      expect(calls, 2);
    });

    test('429 honors Retry-After then succeeds', () async {
      var calls = 0;
      final c = client((r) async {
        calls++;
        return calls == 1
            ? http.Response('slow down', 429, headers: {'retry-after': '0'})
            : json('torrent_streams_a.json');
      });
      expect(await c.streams(torrents, 'movie', 'tt1'), hasLength(3));
      expect(calls, 2);
    });

    test('5xx retries are bounded', () async {
      var calls = 0;
      final c = client((r) async {
        calls++;
        return http.Response('bad gateway', 502);
      });
      await expectLater(
        c.streams(torrents, 'movie', 'tt1'),
        throwsA(
          isA<AddonHttpException>().having((e) => e.statusCode, 'code', 502),
        ),
      );
      expect(calls, 3);
    });

    test('4xx other than 403/429 is not retried', () async {
      var calls = 0;
      final c = client((r) async {
        calls++;
        return http.Response('bad', 400);
      });
      await expectLater(
        c.streams(torrents, 'movie', 'tt1'),
        throwsA(isA<AddonHttpException>()),
      );
      expect(calls, 1);
    });

    test('timeouts are retried, then AddonTimeoutException', () async {
      var calls = 0;
      final c = client((r) {
        calls++;
        return Completer<http.Response>().future;
      }, timeout: const Duration(milliseconds: 20));
      await expectLater(
        c.streams(torrents, 'movie', 'tt1'),
        throwsA(
          isA<AddonTimeoutException>().having(
            (e) => e.timeout,
            'timeout',
            const Duration(milliseconds: 20),
          ),
        ),
      );
      expect(calls, 3);
    });

    test('a timeout followed by a quick answer succeeds', () async {
      var calls = 0;
      final c = client((r) async {
        calls++;
        if (calls == 1) return Completer<http.Response>().future;
        return json('torrent_streams_a.json');
      }, timeout: const Duration(milliseconds: 20));
      expect(await c.streams(torrents, 'movie', 'tt1'), hasLength(3));
    });

    test('network errors are typed and not retried', () async {
      var calls = 0;
      final c = client((r) async {
        calls++;
        throw http.ClientException('Connection refused', r.url);
      });
      await expectLater(
        c.streams(torrents, 'movie', 'tt1'),
        throwsA(
          isA<AddonNetworkException>().having(
            (e) => e.message,
            'message',
            'Connection refused',
          ),
        ),
      );
      expect(calls, 1);
    });
  });

  group('cancellation', () {
    test('cancel aborts an in-flight request', () async {
      final cancel = Completer<void>();
      final c = client((r) => Completer<http.Response>().future);
      final future = c.streams(torrents, 'movie', 'tt1', cancel: cancel.future);
      Timer(const Duration(milliseconds: 10), cancel.complete);
      await expectLater(future, throwsA(isA<AddonCancelledException>()));
    });

    test('cancel stops retry backoff', () async {
      final cancel = Completer<void>();
      var calls = 0;
      final c = AddonClient(
        httpClient: MockClient((r) async {
          calls++;
          return http.Response('down', 503);
        }),
        retryDelay: const Duration(seconds: 30),
        maxRetryDelay: const Duration(seconds: 30),
      );
      final watch = Stopwatch()..start();
      final future = c.streams(torrents, 'movie', 'tt1', cancel: cancel.future);
      Timer(const Duration(milliseconds: 20), cancel.complete);
      await expectLater(future, throwsA(isA<AddonCancelledException>()));
      expect(calls, 1);
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    });
  });

  group('ResponseCache', () {
    test('manifests and metas are served from cache until expiry', () async {
      var now = DateTime.utc(2026, 11, 9);
      final cache = ResponseCache(clock: () => now);
      var calls = 0;
      final c = client((r) async {
        calls++;
        return json('cinemeta_meta_series.json');
      }, cache: cache);
      final a = await c.meta(cinemeta, 'series', 'tt0903747');
      final b = await c.meta(cinemeta, 'series', 'tt0903747');
      expect(identical(a, b), isTrue);
      expect(calls, 1);
      now = now.add(const Duration(minutes: 61));
      await c.meta(cinemeta, 'series', 'tt0903747');
      expect(calls, 2);
    });

    test('stream TTL is capped at 5 minutes', () async {
      var now = DateTime.utc(2026, 11, 9);
      final cache = ResponseCache(
        clock: () => now,
        streamTtl: const Duration(hours: 1),
      );
      expect(cache.streamTtl, const Duration(minutes: 5));
      var calls = 0;
      final c = client((r) async {
        calls++;
        return json('torrent_streams_a.json');
      }, cache: cache);
      await c.streams(torrents, 'series', 'tt0903747:1:1');
      now = now.add(const Duration(minutes: 4));
      await c.streams(torrents, 'series', 'tt0903747:1:1');
      expect(calls, 1);
      now = now.add(const Duration(minutes: 2));
      await c.streams(torrents, 'series', 'tt0903747:1:1');
      expect(calls, 2);
    });

    test('errors and key rejections are not cached', () async {
      final cache = ResponseCache();
      var calls = 0;
      final c = client((r) async {
        calls++;
        return json('debrid_key_rejected.json');
      }, cache: cache);
      for (var i = 0; i < 2; i++) {
        await expectLater(
          c.streams(torrents, 'movie', 'tt1'),
          throwsA(isA<DebridKeyRejectedException>()),
        );
      }
      expect(calls, 2);
      expect(cache.length, 0);
    });

    test('evicts oldest entries beyond maxEntries', () {
      final cache = ResponseCache(maxEntries: 2)
        ..put('a', 1, const Duration(minutes: 1))
        ..put('b', 2, const Duration(minutes: 1))
        ..put('c', 3, const Duration(minutes: 1));
      expect(cache.get<int>('a'), isNull);
      expect(cache.get<int>('c'), 3);
      expect(cache.get<String>('c'), isNull, reason: 'wrong type is a miss');
    });
  });
}
