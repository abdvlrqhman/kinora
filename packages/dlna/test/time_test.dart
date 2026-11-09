import 'package:dlna/dlna.dart';
import 'package:test/test.dart';

void main() {
  group('parseDlnaTime', () {
    test('H:MM:SS and HH:MM:SS', () {
      expect(
        parseDlnaTime('0:42:10'),
        const Duration(minutes: 42, seconds: 10),
      );
      expect(
        parseDlnaTime('01:02:03'),
        const Duration(hours: 1, minutes: 2, seconds: 3),
      );
      expect(parseDlnaTime('123:00:00'), const Duration(hours: 123));
    });

    test('decimal and rational fractions', () {
      expect(parseDlnaTime('0:00:01.500'), const Duration(milliseconds: 1500));
      expect(parseDlnaTime('0:00:01.5'), const Duration(milliseconds: 1500));
      expect(
        parseDlnaTime('0:00:00.1234567'),
        const Duration(microseconds: 123456),
      );
      expect(parseDlnaTime('0:00:02.1/4'), const Duration(milliseconds: 2250));
      expect(parseDlnaTime('0:00:02.1/0'), isNull);
    });

    test('NOT_IMPLEMENTED, empty and garbage are null', () {
      expect(parseDlnaTime('NOT_IMPLEMENTED'), isNull);
      expect(parseDlnaTime(''), isNull);
      expect(parseDlnaTime(null), isNull);
      expect(parseDlnaTime('12:34'), isNull);
      expect(parseDlnaTime('a:bb:cc'), isNull);
    });

    test('tolerates whitespace and a leading +', () {
      expect(parseDlnaTime(' +0:00:05 '), const Duration(seconds: 5));
    });
  });

  group('formatDlnaTime', () {
    test('H:MM:SS', () {
      expect(formatDlnaTime(Duration.zero), '0:00:00');
      expect(
        formatDlnaTime(
          const Duration(minutes: 42, seconds: 10, milliseconds: 999),
        ),
        '0:42:10',
      );
      expect(
        formatDlnaTime(const Duration(hours: 12, minutes: 3, seconds: 4)),
        '12:03:04',
      );
    });

    test('H:MM:SS.mmm', () {
      expect(
        formatDlnaTime(
          const Duration(hours: 1, minutes: 2, seconds: 3, milliseconds: 45),
          withMillis: true,
        ),
        '1:02:03.045',
      );
    });

    test('negative clamps to zero', () {
      expect(formatDlnaTime(const Duration(seconds: -3)), '0:00:00');
    });

    test('round-trips', () {
      const d = Duration(hours: 2, minutes: 5, seconds: 59, milliseconds: 120);
      expect(parseDlnaTime(formatDlnaTime(d, withMillis: true)), d);
    });
  });
}
