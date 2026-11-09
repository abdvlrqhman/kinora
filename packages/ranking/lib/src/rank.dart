import 'dart:math' as math;

import 'package:release_parser/release_parser.dart';

import 'models.dart';
import 'weights.dart';

/// Ranks [candidates] for one movie, or for [episode] of a series.
///
/// Returns every candidate exactly once: playable ones first, best first,
/// then rejected ones (with [RankedCandidate.rejected] set). Gates, applied
/// in order and each only when something passing it survives:
///
/// 1. wrong season / episode (always rejected; names without episode
///    numbers are kept with a warning),
/// 2. not decodable on [RankPrefs.device],
/// 3. not playable on [RankPrefs.castTarget],
/// 4. CAM / TS / TC / SCR.
///
/// Candidates that fail a gate but are kept because nothing better exists
/// get a warning and a penalty. Ties break on availability, then
/// resolution, then [Candidate.id], so the order is deterministic.
List<RankedCandidate> rank(
  List<Candidate> candidates,
  RankPrefs prefs, {
  EpisodeRef? episode,
  RankWeights weights = RankWeights.standard,
}) {
  final evals = [for (final c in candidates) _Eval(c, prefs, episode, weights)];
  for (final e in evals) {
    if (e.wrongEpisode) e.rejected = RejectReason.wrongEpisode;
  }
  _gate(
    evals,
    (e) => e.deviceProblems.isEmpty,
    RejectReason.unplayableOnDevice,
  );
  _gate(evals, (e) => e.tvProblems.isEmpty, RejectReason.unplayableOnTv);
  _gate(evals, (e) => !e.release.source.isPreRelease, RejectReason.preRelease);
  for (final e in evals.where((e) => e.rejected == null)) {
    if (e.deviceProblems.isNotEmpty || e.tvProblems.isNotEmpty) {
      e.score -= weights.keptUnplayablePenalty;
    }
    if (e.release.source.isPreRelease) e.score -= weights.keptPreReleasePenalty;
  }
  evals.sort(_compare);
  return [
    for (final e in evals)
      RankedCandidate(
        candidate: e.candidate,
        score: e.score,
        reasons: e.reasons,
        warnings: e.warnings,
        rejected: e.rejected,
      ),
  ];
}

/// Rejects candidates failing [ok] — but only if at least one passes.
void _gate(List<_Eval> evals, bool Function(_Eval) ok, RejectReason reason) {
  final alive = evals.where((e) => e.rejected == null).toList();
  if (!alive.any(ok)) return;
  for (final e in alive) {
    if (!ok(e)) e.rejected = reason;
  }
}

int _compare(_Eval a, _Eval b) {
  if ((a.rejected == null) != (b.rejected == null)) {
    return a.rejected == null ? -1 : 1;
  }
  final byScore = b.score.compareTo(a.score);
  if (byScore != 0) return byScore;
  final byAvailability = b.availability.compareTo(a.availability);
  if (byAvailability != 0) return byAvailability;
  final byResolution = b.release.resolution.lines.compareTo(
    a.release.resolution.lines,
  );
  if (byResolution != 0) return byResolution;
  return a.candidate.id.compareTo(b.candidate.id);
}

/// Resolution ladder rungs: 480 → 720 → 1080 → 4K → 8K.
const _rung = {
  Resolution.p480: 0.0,
  Resolution.p576: 0.5,
  Resolution.p720: 1.0,
  Resolution.p1080: 2.0,
  Resolution.p1440: 2.5,
  Resolution.p2160: 3.0,
  Resolution.p4320: 4.0,
};

