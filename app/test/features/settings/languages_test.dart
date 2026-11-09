import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinora/core/settings.dart';

import 'settings_harness.dart';

Future<void> _addLanguage(
  WidgetTester tester,
  String query,
  String name,
) async {
  await tester.tap(find.textContaining(RegExp('^Add (a|another) language')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const ValueKey('language-search')), query);
  await tester.pumpAndSettle();
  await tester.tap(find.bySemanticsLabel(RegExp('^$name')).first);
  await tester.pumpAndSettle();
}

void main() {
  kitTest('builds an ordered subtitle language list from the full list', (
    tester,
  ) async {
    final kit = await pumpKit(
      tester,
      location: '/settings/languages',
      size: const Size(390, 1600),
    );
    await tester.pumpAndSettle();
    await _addLanguage(tester, 'arab', 'Arabic');
    await _addLanguage(tester, 'English', 'English');
    // Native names are searchable too.
    await _addLanguage(tester, 'Français', 'French');
    expect(kit.settings.subtitleLanguages, ['ar', 'en', 'fr']);
    expect(find.text('العربية'), findsOneWidget);

    // Drag French to the top.
    final handle = find.byIcon(Icons.drag_handle_rounded).last;
    final drag = await tester.startGesture(tester.getCenter(handle));
    for (var i = 0; i < 12; i++) {
      await drag.moveBy(const Offset(0, -12));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await drag.up();
    await tester.pumpAndSettle();
    expect(kit.settings.subtitleLanguages.first, 'fr');

    await tester.tap(find.bySemanticsLabel('Remove English'));
    await tester.pumpAndSettle();
    expect(kit.settings.subtitleLanguages, isNot(contains('en')));

    // Subtitle mode and audio.
    await tester.tap(find.bySemanticsLabel(RegExp('^Forced only')));
    await tester.pumpAndSettle();
    expect(kit.settings.subtitleMode, SubtitleMode.forcedOnly);
    expect(
      find.bySemanticsLabel(
        'Forced only. Only signs and lines spoken in another language.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.bySemanticsLabel(RegExp('^Dubbed')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('language-search')),
      'spanish',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel(RegExp('^Spanish')).first);
    await tester.pumpAndSettle();
    expect(kit.settings.audioLanguages, ['es', 'original']);
    expect(find.text('Dubbed in Spanish'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel(RegExp('^Original language')));
    await tester.pumpAndSettle();
    expect(kit.settings.audioLanguages, ['original']);

    await tester.tap(
      find.text('Prefer subtitles for the deaf and hard of hearing'),
    );
    await tester.pumpAndSettle();
    expect(kit.settings.preferHearingImpaired, isTrue);
  });

  kitTest('subtitle style previews live and saves', (tester) async {
    final kit = await pumpKit(
      tester,
      location: '/settings/languages/style',
      size: const Size(390, 1400),
    );
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Preview of your subtitle style'), findsOne);

    await tester.tap(find.bySemanticsLabel('Yellow'));
    await tester.tap(find.text('Bold'));
    await tester.tap(find.text('Outline'));
    await tester.pumpAndSettle();
    var style = kit.settings.subtitleStyle;
    expect(style.color, 0xFFFFE45E);
    expect(style.bold, isTrue);
    expect(style.outline, isFalse);

    // Dragging the size slider to the far right saves 200%.
    await tester.drag(find.byType(Slider).first, const Offset(400, 0));
    await tester.pumpAndSettle();
    expect(kit.settings.subtitleStyle.scale, 2);
    expect(find.text('200%'), findsOneWidget);

    await tester.tap(find.text('Reset to default'));
    await tester.pumpAndSettle();
    style = kit.settings.subtitleStyle;
    expect(style, const SubtitleStyle());
  });
}
