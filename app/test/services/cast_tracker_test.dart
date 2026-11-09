import 'package:dlna/dlna.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinora/services/cast_tracker.dart';

void main() {
  final t0 = DateTime(2026, 11, 9, 20);
  DateTime at(int s) => t0.add(Duration(seconds: s));
  PositionInfo pos(int s, {int total = 2851}) => PositionInfo(
    relTime: Duration(seconds: s),
    trackDuration: Duration(seconds: total),
  );
  const playing = TransportState.playing;
  const stopped = TransportState.stopped;

  test('the stop TVs report while loading is not an end', () {
    final t = CastTracker(t0);
    expect(t.answer(stopped, pos(0), at(1)), isNull);
    expect(t.answer(TransportState.transitioning, pos(0), at(20)), isNull);
    expect(t.phase, CastPhase.connecting);
    expect(t.answer(playing, pos(1), at(25)), isNull);
    expect(t.phase, CastPhase.playing);
  });

  test('a TV that never plays ends the cast after a minute', () {
    final t = CastTracker(t0);
    expect(t.answer(stopped, pos(0), at(59)), isNull);
    expect(t.answer(stopped, pos(0), at(61)), CastEnd.neverStarted);
    // An error lingering from before a reload gets 10 s to clear.
    final failed = CastTracker(t0);
    expect(failed.answer(stopped, pos(0), at(1), error: true), isNull);
    expect(failed.answer(stopped, pos(0), at(8), error: true), isNull);
    expect(
      failed.answer(stopped, pos(0), at(12), error: true),
      CastEnd.neverStarted,
    );
    final cleared = CastTracker(t0)
      ..answer(stopped, pos(0), at(1), error: true);
    expect(cleared.answer(playing, pos(1), at(5)), isNull);
    expect(cleared.phase, CastPhase.playing);
  });

  test('a short stop mid-video is ridden out; a lasting one ends it', () {
    final t = CastTracker(t0)..answer(playing, pos(600), at(1));
    expect(t.answer(stopped, pos(0), at(10)), isNull);
    expect(t.answer(stopped, pos(0), at(12)), isNull);
    expect(t.answer(playing, pos(611), at(13)), isNull);
    expect(t.answer(stopped, pos(0), at(20)), isNull);
    expect(t.answer(stopped, pos(0), at(25)), CastEnd.stoppedOnTv);
    expect(t.position, const Duration(seconds: 611), reason: 'zero ignored');
  });

  test('a lasting stop near the end is the end; with an error, a TV error', () {
    final end = CastTracker(t0)..answer(playing, pos(2820), at(1));
    end.answer(stopped, pos(0), at(2));
    expect(end.answer(stopped, pos(0), at(7)), CastEnd.finished);
    final error = CastTracker(t0)..answer(playing, pos(900), at(1));
    error.answer(stopped, pos(0), at(2), error: true);
    expect(error.answer(stopped, pos(0), at(7), error: true), CastEnd.tvError);
    // Stalling in the credits is still the end, not a failure.
    final credits = CastTracker(t0)..answer(playing, pos(2820), at(1));
    credits.answer(stopped, pos(0), at(2), error: true);
    expect(
      credits.answer(stopped, pos(0), at(7), error: true),
      CastEnd.finished,
    );
  });

  test('silence: reconnecting, then lost, back when the TV answers, over after 2 min', () {
    final t = CastTracker(t0)..answer(playing, pos(100), at(1));
    expect(t.silence(at(6)), isNull);
    expect(t.reconnecting, isTrue);
    expect(t.phase, CastPhase.playing);
    expect(t.silence(at(22)), isNull);
    expect(t.phase, CastPhase.lost);
    expect(t.answer(TransportState.transitioning, pos(101), at(30)), isNull);
    expect(t.phase, CastPhase.playing);
    expect(t.reconnecting, isFalse);
    expect(t.silence(at(100)), isNull);
    expect(t.silence(at(151)), CastEnd.lost);
  });

  test('positions before the seek lands are the TV starting, not news', () {
    final t = CastTracker(t0, startAt: const Duration(minutes: 23));
    expect(t.seekTarget, const Duration(minutes: 23));
    t.answer(playing, pos(2), at(3));
    expect(t.position, const Duration(minutes: 23));
    t.answer(playing, pos(23 * 60 + 1), at(5));
    expect(t.position, const Duration(minutes: 23, seconds: 1));
    expect(t.seekTarget, isNull);
    // A TV that ignored the seek: believed after 20 s.
    final stubborn = CastTracker(t0, startAt: const Duration(minutes: 23));
    stubborn.answer(playing, pos(2), at(3));
    stubborn.answer(playing, pos(30), at(30));
    expect(stubborn.position, const Duration(seconds: 30));
  });
}
