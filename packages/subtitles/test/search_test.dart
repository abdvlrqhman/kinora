import 'dart:async';
import 'dart:io';

import 'package:subtitles/subtitles.dart';
import 'package:test/test.dart';

import 'helpers.dart';

final ar = Language.of('ar');
final en = Language.of('en');

/// In-memory provider for orchestrator tests.
final class FakeProvider implements SubtitleProvider {
  FakeProvider(
    this.id, {
    this.results = const [],
    this.delay = Duration.zero,
    this.error,
    this.hang = false,
    this.aggregator = false,
    this.files = const {},
  });

  @override
  final String id;
  final List<SubtitleResult> results;
  final Duration delay;
  final Object? error;
  final bool hang;
  final bool aggregator;
  final Map<String, SubtitleDownload> files;
  CancelToken? lastToken;
  int downloads = 0;

  @override
  String get displayName => id;

  @override
  bool get requiresKey => false;

  @override
  Set<ProviderCapability> get capabilities => {
    if (aggregator) ProviderCapability.aggregator,
  };

  @override
  Future<List<SubtitleResult>> search(
    SubtitleQuery query, {
    CancelToken? cancel,
  }) async {
    lastToken = cancel;
    if (hang) {
      await cancel!.whenCancelled;
      throw SubtitleCancelledException(providerId: id);
    }
    await Future<void>.delayed(delay);
    if (error != null) throw error!;
    return results;
  }

  @override
  Future<SubtitleDownload> download(
    SubtitleResult result, {
    CancelToken? cancel,
  }) async {
    downloads++;
    return files[result.id]!;
  }
}

SubtitleResult r(
  String provider,
  String id,
  String release, {
  Language? language,
  bool hi = false,
  int? downloads,
}) => SubtitleResult(
  providerId: provider,
  id: id,
  language: language ?? ar,
  releaseNames: [release],
  hearingImpaired: hi,
  downloads: downloads,
);

