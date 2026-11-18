import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinora/app/providers.dart';
import 'package:kinora/services/play_request.dart';
import 'package:kinora/services/playback.dart';
import 'package:kinora/services/resolver.dart';
import 'package:stremio/stremio.dart';

import '../features/harness.dart';

ResolvedRelease _release(String id, {String? url, bool aboveLimit = false}) =>
    ResolvedRelease(
      candidateId: id,
      releaseName: id,
      headline: id,
      reasons: const [],
      warnings: const [],
      score: 0,
      aboveLimit: aboveLimit,
      // No link: fails to start, like a dead torrent.
      stream: url == null ? null : StreamItem(url: url),
    );

const _request = PlayRequest(
  type: 'movie',
  mediaId: 'tt1',
  videoId: 'tt1',
  title: 'Movie',
);

void main() {
  late ProviderContainer c;

  PlaybackService service(List<ResolvedRelease> releases) {
    c = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(testDb()),
        resolveWith(releases),
      ],
    );
    addTearDown(c.dispose);
    return c.read(playbackServiceProvider);
  }

  test('a failed 1080p never falls back to a version above the limit', () {
    final s = service([
      _release('1080p'),
      _release('4K', url: 'https://cdn.test/4k.mkv', aboveLimit: true),
    ]);
    expect(
      s.prepare(_request),
      throwsA(
        isA<PlaybackException>().having(
          (e) => e.message,
          'message',
          contains('Choose another version'),
        ),
      ),
    );
  });

  test('a version within the limit plays before one above it', () async {
    final s = service([
      _release('4K', url: 'https://cdn.test/4k.mkv', aboveLimit: true),
      _release('720p', url: 'https://cdn.test/720.mkv'),
    ]);
    final source = await s.prepare(_request);
    expect(source.release?.candidateId, '720p');
  });

  test('only versions above the limit: says so instead of playing', () {
    final s = service([
      _release('4K', url: 'https://cdn.test/4k.mkv', aboveLimit: true),
    ]);
    expect(
      s.prepare(_request),
      throwsA(
        isA<PlaybackException>().having(
          (e) => e.message,
          'message',
          aboveLimitMessage,
        ),
      ),
    );
  });

  test('a version the viewer picks plays even above the limit', () async {
    final s = service([
      _release('1080p'),
      _release('4K', url: 'https://cdn.test/4k.mkv', aboveLimit: true),
    ]);
    final source = await s.prepare(
      const PlayRequest(
        type: 'movie',
        mediaId: 'tt1',
        videoId: 'tt1',
        title: 'Movie',
        candidateId: '4K',
      ),
    );
    expect(source.release?.candidateId, '4K');
  });
}
