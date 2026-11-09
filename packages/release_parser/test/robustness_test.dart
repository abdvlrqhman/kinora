import 'dart:math';

import 'package:release_parser/release_parser.dart';
import 'package:test/test.dart';

void main() {
  test('never throws on random or hostile input', () {
    final rnd = Random(42);
    const alphabet = 'aZ09 .-_[]()+:~/|SsEex5\u{1F1EC}\u{1F1E7}💾👤⚙️';
    final chars = alphabet.runes.toList();
    for (var i = 0; i < 3000; i++) {
      final s = String.fromCharCodes([
        for (var j = rnd.nextInt(60); j > 0; j--)
          chars[rnd.nextInt(chars.length)],
      ]);
      expect(() => parseRelease(s), returnsNormally, reason: s);
      expect(
        () => parseAddonStream(name: s, title: s, description: s),
        returnsNormally,
        reason: s,
      );
    }
    for (final s in [
      '-',
      '[',
      ']',
      '[]',
      '.',
      '..',
      'S',
      'S01E',
      'x',
      '-[',
      '.mkv',
      'www.',
      '[ab',
      '1-',
    ]) {
      expect(() => parseRelease(s), returnsNormally, reason: s);
    }
  });
}
