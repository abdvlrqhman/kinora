import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stremio/stremio.dart';
import 'package:timezone/timezone.dart' as tz;

import '../app/providers.dart';
import '../core/db/database.dart';
import '../core/log.dart';
import 'library.dart';
import 'notices_plan.dart';
import 'ratings.dart';
import 'sources.dart';
import 'suggestions.dart';
import 'trakt.dart';

/// Notifications about followed shows (My list, and shows watched in the
/// last two months) and a weekly pick, scheduled on the phone so they come
/// with Kinora closed. Planned again when Kinora opens or comes back,
/// after a Trakt sync, and when My list or the settings change. Phones
/// only: Windows is left out for now.
final class Notices {
  Notices(this._ref);
  final Ref _ref;
  final _plugin = FlutterLocalNotificationsPlugin();
  var _started = false;
  Timer? _soon;
  DateTime? _plannedAt;
  final _subs = <void Function()>[];

  static bool get supported => Platform.isIOS || Platform.isAndroid;

  /// id → (key, when): what Kinora scheduled, so it can take back its own
  /// (never everything: the download notices are Kinora's too).
  static const _scheduledKey = 'notices.scheduled';

  /// Once-only events already scheduled ("season:…", "pick:…").
  static const _toldKey = 'notices.told';

  AppDatabase get _db => _ref.read(databaseProvider);