/// Scores one candidate and collects its reasons / warnings.
final class _Eval {
  _Eval(this.candidate, RankPrefs prefs, EpisodeRef? episode, RankWeights w)
    : release = candidate.release {
    final r = release;
    final instant = candidate.isDebridCached || r.debridCached == true;

    // Episode validation.
    if (episode != null) {
      if (r.hasEpisodeInfo) {
        wrongEpisode = !coversEpisode(
          r,
          season: episode.season,
          episode: episode.episode,
          absoluteEpisode: episode.absolute,
        );
      } else {
        _warn(RankWarningKind.episodeUnconfirmed, 'Episode not confirmed');
        _penalty += w.episodeUnconfirmedPenalty;
      }
      if ((r.isSeasonPack || r.isCompleteSeries) &&
          !instant &&
          !candidate.isDirectUrl) {
        _warn(RankWarningKind.pack, 'Season pack (slower start)');
        _penalty += w.packPenalty;
      }
    }

    // Playability.
    deviceProblems = _problems(r, prefs.device, 'on this device');
    for (final p in deviceProblems) {
      _warn(RankWarningKind.unplayableOnDevice, p);
    }
    final tv = prefs.castTarget;
    tvProblems = tv == null ? const [] : _problems(r, tv, 'on TV');
    for (final p in tvProblems) {
      _warn(RankWarningKind.unplayableOnTv, p);
    }
    if (r.source.isPreRelease) {
      _warn(RankWarningKind.preRelease, 'Cinema recording (${r.source.label})');
    }

    // Quality.
    final quality =
        w.resolutionShare * _resolutionFit(r.resolution, _target(prefs), w) +
        (1 - w.resolutionShare) * (w.sourceScores[r.source] ?? w.neutral);
    if (r.quality.isNotEmpty) _reason(RankReasonKind.quality, r.quality);

    // Availability.
    if (instant) {
      availability = 1;
      _reason(RankReasonKind.availability, 'Instant (debrid)');
    } else if (candidate.isDirectUrl) {
      availability = 1;
      _reason(RankReasonKind.availability, 'Direct link');
    } else {
      final seeds =
          candidate.live?.seeders ?? candidate.addonSeeders ?? r.seeders;
      if (seeds == null) {
        availability = w.unknownSeedsAvailability;
        _warn(RankWarningKind.unknownSeeds, 'Seeds unknown');
      } else {
        availability = math.min(
          1,
          math.log(1 + math.max(0, seeds)) / math.log(1 + w.seedSaturation),
        );
        if (candidate.live == null) availability *= w.addonSeedTrust;
        if (seeds <= 0) {
          _warn(RankWarningKind.noSeeds, 'No seeds');
        } else if (seeds < w.fewSeeds) {
          _warn(RankWarningKind.fewSeeds, 'Few seeds');
        } else {
          _reason(RankReasonKind.availability, '$seeds seeds');
        }
      }
    }

    final subtitles = _subtitleFit(prefs, w);
    final audio = _audioFit(prefs, w);

    if (tv != null && tvProblems.isEmpty) {
      _reason(RankReasonKind.castable, 'Plays on TV');
    }

    // HDR on the screen that will show it.
    final display = tv ?? prefs.device;
    final hdr10 =
        r.hdr.contains(HdrFormat.hdr10) || r.hdr.contains(HdrFormat.hdr10Plus);
    if (r.hdr.contains(HdrFormat.dolbyVision) && display.dolbyVision) {
      _bonus += w.hdrBonus + w.dolbyVisionBonus;
      _reason(RankReasonKind.hdr, 'Dolby Vision');
    } else if (hdr10 && display.hdr10) {
      _bonus += w.hdrBonus;
      _reason(RankReasonKind.hdr, 'HDR');
    } else if (r.hdr.isNotEmpty && !display.hdr10) {
      _penalty += w.hdrOnSdrPenalty;
      _warn(RankWarningKind.hdrOnSdr, 'HDR on a non-HDR screen');
    }

    if (r.proper || r.repack) {
      _bonus += w.properBonus;
      _reason(RankReasonKind.fix, r.proper ? 'PROPER' : 'REPACK');
    }

    _bitrate(prefs, w);

    score =
        w.availability * availability +
        w.quality * quality +
        w.audioLanguage * audio +
        w.subtitles * subtitles +
        _bonus -
        _penalty;
  }

  final Candidate candidate;
  final ParsedRelease release;
  final reasons = <RankReason>[];
  final warnings = <RankWarning>[];
  bool wrongEpisode = false;
  List<String> deviceProblems = const [];
  List<String> tvProblems = const [];
  double availability = 0;
  double score = 0;
  RejectReason? rejected;
  double _bonus = 0;
  double _penalty = 0;

  void _reason(RankReasonKind kind, String label) =>
      reasons.add(RankReason(kind, label));

  void _warn(RankWarningKind kind, String label) =>
      warnings.add(RankWarning(kind, label));

  double _audioFit(RankPrefs prefs, RankWeights w) {
    final r = release;
    final original = prefs.originalLanguage;
    final wanted = prefs.audioLanguages.isNotEmpty
        ? prefs.audioLanguages
        : [?original];
    final effective = {...r.languages};
    if (original != null &&
        ((r.languages.isEmpty && !r.dubbed) || r.multiAudio || r.dualAudio)) {
      effective.add(original);
    }
    if (wanted.isEmpty || effective.isEmpty) return w.neutral;
    for (var i = 0; i < wanted.length; i++) {
      final lang = wanted[i];
      if (!effective.contains(lang)) continue;
      if (r.languages.contains(lang) && lang != original) {
        _reason(RankReasonKind.audioLanguage, '${languageName(lang)} audio');
      }
      return _decay(i, w);
    }
    if (r.dubbed || (original != null && !effective.contains(original))) {
      _warn(RankWarningKind.dubbed, 'Dubbed audio');
    }
    return w.noAudioMatch;
  }