void main() {
  final query = SubtitleQuery(
    type: MediaType.episode,
    imdbId: 'tt0903747',
    season: 1,
    episode: 1,
    languages: [ar, en],
    releaseNames: const ['Breaking.Bad.S01E01.720p.BluRay.x264-DEMAND'],
  );

  test('streams snapshots as providers answer; groups and ranks', () async {
    final fast = FakeProvider(
      'fast',
      results: [
        r('fast', '1', 'Breaking.Bad.S01E01.720p.HDTV-CTU'),
        r('fast', '2', 'Breaking.Bad.S01E01.1080p.WEB-DL-NTb', language: en),
        r(
          'fast',
          '3',
          'Breaking.Bad.S01E02.720p.BluRay.x264-DEMAND',
        ), // wrong episode
        r(
          'fast',
          '4',
          'Breaking.Bad.S01E01',
          language: Language.of('fr'),
        ), // not wanted
      ],
    );
    final slow = FakeProvider(
      'slow',
      delay: const Duration(milliseconds: 30),
      results: [r('slow', 'a', 'Breaking.Bad.S01E01.720p.BluRay.x264-DEMAND')],
    );
    final updates = await SubtitleSearch(providers: [slow, fast])
        .search(query)
        .toList();
    expect(updates, hasLength(3));
    expect(
      updates.first.providers.values.map((p) => p.state),
      everyElement(ProviderState.pending),
    );
    expect(updates[1].providers['fast']!.state, ProviderState.done);
    expect(updates[1].providers['slow']!.state, ProviderState.pending);
    expect(updates[1].isComplete, isFalse);
    final last = updates.last;
    expect(last.isComplete, isTrue);
    expect(last.providers['fast']!.count, 4);
    expect(last.rejected, 1);
    expect(last.byLanguage.keys, [ar, en]);
    expect(last.counts, {ar: 2, en: 1});
    expect(last.byLanguage[ar]!.map((x) => x.result.key), ['slow:a', 'fast:1']);
    expect(last.best[ar]!.result.key, 'slow:a');
  });

  test('timeouts and failures are reported per provider', () async {
    final ok = FakeProvider(
      'ok',
      results: [r('ok', '1', 'Breaking.Bad.S01E01.720p.BluRay')],
    );
    final hung = FakeProvider('hung', hang: true);
    final broken = FakeProvider(
      'broken',
      error: const SubtitleAuthException('HTTP 401', providerId: 'broken'),
    );
    final buggy = FakeProvider('buggy', error: StateError('bad shape'));
    final last = await SubtitleSearch(
      providers: [ok, hung, broken, buggy],
      providerTimeout: const Duration(milliseconds: 50),
    ).searchAll(query);
    expect(last.providers['ok']!.state, ProviderState.done);
    expect(last.providers['hung']!.state, ProviderState.timedOut);
    expect(hung.lastToken!.isCancelled, isTrue);
    expect(last.providers['broken']!.state, ProviderState.failed);
    expect(last.providers['broken']!.error, isA<SubtitleAuthException>());
    expect(last.providers['buggy']!.error, isA<SubtitleResponseException>());
    expect(last.counts, {ar: 1});
  });

  test(
    'dedupes across providers by release + language + HI, keeps the better',
    () async {
      final os = FakeProvider(
        'opensubtitles',
        results: [
          r(
            'opensubtitles',
            '1',
            'Breaking.Bad.S01E01.720p.BluRay.x264-DEMAND',
            downloads: 5000,
          ),
          r(
            'opensubtitles',
            '1',
            'Breaking.Bad.S01E01.720p.BluRay.x264-DEMAND',
            downloads: 5000,
          ), // same id
          r(
            'opensubtitles',
            '2',
            'Breaking.Bad.S01E01.720p.BluRay.x264-DEMAND',
            hi: true,
          ),
        ],
      );
      final wyzie = FakeProvider(
        'wyzie',
        aggregator: true,
        results: [
          r(
            'wyzie',
            'w1',
            'Breaking.Bad.S01E01.720p.BluRay.x264-DEMAND.srt',
            downloads: 5000,
          ),
          r(
            'wyzie',
            'w2',
            'breaking bad s01e01 720p bluray x264 demand',
            hi: true,
            downloads: 1,
          ),
          r(
            'wyzie',
            'w3',
            'Breaking.Bad.S01E01.720p.BluRay.x264-DEMAND',
            language: en,
          ),
        ],
      );
      final subdl = FakeProvider(
        'subdl',
        results: [
          // Same provider, same release: distinct uploads are both kept.
          r('subdl', 's1', 'Breaking Bad S01E01 Pilot'),
          r('subdl', 's2', 'Breaking Bad S01E01 Pilot'),
        ],
      );
      final last = await SubtitleSearch(providers: [os, wyzie, subdl])
          .searchAll(query);
      expect(last.byLanguage[ar]!.map((x) => x.result.key).toSet(), {
        'opensubtitles:1',
        'opensubtitles:2',
        'subdl:s1',
        'subdl:s2',
      });
      expect(last.byLanguage[en]!.single.result.key, 'wyzie:w3');
    },
  );

  test('cancelling the subscription cancels providers', () async {
    final hung = FakeProvider('hung', hang: true);
    final sub = SubtitleSearch(providers: [hung]).search(query).listen((_) {});
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(hung.lastToken!.isCancelled, isTrue);
  });

  test('external cancel token', () async {
    final token = CancelToken();
    final hung = FakeProvider('hung', hang: true);
    final f = SubtitleSearch(providers: [hung]).searchAll(query, cancel: token);
    await Future<void>.delayed(Duration.zero);
    token.cancel();
    final last = await f;
    expect(last.providers['hung']!.state, ProviderState.cancelled);
  });

  group('load', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('subs_load_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test(
      'downloads, extracts the episode, decodes 1256, parses, caches',
      () async {
        final result = SubtitleResult(
          providerId: 'p',
          id: 'pack',
          language: ar,
          isSeasonPack: true,
        );
        final arabic = SubtitleResult(
          providerId: 'p',
          id: 'ar1256',
          language: ar,
        );
        final p = FakeProvider(
          'p',
          files: {
            'pack': SubtitleDownload(
              bytes: fixtureBytes('archive/season_pack.zip'),
              fileName: 'pack.zip',
            ),
            'ar1256': SubtitleDownload(
              bytes: fixtureBytes('charset/arabic_1256.srt'),
              fileName: 'x.srt',
            ),
          },
        );
        final search = SubtitleSearch(
          providers: [p],
          cache: SubtitleCache(dir),
        );
        const q = SubtitleQuery(
          type: MediaType.episode,
          season: 1,
          episode: 3,
          durationSec: 60,
        );
        final loaded = await search.load(result, query: q);
        expect(loaded.fileName, 'Show.S01E03.1080p.WEB-DL-GRP.srt');
        expect(loaded.document.cues.first.text, 'Episode 3 line one');
        expect(loaded.timing!.exceedsDuration, isFalse);
        await search.load(result, query: q);
        expect(p.downloads, 1, reason: 'second load served from cache');

        final ar1256 = await search.load(arabic);
        expect(ar1256.encoding, 'windows-1256');
        expect(ar1256.document.cues.first.text, 'مرحباً بكم في البرنامج.');
        expect(ar1256.timing, isNull);
      },
    );

    test('unknown provider', () async {
      final search = SubtitleSearch(providers: const []);
      expect(
        () => search.load(
          SubtitleResult(providerId: 'nope', id: '1', language: ar),
        ),
        throwsArgumentError,
      );
    });
  });
}