  /// Sets up taps (to [open] an app path) and the first plan.
  Future<void> start(void Function(String path) open) async {
    if (!supported || _started) return;
    _started = true;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_kinora'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (r) {
          if (r.payload case final path?) open(path);
        },
      );
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        if (launch!.notificationResponse?.payload case final path?) open(path);
      }
    } on Object catch (e) {
      Log.w('notices', 'start: $e');
      return;
    }
    final life = AppLifecycleListener(onResume: planSoon);
    final sync = _ref.read(traktSyncProvider);
    var synced = sync.lastSync;
    void onSync() {
      if (sync.lastSync == synced) return;
      synced = sync.lastSync;
      planSoon(force: true);
    }

    sync.addListener(onSync);
    final list = _ref.listen(myListProvider, (_, _) => planSoon(force: true));
    final settings = _ref.listen(
      settingsProvider.select((s) => (s.notifyShows, s.notifyPicks)),
      (_, _) => planSoon(force: true),
    );
    _subs.addAll([
      life.dispose,
      () => sync.removeListener(onSync),
      list.close,
      settings.close,
    ]);
    planSoon(force: true);
  }

  /// A show was just followed: lets notices through without nagging.
  /// iPhone: quiet (provisional) delivery when the viewer hasn't decided,
  /// no prompt. Android 13+: asks once.
  Future<void> followed() async {
    if (!_started) return;
    try {
      if (Platform.isIOS) {
        final ios = _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >();
        final now = await ios?.checkPermissions();
        if (now != null && !now.isEnabled) {
          // Provisional never prompts. (With alert too: plugin 22 sends
          // nothing when provisional is asked for alone.)
          await ios?.requestPermissions(alert: true, provisional: true);
        }
      } else if (Platform.isAndroid) {
        final android = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        if ((await android?.areNotificationsEnabled() ?? true) ||
            await _kv(_askedKey) != null) {
          return;
        }
        await _setKv(_askedKey, '1');
        await android?.requestNotificationsPermission();
      }
    } on Object catch (e) {
      Log.w('notices', 'permission: $e');
    }
  }

  static const _askedKey = 'notices.asked';

  void dispose() {
    _soon?.cancel();
    for (final s in _subs) {
      s();
    }
  }

  /// Plans again in a few seconds; without [force], at most every 30
  /// minutes (coming back to Kinora often shouldn't refetch every show).
  void planSoon({bool force = false}) {
    if (!_started) return;
    final last = _plannedAt;
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < const Duration(minutes: 30)) {
      return;
    }
    _soon?.cancel();
    _soon = Timer(const Duration(seconds: 5), () => unawaited(plan()));
  }

  Future<void> plan() async {
    _plannedAt = DateTime.now();
    try {
      final s = _ref.read(settingsProvider);
      final tastes = await _ref.read(ratingsProvider).all();
      bool notForMe(String id) =>
          (tastes[id]?.rating ?? 6) <= Taste.notForMe.trakt;
      final episodes = s.notifyShows
          ? await _followedEpisodes(notForMe)
          : const <AirDate>[];
      final picks = s.notifyPicks
          ? [
              for (final p in await _picks())
                if (!notForMe(p.id)) p,
            ]
          : const <MetaPreview>[];
      final told = await _told();
      final now = DateTime.now();
      final planned = planNotices(
        now: now,
        episodes: episodes,
        announced: told,
        picks: picks,
        picked: told,
      );
      final before = await _scheduled();
      final next = <int, (String, DateTime)>{
        for (final p in planned) p.id: (p.key, p.at),
      };
      for (final MapEntry(key: id, value: (key, at)) in before.entries) {
        if (next.containsKey(id) || !at.isAfter(now)) continue;
        // Once-only events stay unless their switch went off.
        final keep = key.startsWith('season:')
            ? s.notifyShows
            : key.startsWith('pick:') && s.notifyPicks;
        if (keep) {
          next[id] = (key, at);
        } else {
          await _plugin.cancel(id: id);
        }
      }
      for (final p in planned) {
        await _plugin.zonedSchedule(
          id: p.id,
          scheduledDate: tz.TZDateTime.from(p.at.toUtc(), tz.UTC),
          notificationDetails: _details(pick: p.key.startsWith('pick:')),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          title: p.title,
          body: p.body,
          payload: p.open,
        );
      }
      await _setKv(
        _scheduledKey,
        jsonEncode({
          for (final MapEntry(key: id, value: (key, at)) in next.entries)
            '$id': [key, at.toUtc().toIso8601String()],
        }),
      );
      await _setKv(
        _toldKey,
        jsonEncode([
          ...told,
          for (final p in planned)
            if (!p.key.startsWith('ep:') && !told.contains(p.key)) p.key,
        ]),
      );
      Log.i(
        'notices',
        'planned ${planned.length} from ${episodes.length} episodes '
            'and ${picks.length} picks',
      );
    } on Object catch (e) {
      Log.w('notices', 'plan: $e');
    }
  }

  static NotificationDetails _details({required bool pick}) =>
      NotificationDetails(
        android: pick
            ? const AndroidNotificationDetails(
                'picks',
                'Picked for you',
                channelDescription: 'One title a week you might like.',
                importance: Importance.low,
                priority: Priority.low,
              )
            : const AndroidNotificationDetails(
                'shows',
                'Shows you follow',
                channelDescription:
                    'New episodes, seasons and finales of your shows.',
                playSound: false,
              ),
        iOS: DarwinNotificationDetails(
          presentSound: false,
          threadIdentifier: pick ? 'picks' : 'shows',
          // A pick waits quietly in Notification Center.
          interruptionLevel: pick
              ? InterruptionLevel.passive
              : InterruptionLevel.active,
        ),
      );

  /// Every episode of followed shows: Cinemeta's list (days only), with
  /// Trakt's real times and kinds when signed in.
  Future<List<AirDate>> _followedEpisodes(
    bool Function(String) notForMe,
  ) async {
    final recent = DateTime.now().subtract(const Duration(days: 60));
    final listed = await _db.select(_db.libraryItems).get();
    final watched =
        await (_db.select(_db.watchProgress)..where(
              (t) =>
                  t.season.isNotNull() & t.updatedAt.isBiggerThanValue(recent),
            ))
            .get();
    final ids = {
      for (final i in listed)
        if (i.type == 'series') i.mediaId,
      for (final w in watched) w.mediaId,
    }.where((id) => id.startsWith('tt') && !notForMe(id)).take(40).toSet();
    final precise = {
      for (final e in await _ref.read(traktSyncProvider).calendar())
        '${e.showId}:${e.season}:${e.episode}': e,
    };
    final out = <AirDate>[];
    for (final id in ids) {
      try {
        final meta = await _ref.read(
          metaProvider((type: 'series', id: id)).future,
        );
        for (final v in meta.videos) {
          final (season, episode, at) = (v.season, v.episode, v.released);
          if (season == null || episode == null || at == null) continue;
          out.add(
            precise.remove('$id:$season:$episode') ??
                (
                  showId: id,
                  show: meta.name,
                  season: season,
                  episode: episode,
                  title: v.title,
                  airsAt: at,
                  precise: false,
                  type: null,
                ),
          );
        }
      } on Object {
        // No details for this show: Trakt's times only.
      }
    }
    out.addAll(precise.values.where((e) => ids.contains(e.showId)));
    return out;
  }

  Future<List<MetaPreview>> _picks() async {
    try {
      return await _ref.read(forYouProvider.future);
    } on Object {
      return const [];
    }
  }

  Future<Set<String>> _told() async {
    try {
      return {
        ...(jsonDecode(await _kv(_toldKey) ?? '[]') as List).cast<String>(),
      };
    } on Object {
      return {};
    }
  }

  Future<Map<int, (String, DateTime)>> _scheduled() async {
    try {
      final j =
          jsonDecode(await _kv(_scheduledKey) ?? '{}') as Map<String, Object?>;
      return {
        for (final MapEntry(:key, :value) in j.entries)
          if (value case [final String k, final String at])
            int.parse(key): (k, DateTime.parse(at)),
      };
    } on Object {
      return {};
    }
  }

  Future<String?> _kv(String key) async => (await (_db.select(
    _db.keyValues,
  )..where((t) => t.key.equals(key))).getSingleOrNull())?.value;

  Future<void> _setKv(String key, String value) => _db
      .into(_db.keyValues)
      .insertOnConflictUpdate(
        KeyValuesCompanion.insert(key: key, value: value),
      );
}

final noticesProvider = Provider<Notices>((ref) {
  final n = Notices(ref);
  ref.onDispose(n.dispose);
  return n;
});
