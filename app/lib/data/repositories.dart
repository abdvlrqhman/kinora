import 'package:drift/drift.dart';

import '../core/db/database.dart';

/// "My list".
final class LibraryRepository {
  LibraryRepository(this._db);
  final AppDatabase _db;

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
  }) => _db.transaction(() async {
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
  ProgressRepository(this._db);
  final AppDatabase _db;
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

  /// Most recent unfinished video per title, newest first.
  Stream<List<WatchProgressData>> watchContinue({int limit = 20}) {
    final q = _db.select(_db.watchProgress)
      ..where(
        (t) =>
            t.completed.equals(false) & t.positionMs.isBiggerThanValue(30000),
      )
      ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]);
    return q.watch().map((rows) {
      final seen = <String>{};
      return [
        for (final r in rows)
          if (seen.add(r.mediaId)) r,
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
  }) {
    final done =
        duration > Duration.zero &&
        position.inMilliseconds / duration.inMilliseconds >= watchedFraction;
    return _db
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
            poster: Value(poster),
            still: Value(still),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  Future<void> setWatched(String videoId, {required bool watched}) =>
      (_db.update(
        _db.watchProgress,
      )..where((t) => t.videoId.equals(videoId))).write(
        WatchProgressCompanion(
          completed: Value(watched),
          updatedAt: Value(DateTime.now()),
        ),
      );

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
