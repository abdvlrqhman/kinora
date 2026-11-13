import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/db/database.dart';
import '../data/repositories.dart';
import 'trakt.dart';

final libraryRepositoryProvider = Provider(
  (ref) => LibraryRepository(
    ref.watch(databaseProvider),
    onToggled: (id, type, {required added}) =>
        ref.read(traktSyncProvider).listChanged(id, type, added: added),
  ),
);
final progressRepositoryProvider = Provider(
  (ref) => ProgressRepository(
    ref.watch(databaseProvider),
    onChanged: (row, {unwatched = false}) =>
        ref.read(traktSyncProvider).progressSaved(row, unwatched: unwatched),
  ),
);
final trackMemoryProvider = Provider(
  (ref) => TrackMemoryRepository(ref.watch(databaseProvider)),
);

/// "My list", newest first.
final myListProvider = StreamProvider<List<LibraryItem>>(
  (ref) => ref.watch(libraryRepositoryProvider).watchAll(),
);

/// Whether a title is in "My list".
final inMyListProvider = StreamProvider.family<bool, String>(
  (ref, mediaId) => ref.watch(libraryRepositoryProvider).watchContains(mediaId),
);

/// Continue watching row.
final continueWatchingProvider = StreamProvider<List<WatchProgressData>>(
  (ref) => ref.watch(progressRepositoryProvider).watchContinue(),
);

/// Progress of every episode of a title (episode list).
final mediaProgressProvider =
    StreamProvider.family<Map<String, WatchProgressData>, String>(
      (ref, mediaId) => ref
          .watch(progressRepositoryProvider)
          .watchMedia(mediaId)
          .map((rows) => {for (final r in rows) r.videoId: r}),
    );
