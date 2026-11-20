import 'dart:async';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stremio/stremio.dart';

import '../app/providers.dart';
import 'trakt.dart';

/// "More like this" from Trakt (signed in only).
final relatedProvider = FutureProvider.autoDispose
    .family<List<MetaPreview>, ({String id, String type})>(
      (ref, title) =>
          ref.watch(traktSyncProvider).related(title.id, title.type),
    );

/// Home's "For you": Trakt's picks for the viewer, minus anything they
/// started here. Fresh every 6 hours, and on signing in or out.
final forYouProvider = FutureProvider<List<MetaPreview>>((ref) async {
  final sync = ref.watch(traktSyncProvider);
  final signedIn = sync.signedIn;
  void changed() {
    if (sync.signedIn != signedIn) ref.invalidateSelf();
  }

  sync.addListener(changed);
  final timer = Timer(const Duration(hours: 6), ref.invalidateSelf);
  ref.onDispose(() {
    sync.removeListener(changed);
    timer.cancel();
  });
  if (!signedIn) return const [];
  final db = ref.read(databaseProvider);
  final started = {
    for (final r in await db.select(db.watchProgress).get()) r.mediaId,
  };
  return [
    for (final m in await sync.recommendations())
      if (!started.contains(m.id)) m,
  ];
});

/// Trending on Trakt, by type (signed in only).
final trendingProvider = FutureProvider.autoDispose
    .family<List<MetaPreview>, String>(
      (ref, type) => ref.watch(traktSyncProvider).trending(type),
    );

/// "Because you watched X": titles like the last one watched here (signed
/// in to Trakt only).
final becauseProvider =
    FutureProvider.autoDispose<({String name, List<MetaPreview> items})?>((
      ref,
    ) async {
      final sync = ref.watch(traktSyncProvider);
      if (!sync.signedIn) return null;
      final db = ref.read(databaseProvider);
      final recent =
          await (db.select(db.watchProgress)
                ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
                ..limit(30))
              .get();
      final last = recent.where((r) => r.mediaId.startsWith('tt')).firstOrNull;
      if (last == null) return null;
      final items = await ref.watch(
        relatedProvider((id: last.mediaId, type: last.type)).future,
      );
      return (name: last.name, items: items);
    });
