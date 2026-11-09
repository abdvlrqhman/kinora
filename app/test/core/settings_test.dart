import 'package:flutter_test/flutter_test.dart';
import 'package:kinora/core/settings.dart';

void main() {
  test('keyless OpenSubtitles is on once for older settings, then theirs', () {
    // Saved before it existed: it turns on, keeping the user's sites.
    final older = AppSettings.fromJson(const {
      'enabledSubtitleProviders': ['subdl'],
    });
    expect(older.enabledSubtitleProviders, ['subdl', freeOpenSubtitlesId]);
    // Turned off later: stays off.
    final off = AppSettings.fromJson(
      older.copyWith(enabledSubtitleProviders: const ['subdl']).toJson(),
    );
    expect(off.enabledSubtitleProviders, ['subdl']);
    expect(const AppSettings().enabledSubtitleProviders, [freeOpenSubtitlesId]);
  });
}
