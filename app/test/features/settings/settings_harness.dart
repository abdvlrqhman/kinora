import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kinora/app/providers.dart';
import 'package:kinora/core/db/database.dart';
import 'package:kinora/core/paths.dart';
import 'package:kinora/core/secure_keys.dart';
import 'package:kinora/core/settings.dart';
import 'package:kinora/features/cast/cast_picker.dart';
import 'package:kinora/features/downloads/downloads_screen.dart';
import 'package:kinora/features/downloads/storage.dart';
import 'package:kinora/features/onboarding/onboarding_screen.dart';
import 'package:kinora/features/settings/settings_screen.dart';
import 'package:kinora/features/settings/storage_page.dart';
import 'package:kinora/services/downloads.dart';
import 'package:kinora/services/play_request.dart';
import 'package:kinora/ui/theme.dart';

import '../../goldens/settings_fonts_helper.dart';

/// Records where a screen navigated to.
final class Nav {
  final played = <PlayRequest>[];
  final locations = <String>[];
}

/// A fresh in-memory database (left open: memory goes with the isolate).
AppDatabase kitDb() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase.forExecutor(NativeDatabase.memory());
}

/// Unmounts the tree so drift streams and close timers finish.
Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

/// [testWidgets] that always unmounts at the end, pass or fail.
void kitTest(String description, WidgetTesterCallback body) =>
    testWidgets(description, (tester) async {
      try {
        await body(tester);
      } finally {
        await unmount(tester);
      }
    });

/// In-memory stand-in for the Keychain/Keystore.
final class FakeSecureStorage extends Fake implements FlutterSecureStorage {
  final values = <String, String>{};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values.remove(key);
}

/// Records download actions and applies them to the database like the real
/// service would (minus files and the engine).
final class FakeDownloadActions implements DownloadActions {
  FakeDownloadActions(this.db);
  final AppDatabase db;
  final calls = <String>[];

  Future<void> _state(String id, String state) =>
      (db.update(db.downloads)..where((t) => t.id.equals(id))).write(
        DownloadsCompanion(state: Value(state), error: const Value(null)),
      );

  @override
  Future<void> download(PlayRequest request) async =>
      calls.add('download ${request.videoId}');
  @override
  Future<void> pause(String downloadId) async {
    calls.add('pause $downloadId');
    await _state(downloadId, 'paused');
  }

  @override
  Future<void> resume(String downloadId) async {
    calls.add('resume $downloadId');
    await _state(downloadId, 'downloading');
  }

  @override
  Future<void> remove(String downloadId) async {
    calls.add('remove $downloadId');
    await (db.delete(db.downloads)..where((t) => t.id.equals(downloadId))).go();
  }
}

/// Everything a settings, onboarding or downloads test needs.
final class Kit {
  Kit._(this.db, this.storage, this.actions, this.paths, this.nav);

  final AppDatabase db;
  final FakeSecureStorage storage;
  final FakeDownloadActions actions;
  final AppPaths paths;
  final Nav nav;
  late ProviderContainer container;

  AppSettings get settings => container.read(settingsProvider);
}

/// Temp directories standing in for the app's folders.
AppPaths tempPaths() {
  final root = Directory.systemTemp.createTempSync('kinora_test');
  addTearDown(() => root.deleteSync(recursive: true));
  final paths = AppPaths(
    support: Directory('${root.path}/support'),
    downloadsRoot: Directory('${root.path}/documents'),
    cache: Directory('${root.path}/cache'),
  );
  for (final d in [
    paths.downloads,
    paths.streams,
    paths.subtitles,
    paths.logs,
  ]) {
    d.createSync(recursive: true);
  }
  return paths;
}

/// A manifest an addon link answers with.
Map<String, Object?> manifestJson(
  String name, {
  List<String> resources = const ['catalog', 'meta'],
}) => {
  'id': 'test.${name.toLowerCase().replaceAll(' ', '')}',
  'version': '1.0.0',
  'name': name,
  'resources': resources,
  'types': ['movie', 'series'],
  'catalogs': resources.contains('catalog')
      ? [
          {'type': 'movie', 'id': 'top'},
        ]
      : <Object?>[],
};

