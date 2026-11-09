import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Every directory Kinora writes to. All of it is the user's to clear from
/// Settings › Storage, except the database and secure keys.
final class AppPaths {
  /// Creates paths from three roots (tests pass temp dirs).
  AppPaths({
    required this.support,
    required this.downloadsRoot,
    required this.cache,
  });

  /// Private app data: database, engine state, resume files, logs.
  final Directory support;

  /// Where finished downloads live (visible in the Files app on iOS).
  final Directory downloadsRoot;

  /// Purgeable data: stream buffers, subtitles, artwork.
  final Directory cache;

  Directory get downloads => Directory(p.join(downloadsRoot.path, 'Kinora'));

  /// Stream buffers. On Android they share the Downloads volume so keeping a
  /// finished stream is a rename, not a multi-GB copy.
  Directory get streams => Directory(
    Platform.isAndroid
        ? p.join(downloadsRoot.path, '.kinora-streams')
        : p.join(cache.path, 'streams'),
  );
  Directory get subtitles => Directory(p.join(cache.path, 'subtitles'));
  Directory get resume => Directory(p.join(support.path, 'resume'));
  Directory get logs => Directory(p.join(support.path, 'logs'));
  File get engineState => File(p.join(support.path, 'engine.state'));
  File get trackers => File(p.join(support.path, 'trackers.txt'));

  /// Resolves platform directories and creates the ones Kinora needs.
  static Future<AppPaths> resolve() async {
    final support = await getApplicationSupportDirectory();
    final cache = await getApplicationCacheDirectory();
    Directory downloads;
    if (Platform.isAndroid) {
      downloads = await getExternalStorageDirectory() ?? support;
    } else {
      downloads = await getApplicationDocumentsDirectory();
    }
    final paths = AppPaths(
      support: support,
      downloadsRoot: downloads,
      cache: cache,
    );
    await paths.ensure();
    return paths;
  }

  /// Creates every directory (idempotent) and keeps re-downloadable videos
  /// out of iCloud backups.
  Future<void> ensure() async {
    for (final d in [support, downloads, streams, subtitles, resume, logs]) {
      await d.create(recursive: true);
    }
    if (Platform.isIOS) {
      try {
        await const MethodChannel('kinora/files')
            .invokeMethod<bool>('excludeFromBackup', downloads.path);
      } on Object {
        // Not fatal: backups just include the videos.
      }
    }
  }
}

/// Total size of a directory tree in bytes (0 if missing).
Future<int> directorySize(Directory dir) async {
  if (!dir.existsSync()) return 0;
  var total = 0;
  await for (final e in dir.list(recursive: true, followLinks: false)) {
    if (e is File) {
      try {
        total += await e.length();
      } on FileSystemException {
        // Vanished mid-scan (stream cache churn); skip.
      }
    }
  }
  return total;
}

/// Deletes everything inside [dir] but keeps the directory.
Future<void> clearDirectory(Directory dir) async {
  if (!dir.existsSync()) return;
  await for (final e in dir.list(followLinks: false)) {
    try {
      await e.delete(recursive: true);
    } on FileSystemException {
      // In use (an open stream); it'll be cleared next time.
    }
  }
}
