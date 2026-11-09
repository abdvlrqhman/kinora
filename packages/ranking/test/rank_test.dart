import 'package:ranking/ranking.dart';
import 'package:release_parser/release_parser.dart';
import 'package:test/test.dart';

const _gb = 1024 * 1024 * 1024;
final _now = DateTime.utc(2026, 11, 9, 12);

Candidate _c(
  String id,
  String name, {
  int? live,
  int? addonSeeds,
  num? gb,
  bool cached = false,
  bool direct = false,
  Map<String, double> subs = const {},
  int? fileIndex,
}) => Candidate(
  id: id,
  release: parseRelease(name),
  addonId: 'test',
  sizeBytes: gb == null ? null : (gb * _gb).round(),
  addonSeeders: addonSeeds,
  live: live == null
      ? null
      : SwarmHealth(seeders: live, leechers: live ~/ 3, measuredAt: _now),
  isDebridCached: cached,
  isDirectUrl: direct,
  subtitleFit: subs,
  fileIndex: fileIndex,
);

/// Modern phone: HEVC 10-bit, HDR10 screen, no AV1 / Dolby Vision.
final _phone = DeviceCaps(hdr10: true);

/// Older phone: no 10-bit HEVC, 1080p max.
final _oldPhone = DeviceCaps(
  h265TenBit: false,
  maxResolution: Resolution.p1080,
);

/// Samsung 5 Series 43" (Full HD) cast profile from PLAN.md §8.
final _samsungFhd = DeviceCaps(
  h265TenBit: false,
  maxResolution: Resolution.p1080,
  audio: {AudioCodec.aac, AudioCodec.ac3, AudioCodec.eac3, AudioCodec.mp3},
  containers: {'mkv', 'mp4', 'ts', 'avi'},
);

RankedCandidate _byId(List<RankedCandidate> r, String id) =>
    r.firstWhere((x) => x.candidate.id == id);

List<String> _labels(RankedCandidate r) => [
  ...r.reasons.map((x) => x.label),
  ...r.warnings.map((x) => x.label),
];

