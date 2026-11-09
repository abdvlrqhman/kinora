import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/shell.dart';
import '../../core/db/database.dart';
import '../../core/format.dart';
import '../../services/downloads.dart';
import '../../services/play_request.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/artwork.dart';
import '../../ui/widgets/media.dart';
import '../../ui/widgets/sheet.dart';
import '../../ui/widgets/states.dart';
import '../settings/languages.dart';
import '../settings/widgets/settings_ui.dart';
import 'storage.dart';

/// Bytes a download takes on the phone right now.
int downloadBytes(DownloadRow r) => r.state == 'completed'
    ? (r.totalBytes > r.doneBytes ? r.totalBytes : r.doneBytes)
    : r.doneBytes;

/// One title in Downloads: a movie, or a show with its episodes in order.
final class DownloadGroup {
  DownloadGroup(this.rows);

  /// Sorted by season, then episode.
  final List<DownloadRow> rows;

  DownloadRow get first => rows.first;
  bool get isShow => rows.any((r) => r.season != null);
  int get bytes => rows.fold(0, (a, r) => a + downloadBytes(r));

  Map<int, List<DownloadRow>> get seasons {
    final out = <int, List<DownloadRow>>{};
    for (final r in rows) {
      (out[r.season ?? 0] ??= []).add(r);
    }
    return out;
  }
}

/// Groups rows by title, newest title first (rows arrive newest first).
List<DownloadGroup> groupDownloads(List<DownloadRow> rows) {
  final byTitle = <String, List<DownloadRow>>{};
  for (final r in rows) {
    (byTitle[r.mediaId] ??= []).add(r);
  }
  return [
    for (final list in byTitle.values)
      DownloadGroup(
        list..sort(
          (a, b) => (a.season ?? 0) != (b.season ?? 0)
              ? (a.season ?? 0).compareTo(b.season ?? 0)
              : (a.episode ?? 0).compareTo(b.episode ?? 0),
        ),
      ),
  ];
}

/// Status of a download in words: a strong part, an optional soft part
/// (sizes), its color and progress (0..1) while it's moving.
typedef DownloadStatus = ({
  String strong,
  String? soft,
  Color color,
  double? progress,
});

DownloadStatus downloadStatus(DownloadRow r) {
  final pct = r.totalBytes > 0
      ? (r.doneBytes / r.totalBytes).clamp(0.0, 1.0)
      : null;
  final sizes = r.totalBytes <= 0
      ? null
      : r.doneBytes > 0
      ? '${Fmt.bytes(r.doneBytes)} of ${Fmt.bytes(r.totalBytes)}'
      : Fmt.bytes(r.totalBytes);
  return switch (r.state) {
    'completed' => (
      strong: 'Downloaded',
      soft: Fmt.bytes(downloadBytes(r)),
      color: KColors.go,
      progress: null,
    ),
    'downloading' when pct != null => (
      strong: 'Downloading ${(pct * 100).floor()}%',
      soft: sizes,
      color: KColors.lamp,
      progress: pct,
    ),
    'downloading' => (
      strong: 'Finding people to download from',
      soft: null,
      color: KColors.lamp,
      progress: null,
    ),
    'paused' when r.error == 'Waiting for Wi-Fi' => (
      strong: 'Waiting for Wi-Fi',
      soft: sizes,
      color: KColors.marquee,
      progress: null,
    ),
    'paused' => (
      strong: pct == null ? 'Paused' : 'Paused at ${(pct * 100).floor()}%',
      soft: sizes,
      color: KColors.haze,
      progress: null,
    ),
    'failed' => (
      strong: 'Couldn’t download',
      soft: r.error ?? 'Try again.',
      color: KColors.cut,
      progress: null,
    ),
    _ => (
      strong: r.releaseName == 'Finding the best version'
          ? 'Finding the best version'
          : 'Waiting to start',
      soft: null,
      color: KColors.haze,
      progress: null,
    ),
  };
}

