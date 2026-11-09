import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:swarm/swarm.dart';
import 'package:test/test.dart';

import 'fake_trackers.dart';

const a = 'dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c';
const b = '08ada5a7a6183aae1e09d831df6748d566095a10';
const unknown = '0123456789abcdef0123456789abcdef01234567';

String hashN(int i) => i.toRadixString(16).padLeft(40, '0');

void main() {
  late List<FakeUdpTracker> udp;
  late List<FakeHttpTracker> httpTrackers;

  Future<FakeUdpTracker> startUdp(
    Map<String, (int, int, int)> stats, {
    InternetAddress? host,
  }) async {
    final t = await FakeUdpTracker.start(stats, host: host);
    udp.add(t);
    return t;
  }

  Future<FakeHttpTracker> startHttp(Map<String, (int, int, int)> stats) async {
    final t = await FakeHttpTracker.start(stats);
    httpTrackers.add(t);
    return t;
  }

  TrackerScraper scraper({DateTime Function()? clock}) => TrackerScraper(
    udpRetransmitAfter: const Duration(milliseconds: 150),
    clock: clock,
    random: Random(7),
  );

  setUp(() {
    udp = [];
    httpTrackers = [];
  });

  tearDown(() async {
    for (final t in udp) {
      t.close();
    }
    for (final t in httpTrackers) {
      await t.close();
    }
  });

  group('UDP (BEP 15)', () {
    test('connect + scrape returns seeders/leechers/completed', () async {
      final t = await startUdp({a: (120, 900, 30), b: (5, 10, 2)});
      final s = scraper();
      final r = await s.scrape(
        [a, b.toUpperCase(), unknown],
        trackers: [t.url],
      );
      expect(
        r[a],
        const SwarmStats(
          seeders: 120,
          leechers: 30,
          completed: 900,
          sources: 1,
        ),
      );
      expect(r[b]!.seeders, 5);
      expect(
        r[unknown],
        const SwarmStats(seeders: 0, leechers: 0, completed: 0, sources: 1),
        reason: 'tracker answered with zeros',
      );
      expect(t.connects, 1);
      s.close();
    });

    test('more than 74 hashes are split into packets', () async {
      final hashes = [for (var i = 1; i <= 150; i++) hashN(i)];
      final t = await startUdp({for (final h in hashes) h: (1, 1, 1)});
      final r = await scraper().scrape(hashes, trackers: [t.url]);
      expect(r, hasLength(150));
      expect(t.scrapeBatchSizes..sort(), [2, 74, 74]);
      expect(t.connects, 1, reason: 'one connection id for all batches');
    });

    test('connection id is reused for one minute', () async {
      var now = DateTime.utc(2026, 11, 9);
      final t = await startUdp({a: (1, 1, 1)});
      final s = scraper(clock: () => now);
      await s.scrape([a], trackers: [t.url]);
      now = now.add(const Duration(seconds: 59));
      expect((await s.scrape([a], trackers: [t.url]))[a]!.seeders, 1);
      expect(t.connects, 1);
      now = now.add(const Duration(seconds: 2));
      await s.scrape([a], trackers: [t.url]);
      expect(t.connects, 2);
    });

    test('a lost packet is retransmitted once', () async {
      final t = await startUdp({a: (7, 7, 7)})
        ..dropFirst = 1;
      final r = await scraper().scrape([a], trackers: [t.url]);
      expect(r[a]!.seeders, 7);
    });

    test('two lost packets give up on that request', () async {
      final t = await startUdp({a: (7, 7, 7)})
        ..dropFirst = 2;
      final watch = Stopwatch()..start();
      final r = await scraper().scrape([a], trackers: [t.url]);
      expect(r, isEmpty);
      expect(watch.elapsed, lessThan(const Duration(milliseconds: 2000)));
    });

    test('junk packets are ignored', () async {
      final t = await startUdp({a: (3, 4, 5)})
        ..garbageFirst = true;
      final r = await scraper().scrape([a], trackers: [t.url]);
      expect(
        r[a],
        const SwarmStats(seeders: 3, leechers: 5, completed: 4, sources: 1),
      );
    });

    test('wrong action or error replies yield nothing, no crash', () async {
      final wrong = await startUdp({a: (1, 1, 1)})
        ..wrongActionOnScrape = true;
      final error = await startUdp({a: (1, 1, 1)})
        ..errorOnScrape = true;
      final s = scraper();
      expect(await s.scrape([a], trackers: [wrong.url, error.url]), isEmpty);
      // The error reply dropped the cached connection id.
      error.errorOnScrape = false;
      expect((await s.scrape([a], trackers: [error.url]))[a]!.sources, 1);
      expect(error.connects, 2);
    });

    test('truncated replies give the rows that are present', () async {
      final t = await startUdp({a: (9, 9, 9), b: (8, 8, 8)})
        ..truncateTo = 1;
      final r = await scraper().scrape([a, b], trackers: [t.url]);
      expect(r.keys, [a]);
    });

    test('IPv6 loopback', () async {
      final InternetAddress v6;
      try {
        (await RawDatagramSocket.bind(InternetAddress.loopbackIPv6, 0)).close();
        v6 = InternetAddress.loopbackIPv6;
      } on SocketException {
        markTestSkipped('no IPv6 loopback');
        return;
      }
      final t = await startUdp({a: (42, 1, 1)}, host: v6);
      expect(t.url.host, '::1');
      final r = await scraper().scrape([a], trackers: [t.url]);
      expect(r[a]!.seeders, 42);
    });
  });

  group('HTTP trackers', () {
    test('/announce is turned into /scrape with bencoded files', () async {
      final t = await startHttp({a: (50, 500, 6), b: (2, 3, 4)});
      final r = await scraper().scrape(
        [a, b, unknown],
        trackers: [t.announce()],
      );
      expect(
        r[a],
        const SwarmStats(seeders: 50, leechers: 6, completed: 500, sources: 1),
      );
      expect(r[b]!.leechers, 4);
      expect(r.containsKey(unknown), isFalse, reason: 'not in files dict');
      expect(t.requests.single.path, '/scrape');
      expect('info_hash='.allMatches(t.requests.single.query), hasLength(3));
    });

    test('announce.php and passkey paths; non-announce URLs skipped', () async {
      final t = await startHttp({a: (1, 1, 1)});
      final r = await scraper().scrape(
        [a],
        trackers: [t.announce('/abc123/announce.php'), t.announce('/tracker')],
      );
      expect(r[a]!.sources, 1);
      expect(t.requests.single.path, '/abc123/scrape.php');
    });
  });

  group('merging and deadlines', () {
    test('max per field over UDP + HTTP trackers, sources counted', () async {
      final u1 = await startUdp({a: (100, 10, 50)});
      final u2 = await startUdp({a: (80, 900, 70), b: (1, 1, 1)});
      final h = await startHttp({a: (90, 20, 5)});
      final r = await scraper().scrape(
        [a, b],
        trackers: [
          u1.url,
          u2.url,
          h.announce(),
          Uri.parse('wss://tracker.example/announce'),
        ],
      );
      expect(
        r[a],
        const SwarmStats(
          seeders: 100,
          leechers: 70,
          completed: 900,
          sources: 3,
        ),
      );
      expect(
        r[b]!.sources,
        2,
        reason: 'UDP zero rows count as answers; HTTP omits unknown hashes',
      );
    });

    test(
      'slow trackers do not block: partial results at the deadline',
      () async {
        final fast = await startUdp({a: (10, 1, 1)});
        final silent = await startUdp({a: (999, 1, 1)})
          ..silent = true;
        final slow = await startUdp({a: (500, 1, 1)})
          ..delay = const Duration(seconds: 2);
        final watch = Stopwatch()..start();
        final r = await scraper().scrape(
          [a],
          trackers: [silent.url, slow.url, fast.url],
          timeout: const Duration(milliseconds: 400),
        );
        expect(watch.elapsed, lessThan(const Duration(milliseconds: 1500)));
        expect(
          r[a],
          const SwarmStats(seeders: 10, leechers: 1, completed: 1, sources: 1),
        );
      },
    );

    test('cancel returns what arrived so far', () async {
      final silent = await startUdp({a: (1, 1, 1)})
        ..silent = true;
      final cancel = Completer<void>();
      Timer(const Duration(milliseconds: 50), cancel.complete);
      final watch = Stopwatch()..start();
      final r = await scraper().scrape(
        [a],
        trackers: [silent.url],
        timeout: const Duration(seconds: 10),
        cancel: cancel.future,
      );
      expect(r, isEmpty);
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('invalid hashes and empty input', () async {
      final t = await startUdp({a: (1, 1, 1)});
      expect(await scraper().scrape(['nope', ''], trackers: [t.url]), isEmpty);
      expect(await scraper().scrape([a], trackers: []), isEmpty);
      expect(t.connects, 0);
      // base32 input is normalized to hex keys.
      final r = await scraper().scrape(
        ['3WBFL3G4PSSV7MF37AJSHWDQMLNR63I4'],
        trackers: [t.url],
      );
      expect(r.keys, [a]);
    });

    test('a closed port yields nothing within the deadline', () async {
      final watch = Stopwatch()..start();
      final r = await scraper().scrape(
        [a],
        trackers: [Uri.parse('udp://127.0.0.1:9/announce')],
        timeout: const Duration(milliseconds: 500),
      );
      expect(r, isEmpty);
      expect(watch.elapsed, lessThan(const Duration(milliseconds: 1500)));
    });
  });
}
