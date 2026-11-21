import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stremio/stremio.dart';

import '../../app/router.dart';
import '../../app/shell.dart';
import '../../core/db/database.dart';
import '../../core/format.dart';
import '../../services/followed.dart' show dayLabel;
import '../../services/library.dart';
import '../../services/trakt.dart';
import '../../ui/tint.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/artwork.dart';
import '../../ui/widgets/media.dart';
import '../../ui/widgets/page_header.dart';
import '../../ui/widgets/sheet.dart';
import '../../ui/widgets/states.dart';
import '../calendar/calendar_screen.dart' show posterOf;
import '../settings/widgets/settings_ui.dart';

/// What you finished, newest first.
final historyProvider = StreamProvider.autoDispose<List<WatchProgressData>>(
  (ref) => ref.watch(progressRepositoryProvider).watchHistory(),
);

/// Your Trakt numbers (signed in only).
final traktStatsProvider = FutureProvider.autoDispose<TraktStats>(
  (ref) => ref.read(traktSyncProvider).stats(),
);

/// [rows] by local day, newest first.
List<(DateTime, List<WatchProgressData>)> byWatchedDay(
  List<WatchProgressData> rows,
) {
  final days = <DateTime, List<WatchProgressData>>{};
  for (final r in rows) {
    final t = r.updatedAt.toLocal();
    (days[DateTime(t.year, t.month, t.day)] ??= []).add(r);
  }
  return [
    for (final d in days.keys.toList()..sort((a, b) => b.compareTo(a)))
      (d, days[d]!),
  ];
}

/// "Science fiction" for Trakt's "science-fiction".
String genreName(String slug) {
  final words = slug.replaceAll('-', ' ');
  return words.isEmpty ? words : words[0].toUpperCase() + words.substring(1);
}

/// "1,240".
String grouped(int n) =>
    n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

/// Settings › Trakt › Watched: your numbers, then everything you finished,
/// any of it can be marked unwatched.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);
    final signedIn = ref.watch(traktSignedInProvider);
    final now = DateTime.now();
    return Scaffold(
      body: RefreshIndicator.adaptive(
        onRefresh: () async {
          if (signedIn) {
            ref.invalidate(traktStatsProvider);
            await ref.read(traktSyncProvider).syncNow();
          }
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            const SliverToBoxAdapter(child: PageHeader(title: 'Watched')),
            if (signedIn) const SliverToBoxAdapter(child: _Stats()),
            ...switch (history) {
              AsyncValue(value: final rows?) when rows.isEmpty => [
                const SliverToBoxAdapter(
                  child: EmptyState(
                    icon: Icons.history_rounded,
                    title: 'Nothing watched yet',
                    message: 'What you finish in Kinora shows up here.',
                  ),
                ),
              ],
              AsyncValue(value: final rows?) => [
                for (final (day, list) in byWatchedDay(rows)) ...[
                  SliverToBoxAdapter(child: _DayHeader(dayLabel(day, now))),
                  SliverList.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) =>
                        HistoryRow(row: list[i], signedIn: signedIn),
                  ),
                ],
              ],
              AsyncError(:final error) => [
                SliverToBoxAdapter(
                  child: ErrorState(message: friendlyError(error)),
                ),
              ],
              _ => [
                const SliverToBoxAdapter(
                  child: Center(child: CircularProgressIndicator.adaptive()),
                ),
              ],
            },
            SliverToBoxAdapter(
              child: SizedBox(
                height: AppShell.bottomInset(context) + KSpace.section,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      KSpace.margin,
      KSpace.x4,
      KSpace.margin,
      KSpace.x2,
    ),
    child: Semantics(header: true, child: Text(label, style: KType.h2)),
  );
}

/// One finished movie or episode; its menu marks it unwatched.
class HistoryRow extends ConsumerWidget {
  const HistoryRow({super.key, required this.row, required this.signedIn});

  final WatchProgressData row;
  final bool signedIn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = row;
    final ep = r.season != null && r.episode != null
        ? Fmt.episode(r.season!, r.episode!)
        : null;
    final what = [r.name, ?ep].join(', ');
    final line = ep == null
        ? 'Movie'
        : [
            ep,
            if (r.episodeTitle case final t? when t.isNotEmpty) t,
          ].join('  ');
    final time = TimeOfDay.fromDateTime(r.updatedAt.toLocal()).format(context);
    void open() => openTitle(context, type: r.type, id: r.mediaId);

    Future<void> unwatch() async {
      final ok = await confirmAction(
        context,
        title: 'Mark $what as unwatched?',
        message: signedIn
            ? 'Kinora and Trakt forget you watched it.'
            : 'Kinora forgets you watched it.',
        action: 'Mark as unwatched',
      );
      if (!ok) return;
      await ref.read(progressRepositoryProvider).unwatch(r.videoId);
      if (context.mounted) showNote(context, 'Marked $what as unwatched');
    }

