import 'package:dlna/dlna.dart';
import 'package:test/test.dart';

import 'package:dlna/testing.dart';

void main() {
  const samsung = CastProfile.samsungFullHdTizen;

  // Traits as the release parser would derive them from real release names.
  final releases = <String, (MediaTraits, List<String>)>{
    'The.Bear.S03E01.1080p.WEB.h264-ETHEL.mkv (EAC3)': (
      const MediaTraits(
        container: CastContainer.mkv,
        videoCodec: VideoCodec.h264,
        videoBitDepth: 8,
        height: 1080,
        audioCodec: AudioCodec.eac3,
      ),
      [],
    ),
    'Severance.S02E01.1080p.ATVP.WEB-DL.DDP5.1.H.265-FLUX.mkv': (
      const MediaTraits(
        container: CastContainer.mkv,
        videoCodec: VideoCodec.hevc,
        height: 1080,
        audioCodec: AudioCodec.eac3,
      ),
      [],
    ),
    'Dune.Part.Two.2024.1080p.BluRay.x265.10bit.AAC5.1-LAMA.mp4': (
      const MediaTraits(
        container: CastContainer.mp4,
        videoCodec: VideoCodec.hevc,
        videoBitDepth: 10,
        height: 1080,
        audioCodec: AudioCodec.aac,
      ),
      [],
    ),
    'Oppenheimer.2023.1080p.BluRay.DTS-HD.MA.5.1.x264-GRP.mkv': (
      const MediaTraits(
        container: CastContainer.mkv,
        videoCodec: VideoCodec.h264,
        height: 1080,
        audioCodec: AudioCodec.dts,
      ),
      ["DTS audio isn't supported by this TV"],
    ),
    'Oppenheimer.2023.2160p.UHD.BluRay.REMUX.DV.HDR10.HEVC.TrueHD.7.1.Atmos.mkv':
        (
          const MediaTraits(
            container: CastContainer.mkv,
            videoCodec: VideoCodec.hevc,
            videoBitDepth: 10,
            width: 3840,
            height: 2160,
            hdr: {HdrFormat.dolbyVision, HdrFormat.hdr10},
            audioCodec: AudioCodec.truehd,
          ),
          [
            "2160p video is above this TV's 1080p maximum",
            "Dolby Vision + HDR10 isn't supported by this TV (colours would look wrong)",
            "Dolby TrueHD audio isn't supported by this TV",
          ],
        ),
    '[SubsPlease] Frieren - 01 (1080p) [Hi10P FLAC].mkv': (
      const MediaTraits(
        container: CastContainer.mkv,
        videoCodec: VideoCodec.h264,
        videoBitDepth: 10,
        height: 1080,
        audioCodec: AudioCodec.flac,
      ),
      [
        "10-bit H.264 video isn't supported by this TV",
        "FLAC audio isn't supported by this TV",
      ],
    ),
    'Old.Movie.2004.DVDRip.XviD.AC3.avi': (
      const MediaTraits(
        container: CastContainer.avi,
        videoCodec: VideoCodec.mpeg4,
        height: 576,
        audioCodec: AudioCodec.ac3,
      ),
      [],
    ),
    'Some.Show.S01E01.720p.HEVC.x265.avi': (
      const MediaTraits(
        container: CastContainer.avi,
        videoCodec: VideoCodec.hevc,
        height: 720,
        audioCodec: AudioCodec.aac,
      ),
      ["HEVC video in AVI files isn't supported by this TV"],
    ),
    'YouTube.Rip.1080p.VP9.Opus.webm': (
      const MediaTraits(
        container: CastContainer.webm,
        videoCodec: VideoCodec.vp9,
        height: 1080,
        audioCodec: AudioCodec.opus,
      ),
      ["VP9 video isn't supported by this TV"],
    ),
    'Movie.2024.1080p.WEB-DL.AV1.Opus.mkv': (
      const MediaTraits(
        container: CastContainer.mkv,
        videoCodec: VideoCodec.av1,
        height: 1080,
        audioCodec: AudioCodec.opus,
      ),
      ["AV1 video isn't supported by this TV"],
    ),
    'Show.S01E01.1080p.WEB-DL.DV.H.265.mkv (DV profile 5 only)': (
      const MediaTraits(
        container: CastContainer.mkv,
        videoCodec: VideoCodec.hevc,
        videoBitDepth: 10,
        height: 1080,
        hdr: {HdrFormat.dolbyVision},
        audioCodec: AudioCodec.eac3,
      ),
      ["Dolby Vision isn't supported by this TV (colours would look wrong)"],
    ),
  };

  group('samsungFullHdTizen', () {
    releases.forEach((name, expected) {
      final (traits, problems) = expected;
      test(name, () {
        final check = samsung.canPlay(traits);
        expect(check.problems, problems);
        expect(check.isPlayable, problems.isEmpty);
      });
    });

    test('unknown traits are not held against the release', () {
      expect(samsung.canPlay(const MediaTraits()).isPlayable, isTrue);
    });

    test('image subtitles are a warning, not a blocker', () {
      final check = samsung.canPlay(
        const MediaTraits(
          container: CastContainer.mkv,
          videoCodec: VideoCodec.h264,
          height: 1080,
          audioCodec: AudioCodec.ac3,
          subtitleFormat: SubtitleFormat.pgs,
        ),
      );
      expect(check.isPlayable, isTrue);
      expect(check.warnings, ["PGS subtitles can't be shown on this TV"]);
    });

    test('HDR10+ falls back to HDR10 on an HDR10 renderer', () {
      const hdrTv = CastProfile(
        name: 'HDR10 TV',
        containers: {CastContainer.mkv},
        videoCodecs: {VideoCodec.hevc: VideoCodecSupport(maxBitDepth: 10)},
        maxWidth: 3840,
        maxHeight: 2160,
        audioCodecs: {AudioCodec.eac3},
        hdrFormats: {HdrFormat.hdr10},
      );
      expect(
        hdrTv.canPlay(const MediaTraits(hdr: {HdrFormat.hdr10Plus})).isPlayable,
        isTrue,
      );
      expect(
        hdrTv
            .canPlay(
              const MediaTraits(hdr: {HdrFormat.dolbyVision, HdrFormat.hdr10}),
            )
            .isPlayable,
        isTrue,
      );
    });
  });

  test('genericDlna is conservative', () {
    final check = CastProfile.genericDlna.canPlay(
      const MediaTraits(
        container: CastContainer.mkv,
        videoCodec: VideoCodec.hevc,
        height: 1080,
        audioCodec: AudioCodec.eac3,
      ),
    );
    expect(check.problems, [
      "MKV files aren't supported by this TV",
      "HEVC video isn't supported by this TV",
      "Dolby Digital Plus (E-AC3) audio isn't supported by this TV",
    ]);
    expect(
      CastProfile.genericDlna
          .canPlay(
            const MediaTraits(
              container: CastContainer.mp4,
              videoCodec: VideoCodec.h264,
              height: 1080,
              audioCodec: AudioCodec.aac,
            ),
          )
          .isPlayable,
      isTrue,
    );
  });

  group('fromSinkProtocols', () {
    final sink = ProtocolInfo.parseList(samsungSink);

    test('learns containers and codecs from a Samsung sink list', () {
      final profile = CastProfile.fromSinkProtocols(sink);
      expect(profile.containers, {
        CastContainer.mkv,
        CastContainer.mp4,
        CastContainer.ts,
        CastContainer.avi,
        CastContainer.mov,
      });
      expect(
        profile.videoCodecs.keys,
        containsAll([VideoCodec.h264, VideoCodec.hevc, VideoCodec.mpeg2]),
      );
      expect(
        profile.audioCodecs,
        containsAll([AudioCodec.aac, AudioCodec.ac3, AudioCodec.mp3]),
      );
      expect(profile.maxHeight, 1080);
    });

    test('narrows the Samsung profile to advertised containers', () {
      final profile = CastProfile.fromSinkProtocols(sink, base: samsung);
      expect(profile.containers, isNot(contains(CastContainer.webm)));
      expect(profile.audioCodecs, isNot(contains(AudioCodec.dts)));
      expect(
        profile.videoCodecs[VideoCodec.hevc],
        samsung.videoCodecs[VideoCodec.hevc],
      );
    });

    test('wildcard or empty sink keeps the base containers', () {
      expect(
        CastProfile.fromSinkProtocols([ProtocolInfo.parse('http-get:*:*:*')])
            .containers,
        CastProfile.genericDlna.containers,
      );
      expect(
        CastProfile.fromSinkProtocols(const []),
        CastProfile(
          name: 'Generic DLNA (renderer protocols)',
          containers: CastProfile.genericDlna.containers,
          videoCodecs: CastProfile.genericDlna.videoCodecs,
          maxWidth: 1920,
          maxHeight: 1080,
          audioCodecs: CastProfile.genericDlna.audioCodecs,
        ),
      );
    });

    test('mimeTypeFor picks what the renderer advertises', () {
      expect(CastContainer.mkv.mimeTypeFor(sink), 'video/x-matroska');
      expect(
        CastContainer.mkv.mimeTypeFor([
          ProtocolInfo.parse('http-get:*:video/x-mkv:*'),
        ]),
        'video/x-mkv',
      );
      expect(CastContainer.ts.mimeTypeFor(const []), 'video/mp2t');
    });
  });

  test('value semantics', () {
    expect(const CastCheck(problems: ['a']), const CastCheck(problems: ['a']));
    expect(
      const MediaTraits(hdr: {HdrFormat.hdr10}),
      const MediaTraits(hdr: {HdrFormat.hdr10}),
    );
    expect(
      samsung,
      CastProfile.fromSinkProtocols(
        const [],
        base: samsung,
      ).copyName(samsung.name),
    );
  });
}

extension on CastProfile {
  CastProfile copyName(String name) => CastProfile(
    name: name,
    containers: containers,
    videoCodecs: videoCodecs,
    maxWidth: maxWidth,
    maxHeight: maxHeight,
    audioCodecs: audioCodecs,
    hdrFormats: hdrFormats,
    subtitleFormats: subtitleFormats,
  );
}