/// Languages of the subtitles saved next to a download.
List<String> savedSubtitleLanguages(DownloadRow r) {
  try {
    return {
      for (final e in jsonDecode(r.subtitlesJson) as List<Object?>)
        if (e is Map<String, Object?> && e['lang'] is String)
          languageName(e['lang']! as String),
    }.toList();
  } on FormatException {
    return const [];
  }
}

String _episodeLabel(DownloadRow r) => r.season != null && r.episode != null
    ? Fmt.episode(r.season!, r.episode!)
    : r.title;

String _spoken(DownloadRow r) => r.season != null && r.episode != null
    ? '${r.title}, season ${r.season} episode ${r.episode}'
    : r.title;

/// The Downloads tab: grouped by title, live progress, play offline.
class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  final _open = <String>{};

  DownloadActions get _actions => ref.read(downloadActionsProvider);

  void _play(DownloadRow r) {
    final path = r.filePath;
    if (path == null || !File(path).existsSync()) {
      showNote(
        context,
        'This file is no longer on your phone. Delete it, then download it '
        'again.',
      );
      return;
    }
    openPlayer(
      context,
      PlayRequest(
        type: r.type,
        mediaId: r.mediaId,
        videoId: r.videoId,
        title: r.title,
        episodeTitle: r.episodeTitle,
        season: r.season,
        episode: r.episode,
        poster: r.poster,
        still: r.still,
        localFile: path,
      ),
    );
  }

  Future<void> _delete(List<DownloadRow> rows, String what) async {
    final bytes = rows.fold(0, (a, r) => a + downloadBytes(r));
    final ok = await confirmAction(
      context,
      title: 'Delete $what?',
      message: bytes > 0
          ? 'Frees ${Fmt.bytes(bytes)}. You can download it again later.'
          : 'You can download it again later.',
      action: 'Delete',
    );
    if (!ok) return;
    for (final r in rows) {
      await _actions.remove(r.id);
    }
  }

  Future<void> _toggle(DownloadRow r) => switch (r.state) {
    'downloading' || 'queued' => _actions.pause(r.id),
    _ => _actions.resume(r.id),
  };

  Future<void> _menu(DownloadRow r) async {
    final label = r.season != null ? '${r.title} ${_episodeLabel(r)}' : r.title;
    final choice = await showGlassSheet<String>(
      context,
      builder: (sheet) => SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                KSpace.margin,
                KSpace.x3,
                KSpace.margin,
                KSpace.x2,
              ),
              child: Text(label, style: KType.h2),
            ),
            if (r.state == 'completed')
              SheetAction(
                icon: Icons.play_arrow_rounded,
                label: 'Play',
                onTap: () => Navigator.pop(sheet, 'play'),
              )
            else
              SheetAction(
                icon: switch (r.state) {
                  'downloading' || 'queued' => Icons.pause_rounded,
                  _ => Icons.download_rounded,
                },
                label: switch (r.state) {
                  'downloading' || 'queued' => 'Pause download',
                  'failed' => 'Try again',
                  _ => 'Resume download',
                },
                onTap: () => Navigator.pop(sheet, 'toggle'),
              ),
            SheetAction(
              icon: Icons.delete_outline_rounded,
              label: 'Delete download',
              color: KColors.cut,
              onTap: () => Navigator.pop(sheet, 'delete'),
            ),
          ],
        ),
      ),
    );
    switch (choice) {
      case 'play':
        _play(r);
      case 'toggle':
        await _toggle(r);
      case 'delete':
        await _delete([r], label);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(downloadsProvider);
    final rows = async.value;
    if (rows == null) {
      return Scaffold(
        body: async.hasError
            ? ErrorState(
                message: friendlyError(async.error!),
                onRetry: () => ref.invalidate(downloadsProvider),
              )
            : const SizedBox.shrink(),
      );
    }
    if (rows.isEmpty) {
      return Scaffold(
        body: Padding(
          padding: EdgeInsets.only(bottom: AppShell.bottomInset(context)),
          child: EmptyState(
            icon: Icons.download_rounded,
            title: 'Nothing here yet',
            message:
                'Downloads you start, and episodes you stream to the end, '
                'appear here.',
            actionLabel: 'Find something to watch',
            onAction: () => context.go('/search'),
          ),
        ),
      );
    }
    final groups = groupDownloads(rows);
    final used = groups.fold(0, (a, g) => a + g.bytes);
    return Scaffold(
      body: ListView(
        padding: EdgeInsets.only(
          top: MediaQuery.paddingOf(context).top + KSpace.x4,
          bottom: AppShell.bottomInset(context),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: KSpace.margin),
            child: Semantics(
              header: true,
              child: Text('Downloads', style: KType.h1),
            ),
          ),
          _Summary(used: used, free: ref.watch(freeSpaceProvider).value),
          for (final g in groups)
            if (g.isShow)
              _ShowGroup(
                group: g,
                open: _open.contains(g.first.mediaId),
                onToggleOpen: () => setState(() {
                  if (!_open.remove(g.first.mediaId)) {
                    _open.add(g.first.mediaId);
                  }
                }),
                episode: (r) => _EpisodeRow(
                  row: r,
                  onTap: () =>
                      r.state == 'completed' ? _play(r) : unawaited(_menu(r)),
                  onMenu: () => unawaited(_menu(r)),
                  onToggle: () => unawaited(_toggle(r)),
                ),
                onDeleteSeason: (season, rows) => unawaited(
                  _delete(rows, 'season $season of ${g.first.title}'),
                ),
                onDeleteShow: () =>
                    unawaited(_delete(g.rows, 'all of ${g.first.title}')),
              )
            else
              _MovieRow(
                row: g.first,
                onTap: () => g.first.state == 'completed'
                    ? _play(g.first)
                    : unawaited(_menu(g.first)),
                onMenu: () => unawaited(_menu(g.first)),
                onToggle: () => unawaited(_toggle(g.first)),
              ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.used, required this.free});

  final int used;
  final int? free;

  @override
  Widget build(BuildContext context) {
    final soft = KType.tabular(KType.label.copyWith(color: KColors.haze));
    final strong = KType.tabular(
      KType.label.copyWith(fontWeight: FontWeight.w700),
    );
    return Semantics(
      label: [
        'Downloads use ${Fmt.bytes(used)}',
        if (free != null) '${Fmt.bytes(free!)} free on this phone',
      ].join('. '),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          KSpace.margin,
          KSpace.x2,
          KSpace.margin,
          KSpace.x3,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: KSpace.x4,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: Fmt.bytes(used), style: strong),
                      TextSpan(text: ' used by Kinora', style: soft),
                    ],
                  ),
                ),
                if (free != null)
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: Fmt.bytes(free!), style: strong),
                        TextSpan(text: ' free', style: soft),
                      ],
                    ),
                  ),
              ],
            ),
            if (free != null && used + free! > 0) ...[
              const SizedBox(height: KSpace.x2),
              ProgressLine(fraction: used / (used + free!)),
            ],
          ],
        ),
      ),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.row});

  final DownloadRow row;

  @override
  Widget build(BuildContext context) {
    final s = downloadStatus(row);
    final subs = savedSubtitleLanguages(row);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: KSpace.x2,
          children: [
            Text(
              s.strong,
              style: KType.tabular(
                KType.label.copyWith(
                  color: s.color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (s.soft != null)
              Text(
                s.soft!,
                style: KType.tabular(
                  KType.label.copyWith(
                    color: row.state == 'failed' ? KColors.cut : KColors.haze,
                  ),
                ),
              ),
          ],
        ),
        if (s.progress != null) ...[
          const SizedBox(height: 6),
          ProgressLine(fraction: s.progress!),
        ],
        if (subs.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('Subtitles in ${subs.join(', ')}', style: KType.small),
        ],
      ],
    );
  }
}

