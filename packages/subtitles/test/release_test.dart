import 'package:subtitles/subtitles.dart';
import 'package:test/test.dart';

void main() {
  final cases = <String, ReleaseInfo>{
    'Breaking.Bad.S01E01.Pilot.1080p.WEB-DL.DD5.1.H.264-NTb.mkv':
        const ReleaseInfo(
          title: 'Breaking Bad',
          season: 1,
          episodes: [1],
          group: 'NTb',
          source: 'webdl',
          resolution: 1080,
          videoCodec: 'h264',
        ),
    'Breaking.Bad.S01E01.720p.BluRay.Sujaidr.Arabic.srt': const ReleaseInfo(
      title: 'Breaking Bad',
      season: 1,
      episodes: [1],
      source: 'bluray',
      resolution: 720,
    ),
    'Inception.2010.1080p.BluRay.x265-YAWNTiC_eng SDH': const ReleaseInfo(
      title: 'Inception',
      year: 2010,
      group: 'YAWNTiC',
      source: 'bluray',
      resolution: 1080,
      videoCodec: 'h265',
    ),
    'Breaking.Bad.S01.2160p.WEBRip.DTS-HD.MA5.1.x264-TrollUHD':
        const ReleaseInfo(
          title: 'Breaking Bad',
          season: 1,
          isPack: true,
          group: 'TrollUHD',
          source: 'webrip',
          resolution: 2160,
          videoCodec: 'h264',
        ),
    'Breaking Bad, SEASON 1 1080p x265 [23.976 FPS]': const ReleaseInfo(
      title: 'Breaking Bad',
      season: 1,
      isPack: true,
      resolution: 1080,
      videoCodec: 'h265',
    ),
    'Show.Name.S02E03E04.720p.HDTV.x264-KILLERS': const ReleaseInfo(
      title: 'Show Name',
      season: 2,
      episodes: [3, 4],
      group: 'KILLERS',
      source: 'hdtv',
      resolution: 720,
      videoCodec: 'h264',
    ),
    'Show.Name.S02E03-05.1080p.AMZN.WEB-DL': const ReleaseInfo(
      title: 'Show Name',
      season: 2,
      episodes: [3, 4, 5],
      source: 'webdl',
      resolution: 1080,
    ),
    'Breaking.Bad.s01e01.dsr.xvid-0tv': const ReleaseInfo(
      title: 'Breaking Bad',
      season: 1,
      episodes: [1],
      group: '0tv',
      source: 'hdtv',
      videoCodec: 'xvid',
    ),
    'breaking.bad.1x01.dvdrip.xvid': const ReleaseInfo(
      title: 'breaking bad',
      season: 1,
      episodes: [1],
      source: 'dvd',
      videoCodec: 'xvid',
    ),
    '[SubsPlease] Sousou no Frieren - 05 (1080p) [ABCD1234].mkv':
        const ReleaseInfo(
          title: 'Sousou no Frieren',
          episodes: [5],
          group: 'SubsPlease',
          resolution: 1080,
        ),
    '1917.2019.2160p.UHD.BluRay.REMUX.HDR.HEVC-FGT': const ReleaseInfo(
      title: '1917',
      year: 2019,
      group: 'FGT',
      source: 'remux',
      resolution: 2160,
      videoCodec: 'h265',
    ),
    'Breaking Bad COMPLETE S01-S05 2160p WEB-DL x264-TrollUHD':
        const ReleaseInfo(
          title: 'Breaking Bad',
          isPack: true,
          group: 'TrollUHD',
          source: 'webdl',
          resolution: 2160,
          videoCodec: 'h264',
        ),
    'Breaking.Bad.S01.S02.S03.S04,S05.WEBRip.Netflix.ar': const ReleaseInfo(
      title: 'Breaking Bad',
      isPack: true,
      source: 'webrip',
    ),
    'S1E01 - Pilot.srt': const ReleaseInfo(season: 1, episodes: [1]),
  };
  cases.forEach((name, expected) {
    test(name, () => expect(parseReleaseName(name), expected));
  });

  test('source families', () {
    expect(sourceFamilyOf('WEB-DL'), SourceFamily.web);
    expect(sourceFamilyOf('webrip'), SourceFamily.web);
    expect(sourceFamilyOf('AMZN'), SourceFamily.web);
    expect(sourceFamilyOf('BDRip'), SourceFamily.bluray);
    expect(sourceFamilyOf('remux'), SourceFamily.bluray);
    expect(sourceFamilyOf('HDTV'), SourceFamily.tv);
    expect(sourceFamilyOf('DVDRip'), SourceFamily.dvd);
    expect(sourceFamilyOf('HDCAM'), SourceFamily.cam);
    expect(sourceFamilyOf(null), SourceFamily.unknown);
    expect(sourceFamilyOf('weird'), SourceFamily.unknown);
  });

  test('toString is readable', () {
    expect(
      parseReleaseName('Show.S01E02.1080p.WEB-DL-GRP').toString(),
      'ReleaseInfo(Show S1 E2 webdl 1080p -GRP)',
    );
  });
}
