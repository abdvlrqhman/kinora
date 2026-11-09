import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../../../core/lang.dart';
import '../../../ui/glass.dart';
import '../../../ui/tint.dart';
import '../../../ui/tokens.dart';
import '../../../ui/widgets/artwork.dart';
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
                    KSpace.x4,
                    KSpace.x2,
                    KSpace.x2,
                  ),
                  child: Row(
                    children: [
                      Expanded(child: Text(title, style: KType.h2)),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: onClose,
                        icon: const Icon(Icons.close_rounded),
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
class TracksPanel extends StatefulWidget {
  const TracksPanel({
    super.key,
    required this.controller,
    required this.onClose,
  });

  final PlayerController controller;
  final VoidCallback onClose;

  @override
  State<TracksPanel> createState() => _TracksPanelState();
}

class _TracksPanelState extends State<TracksPanel> {
  String? _openLanguage;

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
        final langs = byLang.keys.toList()
          ..sort((a, b) => langName(a).compareTo(langName(b)));
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
              if (c.subtitles.isEmpty)
                const _Note('Looking for subtitles in your languages…'),
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
                        onTap: () => c.setSubtitleDelay(
                          c.subtitleDelay - const Duration(milliseconds: 100),
                        ),
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
                        onTap: () => c.setSubtitleDelay(
                          c.subtitleDelay + const Duration(milliseconds: 100),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const _Heading('Sound'),
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: KSpace.margin,
                ),
                title: Text('Night mode', style: KType.body),
                subtitle: Text(
                  'Quieter loud scenes, clearer dialogue',
                  style: KType.small,
                ),
                value: c.nightMode,
                onChanged: (_) => c.toggleNightMode(),
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
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: KSpace.margin),
              children: [
                for (final s in seasons)
                  Padding(
                    padding: const EdgeInsets.only(right: KSpace.x2),
                    child: ChoiceChip(
                      label: Text(s == 0 ? 'Specials' : 'Season $s'),
                      selected: s == season,
                      onSelected: (_) => setState(() => _season = s),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: KSpace.x2),
          Expanded(
            child: all.isEmpty
                ? const _Note('Episode list isn’t available for this title.')
                : ListView.builder(
                    itemCount: list.length,
                    itemExtent: 92,
                    itemBuilder: (context, i) {
                      final e = list[i];
                      final current = e.id == c.request.videoId;
                      return Semantics(
                        button: true,
                        selected: current,
                        label: 'Episode ${e.episode}, ${e.title ?? ''}',
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
                                        'E${e.episode}',
                                        style: KType.small.copyWith(
                                          color: current
                                              ? KinoraTint.of(context)
                                              : KColors.haze,
                                        ),
                                      ),
                                      Text(
                                        e.title ?? 'Episode ${e.episode}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: KType.label,
                                      ),
                                      if (current)
                                        Text('Playing now', style: KType.small),
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

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.onTap,
    this.detail,
    this.indent = false,
  });

  final String label;
  final String? detail;
  final bool selected;
  final bool indent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
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
              if (selected)
                Icon(Icons.check_rounded, color: KinoraTint.of(context)),
            ],
          ),
        ),
      ),
    ),
  );
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
      child: SizedBox(
        height: 52,
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

class _Step extends StatelessWidget {
  const _Step({required this.label, required this.icon, required this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) =>
      GlassIconButton(icon: icon, label: label, onPressed: onTap, size: 44);
}
