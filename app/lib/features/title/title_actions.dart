import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stremio/stremio.dart';

import '../../app/router.dart';
import '../../core/db/database.dart';
import '../../services/downloads.dart';
import '../../services/library.dart';
import '../../services/play_request.dart';
import '../../services/resolver.dart';
import '../../ui/glass.dart';
import '../../ui/tokens.dart';

/// Adds or removes a title from My list (+ / ✓).
class MyListButton extends ConsumerWidget {
  const MyListButton({super.key, required this.meta});

  final MetaPreview meta;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inList = ref.watch(
      inMyListProvider(meta.id).select((a) => a.value ?? false),
    );
    return GlassButton(
      label: 'My list',
      icon: inList ? Icons.check_rounded : Icons.add_rounded,
      semanticLabel: inList
          ? 'In My list. Remove ${meta.name}'
          : 'Add ${meta.name} to My list',
      onPressed: () => unawaited(_toggle(ref, meta)),
    );
  }
}

Future<bool> _toggle(WidgetRef ref, MetaPreview meta) => ref
    .read(libraryRepositoryProvider)
    .toggle(
      mediaId: meta.id,
      type: meta.type,
      name: meta.name,
      poster: meta.poster,
      background: meta.background,
    );

/// A round glass control with a short label underneath.
class ActionTile extends StatelessWidget {
  const ActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.semanticLabel,
    required this.onPressed,
    this.color = KColors.lamp,
  });

  final IconData icon;
  final String label;
  final String semanticLabel;
  final VoidCallback? onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      GlassIconButton(icon: icon, label: semanticLabel, onPressed: onPressed),
      const SizedBox(height: 6),
      ExcludeSemantics(
        child: Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          style: KType.small.copyWith(color: color),
        ),
      ),
    ],
  );
}

/// The My list action as an [ActionTile].
class MyListAction extends ConsumerWidget {
  const MyListAction({super.key, required this.meta});

  final MetaPreview meta;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inList = ref.watch(
      inMyListProvider(meta.id).select((a) => a.value ?? false),
    );
    return ActionTile(
      icon: inList ? Icons.check_rounded : Icons.add_rounded,
      label: 'My list',
      semanticLabel: inList ? 'In My list. Remove' : 'Add to My list',
      onPressed: () => unawaited(_toggle(ref, meta)),
    );
  }
}

/// How a download control looks for one video's download row.
({IconData icon, String label, Color color}) downloadLook(DownloadRow? row) {
  switch (row?.state) {
    case 'completed':
      return (
        icon: Icons.download_done_rounded,
        label: 'Downloaded',
        color: KColors.go,
      );
    case 'downloading':
      final pct = row!.totalBytes > 0
          ? (row.doneBytes * 100 ~/ row.totalBytes)
          : 0;
      return (
        icon: Icons.downloading_rounded,
        label: '$pct%',
        color: KColors.lamp,
      );
    case 'queued':
      return (
        icon: Icons.downloading_rounded,
        label: 'Queued',
        color: KColors.lamp,
      );
    case 'paused':
      return (icon: Icons.pause_rounded, label: 'Paused', color: KColors.haze);
    case 'failed':
      return (
        icon: Icons.refresh_rounded,
        label: 'Try again',
        color: KColors.cut,
      );
    default:
      return (
        icon: Icons.download_rounded,
        label: 'Download',
        color: KColors.lamp,
      );
  }
}

/// Starts, pauses or resumes; a finished download plays offline.
void onDownloadTap(
  BuildContext context,
  WidgetRef ref,
  DownloadRow? row,
  PlayRequest request,
) {
  final actions = ref.read(downloadActionsProvider);
  switch (row?.state) {
    case 'completed':
      openPlayer(context, request.copyWith(localFile: row!.filePath));
    case 'downloading' || 'queued':
      unawaited(actions.pause(row!.id));
    case 'paused':
      unawaited(actions.resume(row!.id));
    default:
      unawaited(actions.download(request));
  }
}

/// Download state of the primary video as an [ActionTile].
class DownloadAction extends ConsumerWidget {
  const DownloadAction({super.key, required this.request});

  final PlayRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final row = ref.watch(
      downloadForVideoProvider(request.videoId).select((a) => a.value),
    );
    final look = downloadLook(row);
    final what = request.isEpisode ? ' ${request.label}' : '';
    return ActionTile(
      icon: look.icon,
      label: look.label,
      color: look.color,
      semanticLabel: '${look.label}$what',
      onPressed: () => onDownloadTap(context, ref, row, request),
    );
  }
}

/// One calm line under Play naming the version it will use.
class ReleaseLine extends ConsumerWidget {
  const ReleaseLine({super.key, required this.video});

  final VideoRef video;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(resolveProvider(video));
    final quiet = KType.label.copyWith(color: KColors.haze);
    final best = result.value?.best;
    final Widget line;
    if (best != null) {
      line = Text.rich(
        TextSpan(
          children: [
            if (best.instant)
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: const EdgeInsets.only(right: KSpace.x2),
                  child: Text(
                    'Instant',
                    style: KType.label.copyWith(
                      color: KColors.go,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            TextSpan(
              text: best.headline,
              style: KType.tabular(
                KType.label.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            if (best.reasons.isNotEmpty)
              TextSpan(text: '   ${best.reasons.first}', style: quiet),
          ],
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
    } else {
      final text = switch (result) {
        AsyncValue(:final value?) =>
          value.message ?? 'No versions found yet. Try again later.',
        AsyncError() => 'Couldn’t check versions right now.',
        _ => 'Finding the best version…',
      };
      line = Text(text, style: quiet, maxLines: 2);
    }
    return Semantics(liveRegion: true, child: line);
  }
}
