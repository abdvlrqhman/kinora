import 'package:swarm/swarm.dart';
import 'package:test/test.dart';

// webtorrent.io's public Big Buck Bunny magnet.
const bigBuckBunny =
    'magnet:?xt=urn:btih:dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c'
    '&dn=Big+Buck+Bunny'
    '&tr=udp%3A%2F%2Fexplodie.org%3A6969'
    '&tr=udp%3A%2F%2Ftracker.coppersurfer.tk%3A6969'
    '&tr=udp%3A%2F%2Ftracker.empire-js.us%3A1337'
    '&tr=udp%3A%2F%2Ftracker.leechers-paradise.org%3A6969'
    '&tr=udp%3A%2F%2Ftracker.opentrackr.org%3A1337'
    '&tr=wss%3A%2F%2Ftracker.btorrent.xyz'
    '&tr=wss%3A%2F%2Ftracker.fastcast.nz'
    '&tr=wss%3A%2F%2Ftracker.openwebtorrent.com'
    '&ws=https%3A%2F%2Fwebtorrent.io%2Ftorrents%2F'
    '&xs=https%3A%2F%2Fwebtorrent.io%2Ftorrents%2Fbig-buck-bunny.torrent';

// libtorrent's official v1+v2 hybrid test torrent.
const hybrid =
    'magnet:?xt=urn:btih:631a31dd0a46257d5078c0dee4e66e26f73e42ac'
    '&xt=urn:btmh:1220d8dd32ac93357c368556af3ac1d95c9d76bd0dff6fa9833ecdac3d53134efabb'
    '&dn=bittorrent-v1-v2-hybrid-test';

