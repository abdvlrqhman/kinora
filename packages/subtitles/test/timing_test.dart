import 'dart:math';

import 'package:subtitles/subtitles.dart';
import 'package:test/test.dart';

/// Irregular, speech-like cue starts over [minutes].
List<Cue> speech(int seed, {int minutes = 40}) {
  final rnd = Random(seed);
  final cues = <Cue>[];
  var t = 5000;
  while (t < minutes * 60000) {
    final len = 800 + rnd.nextInt(3000);
    cues.add(
      Cue(
        start: Duration(milliseconds: t),
        end: Duration(milliseconds: t + len),
        text: 'x',
      ),
    );
    t += len + 200 + rnd.nextInt(4000);
  }
  return cues;
}

List<Cue> transform(
  List<Cue> cues, {
  double scale = 1,
  int offsetMs = 0,
  int jitterMs = 0,
  int seed = 1,
}) {
  final rnd = Random(seed);
  return [
    for (final c in cues)
      if (rnd.nextDouble() > 0.1) // the other track misses ~10% of lines
        Cue(
          start: Duration(
            milliseconds:
                (c.start.inMilliseconds * scale).round() +
                offsetMs +
                rnd.nextInt(jitterMs * 2 + 1) -
                jitterMs,
          ),
          end: Duration(
            milliseconds: (c.end.inMilliseconds * scale).round() + offsetMs,
          ),
          text: c.text,
        ),
  ];
}

void main() {
  group('checkTiming', () {
    final cues = speech(1, minutes: 42);
    test('fits a 45 min episode', () {
      final r = checkTiming(cues, const Duration(minutes: 45));
      expect(r.looksFine, isTrue);
    });
    test('last cue beyond the video', () {
      final r = checkTiming(cues, const Duration(minutes: 30));
      expect(r.exceedsDuration, isTrue);
      expect(r.looksFine, isFalse);
    });
    test('ends far too early', () {
      final r = checkTiming(cues, const Duration(minutes: 90));
      expect(r.endsTooEarly, isTrue);
      expect(r.toString(), contains('too-early'));
    });
    test('empty cue list', () {
      expect(
        checkTiming(const [], const Duration(minutes: 1)).endsTooEarly,
        isTrue,
      );
    });
  });

  group('estimateSync', () {
    final reference = speech(7);

    test('already in sync', () {
      final s = estimateSync(transform(reference, jitterMs: 40), reference)!;
      expect(s.isInSync, isTrue);
      expect(s.confidence, greaterThan(0.8));
    });

    test('constant offset', () {
      // Subtitle shows 2.35 s late: shift it by -2.35 s.
      final late = transform(reference, offsetMs: 2350, jitterMs: 60);
      final s = estimateSync(late, reference)!;
      expect(s.offset.inMilliseconds, closeTo(-2350, 80));
      expect(s.scale, closeTo(1, 0.0005));
      expect(s.confidence, greaterThan(0.8));
    });

    test('23.976 -> 25 fps drift plus offset', () {
      // Subtitle timed for 25 fps playing on 23.976 video: times too short.
      final drifted = transform(
        reference,
        scale: 23.976 / 25,
        offsetMs: -700,
        jitterMs: 40,
      );
      final s = estimateSync(drifted, reference)!;
      expect(s.scale, closeTo(25 / 23.976, 0.001));
      expect(s.confidence, greaterThan(0.8));
      // Applying the suggestion lines the cues up.
      final fixed = SubtitleDocument(
        cues: drifted,
        sourceFormat: SubtitleFormat.srt,
      ).scale(s.scale).shift(s.offset);
      final again = estimateSync(fixed.cues, reference)!;
      expect(again.isInSync, isTrue);
    });

    test('25 -> 23.976 drift', () {
      final drifted = transform(reference, scale: 25 / 23.976, jitterMs: 40);
      final s = estimateSync(drifted, reference)!;
      expect(s.scale, closeTo(23.976 / 25, 0.001));
    });

    test('unrelated tracks or too few cues give low/no confidence', () {
      final other = speech(99);
      final s = estimateSync(other, reference);
      expect(s == null || s.confidence < 0.4, isTrue);
      expect(estimateSync(reference.take(3).toList(), reference), isNull);
    });
  });
}
