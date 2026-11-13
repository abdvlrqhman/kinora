import 'package:flutter_test/flutter_test.dart';
import 'package:kinora/services/cast_service.dart';

void main() {
  test('the home network wins over a virtual adapter', () {
    expect(pickLanAddress(['172.20.128.1', '10.1.0.205']), '10.1.0.205');
    expect(
      pickLanAddress(['10.0.0.4', '192.168.1.20', '172.17.0.1']),
      '192.168.1.20',
    );
  });

  test('loopback, link-local and public addresses never count', () {
    expect(pickLanAddress(['127.0.0.1', '169.254.3.4', '8.8.8.8']), isNull);
    expect(pickLanAddress(['172.32.0.1', 'nonsense']), isNull);
  });
}
