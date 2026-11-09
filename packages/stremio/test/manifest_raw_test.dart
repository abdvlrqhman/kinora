import 'dart:convert';

import 'package:stremio/stremio.dart';
import 'package:test/test.dart';

void main() {
  test('manifest keeps its raw JSON so apps can persist and re-parse it', () {
    final source = {
      'id': 'org.example.addon',
      'version': '1.2.3',
      'name': 'Example',
      'resources': ['stream'],
      'types': ['movie'],
    };
    final parsed = AddonManifest.fromJson(source);
    final again = AddonManifest.fromJson(jsonDecode(jsonEncode(parsed.raw)));
    expect(again.id, 'org.example.addon');
    expect(again.version, '1.2.3');
    expect(again.resources.single.name, 'stream');
  });
}
