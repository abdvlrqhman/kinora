import 'package:drift/drift.dart';

import '../core/db/database.dart';

/// "My list".
final class LibraryRepository {
  LibraryRepository(this._db, {this.onToggled});
  final AppDatabase _db;

  /// Told after a title is added or removed (Trakt sync).
  final void Function(String mediaId, String type, {required bool added})?
  onToggled;

  Stream<List<LibraryItem>> watchAll() => (_db.select(
    _db.libraryItems,
  )..orderBy([(t) => OrderingTerm.desc(t.addedAt)])).watch();

  Stream<bool> watchContains(String mediaId) =>
      (_db.select(_db.libraryItems)..where((t) => t.mediaId.equals(mediaId)))
          .watchSingleOrNull()
          .map((r) => r != null);

  /// Adds or removes; returns whether it's now in the list.
  Future<bool> toggle({
    required String mediaId,
    required String type,
    required String name,
    String? poster,
    String? background,
  }) async {
    final added = await _toggle(mediaId, type, name, poster, background);
    onToggled?.call(mediaId, type, added: added);
    return added;
  }

  Future<bool> _toggle(
    String mediaId,
    String type,
    String name,
    String? poster,
    String? background,
  ) => _db.transaction(() async {
    final existing = await (_db.select(
      _db.libraryItems,
    )..where((t) => t.mediaId.equals(mediaId))).getSingleOrNull();
    if (existing != null) {
      await (_db.delete(
        _db.libraryItems,
      )..where((t) => t.mediaId.equals(mediaId))).go();
      return false;
    }
    await _db
        .into(_db.libraryItems)
        .insert(
          LibraryItemsCompanion.insert(
            mediaId: mediaId,
            type: type,
            name: name,
            poster: Value(poster),
            background: Value(background),
          ),
        );
    return true;
  });
}

/// Watch positions. A video counts as watched past 92% (credits).
final class ProgressRepository {
  ProgressRepository(this._db, {this.onChanged});
  final AppDatabase _db;

  /// Told after a video's progress or watched mark changes (Trakt sync).
  final void Function(WatchProgressData row, {bool unwatched})? onChanged;
  static const watchedFraction = 0.92;

  Future<WatchProgressData?> get(String videoId) => (_db.select(
    _db.watchProgress,
  )..where((t) => t.videoId.equals(videoId))).getSingleOrNull();

  Stream<WatchProgressData?> watch(String videoId) => (_db.select(
    _db.watchProgress,
  )..where((t) => t.videoId.equals(videoId))).watchSingleOrNull();

  /// All progress rows of one show/movie (episode list badges).
  Stream<List<WatchProgressData>> watchMedia(String mediaId) => (_db.select(
    _db.watchProgress,
  )..where((t) => t.mediaId.equals(mediaId))).watch();

