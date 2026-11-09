import 'dart:async';
import 'dart:io';

import 'package:dlna/dlna.dart';
import 'package:dlna/src/discovery.dart' show subnetHosts;
import 'package:test/test.dart';

import 'support/fake_samsung_dmr.dart';

void main() {
  late FakeSamsungDmr tv;

  setUp(() async => tv = await FakeSamsungDmr.start());
  tearDown(() => tv.close());

  group('SSDP discover', () {
    late FakeSsdpResponder ssdp;
    setUp(() async => ssdp = await FakeSsdpResponder.start(tv.location));
    tearDown(() => ssdp.close());

    test('finds the TV once, filters non-renderers, sends 3 rounds', () async {
      final discovery = DlnaDiscovery(
        ssdpAddress: InternetAddress.loopbackIPv4,
        ssdpPort: ssdp.port,
        listenForNotify: false,
      );
      final devices = await discovery
          .discover(timeout: const Duration(milliseconds: 1800))
          .toList();
      discovery.close();

      expect(devices, hasLength(1));
      expect(devices.single.udn, samsungUdn);
      expect(devices.single.friendlyName, '[TV] Samsung 5 Series (43)');
      expect(tv.descriptionHits, 1, reason: 'deduped by location');
      expect(ssdp.searches, hasLength(6));
      final first = ssdp.searches.first;
      expect(first, startsWith('M-SEARCH * HTTP/1.1\r\n'));
      expect(first, contains('HOST: 127.0.0.1:${ssdp.port}\r\n'));
      expect(first, contains('MAN: "ssdp:discover"\r\n'));
      expect(first, contains('MX: 2\r\n'));
      expect(
        first,
        contains('ST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n'),
      );
      expect(first, endsWith('\r\n\r\n'));
      expect(ssdp.searches[1], contains('ST: ssdp:all\r\n'));
    });

    test('cancelling stops the search early', () async {
      final discovery = DlnaDiscovery(
        ssdpAddress: InternetAddress.loopbackIPv4,
        ssdpPort: ssdp.port,
        listenForNotify: false,
      );
      final sub = discovery
          .discover(timeout: const Duration(seconds: 5))
          .listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await sub.cancel();
      final sent = ssdp.searches.length;
      await Future<void>.delayed(const Duration(milliseconds: 900));
      expect(ssdp.searches.length, sent, reason: 'no more M-SEARCH rounds');
      discovery.close();
    });
  });

  group('NOTIFY', () {
    late int port;
    late RawDatagramSocket sender;

    setUp(() async {
      final probe = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      port = probe.port;
      probe.close();
      sender = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    });
    tearDown(() => sender.close());

    DlnaDiscovery notifyDiscovery() => DlnaDiscovery(
      ssdpAddress: InternetAddress.loopbackIPv4,
      ssdpPort: port,
    );

    test('ssdp:alive announcements are discovered', () async {
      final discovery = notifyDiscovery();
      final found = discovery
          .discover(timeout: const Duration(seconds: 3))
          .first;
      final timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
        sender.send(
          samsungNotify(tv.location),
          InternetAddress.loopbackIPv4,
          port,
        );
      });
      final device = await found;
      timer.cancel();
      discovery.close();
      expect(device.udn, samsungUdn);
    });

    test('ssdp:byebye suppresses a device still being described', () async {
      final discovery = notifyDiscovery();
      final devices = discovery
          .discover(timeout: const Duration(milliseconds: 800))
          .toList();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      tv.delay = const Duration(milliseconds: 100);
      sender
        ..send(samsungNotify(tv.location), InternetAddress.loopbackIPv4, port)
        ..send(
          samsungNotify(tv.location, nts: 'ssdp:byebye'),
          InternetAddress.loopbackIPv4,
          port,
        );
      expect(await devices, isEmpty);
      expect(tv.descriptionHits, 1);
      discovery.close();
    });
  });

  group('probeSubnet', () {
    test('finds the TV in a /24 via its description URL', () async {
      final discovery = DlnaDiscovery();
      final stopwatch = Stopwatch()..start();
      final devices = await discovery
          .probeSubnet(
            InternetAddress('127.0.0.2'),
            targets: [
              const ProbeTarget(1, ['/dmr']), // closed port on every host
              ProbeTarget(tv.port, ['/missing', '/dmr']),
            ],
          )
          .toList();
      discovery.close();
      expect(devices.map((d) => d.udn), [samsungUdn]);
      expect(devices.single.location, tv.location);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
    });

    test('rejects bad arguments', () {
      final discovery = DlnaDiscovery();
      expect(
        () => discovery.probeSubnet(InternetAddress.loopbackIPv6),
        throwsArgumentError,
      );
      expect(
        () => discovery.probeSubnet(InternetAddress('10.0.0.1'), prefix: 8),
        throwsRangeError,
      );
      discovery.close();
    });

    test('subnetHosts', () {
      final hosts = subnetHosts(InternetAddress('192.168.1.37'), 24);
      expect(hosts, hasLength(253));
      expect(hosts.first.address, '192.168.1.1');
      expect(hosts.last.address, '192.168.1.254');
      expect(hosts.map((h) => h.address), isNot(contains('192.168.1.37')));
      expect(
        subnetHosts(InternetAddress('10.1.2.5'), 30).map((h) => h.address),
        ['10.1.2.6'],
      );
    });

    test('default targets start with Samsung Tizen :9197/dmr', () {
      expect(ProbeTarget.defaults.first, ProbeTarget.samsungTizen);
      expect(ProbeTarget.samsungLegacy.paths, contains('/smp_14_'));
    });
  });

  group('describe / refresh', () {
    test('refresh re-fetches a remembered device', () async {
      final discovery = DlnaDiscovery();
      final known = await discovery.describe(tv.location);
      final restored = DlnaDevice.fromJson(known.toJson());
      expect(await discovery.refresh(restored), known);
      discovery.close();
    });

    test('refresh detects another device at the old location', () async {
      final discovery = DlnaDiscovery();
      final known = await discovery.describe(tv.location);
      final other = DlnaDevice.fromJson({
        ...known.toJson(),
        'udn': 'uuid:other',
      });
      await expectLater(
        discovery.refresh(other),
        throwsA(isA<DlnaProtocolException>()),
      );
      discovery.close();
    });

    test('errors are typed', () async {
      final discovery = DlnaDiscovery();
      await expectLater(
        discovery.describe(tv.location.replace(path: '/nope')),
        throwsA(
          isA<DlnaHttpException>().having((e) => e.statusCode, 'status', 404),
        ),
      );
      final location = tv.location;
      await tv.close();
      await expectLater(
        discovery.describe(location),
        throwsA(isA<DlnaUnreachableException>()),
      );
      discovery.close();
    });
  });
}
