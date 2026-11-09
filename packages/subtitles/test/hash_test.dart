import 'dart:typed_data';

import 'package:subtitles/subtitles.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('documented vector: breakdance.avi -> 8e245d9679d31e12', () {
    // First and last 64 KiB of the official test file (12,909,756 bytes).
    expect(
      osHash(
        12909756,
        fixtureBytes('hash/breakdance_head.bin'),
        fixtureBytes('hash/breakdance_tail.bin'),
      ),
      '8e245d9679d31e12',
    );
  });

  test('64-bit wrap-around and zero padding', () {
    final ones = Uint8List(osHashChunkSize)
      ..fillRange(0, osHashChunkSize, 0xFF);
    // 2 * 8192 words of 0xFFFF...FF = -16384 (mod 2^64), plus the size.
    expect(osHash(16384, ones, ones), '0000000000000000');
    expect(osHash(0, Uint8List(0), Uint8List(0)), '0000000000000000');
    expect(osHash(131072, Uint8List(0), Uint8List(0)), '0000000000020000');
    final short = Uint8List.fromList([1, 0, 0, 0, 0, 0, 0, 0, 2]);
    expect(osHash(9, short, short), '000000000000000f');
  });
}