/// Answers addon links from [manifests] (by full URL); anything else 404s.
http.Client fakeHttp(Map<String, Map<String, Object?>> manifests) =>
    MockClient((req) async {
      final m = manifests[req.url.toString()];
      return m == null
          ? http.Response('not found', 404)
          : http.Response(
              jsonEncode(m),
              200,
              headers: {'content-type': 'application/json'},
            );
    });

/// Pumps the app's settings, onboarding and downloads routes at [location]
/// with an in-memory database, fake keys, temp folders and no network.
Future<Kit> pumpKit(
  WidgetTester tester, {
  String location = '/settings',
  AppSettings settings = const AppSettings(),
  List<Override> overrides = const [],
  Map<String, Map<String, Object?>> manifests = const {},
  double textScale = 1,
  Size size = const Size(390, 844),
  AppDatabase? db,
  int? freeSpace = 68719476736,
}) async {
  await tester.runAsync(loadKinoraFonts);
  tester.view
    ..physicalSize = size * 3
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final database = db ?? kitDb();
  final kit = Kit._(
    database,
    FakeSecureStorage(),
    FakeDownloadActions(database),
    tempPaths(),
    Nav(),
  );
  Widget stub(String text) => Scaffold(body: Center(child: Text(text)));
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(path: '/', builder: (_, _) => stub('home')),
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
      GoRoute(path: '/downloads', builder: (_, _) => const DownloadsScreen()),
      GoRoute(
        path: '/search',
        builder: (_, s) {
          kit.nav.locations.add(s.uri.toString());
          return stub('search');
        },
      ),
      GoRoute(
        path: '/settings',
        builder: (_, _) => const SettingsScreen(),
        routes: settingsRoutes,
      ),
      GoRoute(
        path: '/player',
        builder: (_, s) {
          kit.nav.played.add(s.extra! as PlayRequest);
          return stub('player');
        },
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        databaseProvider.overrideWithValue(database),
        initialSettingsProvider.overrideWithValue(settings),
        secureKeysProvider.overrideWithValue(SecureKeys(kit.storage)),
        pathsProvider.overrideWithValue(kit.paths),
        httpClientProvider.overrideWithValue(fakeHttp(manifests)),
        downloadActionsProvider.overrideWithValue(kit.actions),
        // No sockets in tests: the TV search finds nothing.
        castSearchProvider.overrideWithValue(() async {}),
        freeSpaceProvider.overrideWith((_) async => freeSpace),
        artworkCacheProvider.overrideWithValue((
          size: () async => 3 * 1024 * 1024,
          clear: () async {},
        )),
        ...overrides,
      ],
      child: Builder(
        builder: (context) {
          kit.container = ProviderScope.containerOf(context);
          return MaterialApp.router(
            debugShowCheckedModeBanner: false,
            theme: withTestFallback(kinoraTheme()),
            routerConfig: router,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
          );
        },
      ),
    ),
  );
  return kit;
}

/// Lets real file and timer work finish (directory scans, deletes).
Future<void> settleIo(WidgetTester tester) async {
  for (var i = 0; i < 25; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 4)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

/// Inserts a download row.
Future<void> addDownload(
  AppDatabase db, {
  required String id,
  String mediaId = 'tt200',
  String type = 'series',
  String title = 'Harbor Lights',
  int? season = 1,
  int? episode,
  String? episodeTitle,
  String state = 'completed',
  int total = 2147483648,
  int done = 2147483648,
  String? error,
  String? filePath,
  String? poster,
  String? still,
  String subtitles = '[]',
  DateTime? at,
}) => db
    .into(db.downloads)
    .insert(
      DownloadsCompanion.insert(
        id: id,
        mediaId: mediaId,
        videoId: season == null ? mediaId : '$mediaId:$season:$episode',
        type: type,
        title: title,
        episodeTitle: Value(episodeTitle),
        season: Value(season),
        episode: Value(episode),
        poster: Value(poster),
        still: Value(still),
        releaseName: 'Harbor.Lights.1080p.WEB-DL',
        kind: 'torrent',
        directory: '/downloads',
        filePath: Value(filePath),
        totalBytes: Value(total),
        doneBytes: Value(done),
        state: state,
        error: Value(error),
        subtitlesJson: Value(subtitles),
        createdAt: Value(at ?? DateTime(2026, 11)),
      ),
    );
