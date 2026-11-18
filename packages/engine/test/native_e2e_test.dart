// End-to-end test of the real native engine: one session seeds a torrent,
// another downloads it by magnet over loopback while a client streams byte
// ranges through the HTTP server. Runs when KINORA_ENGINE_LIB points to a
// host build of libkinora_engine (the `engine` CI workflow does this).
@Tags(['native'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinora_engine/kinora_engine.dart';

import 'support/torrent_builder.dart';

final _lib = Platform.environment['KINORA_ENGINE_LIB'];

Future<(int, Map<String, String>, Uint8List)> _get(
  Uri uri, {
  String method = 'GET',
  String? range,
  Map<String, String> headers = const {},
}) async {
  final client = HttpClient();
  try {
    final req = await client.openUrl(method, uri);
    if (range != null) req.headers.set(HttpHeaders.rangeHeader, range);
    headers.forEach(req.headers.set);
    final res = await req.close().timeout(const Duration(seconds: 60));
    final body = BytesBuilder(copy: false);
    await res.forEach(body.add).timeout(const Duration(seconds: 60));
    final h = <String, String>{};
    res.headers.forEach((k, v) => h[k] = v.join(','));
    return (res.statusCode, h, body.takeBytes());
  } finally {
    client.close(force: true);
  }
}

Future<void> _until(
  bool Function() ok, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final end = DateTime.now().add(timeout);
  while (!ok()) {
    if (DateTime.now().isAfter(end))
      throw TimeoutException('condition not met', timeout);
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

class TimeoutException implements Exception {
  TimeoutException(this.message, this.timeout);
  final String message;
  final Duration timeout;
  @override
  String toString() => 'TimeoutException: $message after $timeout';
}

void main() {
  late Directory root;
  late Uint8List data;
  late TestTorrent torrent;
  const name = 'Kinora.Test.2026.1080p.WEB-DL.mkv';

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('kinora-e2e-');
    final rnd = Random(42);
    // Not piece-aligned on purpose: 5 MiB + 12345 bytes, 64 KiB pieces.
    data = Uint8List.fromList(
      List.generate((5 << 20) + 12345, (_) => rnd.nextInt(256)),
    );
    await Directory('${root.path}/seed').create();
    await File('${root.path}/seed/$name').writeAsBytes(data);
    torrent = TestTorrent.single(name, data);
  });

  tearDownAll(() => root.delete(recursive: true));

  /// A torrent downloaded in full, its state saved, then half its file
  /// gone (as when a watched episode was deleted), loaded again from that
  /// saved state: it believes it has every piece. Returns the session, the
  /// file, and failures it reports.
  Future<(KinoraEngine, String, File, List<EngineEvent>)> staleCopy(
    String tag,
  ) async {
    final seeder = KinoraEngine.start(
      EngineConfig(
        testMode: true,
        resumeDir: (await Directory('${root.path}/rs-seed-$tag').create()).path,
        statePath: '${root.path}/seed-$tag.state',
      ),
    );
    addTearDown(seeder.dispose);
    seeder.add(
      AddTorrent.torrentFile(
        torrent.bytes,
        savePath: '${root.path}/seed',
        seedMode: true,
      ),
    );
    await _until(() => seeder.listenPort > 0);
    final peer = '127.0.0.1:${seeder.listenPort}';
    final resumeDir = await Directory('${root.path}/rs-$tag').create();
    final dl = '${root.path}/dl-$tag';
    final file = File('$dl/$name');
    final config = EngineConfig(
      testMode: true,
      resumeDir: resumeDir.path,
      statePath: '${root.path}/$tag.state',
    );
    final first = KinoraEngine.start(config);
    final ih = first.add(
      AddTorrent.torrentFile(torrent.bytes, savePath: dl, peers: [peer]),
    );
    await _until(
      () => (first.fileProgress(ih)?.first ?? 0) == data.length,
      timeout: const Duration(seconds: 90),
    );
    first.saveResume(ih);
    final saved = File('${resumeDir.path}/$ih.fastresume');
    await _until(saved.existsSync);
    first.dispose();
    file.openSync(mode: FileMode.append)
      ..truncateSync(data.length ~/ 2)
      ..closeSync();

    final stale = KinoraEngine.start(config);
    addTearDown(stale.dispose);
    final failures = <EngineEvent>[];
    final sub = stale.events.listen((e) {
      if (e is TorrentFailed || e is TorrentFileError) failures.add(e);
    });
    addTearDown(sub.cancel);
    stale.add(
      AddTorrent.torrentFile(
        torrent.bytes,
        savePath: dl,
        resumePath: saved.path,
        peers: [peer],
      ),
    );
    // Loaded (Linux trusts the saved state and seeds; Windows notices the
    // short file itself and downloads): either way the rest must follow.
    await _until(
      () => const {
        TorrentState.seeding,
        TorrentState.downloading,
        TorrentState.finished,
      }.contains(stale.status(ih)?.state),
    );
    return (stale, ih, file, failures);
  }

  test(
    'playing a file cut short since its state was saved fetches it again',
    () async {
      final (stale, ih, file, failures) = await staleCopy('play');
      // The player reads the half that's gone.
      final stream = stale.openStream(ih, 0, bitrate: 2 << 20);
      final from = data.length - 100000;
      final (code, _, body) = await _get(
        stream.uri(),
        range: 'bytes=$from-${data.length - 1}',
      );
      expect(code, 206);
      expect(body, data.sublist(from), reason: 'the missing part came in');
      expect(failures, isEmpty, reason: 'it re-checked instead of failing');
    },
    timeout: const Timeout(Duration(minutes: 3)),
    skip: _lib == null ? 'KINORA_ENGINE_LIB not set' : false,
  );

  test(
    'sharing a file cut short since its state was saved fetches it again',
    () async {
      final (stale, ih, file, failures) = await staleCopy('share');
      // Another peer asks the stale copy for the half that's gone.
      final other = KinoraEngine.start(
        EngineConfig(
          testMode: true,
          resumeDir: (await Directory('${root.path}/rs-other').create()).path,
          statePath: '${root.path}/other.state',
        ),
      );
      addTearDown(other.dispose);
      other.add(
        AddTorrent.torrentFile(
          torrent.bytes,
          savePath: '${root.path}/dl-other',
          peers: ['127.0.0.1:${stale.listenPort}'],
        ),
      );
      // Its re-check makes it a downloader again, and a complete torrent
      // drops the seeds it knew: a seed turning up (a tracker's job out
      // there) brings the rest.
      await _until(() => stale.status(ih)?.state != TorrentState.seeding);
      final seed2 = KinoraEngine.start(
        EngineConfig(
          testMode: true,
          resumeDir: (await Directory('${root.path}/rs-seed2b').create()).path,
          statePath: '${root.path}/seed2b.state',
        ),
      );
      addTearDown(seed2.dispose);
      seed2.add(
        AddTorrent.torrentFile(
          torrent.bytes,
          savePath: '${root.path}/seed',
          seedMode: true,
          peers: ['127.0.0.1:${stale.listenPort}'],
        ),
      );
      await _until(
        () =>
            file.lengthSync() == data.length &&
            (other.fileProgress(ih)?.first ?? 0) == data.length,
        timeout: const Duration(seconds: 90),
      );
      expect(file.readAsBytesSync(), data);
      expect(failures, isEmpty, reason: 'it re-checked instead of failing');
    },
    timeout: const Timeout(Duration(minutes: 3)),
    skip: _lib == null ? 'KINORA_ENGINE_LIB not set' : false,
  );

  test(
    'playing a file deleted while its torrent is loaded fetches it again',
    () async {
      final seeder = KinoraEngine.start(
        EngineConfig(
          testMode: true,
          resumeDir: (await Directory(
            '${root.path}/rs-seed-gone',
          ).create()).path,
          statePath: '${root.path}/seed-gone.state',
        ),
      );
      addTearDown(seeder.dispose);
      seeder.add(
        AddTorrent.torrentFile(
          torrent.bytes,
          savePath: '${root.path}/seed',
          seedMode: true,
        ),
      );
      await _until(() => seeder.listenPort > 0);
      final dl = '${root.path}/dl-gone';
      final engine = KinoraEngine.start(
        EngineConfig(
          testMode: true,
          resumeDir: (await Directory('${root.path}/rs-gone').create()).path,
          statePath: '${root.path}/gone.state',
        ),
      );
      addTearDown(engine.dispose);
      final failures = <EngineEvent>[];
      final sub = engine.events.listen((e) {
        if (e is TorrentFailed || e is TorrentFileError) failures.add(e);
      });
      addTearDown(sub.cancel);
      final ih = engine.add(
        AddTorrent.torrentFile(
          torrent.bytes,
          savePath: dl,
          peers: ['127.0.0.1:${seeder.listenPort}'],
        ),
      );
      await _until(
        () => (engine.fileProgress(ih)?.first ?? 0) == data.length,
        timeout: const Duration(seconds: 90),
      );
      // Deleted while the torrent is still loaded (another episode's
      // cleanup, a cleared cache): it still believes it has every piece.
      File('$dl/$name').deleteSync();
      final stream = engine.openStream(ih, 0, bitrate: 2 << 20);
      final got = _get(stream.uri(), range: 'bytes=0-99999');
      // The re-check makes it a downloader again; a seed turning up (a
      // tracker's job out there) brings the file back.
      await _until(() => engine.status(ih)?.state == TorrentState.downloading);
      final seed2 = KinoraEngine.start(
        EngineConfig(
          testMode: true,
          resumeDir: (await Directory(
            '${root.path}/rs-seed-gone2',
          ).create()).path,
          statePath: '${root.path}/seed-gone2.state',
        ),
      );
      addTearDown(seed2.dispose);
      seed2.add(
        AddTorrent.torrentFile(
          torrent.bytes,
          savePath: '${root.path}/seed',
          seedMode: true,
          peers: ['127.0.0.1:${engine.listenPort}'],
        ),
      );
      final (code, _, body) = await got.timeout(const Duration(seconds: 90));
      expect(code, 206);
      expect(body, data.sublist(0, 100000), reason: 'the file came back');
      expect(failures, isEmpty, reason: 'it re-checked instead of failing');
    },
    timeout: const Timeout(Duration(minutes: 3)),
    // Windows won't delete a file the torrent has open.
    skip: _lib == null
        ? 'KINORA_ENGINE_LIB not set'
        : Platform.isWindows
        ? 'files in use can\'t be deleted on Windows'
        : false,
  );

  test(
    'a stream that starts mid-file buffers ahead of it, not from the start',
    () async {
      // Resuming at 16 MiB of 64 MiB: after the deadline window (24 MiB)
      // the next stretch comes before the part already watched.
      const mib = 1 << 20;
      final rnd = Random(7);
      // Never zero: a byte on disk that isn't zero has arrived.
      final big = Uint8List.fromList(
        List.generate(64 * mib, (_) => rnd.nextInt(255) + 1),
      );
      const bigName = 'Kinora.Resume.2026.1080p.WEB-DL.mkv';
      await Directory('${root.path}/seed-big').create();
      await File('${root.path}/seed-big/$bigName').writeAsBytes(big);
      final bigTorrent = TestTorrent.single(bigName, big);

      final seeder = KinoraEngine.start(
        EngineConfig(
          testMode: true,
          resumeDir: (await Directory('${root.path}/rs1').create()).path,
          statePath: '${root.path}/seed-big.state',
        ),
      );
      addTearDown(seeder.dispose);
      seeder.add(
        AddTorrent.torrentFile(
          bigTorrent.bytes,
          savePath: '${root.path}/seed-big',
          seedMode: true,
        ),
      );
      await _until(() => seeder.listenPort > 0);
      final leecher = KinoraEngine.start(
        EngineConfig(
          testMode: true,
          resumeDir: (await Directory('${root.path}/rs2').create()).path,
          statePath: '${root.path}/dl-big.state',
          // Slow enough to see the order pieces come in.
          downloadRateLimit: 4 * mib,
        ),
      );
      addTearDown(leecher.dispose);
      final dl = '${root.path}/dl-big';
      // Paused until the player below asks for 16 MiB: otherwise the first
      // requests, made before it asks, fetch the file's start whatever the
      // order is, and how much of it depends on timing.
      final ih = leecher.add(
        AddTorrent.torrentFile(
          bigTorrent.bytes,
          savePath: dl,
          peers: ['127.0.0.1:${seeder.listenPort}'],
          paused: true,
        ),
      );
      await leecher.waitForFiles(ih, timeout: const Duration(seconds: 60));
      final stream = leecher.openStream(ih, 0, bitrate: 100 << 10);

      // A player reading from 16 MiB on, slowly: it keeps the connection
      // (and so the window) open, as mpv does while it plays.
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final req = await client.getUrl(stream.uri());
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=${16 * mib}-');
      final res = await req.close();
      // (The answer's head comes just before the window is set.)
      await Future<void>.delayed(const Duration(milliseconds: 500));
      leecher.resume(ih);
      final first = Completer<void>();
      late final StreamSubscription<List<int>> reading;
      reading = res.listen((_) {
        if (!first.isCompleted) first.complete();
        reading.pause();
      });
      await first.future.timeout(const Duration(seconds: 60));

      // Until 46 MiB of the file is in: the window and part of what's next.
      await _until(
        () => (leecher.fileProgress(ih)?.first ?? 0) >= 46 * mib,
        timeout: const Duration(seconds: 90),
      );
      final file = await File('$dl/$bigName').open();
      Future<double> arrived(int from, int to) async {
        await file.setPosition(from);
        final bytes = await file.read(to - from);
        return bytes.where((b) => b != 0).length / (to - from);
      }

      final ahead = await arrived(44 * mib, 46 * mib);
      final watched = await arrived(4 * mib, 6 * mib);
      await file.close();
      await reading.cancel();
      expect(ahead, greaterThan(0.9), reason: 'what comes next is in');
      expect(watched, lessThan(0.1), reason: 'the part before waits');
    },
    timeout: const Timeout(Duration(minutes: 4)),
    skip: _lib == null ? 'KINORA_ENGINE_LIB not set' : false,
  );

  test('version', () {
    expect(KinoraEngine.version(), contains('libtorrent 2.'));
  }, skip: _lib == null ? 'KINORA_ENGINE_LIB not set' : false);

  // The app adds a pack's torrent once per episode it downloads, and reads
  // where the files live right after: an empty answer made relative paths.
  test(
    'adding a torrent it already has: its save path is known at once',
    () async {
      final engine = KinoraEngine.start(
        EngineConfig(
          testMode: true,
          resumeDir: (await Directory('${root.path}/again').create()).path,
          statePath: '${root.path}/again.state',
        ),
      );
      addTearDown(engine.dispose);
      final dir = '${root.path}/seed';
      AddTorrent add() =>
          AddTorrent.torrentFile(torrent.bytes, savePath: dir, seedMode: true);
      final ih = engine.add(add());
      expect(engine.status(ih)?.savePath, dir);
      expect(engine.add(add()), ih);
      expect(engine.status(ih)?.savePath, dir);
    },
    skip: _lib == null ? 'KINORA_ENGINE_LIB not set' : false,
  );

  test(
    'magnet → metadata → ranged HTTP streaming → resume',
    () async {
      final seeder = KinoraEngine.start(
        EngineConfig(
          testMode: true,
          resumeDir: root.path,
          statePath: '${root.path}/seed.state',
        ),
      );
      addTearDown(seeder.dispose);
      seeder.add(
        AddTorrent.torrentFile(
          torrent.bytes,
          savePath: '${root.path}/seed',
          seedMode: true,
        ),
      );
      await _until(() => seeder.listenPort > 0);
      final seedPort = seeder.listenPort;

      final resumeDir = await Directory('${root.path}/resume').create();
      final dlDir = '${root.path}/dl';
      var leecher = KinoraEngine.start(
        EngineConfig(
          testMode: true,
          resumeDir: resumeDir.path,
          statePath: '${root.path}/dl.state',
        ),
      );
      final ih = leecher.add(
        AddTorrent.magnet(
          torrent.magnet(name),
          savePath: dlDir,
          peers: ['127.0.0.1:$seedPort'],
        ),
      );
      expect(ih, torrent.infoHash);
      // Adding twice is idempotent.
      expect(
        leecher.add(AddTorrent.magnet(torrent.magnet(name), savePath: dlDir)),
        ih,
      );

      final files = await leecher.waitForFiles(
        ih,
        timeout: const Duration(seconds: 60),
      );
      expect(files, hasLength(1));
      expect(files.single.size, data.length);
      expect(files.single.isVideo, isTrue);

      // As after iOS froze the app: the sockets open again and the
      // download and stream below go on.
      leecher.reopenSockets();
      final stream = leecher.openStream(ih, 0, bitrate: 2 << 20);
      expect(stream.path, endsWith(name));
      final uri = stream.uri();

      // HEAD
      var (code, headers, body) = await _get(uri, method: 'HEAD');
      expect(code, 200);
      expect(headers['content-length'], '${data.length}');
      expect(headers['accept-ranges'], 'bytes');
      expect(headers['content-type'], 'video/x-matroska');
      expect(body, isEmpty);

      // A range in the middle, crossing piece boundaries.
      (code, headers, body) = await _get(uri, range: 'bytes=1000000-1999999');
      expect(code, 206);
      expect(headers['content-range'], 'bytes 1000000-1999999/${data.length}');
      expect(body, Uint8List.sublistView(data, 1000000, 2000000));

      // Suffix range (container index at the end).
      (code, _, body) = await _get(uri, range: 'bytes=-1000');
      expect(code, 206);
      expect(body, Uint8List.sublistView(data, data.length - 1000));

      // Whole file.
      (code, _, body) = await _get(uri);
      expect(code, 200);
      expect(sha1.convert(body), sha1.convert(data));

      // Unsatisfiable range.
      (code, headers, _) = await _get(uri, range: 'bytes=${data.length}-');
      expect(code, 416);
      expect(headers['content-range'], 'bytes */${data.length}');

      // Unknown route.
      (code, _, _) = await _get(uri.replace(path: '/s/nope/x.mkv'));
      expect(code, 404);

      // Extra headers (DLNA / Samsung captions) are sent on the route.
      leecher.setRouteHeaders(stream.token, {
        'transferMode.dlna.org': 'Streaming',
        'Bad\r\nHeader': 'x',
      });
      (code, headers, _) = await _get(uri, method: 'HEAD');
      expect(headers['transfermode.dlna.org'], 'Streaming');
      expect(headers.keys.where((k) => k.contains('bad')), isEmpty);

      await _until(() => leecher.status(ih)?.isComplete ?? false);
      expect(leecher.fileProgress(ih), [data.length]);
      final stats = leecher.streamStats(stream.token)!;
      expect(stats.haveBytes, data.length);
      expect(stats.size, data.length);

      // A local file route (subtitles for a TV).
      final sub = File('${root.path}/sub.srt')
        ..writeAsStringSync('1\n00:00:01,000 --> 00:00:02,000\nHi\n');
      final served = leecher.serveFile(sub.path);
      (code, headers, body) = await _get(served.uri());
      expect(code, 200);
      expect(headers['content-type'], 'text/srt');
      expect(String.fromCharCodes(body), contains('Hi'));

      // Keep it: move the data while the stream stays readable.
      final keepDir = '${root.path}/kept';
      final events = <EngineEvent>[];
      leecher.moveStorage(ih, keepDir);
      await _until(() {
        events.addAll(leecher.pollEvents());
        return events.whereType<StorageMoved>().isNotEmpty;
      });
      expect(File('$keepDir/$name').existsSync(), isTrue);
      (code, _, body) = await _get(uri, range: 'bytes=0-99');
      expect(code, 206);
      expect(body, Uint8List.sublistView(data, 0, 100));
      // Move back so the resume part below finds the data where it expects.
      leecher.moveStorage(ih, dlDir);
      await _until(() {
        events.addAll(leecher.pollEvents());
        return events.whereType<StorageMoved>().length >= 2;
      });

      leecher.closeStream(stream.token);
      (code, _, _) = await _get(uri, method: 'HEAD');
      expect(code, 404);

      // Resume: a new session restores the finished torrent without peers.
      leecher.saveResume(ih);
      await _until(() => File('${resumeDir.path}/$ih.fastresume').existsSync());
      leecher.dispose();
      expect(File('${root.path}/dl.state').existsSync(), isTrue);

      leecher = KinoraEngine.start(
        EngineConfig(testMode: true, resumeDir: resumeDir.path),
      );
      addTearDown(leecher.dispose);
      final again = leecher.add(
        AddTorrent.magnet(
          torrent.magnet(name),
          savePath: dlDir,
          resumePath: '${resumeDir.path}/$ih.fastresume',
        ),
      );
      expect(again, ih);
      expect(
        leecher.files(ih),
        isNotNull,
        reason: 'metadata comes from resume data',
      );
      await _until(() => leecher.status(ih)?.isComplete ?? false);

      // Remove with data.
      leecher.remove(ih, deleteFiles: true);
      await _until(() => !File('$dlDir/$name').existsSync());
      expect(leecher.status(ih), isNull);
    },
    timeout: const Timeout(Duration(minutes: 4)),
    skip: _lib == null ? 'KINORA_ENGINE_LIB not set' : false,
  );
}