  double _subtitleFit(RankPrefs prefs, RankWeights w) {
    final r = release;
    final wanted = prefs.subtitleLanguages;
    var best = 0.0, bestFit = 0.0;
    String? bestLang;
    var bestEmbedded = false;
    for (var i = 0; i < wanted.length; i++) {
      final external = candidate.subtitleFit[wanted[i]] ?? 0;
      final embedded = r.subtitleLanguages.contains(wanted[i])
          ? w.embeddedSubtitleFit
          : 0.0;
      final fit = math.max(external, embedded);
      if (_decay(i, w) * fit > best) {
        best = _decay(i, w) * fit;
        bestFit = fit;
        bestLang = wanted[i];
        bestEmbedded = embedded > external;
      }
    }
    if (bestLang != null && bestFit >= w.subtitleMatchThreshold) {
      _reason(
        RankReasonKind.subtitles,
        '${languageName(bestLang)} subtitles ${bestEmbedded ? 'included' : 'match'}',
      );
    }
    if (r.hardcodedSubs &&
        !(wanted.isNotEmpty && r.subtitleLanguages.contains(wanted.first))) {
      _penalty += w.unwantedHardsubPenalty;
      _warn(RankWarningKind.hardcodedSubs, 'Hardcoded subtitles');
    }
    return best;
  }

  void _bitrate(RankPrefs prefs, RankWeights w) {
    final r = release;
    final size = candidate.sizeBytes ?? r.sizeBytes;
    final minutes = prefs.runtimeMinutes;
    // A pack's size without a file index is the whole pack, not this file.
    final packSize =
        (r.isSeasonPack || r.isCompleteSeries) && candidate.fileIndex == null;
    if (size == null || minutes == null || minutes <= 0 || packSize) return;
    final rate = size / (minutes * 60);
    final bandwidth = prefs.bandwidthBytesPerSec;
    if (bandwidth != null && bandwidth > 0) {
      final excess = rate / (bandwidth * w.streamHeadroom) - 1;
      if (excess > 0) {
        _penalty += math.min(
          w.largeFileMaxPenalty,
          excess * w.largeFilePenaltyPerExcess,
        );
        _warn(RankWarningKind.largeForConnection, 'Large for your connection');
      }
    }
    final floor = w.minBytesPerSecond[r.resolution];
    if (floor != null && rate < floor) {
      _penalty += w.tinyFilePenalty;
      _warn(RankWarningKind.tinyFile, 'Suspiciously small file');
    }
    if (prefs.dataSaver && rate > w.dataSaverBytesPerSecond) {
      _penalty += w.dataSaverPenalty;
      _warn(RankWarningKind.dataHeavy, 'Uses a lot of data');
    }
  }
}

double _decay(int i, RankWeights w) =>
    i < w.languageDecay.length ? w.languageDecay[i] : w.languageDecay.last;

/// Resolution the user can actually use: min of preference, device, TV;
/// 720p in data-saver mode.
Resolution _target(RankPrefs prefs) {
  var target = prefs.maxResolution == Resolution.unknown
      ? Resolution.p4320
      : prefs.maxResolution;
  for (final cap in [
    prefs.device.maxResolution,
    prefs.castTarget?.maxResolution,
  ]) {
    if (cap != null && cap != Resolution.unknown && cap.lines < target.lines) {
      target = cap;
    }
  }
  if (prefs.dataSaver && target.lines > 720) target = Resolution.p720;
  return target;
}

double _resolutionFit(Resolution res, Resolution target, RankWeights w) {
  final have = _rung[res];
  if (have == null) return w.unknownResolutionFit;
  final want = _rung[target]!;
  final fit = have <= want
      ? 1 - w.resolutionStepBelow * (want - have)
      : 1 - w.resolutionStepAbove * (have - want);
  return fit.clamp(0, 1).toDouble();
}

/// Why [r] can't play on [caps] (empty when it can).
List<String> _problems(ParsedRelease r, DeviceCaps caps, String where) {
  final hdr10 =
      r.hdr.contains(HdrFormat.hdr10) || r.hdr.contains(HdrFormat.hdr10Plus);
  final firstAudio = r.audioCodecs.isEmpty ? null : r.audioCodecs.first;
  final container = r.container;
  return [
    if (caps.maxResolution != Resolution.unknown &&
        r.resolution.lines > caps.maxResolution.lines)
      "${r.resolution.label} won't play $where",
    if (r.videoCodec == VideoCodec.h265 && !caps.h265)
      "HEVC won't play $where"
    else if (r.videoCodec == VideoCodec.h265 && r.isTenBit && !caps.h265TenBit)
      "10-bit HEVC won't play $where",
    if (r.videoCodec == VideoCodec.av1 && !caps.av1) "AV1 won't play $where",
    if (r.hdr.contains(HdrFormat.dolbyVision) && !hdr10 && !caps.dolbyVision)
      "Dolby Vision won't display $where",
    if (firstAudio != null &&
        caps.audio.isNotEmpty &&
        !caps.audio.contains(firstAudio))
      "${firstAudio.label} audio won't play $where",
    if (container != null &&
        caps.containers.isNotEmpty &&
        !caps.containers.contains(container))
      "${container.toUpperCase()} won't play $where",
  ];
}
