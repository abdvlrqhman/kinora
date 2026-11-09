import 'dart:math' as math;

import 'package:collection/collection.dart';

import 'language.dart';
import 'models.dart';
import 'release.dart';

/// How closely a subtitle's release matches the video, best first.
enum MatchTier {
  /// Matched by OpenSubtitles file hash: made for this exact file.
  hash,

  /// Same release group, source family and resolution.
  release,

  /// Same release group.
  group,

  /// Same source family (WEB / BluRay / DVD / TV): usually same timings.
  source,

  /// Nothing known either way.
  unknown,

  /// Different source family: timings likely differ.
  mismatch,
}

/// A subtitle that passed the episode/movie check, with its fit for a video.
final class RankedSubtitle {
  const RankedSubtitle({
    required this.result,
    required this.fit,
    required this.tier,
    this.seasonPack = false,
    this.episodeVerified = true,
    this.reasons = const [],
  });

  final SubtitleResult result;

  /// 0..1, higher is a better fit for the video release.
  final double fit;
  final MatchTier tier;

  /// Covers the whole season; the right file is picked from the archive.
  final bool seasonPack;

  /// The episode was confirmed by provider metadata or the release name.
  final bool episodeVerified;

  /// Short English reasons for the UI ("hash match", "same group NTb").
  final List<String> reasons;

  Language get language => result.language;

  @override
  bool operator ==(Object other) =>
      other is RankedSubtitle &&
      other.result == result &&
      other.fit == fit &&
      other.tier == tier &&
      other.seasonPack == seasonPack &&
      other.episodeVerified == episodeVerified &&
      const ListEquality<String>().equals(other.reasons, reasons);

  @override
  int get hashCode => Object.hash(
    result,
    fit,
    tier,
    seasonPack,
    episodeVerified,
    const ListEquality<String>().hash(reasons),
  );

  @override
  String toString() =>
      'RankedSubtitle(${fit.toStringAsFixed(3)} ${tier.name} $result)';
}

enum _Episode { exact, pack, unverified, wrong }

/// Decides which subtitles fit a video release and how well.
///
/// Rules: wrong season/episode (from provider metadata or parsed names) is
/// rejected unless it is a season pack containing the episode; for movies a
/// clearly different year or title is rejected. Ranking: file-hash match >>
/// same group + source + resolution >> same group >> same source family >>
/// same FPS >> rating/downloads; machine translations are penalized; HI and
/// forced follow [prefs] as soft preferences.
final class SubtitleMatcher {
  const SubtitleMatcher({
    this.parser = parseReleaseName,
    this.prefs = const SubtitlePrefs(),
  });

  final ReleaseNameParser parser;
  final SubtitlePrefs prefs;

  static const _tierBase = {
    MatchTier.hash: 0.90,
    MatchTier.release: 0.75,
    MatchTier.group: 0.62,
    MatchTier.source: 0.48,
    MatchTier.unknown: 0.35,
    MatchTier.mismatch: 0.20,
  };

  /// Fit of [subtitle] for [video] in 0..1; 0 when it is for another
  /// episode/movie. [query] supplies the wanted episode, year and FPS (else
  /// taken from [video]); [videoHash] is the hash of the file [video] names.
  double fit(
    SubtitleResult subtitle,
    ReleaseInfo video, {
    SubtitleQuery? query,
    String? videoHash,
  }) => rate(subtitle, video, query: query, videoHash: videoHash)?.fit ?? 0;

