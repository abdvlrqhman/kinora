import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kinora/features/updates/update_prompt.dart';
import 'package:kinora/services/updates.dart';

Map<String, Object?> _release(String tag) => {
  'tag_name': tag,
  'html_url': 'https://github.com/abdvlrqhman/kinora/releases/tag/$tag',
  'draft': false,
  'body': '### Kinora 0.1.8: things\n\n- One\n- Two\n',
  'assets': [
    for (final name in [
      'Kinora-arm64-v8a-release.apk',
      'Kinora-armeabi-v7a-release.apk',
      'Kinora.ipa',
    ])
      {
        'name': name,
        'browser_download_url':
            'https://github.com/abdvlrqhman/kinora/releases/download/$tag/$name',
      },
  ],
};

void main() {
  test('versions compare by number, not text', () {
    expect(isNewer('0.1.8', '0.1.7'), isTrue);
    expect(isNewer('0.1.10', '0.1.9'), isTrue);
    expect(isNewer('0.2.0', '0.1.99'), isTrue);
    expect(isNewer('0.1.7', '0.1.7'), isFalse);
    expect(isNewer('0.1.6', '0.1.7'), isFalse);
    expect(isNewer('1.0', '0.9.9'), isTrue);
  });

  test('a release gives its version, notes and the right files', () {
    final r = KinoraRelease.fromJson(_release('v0.1.8'))!;
    expect(r.version, '0.1.8');
    expect(r.notes, contains('- One'));
    expect(r.apkFor(arm64: true).toString(), endsWith('arm64-v8a-release.apk'));
    expect(
      r.apkFor(arm64: false).toString(),
      endsWith('armeabi-v7a-release.apk'),
    );
    expect(r.ipa.toString(), endsWith('Kinora.ipa'));
    expect(
      KinoraRelease.fromJson({..._release('v1.0.0'), 'draft': true}),
      isNull,
    );
  });

  test('only a newer release is offered, and offline means quiet', () async {
    MockClient answering(Map<String, Object?> j) =>
        MockClient((_) async => http.Response(jsonEncode([j]), 200));
    expect(
      (await newerRelease(answering(_release('v0.1.8')), '0.1.7'))?.version,
      '0.1.8',
    );
    expect(await newerRelease(answering(_release('v0.1.7')), '0.1.7'), isNull);
    final offline = MockClient((_) async => throw Exception('no network'));
    expect(await newerRelease(offline, '0.1.7'), isNull);
    final limited = MockClient((_) async => http.Response('{}', 403));
    expect(await newerRelease(limited, '0.1.7'), isNull);
  });

  test('skipped versions keep their news; pre-releases are left out', () async {
    Map<String, Object?> at(String tag, String body, {bool pre = false}) => {
      ..._release(tag),
      'body': body,
      'prerelease': pre,
    };
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode([
          at('v0.1.11', '### Kinora 0.1.11: next\n\nC\n'),
          // Edited to repeat the one before: shown once.
          at(
            'v0.1.10',
            '### Kinora 0.1.9: cast\n\nA\n\n### Kinora 0.1.10: version\n\nB\n',
          ),
          at('v0.1.9', '### Kinora 0.1.9: cast\n\nA\n', pre: true),
          at('v0.1.8', '### Kinora 0.1.8: old\n\nZ\n'),
        ]),
        200,
      ),
    );
    final r = (await newerRelease(client, '0.1.8'))!;
    expect(r.version, '0.1.11');
    expect(r.ipa.toString(), endsWith('/v0.1.11/Kinora.ipa'));
    expect(
      r.notes,
      '### Kinora 0.1.9: cast\n\nA\n\n'
      '### Kinora 0.1.10: version\n\nB\n\n'
      '### Kinora 0.1.11: next\n\nC',
    );
    expect(await newerRelease(client, '0.1.11'), isNull);
  });

  test('changelog lines wrapped by the commit are joined back', () {
    const notes =
        '### Kinora 0.1.6: wider player\n\n'
        '- Cast and Lock sit at the right edge again: the\n'
        '  chip ended early.\n'
        '- **Plain** `copy`.\n\n'
        '### Kinora 0.1.7: polish\n\nOne paragraph\nwrapped twice.\n';
    expect(Changelog.parse(notes), [
      (true, 'Kinora 0.1.6: wider player'),
      (
        false,
        '•  Cast and Lock sit at the right edge again: the chip ended early.',
      ),
      (false, '•  Plain copy.'),
      (true, 'Kinora 0.1.7: polish'),
      (false, 'One paragraph wrapped twice.'),
    ]);
  });
}
