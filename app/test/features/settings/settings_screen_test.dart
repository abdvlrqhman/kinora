import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinora/app/providers.dart' show kinoraVersion;
import 'package:kinora/core/log.dart';
import 'package:kinora/core/secure_keys.dart';
import 'package:kinora/core/settings.dart';
import 'package:kinora/features/settings/help_pages.dart';

import 'settings_harness.dart';

final back = find.byIcon(Icons.chevron_left_rounded);

Future<void> reveal(WidgetTester tester, Finder f) => tester.scrollUntilVisible(
  f,
  200,
  scrollable: find.byType(Scrollable).first,
);

void main() {
  kitTest('root lists every page and opens each one', (tester) async {
    await pumpKit(
      tester,
      size: const Size(390, 1400),
      settings: const AppSettings(
        subtitleLanguages: ['ar', 'en'],
        enabledSubtitleProviders: ['subdl'],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Subtitles in Arabic, English'), findsOneWidget);
    expect(find.text('SubDL'), findsOneWidget);
    expect(find.text('None yet. Add one to see movies and shows.'), findsOne);

    const pages = {
      'Sources': 'Sources',
      'Languages and subtitles': 'Languages and subtitles',
      'Subtitle sites': 'Subtitle sites',
      'Playback': 'Playback',
      'Downloads': 'Downloads',
      'Network': 'Network',
      'Storage': 'Storage',
      'Diagnostics': 'Diagnostics',
      'About Kinora': 'About Kinora',
    };
    for (final MapEntry(key: row, value: title) in pages.entries) {
      await tester.tap(find.bySemanticsLabel(RegExp('^$row, ')));
      await tester.pumpAndSettle();
      expect(find.text(title), findsWidgets, reason: row);
      expect(back, findsOneWidget, reason: row);
      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(find.text('Watching'), findsOneWidget, reason: row);
    }
  });

  kitTest('every page fits at 1.5x text', (tester) async {
    for (final page in [
      '',
      '/sources',
      '/languages',
      '/languages/style',
      '/subtitle-sites',
      '/playback',
      '/downloads',
      '/network',
      '/storage',
      '/diagnostics',
      '/about',
    ]) {
      await pumpKit(
        tester,
        location: '/settings$page',
        textScale: 1.5,
        settings: const AppSettings(
          subtitleLanguages: ['ar', 'en', 'pt-BR'],
          audioLanguages: ['ar', 'original'],
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: page);
      await tester.fling(
        find.byType(Scrollable).first,
        const Offset(0, -4000),
        4000,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: page);
      await unmount(tester);
    }
  });

  kitTest('playback, downloads and network choices are saved', (tester) async {
    final kit = await pumpKit(tester, location: '/settings/playback');
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('4K'));
    await tester.tap(find.text('Data saver'));
    await tester.tap(find.text('Skip intros'));
    await tester.pumpAndSettle();
    expect(kit.settings.maxResolution, 2160);
    expect(kit.settings.dataSaver, isTrue);
    expect(kit.settings.skipIntros, isFalse);
    await unmount(tester);

    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final dl = await pumpKit(tester, location: '/settings/downloads');
    await tester.pumpAndSettle();
    expect(
      find.text('Episodes you stream to the end are kept in Downloads.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Keep fully streamed episodes'));
    await tester.tap(find.text('Share after downloading'));
    await reveal(tester, find.bySemanticsLabel('1 week'));
    await tester.tap(find.bySemanticsLabel('1 week'));
    await tester.pumpAndSettle();
    expect(dl.settings.keepCompletedStreams, isFalse);
    expect(dl.settings.seedAfterDownload, isTrue);
    expect(dl.settings.keepStreamsHours, 168);
    // The battery row is Android-only.
    await reveal(tester, find.text('Off'));
    expect(find.text('Allow background downloads'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
    await unmount(tester);

    // flutter_test runs as Android by default.
    await pumpKit(tester, location: '/settings/downloads');
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Allow background downloads'));
    await unmount(tester);

    final net = await pumpKit(tester, location: '/settings/network');
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel(RegExp('^Upload speed')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 MB/s'));
    await tester.pumpAndSettle();
    expect(net.settings.uploadLimitKBps, 1024);
    expect(find.text('1 MB/s'), findsOneWidget);
    await tester.tap(find.text('Share while watching'));
    await reveal(tester, find.byKey(const ValueKey('vpn-interface')));
    await tester.enterText(find.byKey(const ValueKey('vpn-interface')), 'tun0');
    await tester.pumpAndSettle();
    expect(net.settings.vpnInterface, 'tun0');
    expect(net.settings.seedWhileWatching, isFalse);
  });

  kitTest('storage shows sizes and clears with confirmation', (tester) async {
    final kit = await pumpKit(tester, location: '/settings/storage');
    File('${kit.paths.streams.path}/a.part')
        .writeAsBytesSync(List.filled(2048, 1));
    File('${kit.paths.downloads.path}/movie.mkv').writeAsBytesSync([1, 2]);
    await addDownload(kit.db, id: 'd1', season: null, title: 'Ember');
    // Re-measure now that the files exist.
    await tester.tap(back);
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel(RegExp('^Storage, ')));
    await settleIo(tester);
    expect(find.text('2 KB'), findsOneWidget); // stream buffer
    expect(find.text('3 MB'), findsOneWidget); // artwork
    expect(find.textContaining('64 GB free on this phone'), findsOneWidget);

    await reveal(tester, find.bySemanticsLabel('Clear Logs'));
    await tester.tap(find.bySemanticsLabel('Clear Stream buffer'));
    await tester.pumpAndSettle();
    expect(find.text('Clear Stream buffer?'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Clear'));
    await settleIo(tester);
    expect(kit.paths.streams.listSync(), isEmpty);
    expect(find.text('Cleared Stream buffer.'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Delete all Downloads'));
    await tester.pumpAndSettle();
    expect(find.text('Delete all downloads?'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Delete all downloads'));
    await settleIo(tester);
    expect(kit.actions.calls, ['remove d1']);
    expect(kit.paths.downloads.listSync(), isEmpty);
  });

  test('redact keeps Kinora’s own setting names', () {
    final out = redact(
      '{"enabledSubtitleProviders":["subdl"],"token":"sk_9f8e7d6c5b4a39281706f5e4"}',
      const [],
      {'enabledSubtitleProviders'},
    );
    expect(out, contains('enabledSubtitleProviders'));
    expect(out, isNot(contains('sk_9f8e')));
  });

  test('redact hides keys, addon configs and long tokens', () {
    const key = 'abcd1234secret';
    final out = redact(
      'GET https://torrentio.strem.fun/realdebrid=$key/stream/x.json '
      'failed; token sk_9f8e7d6c5b4a39281706f5e4 user $key '
      'hash 0123456789abcdef0123456789abcdef01234567',
      [key],
    );
    expect(out, isNot(contains(key)));
    expect(out, isNot(contains('realdebrid')));
    expect(out, isNot(contains('sk_9f8e')));
    expect(out, contains('https://torrentio.strem.fun/…'));
    expect(out, contains('0123456789abcdef0123456789abcdef01234567'));
  });

  kitTest('diagnostics shows versions and the log, and copies it safely', (
    tester,
  ) async {
    Log.i('test', 'Played Harbor Lights');
    Log.w('addons', 'failed https://addon.test/realdebrid=SECRETKEY99/x');
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final kit = await pumpKit(tester, location: '/settings/diagnostics');
    await SecureKeys(kit.storage)
        .write('subdl', const ProviderCredentials(apiKey: 'MYSUBDLKEY'));
    await tester.pumpAndSettle();
    expect(find.text(kinoraVersion), findsOneWidget);
    expect(find.text('Not available on this device'), findsOneWidget);
    expect(find.text('Played Harbor Lights'), findsOneWidget);
    expect(find.textContaining('SECRETKEY99'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Errors'));
    await tester.pumpAndSettle();
    expect(find.text('Played Harbor Lights'), findsNothing);

    Log.i('test', 'key in a log by mistake: MYSUBDLKEY');
    await tester.tap(find.text('Copy diagnostics'));
    await tester.pumpAndSettle();
    expect(copied, contains('Kinora $kinoraVersion'));
    expect(copied, contains('Played Harbor Lights'));
    expect(copied, isNot(contains('SECRETKEY99')));
    expect(copied, isNot(contains('MYSUBDLKEY')));
    expect(find.text('Copied. Keys and links are left out.'), findsOneWidget);
  });

  kitTest('about states the legal note and opens licenses', (tester) async {
    await pumpKit(tester, location: '/settings/about');
    await tester.pumpAndSettle();
    expect(find.textContaining('ships with no content'), findsOneWidget);
    expect(find.textContaining('GPL-3.0'), findsOneWidget);
    await reveal(tester, find.text('Open-source licenses'));
    await tester.tap(find.text('Open-source licenses'));
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
  });
}
