import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

/// Stremio-compatible addons the user added. Nothing is added by default.
class Addons extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Base URL (manifest URL without `/manifest.json`), config segments kept.
  TextColumn get transportUrl => text().unique()();
  TextColumn get manifestJson => text()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  IntColumn get position => integer().withDefault(const Constant(0))();
  DateTimeColumn get addedAt => dateTime().withDefault(currentDateAndTime)();
}

/// "My list".
class LibraryItems extends Table {
  TextColumn get mediaId => text()();
  TextColumn get type => text()();
  TextColumn get name => text()();
  TextColumn get poster => text().nullable()();
  TextColumn get background => text().nullable()();
  DateTimeColumn get addedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {mediaId};
}

/// Playback position per video (movie id or episode id like `tt1:1:2`).
class WatchProgress extends Table {
  TextColumn get videoId => text()();
  TextColumn get mediaId => text()();
  TextColumn get type => text()();
  TextColumn get name => text()();
  TextColumn get episodeTitle => text().nullable()();
  IntColumn get season => integer().nullable()();
  IntColumn get episode => integer().nullable()();
  IntColumn get positionMs => integer()();
  IntColumn get durationMs => integer()();
  BoolColumn get completed => boolean().withDefault(const Constant(false))();
  TextColumn get poster => text().nullable()();
  TextColumn get still => text().nullable()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {videoId};
}

/// Remembered audio/subtitle choices. Keyed by show (`media:<id>`) and by
/// episode (`video:<id>`), never by file, so streams and downloads share it.
class TrackMemory extends Table {
  TextColumn get key => text()();
  TextColumn get audioLanguage => text().nullable()();
  TextColumn get audioTrackId => text().nullable()();
  TextColumn get subtitleLanguage => text().nullable()();

  /// 'off' | 'normal' | 'sdh' | 'forced'
  TextColumn get subtitleVariant => text().nullable()();
  TextColumn get subtitleId => text().nullable()();
  IntColumn get subtitleOffsetMs => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {key};
}

/// Downloads, torrent or HTTP (debrid).
class Downloads extends Table {
  TextColumn get id => text()();
  TextColumn get mediaId => text()();
  TextColumn get videoId => text()();
  TextColumn get type => text()();
  TextColumn get title => text()();
  TextColumn get episodeTitle => text().nullable()();
  IntColumn get season => integer().nullable()();
  IntColumn get episode => integer().nullable()();
  TextColumn get poster => text().nullable()();
  TextColumn get still => text().nullable()();
  TextColumn get releaseName => text()();

  /// 'torrent' | 'http'
  TextColumn get kind => text()();
  TextColumn get infoHash => text().nullable()();
  IntColumn get fileIndex => integer().nullable()();
  TextColumn get url => text().nullable()();
  TextColumn get magnet => text().nullable()();

  /// Folder holding the video (and its subtitles).
  TextColumn get directory => text()();

  /// Final video file once known.
  TextColumn get filePath => text().nullable()();
  IntColumn get totalBytes => integer().withDefault(const Constant(0))();
  IntColumn get doneBytes => integer().withDefault(const Constant(0))();

  /// 'queued' | 'downloading' | 'paused' | 'completed' | 'failed'
  TextColumn get state => text()();
  TextColumn get error => text().nullable()();

  /// JSON list of {lang, path, label} saved next to the video.
  TextColumn get subtitlesJson => text().withDefault(const Constant('[]'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get completedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Small key → JSON value store (settings, caches of tiny things).
class KeyValues extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Recent searches.
class SearchHistory extends Table {
  TextColumn get query => text()();
  DateTimeColumn get at => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {query};
}

@DriftDatabase(
  tables: [
    Addons,
    LibraryItems,
    WatchProgress,
    TrackMemory,
    Downloads,
    KeyValues,
    SearchHistory,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// Opens `kinora.sqlite` in [directory].
  AppDatabase.open(String directory)
    : super(
        driftDatabase(
          name: 'kinora',
          native: DriftNativeOptions(databaseDirectory: () async => directory),
        ),
      );

  /// For tests.
  AppDatabase.forExecutor(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
