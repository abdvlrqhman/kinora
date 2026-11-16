import 'package:dlna/dlna.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinora/app/providers.dart';
import 'package:kinora/core/settings.dart';
import 'package:kinora/features/player/player_controller.dart';
import 'package:kinora/services/cast_service.dart';
import 'package:kinora/services/playback.dart';

void main() {
  test('10-bit pictures are told from 8-bit ones', () {
    for (final f in ['yuv420p10le', 'yuv420p10', 'p010', 'yuv444p12']) {
      expect(PlayerController.tenBitPixels.hasMatch(f), isTrue, reason: f);
    }
    for (final f in ['nv12', 'yuv420p', 'videotoolbox', '']) {
      expect(PlayerController.tenBitPixels.hasMatch(f), isFalse, reason: f);
    }
  });

  test('what a TV turned down is kept with the settings', () {
    final back = AppSettings.fromJson(
      const AppSettings(
        tvRefused: {
          'uuid:tv': ['hevc10', 'flac'],
        },
      ).toJson(),
    );
    expect(back.tvRefused, {
      'uuid:tv': ['hevc10', 'flac'],
    });
  });

  test('the likeliest reason a TV turns a file down', () {
    expect(
      CastService.culprits(
        const MediaTraits(videoCodec: VideoCodec.hevc, videoBitDepth: 10),
      ),
      ['hevc10'],
    );
    expect(
      CastService.culprits(
        const MediaTraits(
          videoCodec: VideoCodec.h264,
          videoBitDepth: 8,
          audioCodec: AudioCodec.flac,
        ),
      ),
      ['flac'],
    );
    // A plain H.264 + AAC file: nothing to blame.
    expect(
      CastService.culprits(
        const MediaTraits(
          videoCodec: VideoCodec.h264,
          videoBitDepth: 8,
          audioCodec: AudioCodec.aac,
        ),
      ),
      isEmpty,
    );
  });

  test('a TV that turned down 10-bit HEVC is warned about next time', () {
    final tv = DlnaDevice(
      udn: 'uuid:tv',
      friendlyName: 'Living Room TV',
      manufacturer: 'Samsung Electronics',
      location: Uri.parse('http://192.168.1.20:9197/dmr'),
      avTransportControlUrl: Uri.parse('http://192.168.1.20:9197/av'),
    );
    final c = ProviderContainer(
      overrides: [
        initialSettingsProvider.overrideWithValue(
          const AppSettings(
            tvRefused: {
              'uuid:tv': ['hevc10'],
            },
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
    final cast = c.read(castServiceProvider);
    // A downloaded episode: its name says nothing about the format.
    final file = PlaybackSource(
      uri: Uri.file('/downloads/[Judas] Gleipnir - S01E08.mkv'),
      kind: PlaybackKind.local,
      fileName: '[Judas] Gleipnir - S01E08.mkv',
    );
    expect(cast.check(tv, file).isPlayable, isTrue, reason: 'name only');
    final heard = cast.check(
      tv,
      file,
      facts: (video: 'hevc', tenBit: true, audio: 'aac'),
    );
    expect(heard.isPlayable, isFalse);
    expect(heard.problems.single, contains('10-bit HEVC'));
    // The same TV still plays 8-bit H.264.
    expect(
      cast
          .check(tv, file, facts: (video: 'h264', tenBit: false, audio: 'aac'))
          .isPlayable,
      isTrue,
    );
  });
}
