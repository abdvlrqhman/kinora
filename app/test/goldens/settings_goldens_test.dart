// Visual review screenshots; excluded from CI comparisons (pixels differ
// between machines). Update with: flutter test --update-goldens --tags golden
@Tags(['golden'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinora/services/trakt.dart';
import 'package:kinora/core/db/database.dart';
import 'package:kinora/core/settings.dart';

import '../features/settings/settings_harness.dart';

/// Golden screens for Onboarding, Settings and Downloads at 390×844 with
/// real fonts and an iPhone's safe areas.
void main() {
  String asset(String name) =>
      Uri.file(File('test/goldens/assets/$name').absolute.path).toString();

  Future<void> phone(WidgetTester tester) async {
    tester.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
    addTearDown(tester.view.resetPadding);
  }

  /// Lets file images load and decode for real (they start in the fake
  /// clock's zone, so they need real time and pumps in turn).
  Future<void> loadImages(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<void> addAddon(
    AppDatabase db,
    String url,
    String name,
    int i,
    List<String> resources,
  ) => db
      .into(db.addons)
      .insert(
        AddonsCompanion.insert(
          transportUrl: url,
          manifestJson: jsonEncode(manifestJson(name, resources: resources)),
          position: Value(i),
        ),
      );

  kitTest('onboarding: your languages', (tester) async {
    await phone(tester);
    await pumpKit(
      tester,
      location: '/onboarding',
      settings: const AppSettings(subtitleLanguages: ['ar', 'en']),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('onboarding-next')));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('onboarding_languages.png'),
    );
  });

  kitTest('settings root', (tester) async {
    await phone(tester);
    final db = kitDb();
    await addAddon(
      db,
      'https://v3-cinemeta.strem.io/manifest.json',
      'Cinemeta',
      0,
      ['catalog', 'meta'],
    );
    await addAddon(
      db,
      'https://opensubtitles-v3.strem.io/manifest.json',
      'OpenSubtitles v3',
      1,
      ['subtitles'],
    );
    await addAddon(
      db,
      'https://streams.test/config=abc/manifest.json',
      'Stream Finder',
      2,
      ['stream'],
    );
    await pumpKit(
      tester,
      db: db,
      settings: const AppSettings(
        subtitleLanguages: ['ar', 'en'],
        enabledSubtitleProviders: ['subdl', 'wyzie'],
      ),
      // A build with Trakt, as the released apps are.
      overrides: [
        traktConfigProvider.overrideWithValue(
          const TraktConfig(clientId: 'kinora'),
        ),
      ],
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('settings_root.png'),
    );
  });

  kitTest('backup', (tester) async {
    await phone(tester);
    await pumpKit(tester, location: '/settings/backup');
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('backup.png'),
    );
  });

  kitTest('onboarding: add your sources', (tester) async {
    await phone(tester);
    await pumpKit(tester, location: '/onboarding');
    await tester.pumpAndSettle();
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byKey(const ValueKey('onboarding-next')));
      await tester.pumpAndSettle();
    }
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('onboarding_sources.png'),
    );
  });

  kitTest('subtitle style', (tester) async {
    await phone(tester);
    await pumpKit(
      tester,
      location: '/settings/languages/style',
      settings: const AppSettings(
        subtitleLanguages: ['en', 'ar'],
        subtitleStyle: SubtitleStyle(backgroundOpacity: 0.3),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('subtitle_style.png'),
    );
  });

  kitTest('downloads with a few rows', (tester) async {
    await phone(tester);
    final db = kitDb();
    await addDownload(
      db,
      id: 'm1',
      mediaId: 'tt100',
      type: 'movie',
      title: 'Ember',
      season: null,
      total: 1932735283,
      done: 1932735283,
      poster: asset('ember_poster.png'),
      subtitles: '[{"lang":"ar","path":"/a","label":"a"}]',
      at: DateTime(2026, 11, 1),
    );
    final eps = [
      ('Low Tide', 'completed', 2147483648, '[{"lang":"ar"},{"lang":"en"}]'),
      ('The Keeper', 'downloading', 966367642, '[]'),
      ('Salt and Iron', 'paused', 0, '[]'),
    ];
    for (final (i, (name, state, done, subs)) in eps.indexed) {
      await addDownload(
        db,
        id: 'e$i',
        episode: i + 1,
        episodeTitle: name,
        state: state,
        done: done,
        error: state == 'paused' ? 'Waiting for Wi-Fi' : null,
        poster: asset('harbor_poster.png'),
        still: asset('still_${i + 1}.png'),
        subtitles: subs,
        at: DateTime(2026, 11, 3),
      );
    }
    await pumpKit(
      tester,
      db: db,
      location: '/downloads',
      freeSpace: 44023414784,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel(RegExp(r'^Harbor Lights\. ')));
    await tester.pumpAndSettle();
    await loadImages(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('downloads.png'),
    );
  });

  // The progress track and the storage meter show how far there is to go.
  kitTest('downloads, a movie in progress', (tester) async {
    await phone(tester);
    final db = kitDb();
    await addDownload(
      db,
      id: 'm1',
      mediaId: 'tt100',
      type: 'movie',
      title: 'Ember',
      season: null,
      state: 'downloading',
      total: 2147483648,
      done: 966367642,
      poster: asset('ember_poster.png'),
      at: DateTime(2026, 11, 3),
    );
    await addDownload(
      db,
      id: 'm2',
      mediaId: 'tt103',
      type: 'movie',
      title: 'Glacier',
      season: null,
      total: 1932735283,
      done: 1932735283,
      poster: asset('glacier_poster.png'),
      subtitles: '[{"lang":"ar","path":"/a","label":"a"}]',
      at: DateTime(2026, 11, 1),
    );
    await pumpKit(
      tester,
      db: db,
      location: '/downloads',
      freeSpace: 44023414784,
    );
    await tester.pumpAndSettle();
    await loadImages(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('downloads_in_progress.png'),
    );
  });
}
