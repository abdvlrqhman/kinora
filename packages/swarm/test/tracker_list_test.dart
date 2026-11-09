import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:swarm/swarm.dart';
import 'package:test/test.dart';

const listText = '''
udp://tracker.opentrackr.org:1337/announce

udp://open.stealth.si:80/announce

# comment
UDP://Tracker.OpenTrackr.org:1337/announce

http://tracker.renfei.net:8080/announce

wss://tracker.openwebtorrent.com
''';

void main() {
  late Directory dir;
  late File cache;
  final now = DateTime(2026, 11, 9, 12);

  setUp(() {
    dir = Directory.systemTemp.createTempSync('swarm_trackers_');
    cache = File('${dir.path}/sub/trackers.txt');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  TrackerList list(MockClientHandler handler) => TrackerList(
    httpClient: MockClient(handler),
    cacheFile: cache,
    clock: () => now,
  );

  final expected = [
    Uri.parse('udp://tracker.opentrackr.org:1337/announce'),
    Uri.parse('udp://open.stealth.si:80/announce'),
    Uri.parse('http://tracker.renfei.net:8080/announce'),
  ];

  test('downloads, normalizes and writes the cache', () async {
    Uri? fetched;
    final l = list((r) async {
      fetched = r.url;
      return http.Response(listText, 200);
    });
    expect(await l.load(), expected);
    expect(fetched, TrackerList.defaultSource);
    expect(cache.readAsLinesSync(), [for (final u in expected) '$u']);
  });

  test('a fresh cache is used without the network', () async {
    cache
      ..createSync(recursive: true)
      ..writeAsStringSync('udp://cached.example:6969/announce\n')
      ..setLastModifiedSync(now.subtract(const Duration(hours: 23)));
    final l = list((r) async => throw StateError('no network expected'));
    expect(await l.load(), [Uri.parse('udp://cached.example:6969/announce')]);
  });

  test('a stale cache is refreshed; forceRefresh skips a fresh one', () async {
    cache
      ..createSync(recursive: true)
      ..writeAsStringSync('udp://cached.example:6969/announce\n')
      ..setLastModifiedSync(now.subtract(const Duration(hours: 25)));
    var calls = 0;
    final l = list((r) async {
      calls++;
      return http.Response(listText, 200);
    });
    expect(await l.load(), expected);
    cache.setLastModifiedSync(now);
    expect(await l.load(forceRefresh: true), expected);
    expect(calls, 2);
  });

  test('offline falls back to the stale cache', () async {
    cache
      ..createSync(recursive: true)
      ..writeAsStringSync('udp://cached.example:6969/announce\n')
      ..setLastModifiedSync(now.subtract(const Duration(days: 30)));
    final l = list(
      (r) async => throw http.ClientException('Failed host lookup', r.url),
    );
    expect(await l.load(), [Uri.parse('udp://cached.example:6969/announce')]);
  });

  test(
    'offline without cache, HTTP errors and empty lists use defaults',
    () async {
      for (final handler in <MockClientHandler>[
        (r) async => throw http.ClientException('offline', r.url),
        (r) async => http.Response('oops', 500),
        (r) async => http.Response('# nothing here\n', 200),
      ]) {
        expect(await list(handler).load(), defaultTrackers);
        expect(cache.existsSync(), isFalse);
      }
    },
  );

  test('works without a cache file', () async {
    final l = TrackerList(
      httpClient: MockClient((r) async => http.Response(listText, 200)),
    );
    expect(await l.load(), expected);
  });

  test('normalizeTrackers', () {
    expect(
      normalizeTrackers([
        'tracker:udp://tracker.opentrackr.org:1337/announce',
        'udp://tracker.opentrackr.org:1337/announce',
        'udp://no-port.example/announce',
        'dht:dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c',
        'https://tracker.example/announce#frag',
        'not a url',
        '',
      ]),
      [
        Uri.parse('udp://tracker.opentrackr.org:1337/announce'),
        Uri.parse('https://tracker.example/announce'),
      ],
    );
    expect(defaultTrackers, isNotEmpty);
  });
}