/// "Downloaded 2.6 GB. Subtitles in Arabic."
String _statusSpoken(DownloadRow r) {
  final s = downloadStatus(r);
  final subs = savedSubtitleLanguages(r);
  return [
    s.strong,
    ?s.soft,
    if (subs.isNotEmpty) 'Subtitles in ${subs.join(', ')}',
  ].join('. ');
}

/// The one trailing control: pause/resume while moving, options when done.
class _Trailing extends StatelessWidget {
  const _Trailing({
    required this.row,
    required this.onMenu,
    required this.onToggle,
  });

  final DownloadRow row;
  final VoidCallback onMenu;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final (icon, label, onTap) = switch (row.state) {
      'completed' => (Icons.more_horiz_rounded, 'Options', onMenu),
      'downloading' || 'queued' => (Icons.pause_rounded, 'Pause', onToggle),
      'failed' => (Icons.refresh_rounded, 'Try again', onToggle),
      _ => (Icons.download_rounded, 'Resume', onToggle),
    };
    return Semantics(
      container: true,
      button: true,
      label: '$label, ${_spoken(row)}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox.square(
          dimension: 48,
          child: Icon(icon, color: KColors.haze, size: 24),
        ),
      ),
    );
  }
}

Map<CustomSemanticsAction, VoidCallback> _a11y(VoidCallback onMenu) => {
  const CustomSemanticsAction(label: 'Download options'): onMenu,
};

