import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';

import '../../../app/providers.dart';
import '../../../core/lang.dart';
import '../../../ui/glass.dart';
import '../../../ui/tint.dart';
import '../../../ui/tokens.dart';
import '../../../ui/widgets/artwork.dart';
import '../../../ui/widgets/media.dart';
import '../../title/episodes.dart';
import '../../../services/subtitle_option.dart';
import '../player_controller.dart';

/// A glass panel that slides in from the right edge.
class SidePanel extends StatelessWidget {
  const SidePanel({
    super.key,
    required this.title,
    required this.onClose,
    required this.child,
  });

  final String title;
  final VoidCallback onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        0,
        pad.top + KSpace.x3,
        pad.right + KSpace.x3,
        pad.bottom + KSpace.x3,
      ),
      child: SizedBox(
        width: 380,
        child: Glass(
          radius: KRadius.sheet,
          tintStrength: 0.08,
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    KSpace.margin,
                    KSpace.x3,
                    KSpace.x3,
                    KSpace.x2,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: Text(title, style: KType.h2),
                        ),
                      ),
                      GlassIconButton(
                        icon: Icons.close_rounded,
                        label: 'Close',
                        onPressed: onClose,
                      ),
                    ],
                  ),
                ),
                Expanded(child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Audio tracks, then subtitles grouped by language (tap a language to see
/// every subtitle in it), timing and night mode.
class TracksPanel extends ConsumerStatefulWidget {
  const TracksPanel({
    super.key,
    required this.controller,
    required this.onClose,
  });

  final PlayerController controller;
  final VoidCallback onClose;

  @override
  ConsumerState<TracksPanel> createState() => _TracksPanelState();
}

class _TracksPanelState extends ConsumerState<TracksPanel> {
  /// The language whose subtitles are listed; starts at the active one.
  late String? _openLanguage = widget.controller.subtitles
      .where((s) => s.id == widget.controller.activeSubtitleId)
      .map((s) => s.language ?? '')
      .firstOrNull;

  void _step(int ms) {
    final c = widget.controller;
    unawaited(c.setSubtitleDelay(c.subtitleDelay + Duration(milliseconds: ms)));
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final audios = c.player.state.tracks.audio
            .where((a) => a.id != 'auto' && a.id != 'no')
            .toList();
        final current = c.player.state.track.audio;
        final byLang = <String?, List<SubtitleOption>>{};
        for (final s in c.subtitles) {
          (byLang[s.language] ??= []).add(s);
        }
        // Your subtitle languages first, in your order; then the rest A-Z.
        final mine = [
          for (final l in ref.watch(
            settingsProvider.select((s) => s.subtitleLanguages),
          ))
            normalizeLang(l),
        ];
        int rank(String? l) {
          final i = mine.indexOf(normalizeLang(l));
          return i < 0 ? mine.length : i;
        }

        final langs = byLang.keys.toList()
          ..sort((a, b) {
            final r = rank(a).compareTo(rank(b));
            return r != 0 ? r : langName(a).compareTo(langName(b));
          });
        final active = c.subtitles
            .where((s) => s.id == c.activeSubtitleId)
            .firstOrNull;
        return SidePanel(
          title: 'Audio and subtitles',
          onClose: widget.onClose,
          child: ListView(
            padding: const EdgeInsets.only(bottom: KSpace.x4),
            children: [
              const _Heading('Audio'),
              if (audios.isEmpty) const _Note('Only one audio track.'),
              for (final a in audios)
                _Choice(
                  label: _audioLabel(a),
                  detail: a.title,
                  selected: a == current,
                  onTap: () => c.selectAudio(a),
                ),
              const _Heading('Subtitles'),
              _Choice(
                label: 'Off',
                selected: active == null,
                onTap: () => c.selectSubtitle(null),
              ),
              if (c.subtitleSearch == SubtitleSearch.searching)
                const _Note('Looking for subtitles in your languages…')
              else if (c.subtitleNote case final note?)
                _SubtitleNote(note: note),
              for (final lang in langs) ...[
                _LanguageRow(
                  name: langName(lang),
                  count: byLang[lang]!.length,
                  selected: active?.language == lang,
                  open: _openLanguage == (lang ?? ''),
                  onTap: () => setState(
                    () => _openLanguage = _openLanguage == (lang ?? '')
                        ? null
                        : lang ?? '',
                  ),
                ),
                if (_openLanguage == (lang ?? ''))
                  for (final s in byLang[lang]!)
                    _Choice(
                      indent: true,
                      label: s.label,
                      detail: [
                        if (s.detail != null) s.detail!,
                        if (s.hearingImpaired) 'For deaf and hard of hearing',
                        if (s.forced) 'Signs and foreign dialogue only',
                        if (s.fit != null && s.fit! >= 0.85)
                          'Matches this version',
                      ].join('\n'),
                      selected: s.id == c.activeSubtitleId,
                      onTap: () => c.selectSubtitle(s),
                    ),
              ],
              if (active != null) ...[
                const _Heading('Subtitle timing'),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: KSpace.margin,
                  ),
                  child: Row(
                    children: [
                      _Step(
                        label: 'Earlier',
                        icon: Icons.remove_rounded,
                        onTap: () => _step(-100),
                        onLongPress: () => _step(-1000),
                      ),
                      Expanded(
                        child: Text(
                          c.subtitleDelay == Duration.zero
                              ? 'In sync'
                              : '${c.subtitleDelay.isNegative ? '' : '+'}${(c.subtitleDelay.inMilliseconds / 1000).toStringAsFixed(1)} s',
                          textAlign: TextAlign.center,
                          style: KType.tabular(KType.title),
                        ),
                      ),
                      _Step(
                        label: 'Later',
                        icon: Icons.add_rounded,
                        onTap: () => _step(100),
                        onLongPress: () => _step(1000),
                      ),
                    ],
                  ),
                ),
              ],
              if (active != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    KSpace.margin,
                    KSpace.x3,
                    KSpace.margin,
                    0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Line appears before it’s said? Wait for it, then '
                        'tap. Hold Earlier or Later to move a whole second.',
                        style: KType.small,
                      ),
                      const SizedBox(height: KSpace.x2),
                      GlassButton(
                        label: 'Line is spoken now',
                        icon: Icons.record_voice_over_rounded,
                        onPressed: c.syncToCurrentLine,
                      ),
                    ],
                  ),
                ),
              const _Heading('Sound'),
              _Choice(
                label: 'Night mode',
                detail: 'Quieter loud scenes, clearer dialogue',
                selected: c.nightMode,
                toggle: true,
                onTap: c.toggleNightMode,
              ),
            ],
          ),
        );
      },
    );
  }

  String _audioLabel(AudioTrack a) {
    final codec = switch ((a.codec ?? '').toLowerCase()) {
      'eac3' => 'E-AC3',
      'ac3' => 'AC3',
      'aac' => 'AAC',
      'dts' => 'DTS',
      'truehd' => 'TrueHD',
      'opus' => 'Opus',
      'flac' => 'FLAC',
      final other => other.toUpperCase(),
    };
    final ch = switch (a.channelscount) {
      1 => 'mono',
      2 => 'stereo',
      6 => '5.1',
      8 => '7.1',
      null => '',
      final n => '$n ch',
    };
    return [
      langName(a.language),
      codec,
      ch,
    ].where((s) => s.isNotEmpty).join(' ');
  }
}

