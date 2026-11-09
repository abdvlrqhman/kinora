import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kinora_engine/kinora_engine.dart';

String b(Object v) => latin1.decode(bencode(v));

void main() {
  test('scalars', () {
    expect(b(42), 'i42e');
    expect(b(-3), 'i-3e');
    expect(b(true), 'i1e');
    expect(b('spam'), '4:spam');
    expect(b('é'), '2:${latin1.decode(utf8.encode('é'))}');
    expect(b(Uint8List.fromList([0, 255])), '2:\x00\xff');
  });

  test('lists skip nulls, dicts sort keys and skip null values', () {
    expect(b(<Object?>['a', null, 1]), 'l1:ai1ee');
    expect(b(<String, Object?>{'z': 1, 'a': 'x', 'n': null}), 'd1:a1:x1:zi1ee');
  });

  test('dict keys sort by raw bytes', () {
    expect(
      b(<String, Object?>{'b': 1, 'B': 2, 'a': 3}),
      'd1:Bi2e1:ai3e1:bi1ee',
    );
  });

  test('rejects unsupported values', () {
    expect(() => bencode(1.5), throwsArgumentError);
  });

  test('config map encodes only set keys', () {
    final s = b(const EngineConfig(testMode: true, dht: false).toMap());
    expect(s, 'd3:dhti0e11:listen_porti0e9:test_modei1ee');
  });
}