  /// Like [fit] with details; null when rejected.
  RankedSubtitle? rate(
    SubtitleResult subtitle,
    ReleaseInfo video, {
    SubtitleQuery? query,
    String? videoHash,
  }) {
    final infos = [for (final n in subtitle.names) parser(n)];
    final episodic =
        query?.isEpisode ?? (video.season != null || video.episodes.isNotEmpty);
    final verdict = episodic
        ? _checkEpisode(
            subtitle,
            infos,
            query?.season ?? video.season,
            query?.episode ?? video.episodes.firstOrNull,
          )
        : _checkMovie(
            infos,
            query?.year ?? video.year,
            query?.title ?? video.title,
          );
    if (verdict == _Episode.wrong) return null;

    final reasons = <String>[];
    final hashHit =
        videoHash != null &&
        subtitle.matchedHash?.toLowerCase() == videoHash.toLowerCase();
    var tier = MatchTier.unknown;
    var sameResolution = false;
    if (hashHit) {
      tier = MatchTier.hash;
      reasons.add('hash match');
    } else {
      // Names without source or group ("Inception") say nothing; judge by
      // the best informative one (e.g. the file name). A mismatch thus needs
      // every informative name to disagree.
      final tiers = [
        for (final i in infos)
          if (i.group != null || i.family != SourceFamily.unknown)
            _tier(i, video),
      ];
      if (tiers.isNotEmpty) {
        tier = tiers.reduce((a, b) => a.index <= b.index ? a : b);
      }
      for (final info in infos) {
        if (info.resolution != null && info.resolution == video.resolution) {
          sameResolution = true;
        }
      }
      switch (tier) {
        case MatchTier.release:
          reasons.add('same release (${video.group})');
        case MatchTier.group:
          reasons.add('same group (${video.group})');
        case MatchTier.source:
          reasons.add('same source (${video.family.name})');
        case MatchTier.mismatch:
          reasons.add('different source');
        case MatchTier.unknown || MatchTier.hash:
          break;
      }
    }

    var score = _tierBase[tier]!;
    if (sameResolution && tier.index > MatchTier.release.index) score += 0.01;
    final videoFps = query?.fps;
    final subFps = subtitle.fps;
    if (videoFps != null && subFps != null && subFps > 0) {
      if ((videoFps - subFps).abs() < 0.01) {
        score += 0.04;
        reasons.add('same FPS');
      } else {
        score -= 0.06;
        reasons.add('FPS ${_fps(subFps)} ≠ ${_fps(videoFps)}');
      }
    }
    final downloads = subtitle.downloads ?? 0;
    score += math.min(1, math.log(1 + downloads) / math.ln10 / 6) * 0.02;
    score += ((subtitle.rating ?? 0).clamp(0, 10) / 10) * 0.01;

    if (subtitle.hearingImpaired == prefs.preferHearingImpaired) {
      score += 0.01;
    } else {
      score -= 0.02;
    }
    if (subtitle.forced != prefs.forcedOnly) {
      // Forced-only subs miss most dialogue (and full ones clutter when only
      // foreign parts are wanted): drop below any normal match.
      score -= 0.45;
      if (subtitle.forced) reasons.add('forced');
    } else {
      score += 0.01;
    }
    if (subtitle.machineTranslated) {
      // A human translation with likely-right timing beats a machine one
      // with exact timing.
      score -= 0.30;
      reasons.add('machine translated');
    }
    if (verdict == _Episode.pack) {
      score -= 0.02;
      reasons.add('season pack');
    } else if (verdict == _Episode.unverified) {
      score -= 0.05;
      reasons.add(episodic ? 'episode not verified' : 'title differs');
    }
    return RankedSubtitle(
      result: subtitle,
      fit: score.clamp(0.01, 1.0),
      tier: tier,
      seasonPack: verdict == _Episode.pack,
      episodeVerified: verdict == _Episode.exact,
      reasons: List.unmodifiable(reasons),
    );
  }

  /// Ranks [subtitles] for [video], dropping rejected ones; best first.
  List<RankedSubtitle> rank(
    Iterable<SubtitleResult> subtitles,
    ReleaseInfo video, {
    SubtitleQuery? query,
    String? videoHash,
  }) => [
    for (final s in subtitles)
      ?rate(s, video, query: query, videoHash: videoHash),
  ]..sort(compareRanked);

  /// Best first; ties broken by downloads, then provider/id for stability.
  static int compareRanked(RankedSubtitle a, RankedSubtitle b) {
    final f = b.fit.compareTo(a.fit);
    if (f != 0) return f;
    final d = (b.result.downloads ?? 0).compareTo(a.result.downloads ?? 0);
    return d != 0 ? d : a.result.key.compareTo(b.result.key);
  }

  /// Groups ranked subtitles by language: [prefs] languages first (in order),
  /// then the rest by English name. Each list is sorted best first.
  Map<Language, List<RankedSubtitle>> groupByLanguage(
    Iterable<RankedSubtitle> ranked,
  ) {
    final groups = <Language, List<RankedSubtitle>>{};
    for (final r in ranked) {
      groups.putIfAbsent(r.language, () => []).add(r);
    }
    final order = groups.keys.toList()
      ..sort((a, b) {
        final ia = prefs.languages.indexOf(a), ib = prefs.languages.indexOf(b);
        if (ia >= 0 || ib >= 0) {
          return (ia < 0 ? 1 << 20 : ia).compareTo(ib < 0 ? 1 << 20 : ib);
        }
        return a.compareTo(b);
      });
    return {
      for (final l in order)
        l: List.unmodifiable(groups[l]!..sort(compareRanked)),
    };
  }