/// Every episode, by season; tap to switch without leaving the player.
class EpisodesPanel extends StatefulWidget {
  const EpisodesPanel({
    super.key,
    required this.controller,
    required this.onClose,
  });

  final PlayerController controller;
  final VoidCallback onClose;

  @override
  State<EpisodesPanel> createState() => _EpisodesPanelState();
}

class _EpisodesPanelState extends State<EpisodesPanel> {
  int? _season;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final all = c.episodes;
    final seasons = {for (final e in all) e.season!}.toList();
    final season =
        _season ?? c.request.season ?? (seasons.isEmpty ? 1 : seasons.first);
    final list = all.where((e) => e.season == season).toList();
    return SidePanel(
      title: 'Episodes',
      onClose: widget.onClose,
      child: Column(
        children: [
          SeasonPicker(
            seasons: [
              ...seasons.where((s) => s > 0),
              if (seasons.contains(0)) 0,
            ],
            selected: season,
            onSelect: (s) => setState(() => _season = s),
          ),
          const SizedBox(height: KSpace.x2),
          Expanded(
            child: all.isEmpty
                ? const _Note('Episode list isn’t available for this title.')
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final e = list[i];
                      final current = e.id == c.request.videoId;
                      final name = e.title ?? 'Episode ${e.episode}';
                      return Semantics(
                        button: true,
                        selected: current,
                        label: [
                          'Episode ${e.episode}, $name',
                          if (current) 'Playing now',
                        ].join('. '),
                        excludeSemantics: true,
                        child: InkWell(
                          onTap: current
                              ? null
                              : () {
                                  widget.onClose();
                                  c.switchTo(c.requestFor(e));
                                },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: KSpace.margin,
                              vertical: 6,
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 128,
                                  child: Artwork(
                                    url: e.thumbnail,
                                    radius: KRadius.still,
                                    aspectRatio: 16 / 9,
                                    memCacheWidth: 300,
                                  ),
                                ),
                                const SizedBox(width: KSpace.x3),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        current
                                            ? 'E${e.episode}  Playing now'
                                            : 'E${e.episode}',
                                        style: KType.small.copyWith(
                                          color: current
                                              ? KinoraTint.of(context)
                                              : KColors.haze,
                                        ),
                                      ),
                                      Text(
                                        name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        textDirection: contentDir(name),
                                        style: KType.label,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Playback speed.
class SpeedPanel extends StatelessWidget {
  const SpeedPanel({
    super.key,
    required this.controller,
    required this.onClose,
  });

  final PlayerController controller;
  final VoidCallback onClose;

  static const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => SidePanel(
      title: 'Speed',
      onClose: onClose,
      child: ListView(
        children: [
          for (final s in speeds)
            _Choice(
              label: s == 1
                  ? 'Normal'
                  : '${s.toString().replaceAll(RegExp(r'\.0$'), '')}×',
              selected: (controller.rate - s).abs() < 0.01,
              onTap: () => controller.setRate(s),
            ),
        ],
      ),
    ),
  );
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      KSpace.margin,
      KSpace.section - 8,
      KSpace.margin,
      KSpace.x2,
    ),
    child: Text(text, style: KType.title.copyWith(color: KColors.haze)),
  );
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: KSpace.margin,
      vertical: KSpace.x2,
    ),
    child: Text(text, style: KType.small),
  );
}

/// One choice with a Spill check when chosen. [toggle] makes it an on/off
/// row (Night mode) instead of one of several.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.onTap,
    this.detail,
    this.indent = false,
    this.toggle = false,
  });

  final String label;
  final String? detail;
  final bool selected;
  final bool indent;
  final bool toggle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: !toggle,
    toggled: toggle ? selected : null,
    selected: toggle ? null : selected,
    inMutuallyExclusiveGroup: toggle ? null : true,
    // Details ("For deaf and hard of hearing") are read too.
    label: [
      label,
      if (detail != null && detail!.isNotEmpty) detail!.replaceAll('\n', '. '),
    ].join('. '),
    excludeSemantics: true,
    child: InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            indent ? KSpace.margin + KSpace.x4 : KSpace.margin,
            10,
            KSpace.margin,
            10,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: KType.body),
                    if (detail != null && detail!.isNotEmpty)
                      Text(
                        detail!,
                        style: KType.small,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              SizedBox.square(
                dimension: 24,
                child: selected
                    ? Icon(Icons.check_rounded, color: KinoraTint.of(context))
                    : null,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// What the subtitle search found nothing for, and where to fix it.
class _SubtitleNote extends StatelessWidget {
  const _SubtitleNote({required this.note});

  final String note;

  @override
  Widget build(BuildContext context) {
    final lower = note.toLowerCase();
    final (String, String)? fix = lower.contains('subtitle sites')
        ? ('Open Subtitle sites', '/settings/subtitle-sites')
        : lower.contains('languages')
        ? ('Open Languages', '/settings/languages')
        : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KSpace.margin,
        KSpace.x2,
        KSpace.margin,
        KSpace.x2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(note, style: KType.label.copyWith(color: KColors.haze)),
          ),
          if (fix != null) ...[
            const SizedBox(height: KSpace.x2),
            // Leaves the player (its progress is saved) for Settings.
            GlassButton(
              label: fix.$1,
              icon: Icons.tune_rounded,
              onPressed: () => context.go(fix.$2),
            ),
          ],
        ],
      ),
    );
  }
}