  /// Per title, the video watched last, newest first: unfinished ones to
  /// resume, and finished episodes (Home shows the episode after them).
  /// Finished movies and videos opened for under 30 s don't count.
  Stream<List<WatchProgressData>> watchContinue({int limit = 60}) {
    final q = _db.select(_db.watchProgress)
      ..where(
        (t) =>
            t.dismissed.equals(false) &
            (t.completed | t.positionMs.isBiggerThanValue(30000)),
      )
      ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]);
    return q.watch().map((rows) {
      final seen = <String>{};
      return [
        for (final r in rows)
          // (An episode's id isn't its show's; some have no season.)
          if (seen.add(r.mediaId) && (!r.completed || r.videoId != r.mediaId))
            r,
      ].take(limit).toList();
    });
  }

  Future<void> save({
    required String videoId,
    required String mediaId,
    required String type,
    required String name,
    required Duration position,
    required Duration duration,
    String? episodeTitle,
    int? season,
    int? episode,
    String? poster,
    String? still,
  }) async {
    final done =
        duration > Duration.zero &&
        position.inMilliseconds / duration.inMilliseconds >= watchedFraction;
    await _db
        .into(_db.watchProgress)
        .insertOnConflictUpdate(
          WatchProgressCompanion.insert(
            videoId: videoId,
            mediaId: mediaId,
            type: type,
            name: name,
            episodeTitle: Value(episodeTitle),
            season: Value(season),
            episode: Value(episode),
            positionMs: position.inMilliseconds,
            durationMs: duration.inMilliseconds,
            completed: Value(done),
            dismissed: const Value(false), // watching again brings it back
            poster: Value(poster),
            still: Value(still),
            updatedAt: Value(DateTime.now()),
          ),
        );
    await _told(videoId);
  }

  Future<void> setWatched(String videoId, {required bool watched}) async {
    await (_db.update(
      _db.watchProgress,
    )..where((t) => t.videoId.equals(videoId))).write(
      WatchProgressCompanion(
        completed: Value(watched),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await _told(videoId, unwatched: !watched);
  }

  Future<void> _told(String videoId, {bool unwatched = false}) async {
    final tell = onChanged;
    if (tell == null) return;
    final row = await get(videoId);
    if (row != null) tell(row, unwatched: unwatched);
  }

  /// Hides a title from Continue watching; progress and watched marks stay.
  Future<void> dismiss(String mediaId) =>
      (_db.update(_db.watchProgress)..where((t) => t.mediaId.equals(mediaId)))
          .write(const WatchProgressCompanion(dismissed: Value(true)));

  Future<void> remove(String mediaId) => (_db.delete(
    _db.watchProgress,
  )..where((t) => t.mediaId.equals(mediaId))).go();
}

/// Remembered audio/subtitle choice for a show and for each episode.
final class TrackChoice {
  const TrackChoice({
    this.audioLanguage,
    this.audioTrackId,
    this.subtitleLanguage,
    this.subtitleVariant,
    this.subtitleId,
    this.subtitleOffsetMs = 0,
  });

  final String? audioLanguage;
  final String? audioTrackId;

  /// null = no choice yet; 'off' via [subtitleVariant].
  final String? subtitleLanguage;
  final String? subtitleVariant;
  final String? subtitleId;
  final int subtitleOffsetMs;

  bool get subtitlesOff => subtitleVariant == 'off';
}

final class TrackMemoryRepository {
  TrackMemoryRepository(this._db);
  final AppDatabase _db;

  static String showKey(String mediaId) => 'media:$mediaId';
  static String videoKey(String videoId) => 'video:$videoId';

  Future<TrackChoice?> read(String key) async {
    final r = await (_db.select(
      _db.trackMemory,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    if (r == null) return null;
    return TrackChoice(
      audioLanguage: r.audioLanguage,
      audioTrackId: r.audioTrackId,
      subtitleLanguage: r.subtitleLanguage,
      subtitleVariant: r.subtitleVariant,
      subtitleId: r.subtitleId,
      subtitleOffsetMs: r.subtitleOffsetMs,
    );
  }

  /// Episode choice first, then the show's.
  Future<TrackChoice?> resolve({
    required String mediaId,
    required String videoId,
  }) async => await read(videoKey(videoId)) ?? await read(showKey(mediaId));

  /// Saves for both the episode and its show, so the next episode follows.
  Future<void> remember({
    required String mediaId,
    required String videoId,
    required TrackChoice choice,
  }) => _db.transaction(() async {
    await _write(videoKey(videoId), choice);
    // The show keeps languages/variant, not the episode-specific ids.
    await _write(
      showKey(mediaId),
      TrackChoice(
        audioLanguage: choice.audioLanguage,
        subtitleLanguage: choice.subtitleLanguage,
        subtitleVariant: choice.subtitleVariant,
        subtitleOffsetMs: choice.subtitleOffsetMs,
      ),
    );
  });

  Future<void> _write(String key, TrackChoice c) => _db
      .into(_db.trackMemory)
      .insertOnConflictUpdate(
        TrackMemoryCompanion.insert(
          key: key,
          audioLanguage: Value(c.audioLanguage),
          audioTrackId: Value(c.audioTrackId),
          subtitleLanguage: Value(c.subtitleLanguage),
          subtitleVariant: Value(c.subtitleVariant),
          subtitleId: Value(c.subtitleId),
          subtitleOffsetMs: Value(c.subtitleOffsetMs),
          updatedAt: Value(DateTime.now()),
        ),
      );
}
