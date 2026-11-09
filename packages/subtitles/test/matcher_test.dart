import 'package:subtitles/subtitles.dart';
import 'package:test/test.dart';

final ar = Language.of('ar');
final en = Language.of('en');

SubtitleResult sub(
  String id,
  List<String> names, {
  Language? language,
  String provider = 'p',
  bool hi = false,
  bool forced = false,
  bool mt = false,
  double? fps,
  int? downloads,
  double? rating,
  String? matchedHash,
  int? season,
  int? episodeFrom,
  int? episodeTo,
  bool pack = false,
}) => SubtitleResult(
  providerId: provider,
  id: id,
  language: language ?? ar,
  releaseNames: names,
  hearingImpaired: hi,
  forced: forced,
  machineTranslated: mt,
  fps: fps,
  downloads: downloads,
  rating: rating,
  matchedHash: matchedHash,
  season: season,
  episodeFrom: episodeFrom,
  episodeTo: episodeTo,
  isSeasonPack: pack,
);

/// Realistic subtitle names for Breaking Bad S01E01 (Arabic).
List<SubtitleResult> breakingBadSubs(String hash) => [
  sub('hash', ['Breaking Bad S01E01 Pilot'], matchedHash: hash, downloads: 50),
  sub(
    'exact',
    ['Breaking.Bad.S01E01.720p.BluRay.x264-DEMAND'],
    fps: 23.976,
    downloads: 9000,
  ),
  sub(
    'exact-mt',
    ['Breaking.Bad.S01E01.720p.BluRay.x264-DEMAND'],
    mt: true,
    downloads: 90000,
  ),
  sub('pack-exact', ['Breaking.Bad.S01.720p.BluRay.x264-DEMAND']),
  sub('group-1080', ['Breaking.Bad.S01E01.1080p.BluRay.x264-DEMAND']),
  sub('source-res', [
    'Breaking.Bad.S01E01.720p.BluRay.x264-REWARD',
  ], fps: 23.976),
  sub(
    'source-res-hi',
    ['Breaking.Bad.S01E01.720p.BluRay.x264-REWARD'],
    hi: true,
    fps: 23.976,
  ),
  sub(
    'source-popular',
    ['Breaking.Bad.S01E01.BDRip.XviD-ORPHEUS'],
    downloads: 250000,
    rating: 9,
  ),
  sub('source-rare', ['Breaking.Bad.S01E01.BDRip.XviD-ORPHEUS'], downloads: 3),
  sub('multi-ep', ['Breaking.Bad.S01E01E02.BluRay']),
  sub(
    'provider-range',
    ['Breaking Bad Season 1'],
    season: 1,
    episodeFrom: 1,
    episodeTo: 7,
  ),
  sub('any-name', [
    'Breaking.Bad.S01E02.HDTV',
    'Breaking.Bad.S01E01.720p.BluRay.x264-SiNNERS',
  ]),
  sub('unknown', ['Breaking Bad S01E01']),
  sub('unverified', ['Pilot']),
  sub('fps-25', ['Breaking.Bad.S01E01.BluRay.x264-PAL'], fps: 25),
  sub('forced', ['Breaking.Bad.S01E01.720p.BluRay.x264-DEMAND'], forced: true),
  sub('hdtv', ['Breaking.Bad.S01E01.720p.HDTV.x264-CTU']),
  sub('web', ['Breaking.Bad.S01E01.Pilot.1080p.WEB-DL.DD5.1.H.264-NTb']),
  sub('multi-season', ['Breaking.Bad.S01.S02.S03.WEBRip.Netflix']),
  // Rejected:
  sub('wrong-ep', ['Breaking.Bad.S01E02.720p.BluRay.x264-DEMAND']),
  sub('wrong-season', ['Breaking.Bad.S02E01.720p.BluRay.x264-DEMAND']),
  sub('wrong-ep-plain', ['Breaking Bad S01E05']),
  sub(
    'wrong-provider-ep',
    ['Breaking Bad'],
    season: 1,
    episodeFrom: 3,
    episodeTo: 3,
  ),
  sub('wrong-provider-season', ['Breaking Bad S01E01'], season: 2),
  sub('wrong-pack-season', ['Breaking.Bad.S03.720p.BluRay.x264-DEMAND']),
];