class _LanguageRow extends StatelessWidget {
  const _LanguageRow({
    required this.name,
    required this.count,
    required this.selected,
    required this.open,
    required this.onTap,
  });

  final String name;
  final int count;
  final bool selected;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    expanded: open,
    label: '$name, $count subtitles',
    excludeSemantics: true,
    child: InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: KSpace.margin),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: KType.body.copyWith(
                    color: selected ? KinoraTint.of(context) : KColors.lamp,
                    fontWeight: selected ? FontWeight.w600 : null,
                  ),
                ),
              ),
              Text('$count', style: KType.tabular(KType.small)),
              const SizedBox(width: KSpace.x2),
              AnimatedRotation(
                turns: open ? 0.25 : 0,
                duration: KMotion.fast,
                child: const Icon(
                  Icons.chevron_right_rounded,
                  color: KColors.haze,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Earlier/Later: tap moves 0.1 s, hold moves 1 s.
class _Step extends StatelessWidget {
  const _Step({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.onLongPress,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) => Semantics(
    onLongPressHint: '$label by one second',
    onLongPress: onLongPress,
    child: GestureDetector(
      onLongPress: () {
        HapticFeedback.mediumImpact();
        onLongPress();
      },
      child: GlassIconButton(icon: icon, label: label, onPressed: onTap),
    ),
  );
}

/// [top] at the top and [bottom] at the bottom of the screen; scrolls
/// instead when large text makes them taller than it.
class FillOrScroll extends StatelessWidget {
  const FillOrScroll({
    super.key,
    required this.padding,
    required this.top,
    required this.bottom,
  });

  final EdgeInsets padding;
  final Widget top;
  final Widget bottom;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) => SingleChildScrollView(
      padding: padding,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: math.max(0, c.maxHeight - padding.vertical),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            top,
            Padding(
              padding: const EdgeInsets.only(top: KSpace.x4),
              child: bottom,
            ),
          ],
        ),
      ),
    ),
  );
}
