import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/db/database.dart';
import 'play_request.dart';

/// Download rows for the Downloads tab, newest first.
final downloadsProvider = StreamProvider<List<DownloadRow>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(
    db.downloads,
  )..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).watch();
});

/// The download of one video, if any (episode badges, offline play).
final downloadForVideoProvider = StreamProvider.family<DownloadRow?, String>((
  ref,
  videoId,
) {
  final db = ref.watch(databaseProvider);
  return (db.select(
    db.downloads,
  )..where((t) => t.videoId.equals(videoId))).watchSingleOrNull();
});

/// Starts, pauses and removes downloads.
abstract interface class DownloadActions {
  /// Downloads [request] using its best (or chosen) release.
  Future<void> download(PlayRequest request);
  Future<void> pause(String downloadId);
  Future<void> resume(String downloadId);
  Future<void> remove(String downloadId);
}

// shortcut: replaced by the real service (engine + background transfers).
final downloadActionsProvider = Provider<DownloadActions>((ref) => _Pending());

final class _Pending implements DownloadActions {
  @override
  Future<void> download(PlayRequest request) async {}
  @override
  Future<void> pause(String downloadId) async {}
  @override
  Future<void> resume(String downloadId) async {}
  @override
  Future<void> remove(String downloadId) async {}
}

/// The finished download file for [videoId], if it's still on disk.
Future<String?> completedDownloadFile(AppDatabase db, String videoId) async {
  final row =
      await (db.select(db.downloads)..where(
            (t) => t.videoId.equals(videoId) & t.state.equals('completed'),
          ))
          .getSingleOrNull();
  final path = row?.filePath;
  return path != null && File(path).existsSync() ? path : null;
}

/// A torrent download of [videoId] still under way (or waiting), with its
/// torrent known: playing it streams that same torrent, so the downloaded
/// part plays at once.
Future<DownloadRow?> unfinishedTorrentDownload(
  AppDatabase db,
  String videoId,
) async {
  final rows =
      await (db.select(db.downloads)..where(
            (t) =>
                t.videoId.equals(videoId) &
                t.kind.equals('torrent') &
                t.infoHash.isNotNull() &
                t.state.isIn(['queued', 'downloading', 'paused']),
          ))
          .get();
  return rows.firstOrNull;
}

/// Subtitle files saved next to a download: [{lang, path, label}].
Future<List<Map<String, String>>> savedDownloadSubtitles(
  AppDatabase db,
  String videoId,
) async {
  final row = await (db.select(
    db.downloads,
  )..where((t) => t.videoId.equals(videoId))).getSingleOrNull();
  if (row == null) return const [];
  try {
    return [
      for (final e in jsonDecode(row.subtitlesJson) as List<Object?>)
        if (e is Map<String, Object?> &&
            e['path'] is String &&
            File(e['path']! as String).existsSync())
          {for (final kv in e.entries) kv.key: '${kv.value}'},
    ];
  } on FormatException {
    return const [];
  }
}
