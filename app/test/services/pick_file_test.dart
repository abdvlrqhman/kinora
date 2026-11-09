import 'package:flutter_test/flutter_test.dart';
import 'package:kinora/services/playback.dart';
import 'package:kinora_engine/kinora_engine.dart';

TorrentFile f(int i, String path, int size) =>
    TorrentFile(index: i, path: path, size: size, offset: 0, isPad: false);

void main() {
  final pack = [
    f(0, 'Show.S01/Show.S01E01.1080p.WEB.mkv', 900),
    f(1, 'Show.S01/Show.S01E02.1080p.WEB.mkv', 950),
    f(2, 'Show.S01/Show.S01E10.1080p.WEB.mkv', 990),
    f(3, 'Show.S01/Sample/Show.S01E02.sample.mkv', 50),
    f(4, 'Show.S01/Show.S01.nfo', 1),
  ];

  test('addon file index wins', () {
    expect(pickFile(pack, fileIndex: 1, season: 1, episode: 10)!.index, 1);
  });

  test('matches SxxEyy without confusing E1 and E10, skips samples', () {
    expect(pickFile(pack, season: 1, episode: 1)!.index, 0);
    expect(pickFile(pack, season: 1, episode: 2)!.index, 1);
    expect(pickFile(pack, season: 1, episode: 10)!.index, 2);
  });

  test('1x02 naming', () {
    final files = [f(0, 'show.1x01.mkv', 10), f(1, 'show.1x02.mkv', 10)];
    expect(pickFile(files, season: 1, episode: 2)!.index, 1);
  });

  test('falls back to the largest video', () {
    expect(pickFile(pack)!.index, 2);
    expect(pickFile([f(0, 'a.nfo', 1)]), isNull);
  });
}
