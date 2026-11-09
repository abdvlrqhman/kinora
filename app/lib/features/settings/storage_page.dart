import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../core/paths.dart';
import '../../services/downloads.dart';
import '../../ui/tokens.dart';
import '../downloads/storage.dart';
import 'widgets/settings_ui.dart';

/// Posters and backdrops cached by cached_network_image.
typedef ArtworkCache = ({
  Future<int> Function() size,
  Future<void> Function() clear,
});

final artworkCacheProvider = Provider<ArtworkCache>(
  (_) => (
    size: () async {
      final tmp = await getTemporaryDirectory();
      return directorySize(
        Directory(p.join(tmp.path, DefaultCacheManager.key)),
      );
    },
    clear: () async {
      await DefaultCacheManager().emptyCache();
      PaintingBinding.instance.imageCache.clear();
    },
  ),
);

/// One kind of data Kinora keeps on the phone.
enum StorageKind { downloads, streams, subtitles, artwork, logs }

/// Bytes per kind (scanned when Storage opens).
final storageUsageProvider = FutureProvider.autoDispose<Map<StorageKind, int>>((
  ref,
) async {
  final paths = ref.watch(pathsProvider);
  final art = ref.watch(artworkCacheProvider);
  Future<int> safe(Future<int> Function() f) async {
    try {
      return await f();
    } on Object {
      return 0;
    }
  }

  final sizes = await Future.wait([
    safe(() => directorySize(paths.downloads)),
    safe(() => directorySize(paths.streams)),
    safe(() => directorySize(paths.subtitles)),
    safe(art.size),
    safe(() => directorySize(paths.logs)),
  ]);
  return {for (final (i, k) in StorageKind.values.indexed) k: sizes[i]};
});

/// Deletes every download (files and rows), then anything left in the
/// downloads folder. Returns how many were removed.
Future<int> deleteAllDownloads(WidgetRef ref) async {
  final db = ref.read(databaseProvider);
  final rows = await db.select(db.downloads).get();
  final actions = ref.read(downloadActionsProvider);
  for (final r in rows) {
    await actions.remove(r.id);
  }
  await clearDirectory(ref.read(pathsProvider).downloads);
  return rows.length;
}

/// Empties the log files. The current one is truncated, not deleted, so
/// the open log keeps writing to it.
Future<void> clearLogs(Directory dir) async {
  if (!dir.existsSync()) return;
  for (final f in dir.listSync().whereType<File>()) {
    try {
      if (p.basename(f.path) == 'kinora.log') {
        f.writeAsBytesSync(const [], flush: true);
      } else {
        f.deleteSync();
      }
    } on FileSystemException {
      // In use; it'll go next time.
    }
  }
}

/// Settings › Storage: what Kinora keeps, with a Clear for each.
class StoragePage extends ConsumerWidget {
  const StoragePage({super.key});

  static const _text = {
    StorageKind.downloads: (
      'Downloads',
      'Movies and episodes saved to watch offline.',
    ),
    StorageKind.streams: (
      'Stream buffer',
      'Parts of videos you streamed. They’re fetched again when needed.',
    ),
    StorageKind.subtitles: ('Subtitles', 'Subtitle files fetched to play.'),
    StorageKind.artwork: (
      'Artwork',
      'Posters and backdrops. They load again from your sources.',
    ),
    StorageKind.logs: ('Logs', 'Diagnostics kept on this phone only.'),
  };

