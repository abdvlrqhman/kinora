// A session configured like the app (no test mode: listening on 0.0.0.0
// and [::]) must find a seeder through a tracker quickly, with that tracker
// first among many unreachable ones. Runs with KINORA_ENGINE_LIB set.
@Tags(['native'])
library;

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kinora_engine/kinora_engine.dart';

import 'support/torrent_builder.dart';

final _lib = Platform.environment['KINORA_ENGINE_LIB'];

void main() {
  test(
    'finds the seeder through the stream\'s tracker within seconds',
    () async {
      final root = await Directory.systemTemp.createTemp('kinora-trk-');
      addTearDown(() => root.delete(recursive: true));
      const name = 'Kinora.Tracker.S01E01.mkv';
      final rnd = Random(7);
      final data = Uint8List.fromList(
        List.generate(300000, (_) => rnd.nextInt(256)),
      );
      await Directory('${root.path}/seed').create();
      await File('${root.path}/seed/$name').writeAsBytes(data);
      final torrent = TestTorrent.single(name, data);

      final seeder = KinoraEngine.start(
        EngineConfig(testMode: true, resumeDir: root.path),
      );
      addTearDown(seeder.dispose);
      seeder.add(
        AddTorrent.torrentFile(
          torrent.bytes,
          savePath: '${root.path}/seed',
          seedMode: true,
        ),
      );
      while (seeder.listenPort == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      final seedPort = seeder.listenPort;

      final tracker = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => tracker.close(force: true));
      tracker.listen((req) async {
        req.response.add(
          bencode({
            'interval': 30,
            'peers': Uint8List.fromList([
              127, 0, 0, 1, seedPort >> 8, seedPort & 0xff, //
            ]),
          }),
        );
        await req.response.close();
      });

      final leecher = KinoraEngine.start(
        EngineConfig(
          resumeDir: (await Directory('${root.path}/r').create()).path,
          dht: false,
          lsd: false,
          upnp: false,
          natpmp: false,
        ),
      );
      addTearDown(leecher.dispose);
      final watch = Stopwatch()..start();
      final ih = leecher.add(
        AddTorrent.magnet(
          torrent.magnet(name),
          savePath: '${root.path}/dl',
          trackers: [
            'http://127.0.0.1:${tracker.port}/announce',
            // Public trackers the app appends; unreachable here.
            for (var i = 1; i <= 20; i++) 'udp://192.0.2.$i:6969/announce',
          ],
        ),
      );
      while (!(leecher.status(ih)?.isComplete ?? false)) {
        if (watch.elapsed > const Duration(seconds: 90)) {
          fail('not finished after 90 s: ${leecher.status(ih)}');
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      // ignore: avoid_print
      print('finished in ${watch.elapsedMilliseconds} ms');
      expect(watch.elapsed, lessThan(const Duration(seconds: 10)));
    },
    skip: _lib == null ? 'KINORA_ENGINE_LIB not set' : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
