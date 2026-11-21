import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/shell.dart';
import '../../services/followed.dart';
import '../../services/notices_plan.dart';
import '../../ui/tint.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/artwork.dart';
import '../../ui/widgets/media.dart';
import '../../ui/widgets/page_header.dart';
import '../../ui/widgets/pointer.dart';
import '../../ui/widgets/states.dart';

/// What airs next for the shows you follow, day by day.
class CalendarScreen extends ConsumerWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final upcoming = ref.watch(upcomingProvider);
    final now = DateTime.now();
    final days = byDay(upcoming.value ?? const []);
    return Scaffold(
      body: RefreshIndicator.adaptive(
        onRefresh: () => ref.refresh(upcomingProvider.future),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            const SliverToBoxAdapter(child: PageHeader(title: 'Coming up')),
            ...switch (upcoming) {
              AsyncValue(value: final _?) when days.isEmpty => [
                SliverToBoxAdapter(
                  child: EmptyState(
                    icon: Icons.event_outlined,
                    title: 'Nothing coming up',
                    message:
                        'Add shows to My list, or watch some, to see when '
                        'their new episodes air.',
                    actionLabel: 'Discover shows',
                    onAction: () => context.go('/search'),
                  ),
                ),
              ],
              AsyncValue(value: final _?) => [
                for (final (day, eps) in days) ...[
                  SliverToBoxAdapter(
                    child: _DayHeader(label: dayLabel(day, now), day: day),
                  ),
                  SliverList.builder(
                    itemCount: eps.length,
                    itemBuilder: (_, i) => CalendarRow(episode: eps[i]),
                  ),
                ],
              ],
              AsyncError(:final error) => [
                SliverToBoxAdapter(
                  child: ErrorState(
                    message: friendlyError(error),
                    onRetry: () => ref.invalidate(upcomingProvider),
                  ),
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
  const _DayHeader({required this.label, required this.day});

  final String label;
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final isToday =
        day.year == today.year &&
        day.month == today.month &&
        day.day == today.day;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KSpace.margin,
        KSpace.x4,
        KSpace.margin,
        KSpace.x2,
      ),
      child: Semantics(
        header: true,
        child: Text(
          label,
          style: KType.h2.copyWith(
            color: isToday ? KinoraTint.of(context) : KColors.title,
          ),
        ),
      ),
    );
  }
}

/// What kind of episode [e] is, worth a badge ("Season premiere"), if any.
String? episodeKind(AirDate e) => switch (e.type) {
  'series_premiere' => 'Premiere',
  'season_premiere' => 'Season premiere',
  'mid_season_premiere' => 'Back',
  'season_finale' => 'Season finale',
  'mid_season_finale' => 'Mid-season finale',
  'series_finale' => 'Series finale',
  null when e.episode == 1 => e.season == 1 ? 'Premiere' : 'Season premiere',
  _ => null,
};

/// One episode: the show's poster, its name, the episode, and when.
class CalendarRow extends StatelessWidget {
  const CalendarRow({super.key, required this.episode});

  final AirDate episode;

  @override
  Widget build(BuildContext context) {
    final e = episode;
    final kind = episodeKind(e);
    final ep = 'S${e.season} E${e.episode}';
    final name = e.title == null || e.title!.isEmpty ? ep : '$ep  ${e.title}';
    final time = e.precise
        ? TimeOfDay.fromDateTime(e.airsAt.toLocal()).format(context)
        : null;
    void open() => openTitle(context, type: 'series', id: e.showId);
    return Semantics(
      button: true,
      label: [e.show, ep, ?e.title, ?kind, ?time].join(', '),
      excludeSemantics: true,
      child: PointerFocus(
        onActivate: open,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KRadius.panel),
        ),
        builder: (context, hovered) => InkWell(
          onTap: open,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: KSpace.margin,
              vertical: KSpace.x2,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 48,
                  child: Artwork(
                    url: posterOf(e.showId),
                    fallbackText: e.show,
                    radius: 8,
                    aspectRatio: 2 / 3,
                    memCacheWidth: decodeWidth(context, 48),
                  ),
                ),
                const SizedBox(width: KSpace.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.show,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: KType.title.copyWith(
                          color: hovered ? KColors.title : KColors.lamp,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: KType.small.copyWith(color: KColors.haze),
                      ),
                      if (kind != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          kind,
                          style: KType.meta.copyWith(
                            color: KinoraTint.of(context),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (time != null) ...[
                  const SizedBox(width: KSpace.x3),
                  Text(time, style: KType.label.copyWith(color: KColors.haze)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A show's poster by its IMDb id.
String posterOf(String imdb) =>
    'https://images.metahub.space/poster/medium/$imdb/img';
