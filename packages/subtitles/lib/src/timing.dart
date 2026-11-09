import 'dart:math' as math;

import 'document.dart';

/// Result of [checkTiming].
final class TimingReport {
  const TimingReport({
    required this.lastCueEnd,
    required this.videoDuration,
    required this.exceedsDuration,
    required this.endsTooEarly,
  });

  final Duration lastCueEnd;
  final Duration videoDuration;

  /// The last cue ends after the video (wrong cut, wrong FPS or wrong file).
  final bool exceedsDuration;

  /// The subtitle stops long before the video ends (partial or wrong cut).
  final bool endsTooEarly;

  bool get looksFine => !exceedsDuration && !endsTooEarly;

  @override
  bool operator ==(Object other) =>
      other is TimingReport &&
      other.lastCueEnd == lastCueEnd &&
      other.videoDuration == videoDuration &&
      other.exceedsDuration == exceedsDuration &&
      other.endsTooEarly == endsTooEarly;

  @override
  int get hashCode =>
      Object.hash(lastCueEnd, videoDuration, exceedsDuration, endsTooEarly);

  @override
  String toString() =>
      'TimingReport(last ${formatSrtTime(lastCueEnd)} / '
      '${formatSrtTime(videoDuration)}'
      '${exceedsDuration ? ' exceeds' : ''}${endsTooEarly ? ' too-early' : ''})';
}

/// Sanity-checks subtitle length against the video.
///
/// Flags a last cue ending more than [tolerance] after the video, or before
/// [minCoverage] of it (credits rarely take more than 30%).
TimingReport checkTiming(
  List<Cue> cues,
  Duration videoDuration, {
  Duration tolerance = const Duration(seconds: 30),
  double minCoverage = 0.7,
}) {
  final last = cues.isEmpty
      ? Duration.zero
      : cues.map((c) => c.end).reduce((a, b) => a > b ? a : b);
  return TimingReport(
    lastCueEnd: last,
    videoDuration: videoDuration,
    exceedsDuration: last > videoDuration + tolerance,
    endsTooEarly: last < videoDuration * minCoverage,
  );
}

/// Suggested correction: `doc.scale(scale).shift(offset)`.
final class SyncSuggestion {
  const SyncSuggestion({
    required this.offset,
    required this.scale,
    required this.confidence,
    required this.matchedCues,
  });

  /// Shift to apply after [scale].
  final Duration offset;

  /// Time scale factor (1.0 = no FPS drift; 25/23.976 ≈ 1.0427).
  final double scale;

  /// 0..1: share of cues that line up with the reference after correction.
  final double confidence;
  final int matchedCues;

  /// Already in sync (within 150 ms, no drift).
  bool get isInSync =>
      offset.inMilliseconds.abs() < 150 && (scale - 1).abs() < 0.0005;

  @override
  bool operator ==(Object other) =>
      other is SyncSuggestion &&
      other.offset == offset &&
      other.scale == scale &&
      other.confidence == confidence &&
      other.matchedCues == matchedCues;

  @override
  int get hashCode => Object.hash(offset, scale, confidence, matchedCues);

  @override
  String toString() =>
      'SyncSuggestion(offset ${offset.inMilliseconds} ms, '
      'scale ${scale.toStringAsFixed(5)}, '
      'confidence ${confidence.toStringAsFixed(2)}, $matchedCues cues)';
}

/// Frame-rate conversions tried by [estimateSync].
const fpsScales = [
  1.0,
  25 / 23.976,
  23.976 / 25,
  24 / 23.976,
  23.976 / 24,
  25 / 24,
  24 / 25,
];

