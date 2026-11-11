import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:kinora_engine/kinora_engine.dart';

import 'fixtures.dart';

/// Everything a real viewer's world has, faked inside the app process:
/// a Stremio source, a BitTorrent tracker and a peer seeding the episode.
final class FakeWorld {
  FakeWorld._(
    this.root,
    this.seeder,
    this._addon,
    this._tracker,
    this.infoHash,
    this.infoHash3,
    this.packHash,
    this.videoBytes,
  );

  static const imdb = 'tt9999999';
  static const show = 'Kinora E2E Show';
  static const fileName = 'Kinora.E2E.S01E01.1080p.WEB-DL.AAC2.0.H.264-KNR.mkv';

  final Directory root;
  final KinoraEngine seeder;
  final HttpServer _addon;
  final HttpServer _tracker;
  final String infoHash;

  /// Episode 3 has a torrent of its own (the explicit-download test).
  final String infoHash3;

  /// A season pack: episodes 4–6 as three files of one torrent.
  final String packHash;
  static const packName = 'Kinora.E2E.S01E04-E06.1080p.WEB-DL-KNR';
  static const packEpisodes = [4, 5, 6];
  final Uint8List videoBytes;

  static String fileFor(int episode) =>
      fileName.replaceFirst('E01', 'E0$episode');

  String get manifestUrl => 'http://127.0.0.1:${_addon.port}/manifest.json';

