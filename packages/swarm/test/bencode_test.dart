import 'dart:convert';
import 'dart:typed_data';

import 'package:swarm/src/bencode.dart';
import 'package:test/test.dart';

import 'fake_trackers.dart';

Object decode(String s) => bdecode(Uint8List.fromList(latin1.encode(s)));

void main() {
  test('ints, strings, lists, dicts', () {
    expect(decode('i42e'), 42);
    expect(decode('i-3e'), -3);
    expect(decode('4:spam'), utf8.encode('spam'));
    expect(decode('l4:spami7ee'), [utf8.encode('spam'), 7]);
    expect(decode('d3:cow3:moo4:spaml1:a1:bee'), {
      'cow': utf8.encode('moo'),
      'spam': [utf8.encode('a'), utf8.encode('b')],
    });
  });

  test('binary info hash keys survive via latin1', () {
    final key = List<int>.generate(20, (i) => 0xf0 + (i % 16));
    final data = Uint8List.fromList(
      bencode({
        'files': {
          key: {'complete': 5, 'downloaded': 9, 'incomplete': 1},
        },
      }),
    );
    final files =
        (bdecode(data) as Map<String, Object>)['files']! as Map<String, Object>;
    expect(latin1.encode(files.keys.single), key);
  });

  test('malformed input throws FormatException', () {
    for (final bad in [
      '',
      'i42',
      'ixe',
      '5:abc',
      'l4:spam',
      'd3:cow',
      'i1ei2e',
      '-1:a',
    ]) {
      expect(() => decode(bad), throwsFormatException, reason: bad);
    }
    expect(() => decode('${'l' * 100}${'e' * 100}'), throwsFormatException);
  });
}
