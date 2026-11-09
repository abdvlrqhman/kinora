import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';

import 'package:drift/drift.dart' show BooleanExpressionOperators, OrderingTerm;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stremio/stremio.dart';

import '../../app/providers.dart';
import '../../core/log.dart';
import '../../services/library.dart';
import '../../services/sources.dart';
import '../title/title_model.dart';

/// Home rows so far.
final class HomeRows {
  const HomeRows(
    this.rows, {
    this.complete = true,
    this.failed = false,
    this.offline = false,
  });

  final List<CatalogRow> rows;

  /// Every catalog answered or gave up.
  final bool complete;

  /// Every catalog failed (none was merely empty).
  final bool failed;

  /// ...and every failure was the network: the phone is probably offline.
  final bool offline;
}

/// Whether the phone has a network at all (Wi-Fi, mobile data, ethernet).
final onlineProvider = StreamProvider<bool>(
  (ref) => Connectivity().onConnectivityChanged.map(
    (r) => r.any((c) => c != ConnectivityResult.none),
  ),
);

/// Home rows as each catalog arrives, in the sources' order, so one slow
/// source never holds the feed on skeletons.
// shortcut: mirrors homeCatalogsProvider's per-catalog fetch (row titles,
// 15 s limit, first 20 rows); move the stream into services/sources.dart.
final homeRowsProvider = StreamProvider<HomeRows>((ref) async* {
  final addons = await ref.watch(enabledAddonsProvider.future);
  final client = ref.watch(addonClientProvider);
  final jobs = [
    for (final a in addons)
      for (final c in a.manifest.catalogs)
        if (c.requiredExtras.isEmpty) (addon: a, catalog: c),
  ];
  if (jobs.isEmpty) {
    yield const HomeRows([]);
    return;
  }
  final slots = List<CatalogRow?>.filled(jobs.length, null);
  final arrived = StreamController<(int, _Fetched)>();
  ref.onDispose(() => unawaited(arrived.close()));
  for (final (i, j) in jobs.indexed) {
    unawaited(
      _fetchRow(client, j.addon, j.catalog).then((f) {
        if (!arrived.isClosed) arrived.add((i, f));
      }),
    );
  }
  var answered = 0, failed = 0, offline = 0;
  await for (final (i, f) in arrived.stream) {
    slots[i] = f.row;
    answered++;
    if (f.error) failed++;
    if (f.network) offline++;
    final complete = answered == jobs.length;
    yield HomeRows(
      [for (final r in slots) ?r].take(20).toList(),
      complete: complete,
      failed: complete && failed == jobs.length,
      offline: complete && offline == jobs.length,
    );
    if (complete) break;
  }
});

typedef _Fetched = ({CatalogRow? row, bool error, bool network});

Future<_Fetched> _fetchRow(
  AddonClient client,
  Addon addon,
  ManifestCatalog c,
) async {
  try {
    final items = await client
        .catalog(addon, c.type, c.id)
        .timeout(const Duration(seconds: 15));
    if (items.isEmpty) return (row: null, error: false, network: false);
    final name = (c.name?.trim().isNotEmpty ?? false) ? c.name!.trim() : c.id;
    final lower = name.toLowerCase();
    final title = lower.contains(typeLabel(c.type)) || lower.contains(c.type)
        ? name
        : '$name ${typeLabel(c.type)}';
    final row = CatalogRow(
      title: title,
      type: c.type,
      items: items,
      addon: addon,
      catalog: c,
    );
    return (row: row, error: false, network: false);
  } on Object catch (e) {
    Log.w('catalog', '${addon.manifest.name}/${c.id}: $e');
    final network =
        e is AddonNetworkException ||
        e is AddonTimeoutException ||
        e is TimeoutException ||
        e is SocketException;
    return (row: null, error: true, network: network);
  }
}

/// A show you follow with episodes that aired since you last watched it
/// (or since you added it to My list), unwatched, in watch order.
final class NewEpisodes {
  const NewEpisodes(this.model, this.episodes);

  final TitleModel model;
  final List<Episode> episodes;

  Episode get next => episodes.first;
}

/// Shows from My list and your history with new episodes, most recently
/// watched first. Local: progress and library, plus each show's details.
final newEpisodesProvider = FutureProvider.autoDispose<List<NewEpisodes>>((
  ref,
) async {
  // Recompute when the library or progress changes.
  final library = await ref.watch(myListProvider.future);
  ref.watch(continueWatchingProvider);
  final db = ref.watch(databaseProvider);
  // shortcut: queries progress here because no repository call lists every
  // show with progress; move to ProgressRepository when services can change.
  final recent =
      await (db.select(db.watchProgress)
            ..where((t) => t.season.isNotNull())
            ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
            ..limit(300))
          .get();
  final since = <String, ({String type, DateTime at, bool started})>{};
  for (final r in recent) {
    since.putIfAbsent(
      r.mediaId,
      () => (type: r.type, at: r.updatedAt, started: true),
    );
  }
  for (final l in library) {
    if (l.type == 'movie') continue;
    since.putIfAbsent(
      l.mediaId,
      () => (type: l.type, at: l.addedAt, started: false),
    );
  }
  final now = DateTime.now();
  final found = await Future.wait([
    for (final MapEntry(key: id, value: s) in since.entries.take(12))
      () async {
        try {
          final model = TitleModel(
            await ref.watch(metaProvider((type: s.type, id: id)).future),
          );
          if (!model.isSeries) return null;
          final watched = {
            for (final r in await (db.select(
              db.watchProgress,
            )..where((t) => t.mediaId.equals(id) & t.completed)).get())
              r.videoId,
          };
          final fresh = [
            for (final e in model.order)
              if (e.released != null &&
                  e.released!.isAfter(s.at) &&
                  aired(e, now) &&
                  !watched.contains(e.id))
                e,
          ];
          // Never started and added mid-season: S1 E5 isn't "new" to you,
          // the show starts at S1 E1 (Title shows that).
          if (fresh.isEmpty ||
              (!s.started && fresh.first.id != model.order.first.id))
            return null;
          return NewEpisodes(model, fresh);
        } on Object {
          return null; // No details: nothing to say about this show.
        }
      }(),
  ]);
  return [for (final f in found) ?f];
});

/// Today's billboard: a show you follow with new episodes, else one of the
/// first ten catalog titles with a backdrop. Changes once a day.
MetaPreview? pickFeatured(
  List<CatalogRow> rows,
  List<NewEpisodes> fresh,
  DateTime today,
) {
  final day =
      DateTime.utc(today.year, today.month, today.day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;
  final followed = [
    for (final f in fresh)
      if (f.model.meta.background != null) f.model.meta,
  ];
  if (followed.isNotEmpty) return followed[day % followed.length];
  final pool = rows
      .expand((r) => r.items)
      .where((m) => m.background != null)
      .take(10)
      .toList();
  if (pool.isNotEmpty) return pool[day % pool.length];
  return rows.firstOrNull?.items.firstOrNull;
}