  static Future<FakeWorld> start() async {
    final root = await Directory.systemTemp.createTemp('kinora-e2e-');
    final video = base64Decode(e2eVideoBase64);
    final seedDir = await Directory('${root.path}/seed').create();
    await File('${seedDir.path}/$fileName').writeAsBytes(video);

    await File('${seedDir.path}/${fileFor(3)}').writeAsBytes(video);
    final torrent = _torrent(fileName, video);
    final torrent3 = _torrent(fileFor(3), video);
    final packDir = await Directory('${seedDir.path}/$packName').create();
    for (final e in packEpisodes) {
      await File('${packDir.path}/${fileFor(e)}').writeAsBytes(video);
    }
    final pack = _pack(packName, [
      for (final e in packEpisodes) (fileFor(e), video),
    ]);
    final seeder = KinoraEngine.start(
      EngineConfig(
        testMode: true,
        resumeDir: (await Directory('${root.path}/seed-resume').create()).path,
      ),
    );
    for (final t in [torrent, torrent3, pack]) {
      seeder.add(
        AddTorrent.torrentFile(t.bytes, savePath: seedDir.path, seedMode: true),
      );
    }
    for (var i = 0; i < 100 && seeder.listenPort == 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    final seedPort = seeder.listenPort;

    final tracker = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    tracker.listen((req) async {
      // BEP 23 compact peers: our seeder on loopback.
      final peers = Uint8List.fromList([
        127,
        0,
        0,
        1,
        seedPort >> 8,
        seedPort & 0xff,
      ]);
      final body = bencode({'interval': 30, 'peers': peers});
      req.response.headers.contentType = ContentType('text', 'plain');
      req.response.add(body);
      await req.response.close();
    });

    final addon = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final world = FakeWorld._(
      root,
      seeder,
      addon,
      tracker,
      torrent.infoHash,
      torrent3.infoHash,
      pack.infoHash,
      video,
    );
    addon.listen(world._serve);
    return world;
  }

  Future<void> _serve(HttpRequest req) async {
    final path = Uri.decodeComponent(req.uri.path);
    final base = 'http://127.0.0.1:${_addon.port}';
    Object? json;
    String? text;
    if (path == '/manifest.json') {
      json = {
        'id': 'org.kinora.e2e',
        'version': '1.0.0',
        'name': 'E2E source',
        'resources': ['catalog', 'meta', 'stream', 'subtitles'],
        'types': ['series'],
        'idPrefixes': ['tt'],
        'catalogs': [
          {'type': 'series', 'id': 'e2e', 'name': 'Test'},
        ],
      };
    } else if (path.startsWith('/catalog/series/e2e')) {
      json = {
        'metas': [
          {'id': imdb, 'type': 'series', 'name': show, 'releaseInfo': '2026'},
        ],
      };
    } else if (path == '/meta/series/$imdb.json') {
      json = {
        'meta': {
          'id': imdb,
          'type': 'series',
          'name': show,
          'description': 'A show that exists only inside the end-to-end test.',
          'runtime': '1 min',
          'videos': [
            {'id': '$imdb:1:1', 'season': 1, 'episode': 1, 'title': 'Pilot'},
            {'id': '$imdb:1:2', 'season': 1, 'episode': 2, 'title': 'Second'},
            {'id': '$imdb:1:3', 'season': 1, 'episode': 3, 'title': 'Third'},
            for (final e in packEpisodes)
              {
                'id': '$imdb:1:$e',
                'season': 1,
                'episode': e,
                'title': 'Pack $e',
              },
          ],
        },
      };
    } else if (path.startsWith('/stream/series/$imdb:1:')) {
      final ep = int.parse(RegExp(r':1:(\d+)').firstMatch(path)!.group(1)!);
      json = {
        'streams': [
          {
            'name': 'E2E\n1080p',
            'title': '${fileFor(ep)}\n👤 5 💾 80 KB ⚙️ E2E',
            'infoHash': packEpisodes.contains(ep)
                ? packHash
                : ep == 3
                ? infoHash3
                : infoHash,
            'fileIdx': packEpisodes.contains(ep) ? ep - packEpisodes.first : 0,
            'behaviorHints': {'filename': fileFor(ep)},
            'sources': ['tracker:http://127.0.0.1:${_tracker.port}/announce'],
          },
        ],
      };
    } else if (path.startsWith('/subtitles/series/$imdb')) {
      json = {
        'subtitles': [
          {'id': 'e2e-en', 'url': '$base/sub.srt', 'lang': 'eng'},
        ],
      };
    } else if (path == '/sub.srt') {
      text = e2eSubtitleSrt;
    }
    if (json == null && text == null) {
      req.response.statusCode = HttpStatus.notFound;
    } else {
      req.response.headers.contentType = json != null
          ? ContentType.json
          : ContentType('text', 'plain', charset: 'utf-8');
      req.response.add(utf8.encode(json != null ? jsonEncode(json) : text!));
    }
    await req.response.close();
  }

  Future<void> dispose() async {
    await _addon.close(force: true);
    await _tracker.close(force: true);
    seeder.dispose();
    await root.delete(recursive: true);
  }

  /// A multi-file torrent (a folder [name] holding [files]); pieces run
  /// across file boundaries, as in real packs.
  static ({Uint8List bytes, String infoHash}) _pack(
    String name,
    List<(String, Uint8List)> files,
  ) {
    const pieceLength = 16384;
    final all = BytesBuilder(copy: false);
    for (final (_, data) in files) {
      all.add(data);
    }
    final data = all.takeBytes();
    final pieces = BytesBuilder(copy: false);
    for (var off = 0; off < data.length; off += pieceLength) {
      final end = off + pieceLength < data.length
          ? off + pieceLength
          : data.length;
      pieces.add(sha1.convert(Uint8List.sublistView(data, off, end)).bytes);
    }
    final info = <String, Object?>{
      'name': name,
      'piece length': pieceLength,
      'pieces': pieces.takeBytes(),
      'files': [
        for (final (file, bytes) in files)
          {
            'length': bytes.length,
            'path': [file],
          },
      ],
    };
    return (
      bytes: bencode({'info': info}),
      infoHash: sha1.convert(bencode(info)).toString(),
    );
  }

  static ({Uint8List bytes, String infoHash}) _torrent(
    String name,
    Uint8List data,
  ) {
    const pieceLength = 16384;
    final pieces = BytesBuilder(copy: false);
    for (var off = 0; off < data.length; off += pieceLength) {
      final end = off + pieceLength < data.length
          ? off + pieceLength
          : data.length;
      pieces.add(sha1.convert(Uint8List.sublistView(data, off, end)).bytes);
    }
    final info = <String, Object?>{
      'name': name,
      'piece length': pieceLength,
      'pieces': pieces.takeBytes(),
      'length': data.length,
    };
    return (
      bytes: bencode({'info': info}),
      infoHash: sha1.convert(bencode(info)).toString(),
    );
  }
}
