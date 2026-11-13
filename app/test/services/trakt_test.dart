import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kinora/app/providers.dart';
import 'package:kinora/core/db/database.dart';
import 'package:kinora/core/secure_keys.dart';
import 'package:kinora/services/library.dart';
import 'package:kinora/services/sources.dart';
import 'package:kinora/services/trakt.dart';

import '../features/harness.dart';
import '../features/settings/settings_harness.dart';

/// A small stand-in for api.trakt.tv: what it holds, and what it was sent.
final class FakeTrakt {
  final calls = <String>[];
  final bodies = <String, Object?>{};
  var pendingPolls = 1;
  var access = 'a1';
  var expireOnce = false;
  var refuseRefresh = false;
  var watchedShows = <Object?>[];
  var playback = <Object?>[];
  var watchlistShows = <Object?>[];
  var activities = 'v1';

  late final client = MockClient((r) async {
    final path = r.url.path;
    final key = '${r.method} $path';
    calls.add(key);
    if (r.body.isNotEmpty) bodies[key] = jsonDecode(r.body);
    http.Response json(Object? body, [int status = 200]) =>
        http.Response(jsonEncode(body), status);
    if (path.startsWith('/oauth/')) {
      return switch (path) {
        '/oauth/device/code' => json({
          'device_code': 'dev',
          'user_code': 'AB12CD',
          'verification_url': 'https://trakt.tv/activate',
          'expires_in': 600,
          'interval': 0,
        }),
        '/oauth/device/token' when pendingPolls-- > 0 => http.Response('', 400),
        '/oauth/device/token' => json(_tokens('a1', 'r1')),
        '/oauth/token' when refuseRefresh => json({
          'error': 'invalid_grant',
        }, 400),
        '/oauth/token' => json(_tokens(access = 'a2', 'r2')),
        _ => json({}),
      };
    }
    if (r.headers['authorization'] != 'Bearer $access' || expireOnce) {
      expireOnce = false;
      return http.Response('', 401);
    }
    return switch (key) {
      'GET /users/settings' => json({
        'user': {'username': 'abd'},
      }),
      'GET /sync/last_activities' => json({
        'episodes': {'watched_at': activities, 'paused_at': activities},
        'movies': {'watched_at': 'm', 'paused_at': 'm', 'watchlisted_at': 'm'},
        'shows': {'watchlisted_at': activities},
        'watchlist': {'updated_at': activities},
      }),
      'GET /sync/watched/shows' => json(watchedShows),
      'GET /sync/watched/movies' => json([]),
      'GET /sync/playback' => json(playback),
      'GET /sync/watchlist/movies' => json([]),
      'GET /sync/watchlist/shows' => json(watchlistShows),
      'GET /shows/tt200/seasons/1/episodes/2' => json({
        'ids': {'trakt': 42},
      }),
      _ => json({}, 201),
    };
  });

  Map<String, Object?> _tokens(String a, String r) => {
    'access_token': a,
    'refresh_token': r,
    'token_type': 'bearer',
    'expires_in': 7 * 86400,
    'scope': 'public',
    'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
  };
}