void main() {
  group('episode with 20 realistic candidates', () {
    const show = 'The.Last.of.Us';
    final candidates = [
      _c(
        'best',
        '$show.S01E03.Long.Long.Time.1080p.HMAX.WEB-DL.DDP5.1.H.264-NTb',
        live: 214,
        gb: 4.2,
        subs: {'ar': 0.95, 'en': 0.9},
      ),
      _c(
        'x265',
        '$show.S01E03.1080p.WEB.H265-GGEZ',
        live: 120,
        gb: 1.6,
        subs: {'en': 0.8},
      ),
      _c(
        '4kdv',
        '$show.S01E03.Long.Long.Time.2160p.HMAX.WEB-DL.DDP5.1.Atmos.DV.HDR.H.265-FLUX',
        live: 300,
        gb: 9.5,
        subs: {'ar': 0.6},
      ),
      _c(
        'remux',
        '$show.S01E03.1080p.BluRay.REMUX.AVC.TrueHD.Atmos.7.1-FraMeSToR',
        live: 40,
        gb: 28,
      ),
      _c(
        'wrong',
        '$show.S01E04.Please.Hold.to.My.Hand.1080p.HMAX.WEB-DL.DDP5.1.H.264-NTb',
        live: 500,
        gb: 4,
      ),
      _c(
        'pack',
        '$show.S01.1080p.HMAX.WEB-DL.DDP5.1.H.264-NTb',
        live: 800,
        gb: 4.2,
        fileIndex: 2,
        subs: {'ar': 0.95},
      ),
      _c('hdtv', '$show.S01E03.720p.HDTV.x264-SYNCOPY', live: 60, gb: 1.1),
      _c(
        'webrip',
        '$show.S01E03.1080p.WEBRip.x264-ION10',
        live: 35,
        gb: 2,
        subs: {'en': 0.7},
      ),
      _c(
        'hindi',
        '$show.S01E03.1080p.WEB-DL.Hindi.Dubbed.x264',
        live: 900,
        gb: 2.5,
      ),
      _c(
        'dual',
        '$show.S01E03.1080p.WEB-DL.Dual.Audio.Hindi.English.x264-Telly',
        live: 70,
        gb: 3,
      ),
      _c('tiny', '$show.S01E03.1080p.WEB.x264-FAKE', live: 1000, gb: 0.15),
      _c(
        'noseed',
        '$show.S01E03.1080p.AMZN.WEB-DL.DDP5.1.H.264-NTb',
        live: 0,
        gb: 4,
      ),
      _c(
        'stale',
        '$show.S01E03.1080p.WEB-DL.DD5.1.H.264-GRP',
        addonSeeds: 400,
        gb: 3.8,
      ),
      _c('unknown', '$show.S01E03.720p.WEB-DL.x264-GRP2', gb: 1.2),
      _c('av1', '$show.S01E03.1080p.WEB.AV1.Opus-GRP', live: 50, gb: 1),
      _c('dvonly', '$show.S01E03.2160p.WEB-DL.DV.H.265-GRP', live: 90, gb: 8),
      _c(
        'e02',
        '$show.S01E02.Infected.1080p.WEB-DL.H.264-NTb',
        live: 600,
        gb: 4,
      ),
      _c('multi', '$show.S01E01-E03.1080p.WEB-DL.x264-GRP', live: 30, gb: 9),
      _c(
        'noinfo',
        'The Last of Us Long Long Time 1080p WEB-DL',
        live: 100,
        gb: 4,
      ),
      _c('proper', '$show.S01E03.PROPER.720p.WEB.H264-GGEZ', live: 20, gb: 1.4),
    ];
    final prefs = RankPrefs(
      device: _phone,
      subtitleLanguages: ['ar', 'en'],
      maxResolution: Resolution.p1080,
      bandwidthBytesPerSec: 3e6,
      runtimeMinutes: 75,
      originalLanguage: 'en',
    );
    final ranked = rank(
      candidates,
      prefs,
      episode: const EpisodeRef(season: 1, episode: 3),
    );

    test('fixture size', () => expect(candidates, hasLength(20)));

    test('picks the healthy 1080p WEB-DL with Arabic subtitles', () {
      final best = ranked.first;
      expect(best.candidate.id, 'best');
      expect(best.isRejected, isFalse);
      expect(best.summary, '1080p WEB-DL · 214 seeds · Arabic subtitles match');
      expect(best.warnings, isEmpty);
    });

    test('every candidate is returned once', () {
      expect(ranked.map((r) => r.candidate.id).toSet(), hasLength(20));
    });

    test('wrong episodes are rejected and sorted last', () {
      expect(_byId(ranked, 'wrong').rejected, RejectReason.wrongEpisode);
      expect(_byId(ranked, 'e02').rejected, RejectReason.wrongEpisode);
      expect(_byId(ranked, 'multi').rejected, isNull);
      final firstRejected = ranked.indexWhere((r) => r.isRejected);
      expect(ranked.skip(firstRejected).every((r) => r.isRejected), isTrue);
    });

    test('what this phone cannot decode is rejected', () {
      expect(_byId(ranked, 'av1').rejected, RejectReason.unplayableOnDevice);
      expect(
        _labels(_byId(ranked, 'av1')),
        contains("AV1 won't play on this device"),
      );
      expect(_byId(ranked, 'dvonly').rejected, RejectReason.unplayableOnDevice);
      expect(
        _labels(_byId(ranked, 'dvonly')),
        contains("Dolby Vision won't display on this device"),
      );
    });

    test('season pack ranks just below the same single episode', () {
      final pack = _byId(ranked, 'pack');
      expect(pack.isRejected, isFalse);
      expect(_labels(pack), contains('Season pack (slower start)'));
      expect(ranked.indexOf(pack), 1);
      expect(ranked.first.score - pack.score, closeTo(0.05, 1e-9));
    });

    test('warnings explain the losers', () {
      expect(
        _labels(_byId(ranked, 'remux')),
        contains('Large for your connection'),
      );
      expect(
        _labels(_byId(ranked, 'tiny')),
        contains('Suspiciously small file'),
      );
      expect(_labels(_byId(ranked, 'hindi')), contains('Dubbed audio'));
      expect(_labels(_byId(ranked, 'noseed')), contains('No seeds'));
      expect(_labels(_byId(ranked, 'unknown')), contains('Seeds unknown'));
      expect(
        _labels(_byId(ranked, 'noinfo')),
        contains('Episode not confirmed'),
      );
      expect(_labels(_byId(ranked, 'proper')), contains('PROPER'));
      expect(_labels(_byId(ranked, '4kdv')), contains('HDR'));
      expect(_labels(_byId(ranked, 'dual')), isNot(contains('Dubbed audio')));
    });

    test('stale addon seeds count less than a live scrape', () {
      final stale = _byId(ranked, 'stale');
      expect(_labels(stale), contains('400 seeds'));
      final scraped = rank(
        [_c('stale', stale.candidate.release.raw, live: 400, gb: 3.8)],
        prefs,
        episode: const EpisodeRef(season: 1, episode: 3),
      ).single;
      expect(scraped.score, greaterThan(stale.score));
    });

    test('a 4K file above the 1080p preference loses to 1080p ones', () {
      final fourK = ranked.indexWhere((r) => r.candidate.id == '4kdv');
      expect(
        fourK,
        greaterThan(ranked.indexWhere((r) => r.candidate.id == 'x265')),
      );
    });

    test('ranking is deterministic regardless of input order', () {
      final shuffled = [...candidates.reversed];
      final again = rank(
        shuffled,
        prefs,
        episode: const EpisodeRef(season: 1, episode: 3),
      );
      expect(
        again.map((r) => r.candidate.id),
        ranked.map((r) => r.candidate.id),
      );
      expect(again, ranked);
    });
  });

  group('cast to a Samsung Full HD TV (no DTS, no 10-bit)', () {
    final candidates = [
      _c('a-dts', 'Movie.2019.1080p.BluRay.x264.DTS-FGT', live: 300, gb: 9),
      _c('b-web', 'Movie.2019.1080p.WEB-DL.DDP5.1.H.264-NTb', live: 120, gb: 6),
      _c(
        'c-10bit',
        'Movie.2019.1080p.BluRay.x265.10bit.AAC5.1-Tigole',
        live: 500,
        gb: 4,
      ),
      _c('d-4k', 'Movie.2019.2160p.WEB-DL.DDP5.1.H.264-GRP', live: 150, gb: 15),
    ];

    test('on the phone the DTS BluRay can win', () {
      final ranked = rank(
        candidates,
        RankPrefs(device: _phone, maxResolution: Resolution.p1080),
      );
      expect(ranked.first.candidate.id, 'a-dts');
      expect(ranked.where((r) => r.isRejected), isEmpty);
    });

    test('with the TV selected the DTS release loses', () {
      final ranked = rank(
        candidates,
        RankPrefs(device: _phone, castTarget: _samsungFhd),
      );
      final best = ranked.first;
      expect(best.candidate.id, 'b-web');
      expect(best.reasons.map((r) => r.label), contains('Plays on TV'));
      final dts = _byId(ranked, 'a-dts');
      expect(dts.rejected, RejectReason.unplayableOnTv);
      expect(_labels(dts), contains("DTS audio won't play on TV"));
      expect(
        _labels(_byId(ranked, 'c-10bit')),
        contains("10-bit HEVC won't play on TV"),
      );
      expect(_labels(_byId(ranked, 'd-4k')), contains("4K won't play on TV"));
    });

    test('nothing plays on the TV: kept with warnings and a penalty', () {
      final onlyDts = [candidates.first];
      final ranked = rank(
        onlyDts,
        RankPrefs(device: _phone, castTarget: _samsungFhd),
      );
      expect(ranked.single.isRejected, isFalse);
      expect(_labels(ranked.single), contains("DTS audio won't play on TV"));
      final free = rank(onlyDts, RankPrefs(device: _phone));
      expect(ranked.single.score, lessThan(free.single.score - 0.4));
    });

    test('containers and plain HEVC', () {
      final tv = DeviceCaps(h265: false, containers: {'mkv', 'mp4'});
      final ranked = rank([
        _c('avi', 'Movie.2005.DVDRip.XviD.AC3-BiA.avi', live: 50),
        _c('hevc', 'Movie.2019.1080p.WEB-DL.x265-GRP.mkv', live: 50),
      ], RankPrefs(device: _phone, castTarget: tv));
      expect(_labels(_byId(ranked, 'avi')), contains("AVI won't play on TV"));
      expect(_labels(_byId(ranked, 'hevc')), contains("HEVC won't play on TV"));
    });
  });

  group('availability', () {
    test('no seeds anywhere: debrid wins', () {
      final ranked = rank([
        _c(
          'remux',
          'Movie.2020.2160p.BluRay.REMUX.HEVC.TrueHD-FGT',
          live: 0,
          gb: 60,
        ),
        _c('web', 'Movie.2020.1080p.WEB-DL.DDP5.1.H.264-NTb', live: 0, gb: 5),
        _c(
          'debrid',
          'Movie.2020.720p.WEB-DL.AAC2.0.H.264-NTb',
          cached: true,
          gb: 2,
        ),
      ], RankPrefs(device: _phone));
      expect(ranked.first.candidate.id, 'debrid');
      expect(ranked.first.summary, '720p WEB-DL · Instant (debrid)');
    });

    test('addon cache marker counts as cached', () {
      final release = parseAddonStream(
        name: '[RD+] Torrentio\n1080p',
        title:
            'Movie.2020.1080p.WEB-DL.H.264-NTb\n👤 0 💾 4 GB ⚙️ TorrentGalaxy',
      );
      final ranked = rank([
        Candidate(id: 'rd', release: release, addonId: 'torrentio'),
        _c('p2p', 'Movie.2020.1080p.WEB-DL.H.264-NTb', live: 30),
      ], RankPrefs(device: _phone));
      expect(ranked.first.candidate.id, 'rd');
      expect(
        ranked.first.reasons.map((r) => r.label),
        contains('Instant (debrid)'),
      );
    });

    test('direct links are instant', () {
      final ranked = rank([
        _c('http', 'Movie.2020.1080p.WEB-DL.H.264', direct: true),
        _c('p2p', 'Movie.2020.1080p.WEB-DL.H.264-NTb', live: 3),
      ], RankPrefs(device: _phone));
      expect(ranked.first.candidate.id, 'http');
      expect(ranked.first.summary, contains('Direct link'));
      expect(_labels(ranked.last), contains('Few seeds'));
    });

    test('live seeds beat bigger stale addon numbers', () {
      final ranked = rank([
        Candidate(
          id: 'stale',
          release: parseRelease('Movie.2020.1080p.WEB-DL.H.264-A'),
          addonId: 'x',
          addonSeeders: 500,
          live: SwarmHealth(seeders: 3, leechers: 40, measuredAt: _now),
        ),
        _c('fresh', 'Movie.2020.1080p.WEB-DL.H.264-B', live: 80),
      ], RankPrefs(device: _phone));
      expect(ranked.first.candidate.id, 'fresh');
      expect(_labels(ranked.last), contains('Few seeds'));
    });
  });

  group('quality and fit', () {
    test('CAM is rejected when a real release exists', () {
      final ranked = rank([
        _c('cam', 'Movie.2024.HDCAM.x264-SUNSCREEN', live: 5000),
        _c('web', 'Movie.2024.1080p.WEB-DL.H.264-NTb', live: 10),
      ], RankPrefs(device: _phone));
      expect(ranked.first.candidate.id, 'web');
      expect(_byId(ranked, 'cam').rejected, RejectReason.preRelease);
      expect(_labels(_byId(ranked, 'cam')), contains('Cinema recording (CAM)'));
    });

    test('only cinema recordings: kept with a warning', () {
      final ranked = rank([
        _c('cam', 'Movie.2024.HDCAM.x264-SUNSCREEN', live: 5000),
        _c('ts', 'Movie.2024.HDTS.1080p.x264-GRP', live: 800),
      ], RankPrefs(device: _phone));
      expect(ranked.every((r) => !r.isRejected), isTrue);
      expect(ranked.first.candidate.id, 'ts');
      expect(_labels(ranked.first), contains('Cinema recording (TS)'));
    });

    test('older phone: 10-bit HEVC rejected when H.264 exists', () {
      final both = [
        _c('hevc10', 'Movie.2021.1080p.BluRay.x265.10bit-GRP', live: 400),
        _c('avc', 'Movie.2021.1080p.BluRay.x264-GRP', live: 40),
      ];
      final ranked = rank(both, RankPrefs(device: _oldPhone));
      expect(ranked.first.candidate.id, 'avc');
      expect(_byId(ranked, 'hevc10').rejected, RejectReason.unplayableOnDevice);
      final alone = rank([both.first], RankPrefs(device: _oldPhone));
      expect(alone.single.isRejected, isFalse);
      expect(
        _labels(alone.single),
        contains("10-bit HEVC won't play on this device"),
      );
    });

    test('preferred maximum wins; going over it ranks below going under', () {
      final ranked = rank([
        _c('720', 'Movie.2021.720p.WEB-DL.H.264-A', live: 100),
        _c('1080', 'Movie.2021.1080p.WEB-DL.H.264-A', live: 100),
        _c('2160', 'Movie.2021.2160p.WEB-DL.H.264-A', live: 100),
      ], RankPrefs(device: _phone, maxResolution: Resolution.p1080));
      expect(ranked.map((r) => r.candidate.id), ['1080', '720', '2160']);
    });

    test('source order: remux > bluray > web-dl > webrip > hdtv', () {
      final ranked = rank([
        _c('hdtv', 'Movie.2021.1080p.HDTV.x264-A', live: 100),
        _c('webrip', 'Movie.2021.1080p.WEBRip.x264-A', live: 100),
        _c('remux', 'Movie.2021.1080p.BluRay.REMUX.AVC-A', live: 100),
        _c('webdl', 'Movie.2021.1080p.WEB-DL.x264-A', live: 100),
        _c('bluray', 'Movie.2021.1080p.BluRay.x264-A', live: 100),
      ], RankPrefs(device: _phone));
      expect(ranked.map((r) => r.candidate.id), [
        'remux',
        'bluray',
        'webdl',
        'webrip',
        'hdtv',
      ]);
    });

    test('HDR only helps on an HDR screen', () {
      final candidates = [
        _c('hdr', 'Movie.2021.2160p.WEB-DL.HDR.H.265-A', live: 100),
      ];
      final sdr = rank(candidates, RankPrefs(device: DeviceCaps()));
      expect(_labels(sdr.single), contains('HDR on a non-HDR screen'));
      final hdr = rank(candidates, RankPrefs(device: _phone));
      expect(hdr.single.reasons.map((r) => r.label), contains('HDR'));
      final dv = rank([
        _c('dv', 'Movie.2021.2160p.WEB-DL.DV.HDR.H.265-A', live: 100),
      ], RankPrefs(device: DeviceCaps(hdr10: true, dolbyVision: true)));
      expect(dv.single.reasons.map((r) => r.label), contains('Dolby Vision'));
    });

    test('PROPER beats the same release without it', () {
      final ranked = rank([
        _c('plain', 'Movie.2021.1080p.WEB-DL.H.264-A', live: 100),
        _c('proper', 'Movie.2021.PROPER.1080p.WEB-DL.H.264-B', live: 100),
        _c('repack', 'Movie.2021.REPACK.720p.WEB-DL.H.264-C', live: 100),
      ], RankPrefs(device: _phone));
      expect(ranked.first.candidate.id, 'proper');
      expect(_labels(_byId(ranked, 'repack')), contains('REPACK'));
    });

    test('data saver prefers small 720p files', () {
      final ranked = rank([
        _c('1080', 'Movie.2021.1080p.WEB-DL.H.264-A', live: 100, gb: 6),
        _c('720', 'Movie.2021.720p.WEB-DL.H.264-A', live: 100, gb: 1),
      ], RankPrefs(device: _phone, dataSaver: true, runtimeMinutes: 120));
      expect(ranked.first.candidate.id, '720');
      expect(_labels(ranked.last), contains('Uses a lot of data'));
    });
  });

  group('languages', () {
    final candidates = [
      _c('orig', 'Movie.2020.1080p.WEB-DL.H.264-A', live: 100),
      _c('arabic', 'Movie.2020.1080p.WEB-DL.ARABIC.Dubbed.H.264-B', live: 100),
    ];

    test('preferred dub wins and says so', () {
      final ranked = rank(
        candidates,
        RankPrefs(
          device: _phone,
          audioLanguages: ['ar'],
          originalLanguage: 'en',
        ),
      );
      expect(ranked.first.candidate.id, 'arabic');
      expect(
        ranked.first.reasons.map((r) => r.label),
        contains('Arabic audio'),
      );
    });

    test('original audio by default; dubs warned', () {
      final ranked = rank(
        candidates,
        RankPrefs(device: _phone, originalLanguage: 'en'),
      );
      expect(ranked.first.candidate.id, 'orig');
      expect(_labels(ranked.last), contains('Dubbed audio'));
    });

    test('first subtitle language weighs most', () {
      final ranked = rank([
        _c('en', 'Movie.2020.1080p.WEB-DL.H.264-A', live: 100, subs: {'en': 1}),
        _c(
          'ar',
          'Movie.2020.1080p.WEB-DL.H.264-B',
          live: 100,
          subs: {'ar': 0.9},
        ),
      ], RankPrefs(device: _phone, subtitleLanguages: ['ar', 'en']));
      expect(ranked.first.candidate.id, 'ar');
      expect(ranked.first.summary, contains('Arabic subtitles match'));
      expect(ranked.last.summary, contains('English subtitles match'));
    });

    test('embedded subtitles count; unwanted hardsubs are penalised', () {
      final ranked = rank([
        _c('esub', 'Movie.2020.720p.BluRay.x264.ESub-A', live: 100),
        _c('korsub', 'Movie.2020.720p.HDRip.KORSUB.x264-B', live: 100),
      ], RankPrefs(device: _phone, subtitleLanguages: ['en']));
      expect(ranked.first.summary, contains('English subtitles included'));
      expect(_labels(ranked.last), contains('Hardcoded subtitles'));
    });
  });

  group('anime', () {
    test('absolute episode numbers match via EpisodeRef.absolute', () {
      final ranked = rank(
        [
          _c(
            'ep',
            '[SubsPlease] One Piece - 1071 (1080p) [ABCDEF12].mkv',
            live: 900,
          ),
          _c(
            'other',
            '[SubsPlease] One Piece - 1070 (1080p) [ABCDEF13].mkv',
            live: 900,
          ),
        ],
        RankPrefs(device: _phone),
        episode: const EpisodeRef(season: 21, episode: 180, absolute: 1071),
      );
      expect(ranked.first.candidate.id, 'ep');
      expect(ranked.last.rejected, RejectReason.wrongEpisode);
    });
  });

  test('empty input', () {
    expect(rank(const [], RankPrefs(device: _phone)), isEmpty);
  });

  test('custom weights change the outcome', () {
    final candidates = [
      _c('seeds', 'Movie.2020.720p.WEB-DL.H.264-A', live: 900),
      _c('quality', 'Movie.2020.1080p.BluRay.REMUX.AVC-B', live: 4),
    ];
    final prefs = RankPrefs(device: _phone);
    expect(rank(candidates, prefs).first.candidate.id, 'seeds');
    const qualityFirst = RankWeights(availability: 0.05, quality: 0.9);
    expect(
      rank(candidates, prefs, weights: qualityFirst).first.candidate.id,
      'quality',
    );
  });

  group('value types', () {
    test('equality, hashCode and toString', () {
      final a = _c(
        'x',
        'Movie.2020.1080p.WEB-DL.H.264-A',
        live: 4,
        subs: {'ar': 0.5},
      );
      final b = _c(
        'x',
        'Movie.2020.1080p.WEB-DL.H.264-A',
        live: 4,
        subs: {'ar': 0.5},
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(_c('x', 'Movie.2020.1080p.WEB-DL.H.264-A', live: 6)));
      expect(a.toString(), contains('via test'));
      expect(a.live.toString(), contains('4 seeders'));
      expect(() => a.subtitleFit['en'] = 1, throwsUnsupportedError);

      expect(
        DeviceCaps(audio: {AudioCodec.aac}),
        DeviceCaps(audio: {AudioCodec.aac}),
      );
      expect(DeviceCaps().hashCode, DeviceCaps().hashCode);
      expect(DeviceCaps().toString(), contains('audio: any'));
      expect(_samsungFhd.toString(), contains('AAC'));

      final p1 = RankPrefs(device: _phone, subtitleLanguages: ['ar']);
      final p2 = RankPrefs(device: _phone, subtitleLanguages: ['ar']);
      expect(p1, p2);
      expect(p1.hashCode, p2.hashCode);
      expect(p1.toString(), contains('[ar]'));

      const e = EpisodeRef(season: 1, episode: 2, absolute: 14);
      expect(e, const EpisodeRef(season: 1, episode: 2, absolute: 14));
      expect(
        e.hashCode,
        const EpisodeRef(season: 1, episode: 2, absolute: 14).hashCode,
      );
      expect(e.toString(), 'EpisodeRef(S1E2 #14)');
      expect(
        const EpisodeRef(season: 1, episode: 2).toString(),
        'EpisodeRef(S1E2)',
      );

      const reason = RankReason(RankReasonKind.availability, '5 seeds');
      expect(reason, const RankReason(RankReasonKind.availability, '5 seeds'));
      expect(
        reason.hashCode,
        const RankReason(RankReasonKind.availability, '5 seeds').hashCode,
      );
      expect(reason.toString(), '5 seeds');
      const warning = RankWarning(RankWarningKind.fewSeeds, 'Few seeds');
      expect(warning, const RankWarning(RankWarningKind.fewSeeds, 'Few seeds'));
      expect(
        warning.hashCode,
        const RankWarning(RankWarningKind.fewSeeds, 'Few seeds').hashCode,
      );
      expect(warning.toString(), 'Few seeds');

      final r1 = rank([a], RankPrefs(device: _phone)).single;
      final r2 = rank([b], RankPrefs(device: _phone)).single;
      expect(r1, r2);
      expect(r1.hashCode, r2.hashCode);
      expect(r1.toString(), contains('warn: Few seeds'));
      final rejected = RankedCandidate(
        candidate: a,
        score: 0,
        rejected: RejectReason.wrongEpisode,
      );
      expect(rejected.toString(), contains('rejected: wrongEpisode'));

      expect(RankWeights.standard, const RankWeights());
      expect(RankWeights.standard.hashCode, const RankWeights().hashCode);
      expect(RankWeights.standard, isNot(const RankWeights(quality: 0.5)));
      expect(RankWeights.standard.toString(), contains('A 0.35'));
    });
  });
}
