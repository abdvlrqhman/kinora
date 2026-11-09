import 'package:release_parser/release_parser.dart';
import 'package:test/test.dart';

void main() {
  bool covers(String name, int s, int e, {int? abs}) => coversEpisode(
    parseRelease(name),
    season: s,
    episode: e,
    absoluteEpisode: abs,
  );

  test('exact episode', () {
    expect(covers('Show.S02E05.1080p.WEB', 2, 5), isTrue);
    expect(covers('Show.S02E05.1080p.WEB', 2, 6), isFalse);
    expect(covers('Show.S02E05.1080p.WEB', 1, 5), isFalse);
    expect(covers('Show 2x05 720p HDTV', 2, 5), isTrue);
  });

  test('multi-episode files', () {
    expect(covers('Show.S01E01-E03.1080p', 1, 2), isTrue);
    expect(covers('Show.S01E01E02.1080p', 1, 2), isTrue);
    expect(covers('Show.S01E01E02.1080p', 1, 3), isFalse);
  });

  test('season packs and ranges', () {
    expect(covers('Show.S03.1080p.BluRay', 3, 9), isTrue);
    expect(covers('Show.S03.1080p.BluRay', 2, 9), isFalse);
    expect(covers('Show S01-S05 1080p', 4, 1), isTrue);
    expect(covers('Show Season 1-3 1080p', 4, 1), isFalse);
  });

  test('complete series without season numbers', () {
    expect(covers('Show.Complete.Series.1080p', 7, 3), isTrue);
  });

  test('absolute-numbered anime', () {
    const name = '[SubsPlease] One Piece - 1071 (1080p) [ABCDEF12].mkv';
    expect(covers(name, 21, 180, abs: 1071), isTrue);
    expect(covers(name, 21, 180), isFalse);
    expect(covers('[SubsPlease] Dandadan - 05 (1080p)', 1, 5), isTrue);
    expect(
      covers('[SubsPlease] Dandadan (01-12) (1080p) [Batch]', 1, 7),
      isTrue,
    );
  });

  test('no episode info is not a match (but is distinguishable)', () {
    final r = parseRelease('Some.Show.1080p.WEB-DL');
    expect(coversEpisode(r, season: 1, episode: 1), isFalse);
    expect(r.hasEpisodeInfo, isFalse);
  });
}