void main() {
  late AppDatabase db;
  late FakeTrakt trakt;
  late FakeSecureStorage store;
  late ProviderContainer c;

  setUp(() {
    db = testDb();
    trakt = FakeTrakt();
    store = FakeSecureStorage();
    c = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        httpClientProvider.overrideWithValue(trakt.client),
        secureKeysProvider.overrideWithValue(SecureKeys(store)),
        traktConfigProvider.overrideWithValue(
          const TraktConfig(clientId: 'kinora', api: 'https://trakt.test'),
        ),
        metaProvider.overrideWith((ref, key) async => throw StateError('off')),
      ],
    );
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });

  Future<void> signIn() async {
    final sync = c.read(traktSyncProvider);
    final code = await sync.startSignIn();
    expect(code.userCode, 'AB12CD');
    expect(await sync.finishSignIn(code), TraktSignIn.approved);
    await sync.syncNow();
  }

  test('sign in with a code, then the first sync goes both ways', () async {
    // On this phone: a finished episode and a title in My List.
    await saveProgress(
      db,
      videoId: 'tt200:1:1',
      mediaId: 'tt200',
      season: 1,
      episode: 1,
      positionMs: 3000000,
      completed: true,
      at: DateTime(2026, 11),
    );
    await db
        .into(db.libraryItems)
        .insert(
          LibraryItemsCompanion.insert(
            mediaId: 'tt300',
            type: 'series',
            name: 'Glass Harbor',
          ),
        );
    // On Trakt: E3 watched, E4 half watched, and a show on the watchlist.
    trakt
      ..watchedShows = [
        {
          'show': {
            'title': 'Harbor Lights',
            'ids': {'imdb': 'tt200'},
          },
          'seasons': [
            {
              'number': 1,
              'episodes': [
                {
                  'number': 3,
                  'plays': 1,
                  'last_watched_at': '2026-11-05T20:00:00Z',
                },
              ],
            },
          ],
        },
      ]
      ..playback = [
        {
          'type': 'episode',
          'progress': 50.0,
          'paused_at': '2026-11-06T20:00:00Z',
          'id': 7,
          'episode': {
            'season': 1,
            'number': 4,
            'title': 'Harbor Lights',
            'runtime': 50,
          },
          'show': {
            'title': 'Harbor Lights',
            'ids': {'imdb': 'tt200'},
          },
        },
      ]
      ..watchlistShows = [
        {
          'type': 'show',
          'show': {
            'title': 'North Wind',
            'ids': {'imdb': 'tt201'},
          },
        },
      ];

    await signIn();
    final sync = c.read(traktSyncProvider);
    expect(sync.user, 'abd');
    expect(trakt.calls, contains('POST /oauth/device/token'));
    // Sent: this phone's watched episode and My List.
    final history = trakt.bodies['POST /sync/history']! as Map<String, Object?>;
    expect(jsonEncode(history), contains('"imdb":"tt200"'));
    expect(jsonEncode(history), contains('"number":1'));
    expect(
      jsonEncode(trakt.bodies['POST /sync/watchlist']),
      contains('"imdb":"tt300"'),
    );
    // Brought in: E3 watched, E4 at 25 min of 50, North Wind in My List
    // (and Glass Harbor kept: the first sync merges).
    final repo = c.read(progressRepositoryProvider);
    expect((await repo.get('tt200:1:3'))!.completed, isTrue);
    final e4 = (await repo.get('tt200:1:4'))!;
    expect(e4.completed, isFalse);
    expect(e4.positionMs, 25 * 60000);
    final list = await db.select(db.libraryItems).get();
    expect(list.map((i) => i.mediaId), containsAll(['tt300', 'tt201']));
    expect(sync.lastSync, isNotNull);
    expect(sync.brought, (watched: 1, resume: 1, listed: 1));
    // The sign-in lives in secure storage, not the database.
    expect(store.values.keys, contains('secret.trakt.tokens'));
  });

  test('progress queues for Trakt, one entry per video, sent by id', () async {
    await signIn();
    final repo = c.read(progressRepositoryProvider);
    for (final minutes in [10, 20]) {
      await repo.save(
        videoId: 'tt200:1:2',
        mediaId: 'tt200',
        type: 'series',
        name: 'Harbor Lights',
        season: 1,
        episode: 2,
        position: Duration(minutes: minutes),
        duration: const Duration(minutes: 40),
      );
    }
    // Let the queue writes land, then sync (which sends the queue first).
    await Future<void>.delayed(const Duration(milliseconds: 50));
    trakt.calls.clear();
    await c.read(traktSyncProvider).syncNow();
    // A pause goes as a stop under 80 % (Trakt saves it as a pause).
    expect(trakt.calls.where((k) => k == 'POST /scrobble/stop'), hasLength(1));
    final body = trakt.bodies['POST /scrobble/stop']! as Map<String, Object?>;
    expect(body['progress'], 50.0);
    expect(jsonEncode(body['episode']), contains('"trakt":42'));
  });

  test('a refused sign-in renewal signs out and says so', () async {
    await signIn();
    trakt
      ..expireOnce = true
      ..refuseRefresh = true;
    final sync = c.read(traktSyncProvider);
    await sync.syncNow();
    expect(sync.signedIn, isFalse);
    expect(sync.note, contains('Sign in again'));
    expect(store.values.keys, isNot(contains('secret.trakt.tokens')));
  });

  test(
    'an expired access token is renewed once, and the call goes on',
    () async {
      await signIn();
      trakt.expireOnce = true;
      trakt.activities = 'v2';
      final sync = c.read(traktSyncProvider);
      await sync.syncNow();
      expect(sync.signedIn, isTrue);
      expect(trakt.calls, contains('POST /oauth/token'));
      expect(trakt.access, 'a2');
    },
  );

  test('later syncs: My List follows Trakt, removals too', () async {
    trakt.watchlistShows = [
      {
        'type': 'show',
        'show': {
          'title': 'North Wind',
          'ids': {'imdb': 'tt201'},
        },
      },
    ];
    await signIn();
    expect((await db.select(db.libraryItems).get()).map((i) => i.mediaId), [
      'tt201',
    ]);
    // Removed on another device.
    trakt
      ..watchlistShows = []
      ..activities = 'v2';
    await c.read(traktSyncProvider).syncNow();
    expect(await db.select(db.libraryItems).get(), isEmpty);
  });

  test('My List changes here go to Trakt', () async {
    await signIn();
    await c
        .read(libraryRepositoryProvider)
        .toggle(mediaId: 'tt100', type: 'movie', name: 'The Long Light');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    trakt.calls.clear();
    await c.read(traktSyncProvider).syncNow();
    expect(
      jsonEncode(trakt.bodies['POST /sync/watchlist']),
      contains('"movies":[{"ids":{"imdb":"tt100"}}]'),
    );
  });

  test('not signed in: nothing is queued or sent', () async {
    await c
        .read(progressRepositoryProvider)
        .save(
          videoId: 'tt100',
          mediaId: 'tt100',
          type: 'movie',
          name: 'The Long Light',
          position: const Duration(minutes: 10),
          duration: const Duration(minutes: 100),
        );
    await c.read(traktSyncProvider).syncNow();
    expect(trakt.calls, isEmpty);
    expect(await db.select(db.keyValues).get(), isEmpty);
  });

  test('without the app id in this build, Trakt is unavailable', () {
    final plain = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(plain.dispose);
    expect(plain.read(traktSyncProvider).available, isFalse);
  });
}