  /// The best subtitle per language for [video] (what the release ranking
  /// consumes as `Map<Language, fit>`).
  Map<Language, RankedSubtitle> bestPerLanguage(
    Iterable<SubtitleResult> subtitles,
    ReleaseInfo video, {
    SubtitleQuery? query,
    String? videoHash,
  }) => {
    for (final e in groupByLanguage(
      rank(subtitles, video, query: query, videoHash: videoHash),
    ).entries)
      e.key: e.value.first,
  };

  MatchTier _tier(ReleaseInfo sub, ReleaseInfo video) {
    final sameGroup =
        sub.group != null &&
        video.group != null &&
        sub.group!.toLowerCase() == video.group!.toLowerCase();
    final a = sub.family, b = video.family;
    final familyKnown = a != SourceFamily.unknown && b != SourceFamily.unknown;
    final sameFamily = familyKnown && a == b;
    if (sameGroup &&
        sameFamily &&
        sub.resolution != null &&
        sub.resolution == video.resolution) {
      return MatchTier.release;
    }
    if (sameGroup && (sameFamily || !familyKnown)) return MatchTier.group;
    if (sameFamily) return MatchTier.source;
    if (familyKnown) return MatchTier.mismatch;
    return MatchTier.unknown;
  }

  _Episode _checkEpisode(
    SubtitleResult sub,
    List<ReleaseInfo> infos,
    int? season,
    int? episode,
  ) {
    // Provider metadata first (curated at upload time).
    var providerExact = false;
    var providerPack = sub.isSeasonPack;
    if (season != null && sub.season != null && sub.season! > 0) {
      if (sub.season != season) return _Episode.wrong;
    }
    final from = sub.episodeFrom;
    if (episode != null && from != null && from > 0 && !sub.isSeasonPack) {
      final to = math.max(from, sub.episodeTo ?? from);
      if (episode < from || episode > to) return _Episode.wrong;
      if (from == to) {
        providerExact = true;
      } else {
        providerPack = true;
      }
    }

    var match = false, pack = false, wrong = false;
    for (final i in infos) {
      if (season != null && i.season != null && i.season != season) {
        wrong = true;
      } else if (i.episodes.isNotEmpty && episode != null) {
        if (i.episodes.contains(episode)) {
          match = true;
        } else {
          wrong = true;
        }
      } else if (i.isPack || (i.season != null && i.episodes.isEmpty)) {
        pack = true;
      }
    }
    if (providerExact || match) return _Episode.exact;
    if (wrong && !pack && !providerPack) return _Episode.wrong;
    if (pack || providerPack) return _Episode.pack;
    return _Episode.unverified;
  }

  _Episode _checkMovie(List<ReleaseInfo> infos, int? year, String? title) {
    final withYear = infos.where((i) => i.year != null).toList();
    if (year != null &&
        withYear.isNotEmpty &&
        withYear.every((i) => (i.year! - year).abs() > 1)) {
      return _Episode.wrong;
    }
    // A TV episode offered for a movie.
    if (infos.isNotEmpty && infos.every((i) => i.episodes.isNotEmpty)) {
      return _Episode.wrong;
    }
    // Different titles may be localized ("Origen" for Inception): only a
    // soft signal.
    final want = _tokens(title);
    final withTitle = infos.where((i) => _tokens(i.title).isNotEmpty).toList();
    if (want.isNotEmpty &&
        withTitle.isNotEmpty &&
        withTitle.every((i) => _tokens(i.title).intersection(want).isEmpty)) {
      return _Episode.unverified;
    }
    return _Episode.exact;
  }

  static const _stop = {'the', 'a', 'an', 'of', 'and', 'la', 'le', 'el', 'de'};

  Set<String> _tokens(String? s) => s == null
      ? const {}
      : {
          for (final t in s.toLowerCase().split(
            RegExp(r'[^\p{L}\p{N}]+', unicode: true),
          ))
            if (t.isNotEmpty && !_stop.contains(t)) t,
        };

  static String _fps(double f) =>
      f.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');
}
