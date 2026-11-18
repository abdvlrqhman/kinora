import 'dart:async';

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