void main() {
  const hash = '8e245d9679d31e12';
  final query = SubtitleQuery(
    type: MediaType.episode,
    imdbId: 'tt0903747',
    title: 'Breaking Bad',
    season: 1,
    episode: 1,
    languages: [ar, en],
    releaseNames: const ['Breaking.Bad.S01E01.720p.BluRay.x264-DEMAND.mkv'],
    fileHash: hash,
    fps: 23.976,
  );
  final video = parseReleaseName(query.releaseNames.first);
  const matcher = SubtitleMatcher();

  final subs = breakingBadSubs(hash);

  test('ranks realistic Arabic subtitles for a BluRay DEMAND release', () {
    final ranked = matcher.rank(subs, video, query: query, videoHash: hash);
    expect(ranked.map((r) => r.result.id), [
      'hash', // file-hash match
      'exact', // same group + source + resolution (+ same FPS)
      'pack-exact', // same, but a season pack
      'group-1080', // same group
      'source-res', // same source family + resolution + FPS
      'source-popular', // same source family, very popular
      'source-res-hi', // HI not wanted
      'any-name', // one of its release names matches
      'source-rare',
      'multi-ep', // S01E01E02 file
      'exact-mt', // machine translated: drops two tiers
      'fps-25', // FPS mismatch
      'unknown', // no release info
      'provider-range', // provider says episodes 1-7
      'unverified', // no episode in its name
      'forced', // forced-only, not wanted
      'hdtv', // different source family
      'web',
      'multi-season',
    ]);
  });

  test('wrong season/episode is rejected, packs are flagged', () {
    final ranked = matcher.rank(subs, video, query: query, videoHash: hash);
    final ids = ranked.map((r) => r.result.id).toSet();
    for (final id in [
      'wrong-ep',
      'wrong-season',
      'wrong-ep-plain',
      'wrong-provider-ep',
      'wrong-provider-season',
      'wrong-pack-season',
    ]) {
      expect(ids, isNot(contains(id)), reason: id);
      expect(
        matcher.fit(subs.firstWhere((s) => s.id == id), video, query: query),
        0,
      );
    }
    RankedSubtitle r(String id) => ranked.firstWhere((x) => x.result.id == id);
    expect(r('pack-exact').seasonPack, isTrue);
    expect(r('provider-range').seasonPack, isTrue);
    expect(r('multi-season').seasonPack, isTrue);
    expect(r('exact').seasonPack, isFalse);
    expect(r('exact').episodeVerified, isTrue);
    expect(r('unverified').episodeVerified, isFalse);
    expect(r('hash').tier, MatchTier.hash);
    expect(r('exact').tier, MatchTier.release);
    expect(r('group-1080').tier, MatchTier.group);
    expect(r('source-res').tier, MatchTier.source);
    expect(r('unknown').tier, MatchTier.unknown);
    expect(r('hdtv').tier, MatchTier.mismatch);
    expect(r('hash').reasons, contains('hash match'));
    expect(
      r('exact').reasons,
      containsAll(['same release (DEMAND)', 'same FPS']),
    );
    expect(r('exact-mt').reasons, contains('machine translated'));
    expect(r('fps-25').reasons, contains('FPS 25 ≠ 23.976'));
  });

  test('fit is within 0..1 and tiers dominate popularity', () {
    for (final s in subs) {
      final f = matcher.fit(s, video, query: query, videoHash: hash);
      expect(f, inInclusiveRange(0, 1));
    }
    final rare = matcher.fit(subs[1], video, query: query);
    final popularUnknown = matcher.fit(
      sub('x', ['Breaking Bad S01E01'], downloads: 10000000, rating: 10),
      video,
      query: query,
    );
    expect(rare, greaterThan(popularUnknown));
  });

  test('hash only counts for the file it was computed from', () {
    final s = subs.first;
    final other = parseReleaseName('Breaking.Bad.S01E01.1080p.WEB-DL-NTb');
    expect(matcher.rate(s, other, query: query)!.tier, isNot(MatchTier.hash));
    expect(
      matcher.rate(s, video, query: query, videoHash: hash)!.tier,
      MatchTier.hash,
    );
  });

  test('preferences: HI and forced are soft', () {
    const hiMatcher = SubtitleMatcher(
      prefs: SubtitlePrefs(preferHearingImpaired: true),
    );
    final plain = subs.firstWhere((s) => s.id == 'source-res');
    final hiSub = subs.firstWhere((s) => s.id == 'source-res-hi');
    expect(
      hiMatcher.fit(hiSub, video, query: query),
      greaterThan(hiMatcher.fit(plain, video, query: query)),
    );
    expect(
      matcher.fit(plain, video, query: query),
      greaterThan(matcher.fit(hiSub, video, query: query)),
    );
    const forcedMatcher = SubtitleMatcher(
      prefs: SubtitlePrefs(forcedOnly: true),
    );
    final forced = subs.firstWhere((s) => s.id == 'forced');
    final exact = subs.firstWhere((s) => s.id == 'exact');
    expect(
      forcedMatcher.fit(forced, video, query: query),
      greaterThan(forcedMatcher.fit(exact, video, query: query)),
    );
  });

  test('bestPerLanguage and grouping follow language preferences', () {
    final mixed = [
      ...subs,
      sub('en-web', ['Breaking.Bad.S01E01.1080p.WEB-DL-NTb'], language: en),
      sub('en-exact', [
        'Breaking.Bad.S01E01.720p.BluRay.x264-DEMAND',
      ], language: en),
      sub('fr', ['Breaking.Bad.S01E01'], language: Language.of('fr')),
    ];
    final m = SubtitleMatcher(prefs: SubtitlePrefs(languages: [en, ar]));
    final best = m.bestPerLanguage(mixed, video, query: query, videoHash: hash);
    expect(best.keys.map((l) => l.code), ['en', 'ar', 'fr']);
    expect(best[en]!.result.id, 'en-exact');
    expect(best[ar]!.result.id, 'hash');
    final groups = m.groupByLanguage(m.rank(mixed, video, query: query));
    expect(groups[en]!.map((r) => r.result.id), ['en-exact', 'en-web']);
  });

  test('movies: wrong year or TV episode rejected; other titles soft', () {
    final movie = SubtitleQuery(
      type: MediaType.movie,
      imdbId: 'tt1375666',
      title: 'Inception',
      year: 2010,
      languages: [en],
    );
    final v = parseReleaseName('Inception.2010.1080p.BluRay.x264-SPARKS');
    double f(String name) =>
        matcher.fit(sub(name, [name], language: en), v, query: movie);
    expect(f('Inception.2010.1080p.BluRay.x264-SPARKS'), greaterThan(0.7));
    expect(f('Inception.2011.720p.BluRay'), greaterThan(0));
    expect(f('Interstellar.2014.1080p.BluRay'), 0);
    expect(f('Inception.1999.DVDRip'), 0);
    expect(f('Some.Show.S01E01.720p'), 0);
    expect(f('Origen.2010.1080p.BluRay'), greaterThan(0));
    expect(
      f('Origen.2010.1080p.BluRay'),
      lessThan(f('Inception.2010.1080p.BluRay')),
    );
    expect(f('Inception'), greaterThan(0));
  });

  test('uninformative names defer to the informative file name', () {
    final v = parseReleaseName('Inception.2010.1080p.BluRay.x264-SPARKS');
    final s = SubtitleResult(
      providerId: 'stremio',
      id: '1',
      language: en,
      releaseNames: const ['Inception'],
      fileName: 'Inception.2010.480p.TS.XviD-ViSiON.srt',
    );
    expect(matcher.rate(s, v)!.tier, MatchTier.mismatch);
  });

  test('episode info falls back to the video release when no query', () {
    final r = matcher.rate(
      sub('a', ['Show.S01E02.WEB']),
      parseReleaseName('Show.S01E01.WEB-GRP'),
    );
    expect(r, isNull);
    final ok = matcher.rate(
      sub('b', ['Show.S01E01.WEB']),
      parseReleaseName('Show.S01E01.WEB-GRP'),
    );
    expect(ok!.tier, MatchTier.source);
  });
}
