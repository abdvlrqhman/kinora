import 'package:dlna/dlna.dart';

/// What the TV is doing.
enum CastPhase { idle, connecting, playing, paused, stopped, lost }

/// Why a cast ended on its own.
enum CastEnd {
  /// The video played to (nearly) its end.
  finished,

  /// The TV stopped mid-video (its remote, or its player quit).
  stoppedOnTv,

  /// The TV's player reported an error mid-video: worth loading it again.
  tvError,

  /// The TV never started the video.
  neverStarted,

  /// The TV stopped answering for too long.
  lost,
}

/// Reads the TV's answers over time. TVs say "stopped" for a moment while
/// they load or buffer, and miss an answer now and then on Wi-Fi: only a
/// stop that lasts, or a long silence, ends the cast.
final class CastTracker {
  CastTracker(this.startedAt, {Duration startAt = Duration.zero})
    : position = startAt,
      seekTarget = startAt > const Duration(seconds: 5) ? startAt : null;

  /// How long the TV may take to start (torrents fetch the file's index).
  static const connectLimit = Duration(seconds: 60);

  /// How long a stop must last to count.
  static const stopConfirm = Duration(seconds: 4);

  /// Silent this long: shown as lost (polling goes on).
  static const lostAfter = Duration(seconds: 20);

  /// Silent this long: the cast is over.
  static const giveUpAfter = Duration(minutes: 2);

  final DateTime startedAt;
  CastPhase phase = CastPhase.connecting;
  Duration position;
  Duration duration = Duration.zero;

  /// No answer just now (shown as "Reconnecting").
  bool reconnecting = false;

  /// The TV has played at least once.
  bool get started => _firstPlay != null;

  /// Where the TV should go once it plays (it ignores seeks before);
  /// positions before it are the TV's start, not news.
  Duration? seekTarget;

  DateTime? _firstPlay;
  DateTime? _lastAnswer;
  DateTime? _stoppedSince;

  /// The TV answered. Returns why the cast ended, or null while it goes on.
  CastEnd? answer(
    TransportState state,
    PositionInfo p,
    DateTime now, {
    bool error = false,
  }) {
    _lastAnswer = now;
    reconnecting = false;
    if (phase == CastPhase.lost) {
      phase = started ? CastPhase.playing : CastPhase.connecting;
    }
    final total = p.trackDuration;
    if (total != null && total > Duration.zero) duration = total;
    final rel = p.relTime;
    final target = seekTarget;
    if (target != null &&
        _firstPlay != null &&
        now.difference(_firstPlay!) > const Duration(seconds: 20)) {
      seekTarget = null; // the TV ignored the seek: believe it
    }
    // Zero is what TVs say while loading and after stopping.
    if (rel != null && rel > Duration.zero) {
      if (seekTarget == null || rel >= target! - const Duration(seconds: 15)) {
        position = rel;
        seekTarget = null;
      }
    }
    switch (state) {
      case TransportState.playing || TransportState.pausedPlayback:
        _stoppedSince = null;
        _firstPlay ??= now;
        phase = state == TransportState.playing
            ? CastPhase.playing
            : CastPhase.paused;
      case TransportState.stopped || TransportState.noMediaPresent:
        if (!started) {
          if (error) return CastEnd.neverStarted;
          return now.difference(startedAt) > connectLimit
              ? CastEnd.neverStarted
              : null;
        }
        final since = _stoppedSince ??= now;
        if (now.difference(since) < stopConfirm) return null;
        if (error) return CastEnd.tvError;
        final nearEnd =
            duration > Duration.zero &&
            duration - position < const Duration(seconds: 60);
        return nearEnd ? CastEnd.finished : CastEnd.stoppedOnTv;
      case TransportState.transitioning || TransportState.unknown:
        _stoppedSince = null; // loading or buffering
        if (!started && now.difference(startedAt) > connectLimit) {
          return CastEnd.neverStarted;
        }
    }
    return null;
  }

  /// The TV didn't answer. Returns [CastEnd.lost] once it's been silent
  /// for too long.
  CastEnd? silence(DateTime now) {
    reconnecting = true;
    final quiet = now.difference(_lastAnswer ?? startedAt);
    if (quiet >= giveUpAfter) return CastEnd.lost;
    if (quiet >= lostAfter) phase = CastPhase.lost;
    return null;
  }
}