/// Estimates how to align [subtitle] with [reference] cues (e.g. an
/// embedded track) by cross-correlating cue start times: for each candidate
/// [fpsScales] factor, a histogram of pairwise start differences within
/// [maxOffset] peaks at the constant offset; the best peak is refined with a
/// least-squares fit over matched pairs. Returns null with fewer than
/// [minMatches] aligned cues.
SyncSuggestion? estimateSync(
  List<Cue> subtitle,
  List<Cue> reference, {
  Duration maxOffset = const Duration(minutes: 2),
  int minMatches = 5,
}) {
  final sub = [for (final c in subtitle) c.start.inMilliseconds.toDouble()]
    ..sort();
  final ref = [for (final c in reference) c.start.inMilliseconds.toDouble()]
    ..sort();
  if (sub.length < minMatches || ref.length < minMatches) return null;
  final limit = maxOffset.inMilliseconds.toDouble();

  SyncSuggestion? best;
  for (final scale in fpsScales) {
    final s = [for (final t in sub) t * scale];
    final lag = _peakLag(s, ref, limit);
    if (lag == null) continue;
    final pairs = _pairs(s, ref, lag, 250);
    if (pairs.length < minMatches) continue;
    // Refine: ref ≈ a * s + b over matched pairs.
    var a = 1.0, b = lag;
    if (pairs.length >= 10) {
      final fit = _leastSquares(pairs);
      if ((fit.$1 - 1).abs() < 0.01) (a, b) = fit;
    }
    final refined = [for (final t in s) t * a];
    final matched = _pairs(refined, ref, b, 200).length;
    final confidence = matched / math.min(sub.length, ref.length);
    final candidate = SyncSuggestion(
      offset: Duration(milliseconds: b.round()),
      scale: scale * a,
      confidence: confidence.clamp(0, 1),
      matchedCues: matched,
    );
    // Prefer no FPS change unless another factor is clearly better.
    final margin = best == null || best.scale == 1.0 ? 0.1 : 0.0;
    if (best == null || candidate.confidence > best.confidence + margin) {
      best = candidate;
    }
  }
  return best != null && best.matchedCues >= minMatches ? best : null;
}

/// Most common start difference (ref - sub) in 100 ms bins, smoothed.
double? _peakLag(List<double> sub, List<double> ref, double limit) {
  const bin = 100.0;
  final votes = <int, int>{};
  var lo = 0;
  for (final t in sub) {
    while (lo < ref.length && ref[lo] < t - limit) {
      lo++;
    }
    for (var j = lo; j < ref.length && ref[j] <= t + limit; j++) {
      final k = ((ref[j] - t) / bin).round();
      votes[k] = (votes[k] ?? 0) + 1;
    }
  }
  if (votes.isEmpty) return null;
  int? bestK;
  var bestV = -1;
  for (final k in votes.keys) {
    final v = (votes[k - 1] ?? 0) + 2 * votes[k]! + (votes[k + 1] ?? 0);
    if (v > bestV || (v == bestV && k.abs() < bestK!.abs())) {
      bestV = v;
      bestK = k;
    }
  }
  // Median of the raw differences near the peak.
  final near = <double>[];
  for (final t in sub) {
    for (final r in ref) {
      final d = r - t;
      if ((d - bestK! * bin).abs() <= 1.5 * bin) near.add(d);
    }
  }
  near.sort();
  return near.isEmpty ? bestK! * bin : near[near.length ~/ 2];
}

/// One-to-one pairs (sub, ref) whose difference is within [tol] of [lag].
List<(double, double)> _pairs(
  List<double> sub,
  List<double> ref,
  double lag,
  double tol,
) {
  final out = <(double, double)>[];
  var j = 0;
  for (final t in sub) {
    final target = t + lag;
    while (j < ref.length && ref[j] < target - tol) {
      j++;
    }
    if (j < ref.length && (ref[j] - target).abs() <= tol) {
      out.add((t, ref[j]));
      j++;
    }
  }
  return out;
}

(double, double) _leastSquares(List<(double, double)> pairs) {
  final n = pairs.length.toDouble();
  var sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0;
  for (final (x, y) in pairs) {
    sx += x;
    sy += y;
    sxx += x * x;
    sxy += x * y;
  }
  final den = n * sxx - sx * sx;
  if (den == 0) return (1, (sy - sx) / n);
  final a = (n * sxy - sx * sy) / den;
  return (a, (sy - a * sx) / n);
}