    void menu() => unawaited(
      showGlassSheet<void>(
        context,
        builder: (sheet) => Column(
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
              child: Text(what, style: KType.h2),
            ),
            SheetAction(
              icon: Icons.info_outline_rounded,
              label: 'Go to title',
              onTap: () {
                Navigator.pop(sheet);
                open();
              },
            ),
            SheetAction(
              icon: Icons.remove_done_rounded,
              label: 'Mark as unwatched',
              color: KColors.cut,
              onTap: () {
                Navigator.pop(sheet);
                unawaited(unwatch());
              },
            ),
            const SizedBox(height: KSpace.x2),
          ],
        ),
      ),
    );

    return Pressable(
      label: '$what, $time',
      onTap: open,
      onLongPress: menu,
      actions: {
        const CustomSemanticsAction(label: 'Mark as unwatched'): () =>
            unawaited(unwatch()),
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: KSpace.margin,
          vertical: KSpace.x2,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              child: Artwork(
                url: r.poster ?? posterOf(r.mediaId),
                fallbackText: r.name,
                radius: 8,
                aspectRatio: 2 / 3,
                memCacheWidth: decodeWidth(context, 44),
              ),
            ),
            const SizedBox(width: KSpace.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: KType.title,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    line,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: KType.small.copyWith(color: KColors.haze),
                  ),
                ],
              ),
            ),
            const SizedBox(width: KSpace.x2),
            Text(time, style: KType.label.copyWith(color: KColors.haze)),
            IconButton(
              tooltip: 'More for $what',
              onPressed: menu,
              icon: const Icon(Icons.more_horiz_rounded, color: KColors.haze),
            ),
          ],
        ),
      ),
    );
  }
}

/// This year in hours, the shows you watched most and your genres; all
/// time underneath. Quiet when Trakt can't be reached: history still works.
class _Stats extends ConsumerWidget {
  const _Stats();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(traktStatsProvider);
    final year = DateTime.now().year;
    final accent = KinoraTint.of(context);
    return switch (stats) {
      AsyncValue(value: final s?) => Padding(
        padding: const EdgeInsets.fromLTRB(
          KSpace.margin,
          KSpace.x2,
          KSpace.margin,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              label:
                  '${grouped(s.yearMinutes ~/ 60)} hours watched in $year, '
                  '${grouped(s.yearPlays)} plays',
              excludeSemantics: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${grouped(s.yearMinutes ~/ 60)} hours',
                    style: KType.hero.copyWith(color: accent),
                  ),
                  Text(
                    'watched in $year, ${grouped(s.yearPlays)} plays',
                    style: KType.body.copyWith(color: KColors.haze),
                  ),
                ],
              ),
            ),
            const SizedBox(height: KSpace.x2),
            Text(
              'In all: ${grouped(s.minutes ~/ 60)} hours, '
              '${grouped(s.episodes)} episodes of ${grouped(s.shows)} shows, '
              '${grouped(s.movies)} movies.',
              style: KType.small.copyWith(color: KColors.haze),
            ),
            if (s.topShows.isNotEmpty) ...[
              const SizedBox(height: KSpace.x4),
              Semantics(
                header: true,
                child: Text('Most watched in $year', style: KType.title),
              ),
              const SizedBox(height: KSpace.x2),
              SizedBox(
                // Poster (144) and two lines, at up to 1.3× text.
                height: 214,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: s.topShows.length,
                  separatorBuilder: (_, _) => const SizedBox(width: KSpace.x3),
                  itemBuilder: (context, i) => _TopShow(
                    show: s.topShows[i].show,
                    episodes: s.topShows[i].episodes,
                  ),
                ),
              ),
            ],
            if (s.topGenres.isNotEmpty) ...[
              const SizedBox(height: KSpace.x4),
              Semantics(
                header: true,
                child: Text('Your genres in $year', style: KType.title),
              ),
              const SizedBox(height: KSpace.x2),
              for (final g in s.topGenres)
                _GenreBar(
                  name: genreName(g.genre),
                  share: g.share,
                  color: accent,
                ),
            ],
          ],
        ),
      ),
      AsyncError() => Padding(
        padding: const EdgeInsets.fromLTRB(
          KSpace.margin,
          KSpace.x2,
          KSpace.margin,
          0,
        ),
        child: Text(
          'Your Trakt numbers couldn’t load. Pull down to try again.',
          style: KType.small.copyWith(color: KColors.haze),
        ),
      ),
      _ => const Padding(
        padding: EdgeInsets.all(KSpace.x4),
        child: Center(child: CircularProgressIndicator.adaptive()),
      ),
    };
  }
}

class _TopShow extends StatelessWidget {
  const _TopShow({required this.show, required this.episodes});

  final MetaPreview show;
  final int episodes;

  @override
  Widget build(BuildContext context) {
    final count = episodes == 1 ? '1 episode' : '$episodes episodes';
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Pressable(
        plain: true,
        label: '${show.name}, $count',
        onTap: () => openTitle(context, type: 'series', id: show.id),
        child: SizedBox(
          width: 96,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Artwork(
                url: show.poster,
                fallbackText: show.name,
                radius: KRadius.poster,
                aspectRatio: 2 / 3,
                memCacheWidth: decodeWidth(context, 96),
              ),
              const SizedBox(height: 6),
              Text(
                show.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: KType.label,
              ),
              Text(count, style: KType.small.copyWith(color: KColors.haze)),
            ],
          ),
        ),
      ),
    );
  }
}

/// One genre's share of this year's plays: its name and percent in ink,
/// a thin bar in the accent.
class _GenreBar extends StatelessWidget {
  const _GenreBar({
    required this.name,
    required this.share,
    required this.color,
  });

  final String name;
  final double share;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final pct = '${(share * 100).round()}%';
    return Semantics(
      label: '$name, $pct',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: KSpace.x2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(name, style: KType.label)),
                Text(
                  pct,
                  style: KType.tabular(
                    KType.label.copyWith(color: KColors.haze),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 6,
                child: Stack(
                  children: [
                    const Positioned.fill(
                      child: ColoredBox(color: KColors.raised),
                    ),
                    FractionallySizedBox(
                      widthFactor: share.clamp(0.0, 1.0),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