class _MovieRow extends StatelessWidget {
  const _MovieRow({
    required this.row,
    required this.onTap,
    required this.onMenu,
    required this.onToggle,
  });

  final DownloadRow row;
  final VoidCallback onTap;
  final VoidCallback onMenu;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      KSpace.margin,
      KSpace.x2,
      KSpace.x2,
      KSpace.x2,
    ),
    child: Row(
      children: [
        Expanded(
          child: Pressable(
            label: '${row.title}. ${_statusSpoken(row)}',
            hint: row.state == 'completed' ? 'Plays offline' : null,
            onTap: onTap,
            onLongPress: onMenu,
            actions: _a11y(onMenu),
            child: Row(
              children: [
                SizedBox(
                  width: 64,
                  child: Artwork(
                    url: row.poster,
                    fallbackText: row.title,
                    radius: KRadius.poster,
                    aspectRatio: 2 / 3,
                    memCacheWidth: decodeWidth(context, 64),
                  ),
                ),
                const SizedBox(width: KSpace.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(row.title, style: KType.title),
                      const SizedBox(height: KSpace.x1),
                      _Status(row: row),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        _Trailing(row: row, onMenu: onMenu, onToggle: onToggle),
      ],
    ),
  );
}

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({
    required this.row,
    required this.onTap,
    required this.onMenu,
    required this.onToggle,
  });

  final DownloadRow row;
  final VoidCallback onTap;
  final VoidCallback onMenu;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final label = _episodeLabel(row);
    final name = row.episodeTitle;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KSpace.margin,
        KSpace.x2,
        KSpace.x2,
        KSpace.x2,
      ),
      child: Row(
        children: [
          Expanded(
            child: Pressable(
              label: [_spoken(row), ?name, _statusSpoken(row)].join('. '),
              hint: row.state == 'completed' ? 'Plays offline' : null,
              onTap: onTap,
              onLongPress: onMenu,
              actions: _a11y(onMenu),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 112,
                    child: Artwork(
                      url: row.still ?? row.poster,
                      radius: KRadius.still,
                      aspectRatio: 16 / 9,
                      alignment: row.still == null
                          ? Alignment.topCenter
                          : Alignment.center,
                      memCacheWidth: decodeWidth(context, 112),
                    ),
                  ),
                  const SizedBox(width: KSpace.x3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: label,
                                style: KType.tabular(
                                  KType.label.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (name != null)
                                TextSpan(
                                  text: '  $name',
                                  style: KType.label.copyWith(
                                    color: KColors.haze,
                                  ),
                                ),
                            ],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: KSpace.x1),
                        _Status(row: row),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          _Trailing(row: row, onMenu: onMenu, onToggle: onToggle),
        ],
      ),
    );
  }
}

