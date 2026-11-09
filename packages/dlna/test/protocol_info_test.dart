import 'package:dlna/dlna.dart';
import 'package:test/test.dart';

import 'support/fake_samsung_dmr.dart';

void main() {
  test('parses a Sink list', () {
    final list = ProtocolInfo.parseList('$samsungSink,garbage,,');
    expect(list, hasLength(15));
    expect(list.first.mimeType, 'video/x-matroska');
    expect(list.first.dlnaProfile, isNull);
    final avc = list.firstWhere((p) => p.dlnaProfile == 'AVC_MP4_HP_HD_AAC');
    expect(avc.protocol, 'http-get');
    expect(avc.network, '*');
    expect('$avc', 'http-get:*:video/mp4:DLNA.ORG_PN=AVC_MP4_HP_HD_AAC');
    expect(ProtocolInfo.parse('$avc'), avc);
  });

  test('DLNA.ORG_PN among other parameters', () {
    expect(
      ProtocolInfo.parse(
        'http-get:*:video/mpeg:DLNA.ORG_OP=01;DLNA.ORG_PN=MPEG_TS_HD_NA;DLNA.ORG_CI=0',
      ).dlnaProfile,
      'MPEG_TS_HD_NA',
    );
    expect(() => ProtocolInfo.parse('http-get:*'), throwsFormatException);
  });
}