  Future<void> _clear(
    BuildContext context,
    WidgetRef ref,
    StorageKind kind,
    int size,
  ) async {
    final name = _text[kind]!.$1;
    final downloads = kind == StorageKind.downloads;
    final ok = await confirmAction(
      context,
      title: downloads ? 'Delete all downloads?' : 'Clear $name?',
      message: downloads
          ? 'Removes every download (${Fmt.bytes(size)}) from this phone. '
                'You can download them again later.'
          : kind == StorageKind.streams
          ? 'Frees ${Fmt.bytes(size)}. What’s playing right now keeps '
                'playing.'
          : 'Frees ${Fmt.bytes(size)}.',
      action: downloads ? 'Delete all downloads' : 'Clear',
    );
    if (!ok) return;
    final paths = ref.read(pathsProvider);
    switch (kind) {
      case StorageKind.downloads:
        await deleteAllDownloads(ref);
      case StorageKind.streams:
        await clearDirectory(paths.streams);
      case StorageKind.subtitles:
        await clearDirectory(paths.subtitles);
      case StorageKind.artwork:
        await ref.read(artworkCacheProvider).clear();
      case StorageKind.logs:
        await clearLogs(paths.logs);
    }
    ref.invalidate(storageUsageProvider);
    ref.invalidate(freeSpaceProvider);
    if (context.mounted) {
      showNote(
        context,
        downloads ? 'Deleted all downloads.' : 'Cleared $name.',
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usage = ref.watch(storageUsageProvider);
    final free = ref.watch(freeSpaceProvider).value;
    final sizes = usage.value;
    final total = sizes?.values.fold<int>(0, (a, b) => a + b);
    return SettingsPage(
      title: 'Storage',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            KSpace.margin,
            KSpace.x3,
            KSpace.margin,
            KSpace.x2,
          ),
          child: Semantics(
            label: [
              if (total != null) 'Kinora uses ${Fmt.bytes(total)}',
              if (free != null) '${Fmt.bytes(free)} free on this phone',
            ].join('. '),
            excludeSemantics: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  total == null ? ' ' : Fmt.bytes(total),
                  style: KType.tabular(KType.hero),
                ),
                Text(
                  [
                    'used by Kinora',
                    if (free != null) '${Fmt.bytes(free)} free on this phone',
                  ].join('    '),
                  style: KType.tabular(
                    KType.body.copyWith(color: KColors.haze),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (usage.hasError)
          const Note(
            'Couldn’t measure storage. Leave this page and open it again.',
            color: KColors.cut,
          ),
        for (final kind in StorageKind.values)
          _StorageRow(
            name: _text[kind]!.$1,
            detail: _text[kind]!.$2,
            size: sizes?[kind],
            action: kind == StorageKind.downloads ? 'Delete all' : 'Clear',
            onClear: sizes == null || (sizes[kind] ?? 0) == 0
                ? null
                : () => unawaited(_clear(context, ref, kind, sizes[kind]!)),
          ),
        const Note(
          'Your settings, sources and keys aren’t counted here. Remove them '
          'from their own pages.',
          top: KSpace.x4,
        ),
      ],
    );
  }
}

class _StorageRow extends StatelessWidget {
  const _StorageRow({
    required this.name,
    required this.detail,
    required this.size,
    required this.action,
    required this.onClear,
  });

  final String name;
  final String detail;
  final int? size;
  final String action;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final sizeText = size == null ? 'Measuring' : Fmt.bytes(size!);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KSpace.margin,
        KSpace.x3,
        KSpace.x2,
        KSpace.x3,
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              label: '$name, $sizeText. $detail',
              excludeSemantics: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: KSpace.x3,
                    crossAxisAlignment: WrapCrossAlignment.end,
                    children: [
                      Text(name, style: KType.title),
                      Text(
                        sizeText,
                        style: KType.tabular(
                          KType.title.copyWith(
                            color: KColors.haze,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: KType.label.copyWith(color: KColors.haze),
                  ),
                ],
              ),
            ),
          ),
          Semantics(
            container: true,
            button: true,
            enabled: onClear != null,
            label: '$action $name',
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onClear,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: KSpace.x3,
                    vertical: KSpace.x3,
                  ),
                  child: Text(
                    action,
                    style: KType.title.copyWith(
                      color: onClear == null ? KColors.reel : KColors.cut,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