class _ShowGroup extends StatelessWidget {
  const _ShowGroup({
    required this.group,
    required this.open,
    required this.onToggleOpen,
    required this.episode,
    required this.onDeleteSeason,
    required this.onDeleteShow,
  });

  final DownloadGroup group;
  final bool open;
  final VoidCallback onToggleOpen;
  final Widget Function(DownloadRow) episode;
  final void Function(int season, List<DownloadRow> rows) onDeleteSeason;
  final VoidCallback onDeleteShow;

  @override
  Widget build(BuildContext context) {
    final first = group.first;
    final n = group.rows.length;
    final active = group.rows.where((r) => r.state != 'completed').length;
    final soft = KType.tabular(KType.label.copyWith(color: KColors.haze));
    final reduce = reduceMotion(context);
    final summary = [
      n == 1 ? '1 episode' : '$n episodes',
      Fmt.bytes(group.bytes),
      if (active > 0) '$active in progress',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Pressable(
          label: '${first.title}. ${summary.join(', ')}',
          hint: open ? 'Hides episodes' : 'Shows episodes',
          onTap: onToggleOpen,
          onLongPress: onDeleteShow,
          actions: {
            const CustomSemanticsAction(label: 'Delete show'): onDeleteShow,
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              KSpace.margin,
              KSpace.x2,
              KSpace.x2,
              KSpace.x2,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 64,
                  child: Artwork(
                    url: first.poster,
                    fallbackText: first.title,
                    radius: KRadius.poster,
                    aspectRatio: 2 / 3,
                    memCacheWidth: decodeWidth(context, 64),
                  ),
                ),
                const SizedBox(width: KSpace.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(first.title, style: KType.title),
                      const SizedBox(height: KSpace.x1),
                      Wrap(
                        spacing: KSpace.x3,
                        children: [
                          for (final s in summary) Text(s, style: soft),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox.square(
                  dimension: 48,
                  child: AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: reduce ? Duration.zero : KMotion.base,
                    curve: KMotion.curve,
                    child: const Icon(
                      Icons.expand_more_rounded,
                      color: KColors.haze,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: reduce ? Duration.zero : KMotion.base,
          curve: KMotion.curve,
          alignment: Alignment.topCenter,
          child: !open
              ? const SizedBox(width: double.infinity)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final MapEntry(key: season, value: rows)
                        in group.seasons.entries) ...[
                      _SeasonHeader(
                        title: first.title,
                        season: season,
                        rows: rows,
                        onDelete: () => onDeleteSeason(season, rows),
                      ),
                      for (final r in rows) episode(r),
                    ],
                    ActionRow(
                      icon: Icons.delete_outline_rounded,
                      label: 'Delete show',
                      detail: 'Removes every downloaded episode.',
                      color: KColors.cut,
                      onTap: onDeleteShow,
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _SeasonHeader extends StatelessWidget {
  const _SeasonHeader({
    required this.title,
    required this.season,
    required this.rows,
    required this.onDelete,
  });

  final String title;
  final int season;
  final List<DownloadRow> rows;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final name = season == 0 ? 'Specials' : 'Season $season';
    final bytes = rows.fold(0, (a, r) => a + downloadBytes(r));
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KSpace.margin,
        KSpace.x3,
        KSpace.x2,
        0,
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Wrap(
                spacing: KSpace.x3,
                crossAxisAlignment: WrapCrossAlignment.end,
                children: [
                  Text(name, style: KType.h2),
                  if (bytes > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        Fmt.bytes(bytes),
                        style: KType.tabular(
                          KType.label.copyWith(color: KColors.haze),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Semantics(
            container: true,
            button: true,
            label: 'Delete $name of $title',
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onDelete,
              child: const SizedBox.square(
                dimension: 48,
                child: Icon(
                  Icons.delete_outline_rounded,
                  color: KColors.haze,
                  size: 22,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