void main() {
  group('Magnet.parse', () {
    test('real-world magnet with many trackers and a web seed', () {
      final m = Magnet.parse(bigBuckBunny);
      expect(m.infoHash, 'dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c');
      expect(m.name, 'Big Buck Bunny');
      expect(m.trackers, hasLength(8));
      expect(m.trackers.first, 'udp://explodie.org:6969');
      expect(m.trackers.last, 'wss://tracker.openwebtorrent.com');
      expect(m.webSeeds, ['https://webtorrent.io/torrents/']);
      expect(m.infoHashV2, isNull);
    });

    test('base32 hash becomes lowercase hex', () {
      final m = Magnet.parse(
        'magnet:?xt=urn:btih:3WBFL3G4PSSV7MF37AJSHWDQMLNR63I4&dn=Big+Buck+Bunny',
      );
      expect(m.infoHash, 'dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c');
      expect(
        Magnet.parse('magnet:?xt=urn:btih:bcw2lj5gda5k4hqj3ay56z2i2vtaswqq')
            .infoHash,
        '08ada5a7a6183aae1e09d831df6748d566095a10',
      );
    });

    test('uppercase hex, uppercase scheme and URN', () {
      final m = Magnet.parse(
        'MAGNET:?XT=URN:BTIH:DD8255ECDC7CA55FB0BBF81323D87062DB1F6D1C',
      );
      expect(m.infoHash, 'dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c');
    });

    test('v1+v2 hybrid keeps the btmh multihash', () {
      final m = Magnet.parse(hybrid);
      expect(m.infoHash, '631a31dd0a46257d5078c0dee4e66e26f73e42ac');
      expect(
        m.infoHashV2,
        '1220d8dd32ac93357c368556af3ac1d95c9d76bd0dff6fa9833ecdac3d53134efabb',
      );
      final v2only = Magnet.parse(
        'magnet:?xt=urn:btmh:1220d8dd32ac93357c368556af3ac1d95c9d76bd0dff6fa9833ecdac3d53134efabb',
      );
      expect(v2only.infoHash, isNull);
      expect(v2only.infoHashV2, startsWith('1220'));
    });

    test('unicode names (encoded and raw), xl, x.pe, indexed keys', () {
      final m = Magnet.parse(
        'magnet:?xt=urn:btih:dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c'
        '&dn=%E9%80%B2%E6%92%83%E3%81%AE%E5%B7%A8%E4%BA%BA%20S01E01%20%5B1080p%5D'
        '&xl=1299227607'
        '&tr.1=udp%3A%2F%2Ftracker.opentrackr.org%3A1337%2Fannounce'
        '&tr.2=udp%3A%2F%2Ftracker.opentrackr.org%3A1337%2Fannounce'
        '&tr.3=http%3A%2F%2Ftracker.renfei.net%3A8080%2Fannounce'
        '&x.pe=10.0.0.5:51413&x.pe=[2001:db8::1]:6881',
      );
      expect(m.name, '進撃の巨人 S01E01 [1080p]');
      expect(m.exactLength, 1299227607);
      expect(m.trackers, [
        'udp://tracker.opentrackr.org:1337/announce',
        'http://tracker.renfei.net:8080/announce',
      ], reason: 'duplicates dropped');
      expect(m.peers, ['10.0.0.5:51413', '[2001:db8::1]:6881']);

      final raw = Magnet.parse(
        'magnet:?xt=urn:btih:dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c&dn=الحلقة 1',
      );
      expect(raw.name, 'الحلقة 1');
    });

    test('tolerates junk params, stray % and empty pairs', () {
      final m = Magnet.parse(
        'magnet:?&&xt=urn:btih:dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c'
        '&dn=100%25+legit+%ZZ&foo&=bar&xl=abc&xt=urn:ed2k:31d6cfe0d16ae931b73c59d7e0c089c0',
      );
      expect(m.infoHash, 'dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c');
      expect(m.name, '100%25+legit+%ZZ', reason: 'undecodable kept raw');
      expect(m.exactLength, isNull);
    });

    test('bad input throws MagnetFormatException', () {
      for (final input in [
        '',
        'https://example.com',
        'magnet:?dn=no+hash',
        'magnet:?xt=urn:btih:xyz',
        'magnet:?xt=urn:btih:dd8255ecdc7ca55fb0bbf81323d87062db1f6d1',
        'magnet:?xt=urn:btmh:1220abc',
        'magnet:?xt=urn:sha1:YNCKHTQCWBTRNJIV4WNAE52SJUQCZO5C',
      ]) {
        expect(
          () => Magnet.parse(input),
          throwsA(isA<MagnetFormatException>()),
          reason: input,
        );
        expect(Magnet.tryParse(input), isNull);
      }
    });
  });

  group('building', () {
    test('from info hash, trackers and name; round-trips', () {
      final m = Magnet(
        infoHash: 'DD8255ECDC7CA55FB0BBF81323D87062DB1F6D1C',
        name: 'Big Buck Bunny (2008) & friends',
        trackers: [
          'udp://tracker.opentrackr.org:1337/announce',
          '',
          'udp://tracker.opentrackr.org:1337/announce',
          'http://tracker.renfei.net:8080/announce?passkey=a b',
        ],
      );
      final text = m.toString();
      expect(
        text,
        'magnet:?xt=urn:btih:dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c'
        '&dn=Big%20Buck%20Bunny%20(2008)%20%26%20friends'
        '&tr=udp%3A%2F%2Ftracker.opentrackr.org%3A1337%2Fannounce'
        '&tr=http%3A%2F%2Ftracker.renfei.net%3A8080%2Fannounce%3Fpasskey%3Da%20b',
      );
      expect(Magnet.parse(text), m);
      expect(Magnet.parse(text).hashCode, m.hashCode);
      expect(m.toUri().scheme, 'magnet');
      expect(Magnet.parse(m.toUri().toString()), m);
    });

    test('round-trips real magnets', () {
      for (final input in [bigBuckBunny, hybrid]) {
        final m = Magnet.parse(input);
        expect(Magnet.parse(m.toString()), m);
      }
    });

    test('requires a valid hash', () {
      expect(() => Magnet(name: 'x'), throwsA(isA<MagnetFormatException>()));
      expect(
        () => Magnet(infoHash: 'nope'),
        throwsA(isA<MagnetFormatException>()),
      );
    });
  });

  test('normalizeInfoHash', () {
    expect(
      normalizeInfoHash(' DD8255ECDC7CA55FB0BBF81323D87062DB1F6D1C '),
      'dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c',
    );
    expect(
      normalizeInfoHash('3WBFL3G4PSSV7MF37AJSHWDQMLNR63I4'),
      'dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c',
    );
    expect(normalizeInfoHash('3WBFL3G4PSSV7MF37AJSHWDQMLNR63I1'), isNull);
    expect(normalizeInfoHash(''), isNull);
  });
}
