import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stremio/stremio.dart';
import 'package:test/test.dart';

import 'helpers.dart';

http.Response json(String name) =>
    http.Response.bytes(utf8.encode(fixtureText(name)), 200);

void main() {
  final fast = streamAddon('https://fast.example', id: 'fast');
  final slow = streamAddon('https://slow.example', id: 'slow');
  final dead = streamAddon('https://dead.example', id: 'dead');
  final debrid = streamAddon('https://debrid.example', id: 'debrid');
  final cinemeta = fixtureAddon(
    'cinemeta_manifest.json',
    'https://v3-cinemeta.strem.io/manifest.json',
  );
  final kitsu = fixtureAddon(
    'kitsu_manifest.json',
    'https://anime-kitsu.strem.fun/manifest.json',
  );
  final opensubs = fixtureAddon(
    'opensubtitles_manifest.json',
    'https://opensubtitles-v3.strem.io/manifest.json',
  );

  late List<Uri> requested;
  late bool deadIsUp;

  AddonAggregator aggregator({DateTime Function()? clock}) {
    final client = AddonClient(
      maxRetries: 0,
      httpClient: MockClient((r) async {
        requested.add(r.url);
        switch (r.url.host) {
          case 'fast.example':
            return json('torrent_streams_a.json');
          case 'slow.example':
            await Future<void>.delayed(const Duration(milliseconds: 40));
            return json('torrent_streams_b.json');
          case 'dead.example':
            if (deadIsUp) return json('torrent_streams_a.json');
            return Completer<http.Response>().future;
          case 'debrid.example':
            return json('debrid_key_rejected.json');
          case 'v3-cinemeta.strem.io':
            return json('cinemeta_search_series.json');
          case 'opensubtitles-v3.strem.io':
            return json('opensubtitles_series.json');
        }
        return http.Response('no route', 500);
      }),
    );
    return AddonAggregator(
      client,
      perAddonTimeout: const Duration(milliseconds: 150),
      clock: clock,
    );
  }

  setUp(() {
    requested = [];
    deadIsUp = false;
  });

  test('streams arrive per addon as they finish; merged is deduped', () async {
    final agg = aggregator();
    final q = agg.streams(
      [dead, slow, fast, cinemeta],
      'series',
      'tt0903747:1:1',
    );
    final order = <String>[];
    final results = <AddonResult<StreamItem>>[];
    await for (final r in q.results) {
      order.add(r.addon.manifest.id);
      results.add(r);
    }
    expect(order, ['fast', 'slow', 'dead']);
    expect(
      requested.map((u) => u.host),
      isNot(contains('v3-cinemeta.strem.io')),
    );
    expect(results[0].items, hasLength(3));
    expect(results[0].isSuccess, isTrue);
    expect(results[2].error, isA<AddonTimeoutException>());
    expect(results[2].items, isEmpty);

    final merged = await q.merged;
    // a: 3 streams, b: 2 streams of which one duplicates a's 1080p hash.
    expect(merged, hasLength(4));
    expect(merged.first.name, 'TorrentIndex 1080p', reason: 'addon order');
    expect(
      merged.first.trackers,
      containsAll([
        'udp://tracker.opentrackr.org:1337/announce',
        'http://tracker.renfei.net:8080/announce',
        'udp://open.stealth.si:80/announce',
      ]),
    );
  });

  test('health tracks latency, failures and recovery', () async {
    final t0 = DateTime.utc(2026, 11, 9, 12);
    final agg = aggregator(clock: () => t0);
    await agg.streams([fast, dead], 'movie', 'tt1254207').merged;
    await agg.streams([fast, dead], 'movie', 'tt1254207').merged;
    var h = agg.health;
    expect(h[fast.transportUrl]!.isHealthy, isTrue);
    expect(h[fast.transportUrl]!.lastLatency, isNotNull);
    expect(h[fast.transportUrl]!.lastCheckedAt, t0);
    expect(h[dead.transportUrl]!.consecutiveFailures, 2);
    expect(h[dead.transportUrl]!.lastError, isA<AddonTimeoutException>());
    expect(
      h[dead.transportUrl]!.lastLatency,
      greaterThanOrEqualTo(const Duration(milliseconds: 150)),
    );

    deadIsUp = true;
    await agg.streams([dead], 'movie', 'tt1254207').merged;
    h = agg.health;
    expect(h[dead.transportUrl]!.consecutiveFailures, 0);
    expect(h[dead.transportUrl]!.isHealthy, isTrue);
  });

  test('a rejected debrid key is a typed per-addon error', () async {
    final agg = aggregator();
    final q = agg.streams([fast, debrid], 'movie', 'tt1254207');
    final results = await q.results.toList();
    final bad = results.singleWhere((r) => r.addon == debrid);
    expect(bad.error, isA<DebridKeyRejectedException>());
    expect(await q.merged, hasLength(3));
    expect(agg.health[debrid.transportUrl]!.consecutiveFailures, 1);
  });

  test('outer cancel stops everything without hurting health', () async {
    final agg = aggregator();
    final cancel = Completer<void>();
    final q = agg.streams([dead], 'movie', 'tt1', cancel: cancel.future);
    Timer(const Duration(milliseconds: 10), cancel.complete);
    final results = await q.results.toList();
    expect(results.single.error, isA<AddonCancelledException>());
    expect(await q.merged, isEmpty);
    expect(agg.health, isEmpty);
  });

  test('no supporting addon completes immediately', () async {
    final agg = aggregator();
    final q = agg.streams([cinemeta], 'movie', 'tt1');
    expect(await q.results.toList(), isEmpty);
    expect(await q.merged, isEmpty);
    expect(requested, isEmpty);
  });

  test('subtitles only ask addons whose prefixes match', () async {
    final agg = aggregator();
    final q = agg.subtitles(
      [opensubs, kitsu],
      'series',
      'tt0903747:1:1',
      videoHash: 'abc',
    );
    final merged = await q.merged;
    expect(requested.single.host, 'opensubtitles-v3.strem.io');
    expect(requested.single.path, contains('videoHash=abc'));
    expect(merged, hasLength(5));
  });

  test('search uses catalogs that declare the search extra', () async {
    final agg = aggregator();
    final merged = await agg
        .search([cinemeta, kitsu, fast], 'series', 'breaking bad')
        .merged;
    expect(requested.map((u) => u.toString()), [
      'https://v3-cinemeta.strem.io/catalog/series/top/search=breaking%20bad.json',
    ]);
    expect(merged.first.name, 'Breaking Bad');
  });
}
