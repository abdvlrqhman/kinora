import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../services/resolver.dart';
import '../../ui/glass.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/media.dart';
import '../../ui/widgets/sheet.dart';
import '../../ui/widgets/states.dart';
import 'title_model.dart';

/// Opens the version picker for [video]; [onPick] plays the chosen one.
Future<void> showVersionsSheet(
  BuildContext context, {
  required VideoRef video,
  required String subtitle,
  required ValueChanged<ResolvedRelease> onPick,
}) => showGlassSheet<void>(
  context,
  builder: (_) =>
      VersionsSheet(video: video, subtitle: subtitle, onPick: onPick),
);

/// Every version of one video, best first, filterable by resolution.
class VersionsSheet extends ConsumerStatefulWidget {
  const VersionsSheet({
    super.key,
    required this.video,
    required this.subtitle,
    required this.onPick,
  });

  final VideoRef video;

  /// What is being played ("S1 E3  Pilot" or the movie's name).
  final String subtitle;
  final ValueChanged<ResolvedRelease> onPick;

  @override
  ConsumerState<VersionsSheet> createState() => _VersionsSheetState();
}

class _VersionsSheetState extends ConsumerState<VersionsSheet> {
  /// Selected resolution; null shows all.
  String? _filter;

  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(versionGroupsProvider(widget.video));
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(
        KSpace.margin,
        KSpace.x2,
        KSpace.margin,
        KSpace.x3,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text('Choose another version', style: KType.h2),
          ),
          const SizedBox(height: 2),
          Text(
            widget.subtitle,
            style: KType.label.copyWith(color: KColors.haze),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
    final Widget body = switch (groups) {
      AsyncValue(:final value?) when value.all.isNotEmpty => _List(
        groups: value,
        filter: _filter,
        onFilter: (f) => setState(() => _filter = f),
        onPick: (r) {
          Navigator.of(context).pop();
          widget.onPick(r);
        },
      ),
      AsyncValue(:final value?) => _Note(
        value.message ?? 'No one is sharing this right now. Try again later.',
      ),
      AsyncError(:final error) => _Note(friendlyError(error)),
      _ => const _Note('Finding versions…'),
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        Flexible(child: body),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      KSpace.margin,
      KSpace.x2,
      KSpace.margin,
      KSpace.section,
    ),
    child: Semantics(
      liveRegion: true,
      child: Text(text, style: KType.body.copyWith(color: KColors.haze)),
    ),
  );
}

class _List extends StatelessWidget {
  const _List({
    required this.groups,
    required this.filter,
    required this.onFilter,
    required this.onPick,
  });

  final VersionGroups groups;
  final String? filter;
  final ValueChanged<String?> onFilter;
  final ValueChanged<ResolvedRelease> onPick;

  @override
  Widget build(BuildContext context) {
    final shown = filter == null
        ? groups.all
        : groups.byResolution.where((g) => g.$1 == filter).firstOrNull?.$2 ??
              groups.all;
    final best = groups.all.first;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (groups.byResolution.length > 1)
          _Filters(groups: groups, selected: filter, onSelect: onFilter),
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: KSpace.x3),
            itemCount: shown.length,
            itemBuilder: (_, i) => _ReleaseTile(
              release: shown[i],
              isBest: identical(shown[i], best),
              onTap: () => onPick(shown[i]),
            ),
          ),
        ),
      ],
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.groups,
    required this.selected,
    required this.onSelect,
  });

  final VersionGroups groups;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    final chips = <(String?, String, int)>[
      (null, 'All', groups.all.length),
      for (final (res, list) in groups.byResolution) (res, res, list.length),
    ];
    return SizedBox(
      height: 48,
      child: GlassGroup(
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: KSpace.margin - 4),
          itemCount: chips.length,
          itemBuilder: (_, i) {
            final (value, label, count) = chips[i];
            final on = value == selected;
            final text = Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: label,
                    style: KType.label.copyWith(
                      fontWeight: FontWeight.w600,
                      color: on ? KColors.lamp : KColors.haze,
                    ),
                  ),
                  TextSpan(
                    text: '  $count',
                    style: KType.tabular(
                      KType.small.copyWith(
                        color: on ? KColors.haze : KColors.reel,
                      ),
                    ),
                  ),
                ],
              ),
            );
            return Semantics(
              button: true,
              selected: on,
              label: '$label, $count versions',
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelect(value),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 48),
                    child: on
                        ? Glass(
                            tintStrength: 0.3,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: Center(child: text),
                          )
                        : Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Center(child: text),
                          ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ReleaseTile extends StatelessWidget {
  const _ReleaseTile({
    required this.release,
    required this.isBest,
    required this.onTap,
  });

  final ResolvedRelease release;
  final bool isBest;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = release;
    final facts = KType.tabular(KType.small);
    final mark = KType.label.copyWith(
      color: KColors.go,
      fontWeight: FontWeight.w700,
    );
    return Pressable(
      label: [
        r.headline,
        if (isBest) 'Best match',
        if (r.instant) 'Instant',
        ...r.reasons,
        ...r.warnings,
        if (r.sizeBytes != null) Fmt.bytes(r.sizeBytes!),
        if (r.seeders != null) '${r.seeders} seeds',
      ].join('. '),
      hint: 'Plays this version',
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: KSpace.margin,
          vertical: KSpace.x3,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(r.headline, style: KType.tabular(KType.title)),
                ),
                if (isBest) ...[
                  const SizedBox(width: KSpace.x2),
                  Text('Best', style: mark),
                ],
                if (r.instant) ...[
                  const SizedBox(width: KSpace.x2),
                  const Icon(Icons.bolt_rounded, size: 18, color: KColors.go),
                  Text('Instant', style: mark),
                ],
              ],
            ),
            if (r.reasons.isNotEmpty) ...[
              const SizedBox(height: 2),
              Wrap(
                spacing: KSpace.x3,
                children: [
                  for (final reason in r.reasons)
                    Text(
                      reason,
                      style: KType.label.copyWith(color: KColors.haze),
                    ),
                ],
              ),
            ],
            for (final w in r.warnings)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text.rich(
                  TextSpan(
                    children: [
                      const WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Padding(
                          padding: EdgeInsets.only(right: KSpace.x1),
                          child: Icon(
                            Icons.warning_amber_rounded,
                            size: 15,
                            color: KColors.marquee,
                          ),
                        ),
                      ),
                      TextSpan(text: w),
                    ],
                  ),
                  style: KType.label.copyWith(color: KColors.marquee),
                ),
              ),
            const SizedBox(height: KSpace.x1),
            Wrap(
              spacing: KSpace.x4,
              children: [
                if (r.sizeBytes != null)
                  Text(
                    Fmt.bytes(r.sizeBytes!),
                    style: facts.copyWith(color: KColors.lamp),
                  ),
                if (r.seeders != null)
                  Text(
                    r.seeders == 1 ? '1 seed' : '${r.seeders} seeds',
                    style: facts,
                  ),
                if (r.addonName != null)
                  Text(
                    r.addonName!,
                    style: facts.copyWith(color: KColors.reel),
                  ),
              ],
            ),
            Text(
              r.releaseName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: KType.small.copyWith(color: KColors.reel),
            ),
          ],
        ),
      ),
    );
  }
}
