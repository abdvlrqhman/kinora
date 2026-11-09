import 'package:flutter_test/flutter_test.dart';
import 'package:kinora_engine/kinora_engine.dart';

void main() {
  test('status parses and computes eta', () {
    final s = TorrentStatus.fromJson({
      'ih': 'ab' * 20,
      'name': 'Show S01E01',
      'state': 'downloading',
      'paused': false,
      'has_metadata': true,
      'progress': 0.5,
      'total_wanted': 1000,
      'total_wanted_done': 500,
      'download_rate': 100,
      'num_peers': 3,
      'num_seeds': 2,
      'save_path': '/tmp',
      'error': null,
    });
    expect(s.state, TorrentState.downloading);
    expect(s.eta, const Duration(seconds: 5));
    expect(s.isComplete, isFalse);
  });

  test('stalled status has no eta', () {
    final s = TorrentStatus.fromJson({'ih': 'a', 'state': 'metadata'});
    expect(s.eta, isNull);
    expect(s.state, TorrentState.metadata);
  });

  test('files detect video and samples', () {
    TorrentFile f(String p) => TorrentFile.fromJson({
      'index': 0,
      'path': p,
      'size': 1,
      'offset': 0,
      'pad': false,
    });
    expect(f('Show/Show.S01E01.1080p.mkv').isVideo, isTrue);
    expect(f('Show/Sample/show-sample.mkv').isVideo, isFalse);
    expect(f('Show/Show.S01E01.nfo').isVideo, isFalse);
    expect(f('Movie/Movie.2024.MP4').extension, 'mp4');
  });

  test('events parse by type', () {
    expect(
      EngineEvent.fromJson({'type': 'metadata', 'ih': 'x'}),
      isA<MetadataReceived>(),
    );
    expect(
      EngineEvent.fromJson({'type': 'listen', 'port': 6881}),
      isA<ListenSucceeded>(),
    );
    expect(
      EngineEvent.fromJson({'type': 'whatever', 'message': 'm'}),
      isA<EngineLog>(),
    );
  });

  test('stream handle builds LAN uris', () {
    const h = StreamHandle(token: 't', path: '/s/t/a.mkv', size: 1, port: 8080);
    expect(h.uri().toString(), 'http://127.0.0.1:8080/s/t/a.mkv');
    expect(h.uri(host: '192.168.1.5').host, '192.168.1.5');
  });
}
