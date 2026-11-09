import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinora/app/providers.dart';
import 'package:kinora/core/secure_keys.dart';
import 'package:kinora/core/settings.dart';
import 'package:kinora/features/settings/subtitle_sites.dart';
import 'package:kinora/services/subtitles_service.dart';
import 'package:kinora/ui/theme.dart';
import 'package:subtitles/subtitles.dart';

import 'settings_harness.dart';

/// A provider that answers a search with [results] or throws [error].
final class _FakeProvider extends Fake implements SubtitleProvider {
  _FakeProvider(this.id, {this.error});

  @override
  final String id;
  final SubtitleException? error;
  SubtitleQuery? asked;

  @override
  Set<ProviderCapability> get capabilities => const {};

  @override
  Future<List<SubtitleResult>> search(
    SubtitleQuery query, {
    CancelToken? cancel,
  }) async {
    asked = query;
    if (error != null) throw error!;
    return [
      for (var i = 0; i < 3; i++)
        SubtitleResult(
          providerId: id,
          id: '$i',
          language: Language.of('en'),
          releaseNames: const ['The.Shawshank.Redemption.1994.1080p.BluRay'],
        ),
    ];
  }
}

void main() {
  kitTest('a key is required, saved securely, and forgotten when off', (
    tester,
  ) async {
    final kit = await pumpKit(tester, location: '/settings/subtitle-sites');
    await tester.pumpAndSettle();
    expect(kit.settings.enabledSubtitleProviders, isEmpty);

    await tester.tap(find.text('SubDL'));
    await tester.pumpAndSettle();
    expect(
      find.text('Get your API key at subdl.com › Account › API.'),
      findsOne,
    );
    await tester.tap(find.text('Save and turn on'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your API key to turn on SubDL.'), findsOneWidget);
    expect(kit.settings.enabledSubtitleProviders, isEmpty);

    await tester.enterText(find.byKey(const ValueKey('key-subdl')), ' abc123 ');
    await tester.tap(find.text('Save and turn on'));
    await tester.pumpAndSettle();
    expect(kit.settings.enabledSubtitleProviders, ['subdl']);
    final saved = jsonDecode(kit.storage.values['provider.subdl']!) as Map;
    expect(saved['apiKey'], 'abc123');
    expect(find.textContaining('Your key is saved on this phone.'), findsOne);
    // The key never shows again.
    expect(find.text('abc123'), findsNothing);

    await tester.tap(find.text('SubDL'));
    await tester.pumpAndSettle();
    expect(kit.settings.enabledSubtitleProviders, isEmpty);
    expect(kit.storage.values, isEmpty);
  });

  kitTest('OpenSubtitles takes both username and password or neither', (
    tester,
  ) async {
    final kit = await pumpKit(
      tester,
      location: '/settings/subtitle-sites',
      size: const Size(390, 1600),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('OpenSubtitles.com'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('key-opensubtitles')),
      'k',
    );
    await tester.enterText(
      find.byKey(const ValueKey('user-opensubtitles')),
      'me',
    );
    await tester.tap(find.text('Save and turn on'));
    await tester.pumpAndSettle();
    expect(
      find.text('Enter both your username and password, or leave both empty.'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('pass-opensubtitles')),
      'pw',
    );
    await tester.tap(find.text('Save and turn on'));
    await tester.pumpAndSettle();
    expect(kit.settings.enabledSubtitleProviders, ['opensubtitles']);
  });

  kitTest('Test runs one search and reports the result in words', (
    tester,
  ) async {
    final working = _FakeProvider('subdl');
    final rejected = _FakeProvider(
      'subsource',
      error: const SubtitleAuthException('401', providerId: 'subsource'),
    );
    await pumpKit(
      tester,
      location: '/settings/subtitle-sites',
      size: const Size(390, 1400),
      settings: const AppSettings(
        enabledSubtitleProviders: ['subdl', 'subsource'],
      ),
      overrides: [
        subtitleProvidersProvider.overrideWith(
          (_) async => [working, rejected],
        ),
      ],
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Test SubDL'));
    await tester.pumpAndSettle();
    expect(
      find.text('Working. Found 3 subtitles for The Shawshank Redemption.'),
      findsOneWidget,
    );
    expect(working.asked?.imdbId, 'tt0111161');

    await tester.tap(find.bySemanticsLabel('Test SubSource'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'SubSource didn’t accept your key. Check it, then save it again.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a site without a key turns on in one tap', (tester) async {
    final storage = FakeSecureStorage();
    const free = ProviderInfo(
      id: 'free',
      name: 'Free Subs',
      description: 'No key needed.',
      keyLabel: '',
      needsKey: false,
    );
    final db = kitDb();
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          secureKeysProvider.overrideWithValue(SecureKeys(storage)),
        ],
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return MaterialApp(
              theme: kinoraTheme(),
              home: const Scaffold(body: SubtitleSiteTile(info: free)),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('Free Subs'));
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).enabledSubtitleProviders, ['free']);
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('Your key is saved'), findsNothing);
    await unmount(tester);
  });

  test('every error reads as words', () {
    expect(
      subtitleErrorText(
        const SubtitleNetworkException('t', isTimeout: true),
        'SubDL',
      ),
      'SubDL took too long to answer. Try again.',
    );
    expect(
      subtitleErrorText(
        const SubtitleHttpException('x', statusCode: 503),
        'SubDL',
      ),
      'SubDL answered with error 503. Try again later.',
    );
  });
}
