import 'package:flutter_test/flutter_test.dart';
import 'package:kinora/core/log.dart';

void main() {
  test('redacts addon config paths and long tokens, keeps info-hashes', () {
    const ih = '0123456789abcdef0123456789abcdef01234567';
    final s = Log.redact(
      'fetch https://torrentio.strem.fun/realdebrid=ABCDEFGHIJKLMNOPQRSTUVWXYZ123456/manifest.json '
      'key=sk_00000000fake0000token0000for0000tests0000000000 ih=$ih',
    );
    expect(s, contains('https://torrentio.strem.fun/…'));
    expect(s, isNot(contains('ABCDEFGHIJKLMNOP')));
    expect(s, isNot(contains('fake0000token')));
    expect(s, contains(ih));
  });

  test('short urls stay readable', () {
    expect(
      Log.redact('GET https://v3-cinemeta.strem.io/manifest.json'),
      'GET https://v3-cinemeta.strem.io/manifest.json',
    );
  });
}
