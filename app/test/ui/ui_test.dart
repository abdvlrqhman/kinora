import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinora/ui/tint.dart';
import 'package:kinora/ui/tokens.dart';
import 'package:kinora/ui/widgets/media.dart';
import 'package:kinora/ui/widgets/states.dart';
import 'package:stremio/stremio.dart';

void main() {
  test('a Blackout label reads on the lit fill of every artwork accent', () {
    for (var hue = 0.0; hue < 360; hue += 5) {
      for (final sat in [0.45, 0.8]) {
        final accent = HSLColor.fromAHSL(1, hue, sat, 0.66).toColor();
        final fill = readableFill(accent, KColors.blackout);
        expect(
          contrastRatio(fill, KColors.blackout),
          greaterThanOrEqualTo(4.5),
          reason: 'hue $hue, saturation $sat',
        );
      }
    }
    // Already readable: left alone.
    expect(readableFill(KColors.marquee, KColors.blackout), KColors.marquee);
    // A light label darkens the fill instead.
    final dark = readableFill(KColors.marquee, KColors.lamp);
    expect(contrastRatio(dark, KColors.lamp), greaterThanOrEqualTo(4.5));
  });

  test('content direction follows the first letter', () {
    expect(contentDir('مسلسل (2023)'), TextDirection.rtl);
    expect(contentDir('(2023) שלום'), TextDirection.rtl);
    expect(contentDir('Harbor Lights'), TextDirection.ltr);
    expect(contentDir('2049 Blade'), TextDirection.ltr);
    expect(contentDir(''), TextDirection.ltr);
  });

  test('errors are plain words, never a link', () {
    final url = Uri.parse('https://addon.test/realdebrid=SECRET/meta.json');
    for (final e in <Object>[
      AddonHttpException(500, url),
      AddonResponseException('Unexpected <html>', uri: url),
      const FormatException('Unexpected character'),
      Exception('Connection closed before full header was received'),
    ]) {
      final text = friendlyError(e);
      expect(text, isNot(contains('http')), reason: '$e');
      expect(text, isNot(contains('SECRET')), reason: '$e');
      expect(text, isNot(contains('Exception')), reason: '$e');
    }
    expect(
      friendlyError(StateError('No source has details for this title.')),
      'No source has details for this title.',
    );
    expect(
      friendlyError(Exception('weird')),
      'Something went wrong. Try again.',
    );
  });
}
