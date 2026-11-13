import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/desktop.dart';
import '../../app/router.dart';
import '../../app/shell.dart';
import '../../core/db/database.dart';
import '../../core/format.dart';
import '../../services/downloads.dart';
import '../../services/play_request.dart';
import '../../ui/layout.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/artwork.dart';
import '../../ui/widgets/media.dart';
import '../../ui/widgets/sheet.dart';
import '../../ui/widgets/states.dart';
import '../settings/languages.dart';
import '../settings/widgets/settings_ui.dart';
import 'download_prompts.dart';
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

/// "about 6 min left" for a download moving at [bytesPerSecond].
String? etaLabel(int bytesLeft, double? bytesPerSecond) {
  if (bytesPerSecond == null || bytesPerSecond <= 0 || bytesLeft <= 0) {
    return null;
  }
  final minutes = (bytesLeft / bytesPerSecond / 60).round();
  if (minutes < 1) return 'less than a minute left';
  if (minutes < 60) return 'about $minutes min left';
  return 'about ${Fmt.duration(Duration(minutes: minutes))} left';
}

/// [rate] is the measured speed (bytes/s) of a moving download, for its
/// time left.
DownloadStatus downloadStatus(DownloadRow r, {double? rate}) {
  final pct = r.totalBytes > 0
      ? (r.doneBytes / r.totalBytes).clamp(0.0, 1.0)
      : null;
  final sizes = r.totalBytes <= 0
      ? null
      : r.doneBytes > 0
      ? '${Fmt.bytes(r.doneBytes)} of ${Fmt.bytes(r.totalBytes)}'
      // (Not on the phone yet, so the show's total leaves it out.)
      : '${Fmt.bytes(r.totalBytes)} to download';
  return switch (r.state) {
    'completed' => (
      strong: 'Downloaded',
      soft: Fmt.bytes(downloadBytes(r)),
      color: KColors.go,
      progress: null,
    ),
    'downloading' when pct != null => (
      strong: 'Downloading ${(pct * 100).floor()}%',
      soft: [
        ?sizes,
        if (rate != null && rate > 0) Fmt.speed(rate.round()),
        ?etaLabel(r.totalBytes - r.doneBytes, rate),
      ].join('  '),
      color: KColors.lamp,
      progress: pct,
    ),
    'downloading' => (
      strong: 'Finding people to download from',
      soft: null,
      color: KColors.lamp,
      progress: null,
    ),
    'queued' when r.error == waitingForTurn => (
      strong: waitingForTurn,
      soft: sizes,
      color: KColors.haze,
      progress: null,
    ),
    'paused' when r.error == waitingForWifi => (
      strong: waitingForWifi,
      soft: sizes,
      color: KColors.caution,
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

bool _waiting(DownloadRow r) =>
    r.state == 'paused' && r.error == waitingForWifi;

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

  /// Last size and measured speed of each moving download, for time left.
  // shortcut: measured from row updates here; a rate column or getter on
  // the downloads service would be steadier.
  final _speeds = <String, ({int bytes, DateTime at, double? rate})>{};

  double? _rate(DownloadRow r) {
    if (r.state != 'downloading') {
      _speeds.remove(r.id);
      return null;
    }
    final now = DateTime.now();
    final prev = _speeds[r.id];
    if (prev == null || r.doneBytes < prev.bytes) {
      _speeds[r.id] = (bytes: r.doneBytes, at: now, rate: null);
      return null;
    }
    final secs = now.difference(prev.at).inMilliseconds / 1000;
    if (r.doneBytes == prev.bytes) return secs > 15 ? null : prev.rate;
    if (secs <= 0) return prev.rate;
    final sample = (r.doneBytes - prev.bytes) / secs;
    final rate = prev.rate == null ? sample : prev.rate! * 0.7 + sample * 0.3;
    _speeds[r.id] = (bytes: r.doneBytes, at: now, rate: rate);
    return rate;
  }

  void _tap(DownloadRow r) => r.state == 'completed'
      ? _play(r)
      : _waiting(r)
      ? unawaited(showWifiWaitSheet(context, ref, r))
      : unawaited(_menu(r));

  DownloadActions get _actions => ref.read(downloadActionsProvider);

  void _play(DownloadRow r) {
    final path = r.filePath;
    if (path == null || !File(path).existsSync()) {
      showNote(
        context,
        'This file is no longer on $yourDevice. Delete it, then download it '
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
                  _ when _waiting(r) => 'Download on mobile data',
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
    final free = ref.watch(freeSpaceProvider).value;
    // One flat, lazily built list: an open show with hundreds of episodes
    // only builds the rows on screen.
    final items = <Widget Function()>[
      () => Padding(
        padding: const EdgeInsets.symmetric(horizontal: KSpace.margin),
        child: Semantics(
          header: true,
          child: Text('Downloads', style: KType.h1),
        ),
      ),
      () => _Summary(used: used, free: free),
    ];
    Widget row(DownloadRow r) => _EpisodeRow(
      row: r,
      rate: _rate(r),
      onTap: () => _tap(r),
      onMenu: () => unawaited(_menu(r)),
      onToggle: () => _waiting(r)
          ? unawaited(showWifiWaitSheet(context, ref, r))
          : unawaited(_toggle(r)),
    );
    for (final g in groups) {
      final first = g.first;
      if (!g.isShow) {
        items.add(
          () => _MovieRow(
            row: first,
            rate: _rate(first),
            onTap: () => _tap(first),
            onMenu: () => unawaited(_menu(first)),
            onToggle: () => _waiting(first)
                ? unawaited(showWifiWaitSheet(context, ref, first))
                : unawaited(_toggle(first)),
          ),
        );
        continue;
      }
      final open = _open.contains(first.mediaId);
      items.add(
        () => _ShowHeader(
          group: g,
          open: open,
          onToggleOpen: () => setState(() {
            if (!_open.remove(first.mediaId)) _open.add(first.mediaId);
          }),
          onDeleteShow: () =>
              unawaited(_delete(g.rows, 'all of ${first.title}')),
        ),
      );
      if (!open) continue;
      for (final MapEntry(key: season, value: list) in g.seasons.entries) {
        items.add(
          () => _SeasonHeader(
            title: first.title,
            season: season,
            rows: list,
            onDelete: () =>
                unawaited(_delete(list, 'season $season of ${first.title}')),
          ),
        );
        for (final r in list) {
          items.add(() => row(r));
        }
      }
    }
    return Scaffold(
      body: ListView.builder(
        padding: EdgeInsets.only(
          top: MediaQuery.paddingOf(context).top + KSpace.x4,
          bottom: AppShell.bottomInset(context),
          left: KLayout.side(context),
          right: KLayout.side(context),
        ),
        itemCount: items.length,
        itemBuilder: (_, i) => items[i](),
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
        if (free != null) '${Fmt.bytes(free!)} free on $thisDevice',
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
              ProgressLine(
                fraction: used / (used + free!),
                height: 4,
                trackAlpha: 0.16,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.row, this.rate});

  final DownloadRow row;
  final double? rate;

  @override
  Widget build(BuildContext context) {
    final s = downloadStatus(row, rate: rate);
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
            if (s.soft?.isNotEmpty ?? false)
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
String _statusSpoken(DownloadRow r, {double? rate}) {
  final s = downloadStatus(r, rate: rate);
  final subs = savedSubtitleLanguages(r);
  return [
    s.strong,
    if (s.soft?.isNotEmpty ?? false) s.soft!,
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
      // Waiting for Wi-Fi: asks before using mobile data.
      _ when _waiting(row) => (
        Icons.more_horiz_rounded,
        'Download options',
        onToggle,
      ),
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
    this.rate,
  });

  final DownloadRow row;
  final double? rate;
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
            label: '${row.title}. ${_statusSpoken(row, rate: rate)}',
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
                      Text(
                        row.title,
                        style: KType.title,
                        textDirection: contentDir(row.title),
                      ),
                      const SizedBox(height: KSpace.x1),
                      _Status(row: row, rate: rate),
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
    this.rate,
  });

  final DownloadRow row;
  final double? rate;
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
              label: [
                _spoken(row),
                ?name,
                _statusSpoken(row, rate: rate),
              ].join('. '),
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
                                  text: '  ${isolate(name)}',
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
                        _Status(row: row, rate: rate),
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

/// A show's row: poster, name and a summary; tap opens its episodes, long
/// press offers to delete the whole show.
class _ShowHeader extends StatelessWidget {
  const _ShowHeader({
    required this.group,
    required this.open,
    required this.onToggleOpen,
    required this.onDeleteShow,
  });

  final DownloadGroup group;
  final bool open;
  final VoidCallback onToggleOpen;
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
    return Pressable(
      label: '${first.title}. ${summary.join(', ')}',
      hint: open
          ? 'Hides episodes. Long press to delete the show'
          : 'Shows episodes. Long press to delete the show',
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
                  Text(
                    first.title,
                    style: KType.title,
                    textDirection: contentDir(first.title),
                  ),
                  const SizedBox(height: KSpace.x1),
                  Wrap(
                    spacing: KSpace.x3,
                    children: [for (final s in summary) Text(s, style: soft)],
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
