import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import '../../../app/providers.dart';
import '../../../core/settings.dart';
import '../../../ui/tokens.dart';

final _rtl = RegExp(r'[֐-ࣿיִ-﷿ﹰ-﻿]');

/// Renders the current subtitle lines with the user's style. Kinora draws
/// subtitles itself (not libass) so every script, including Arabic and
/// Hebrew, uses the system's fonts and bidi shaping.
class SubtitleOverlay extends ConsumerWidget {
  const SubtitleOverlay({super.key, required this.player, required this.lift});

  final Player player;

  /// Extra bottom space while controls are visible.
  final double lift;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(settingsProvider.select((s) => s.subtitleStyle));
    return StreamBuilder<List<String>>(
      stream: player.stream.subtitle,
      initialData: player.state.subtitle,
      builder: (context, snap) {
        final lines = (snap.data ?? const [])
            .expand((l) => l.split('\n'))
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .toList();
        if (lines.isEmpty) return const SizedBox.shrink();
        return LayoutBuilder(
          builder: (context, c) {
            final size = (c.maxHeight * 0.052).clamp(15.0, 44.0) * style.scale;
            return Padding(
              padding: EdgeInsets.only(
                left: c.maxWidth * 0.08,
                right: c.maxWidth * 0.08,
                bottom: c.maxHeight * style.bottomMargin + lift,
              ),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: _Lines(lines: lines, style: style, fontSize: size),
              ),
            );
          },
        );
      },
    );
  }
}

class _Lines extends StatelessWidget {
  const _Lines({
    required this.lines,
    required this.style,
    required this.fontSize,
  });

  final List<String> lines;
  final SubtitleStyle style;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final text = lines.join('\n');
    final dir = _rtl.hasMatch(text) ? TextDirection.rtl : TextDirection.ltr;
    final base = TextStyle(
      fontFamily: KType.text,
      fontSize: fontSize,
      height: 1.25,
      fontWeight: style.bold ? FontWeight.w700 : FontWeight.w600,
      fontVariations: [FontVariation.weight(style.bold ? 700 : 600)],
      color: Color(style.color),
      shadows: style.outline
          ? const [Shadow(blurRadius: 4, color: Color(0xCC000000))]
          : null,
    );
    Widget label = Stack(
      children: [
        if (style.outline)
          Text(
            text,
            textAlign: TextAlign.center,
            textDirection: dir,
            style: base.copyWith(
              color: null,
              shadows: const [],
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = fontSize * 0.14
                ..strokeJoin = StrokeJoin.round
                ..color = const Color(0xE6000000),
            ),
          ),
        Text(
          text,
          textAlign: TextAlign.center,
          textDirection: dir,
          style: base,
        ),
      ],
    );
    if (style.backgroundOpacity > 0) {
      label = DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: style.backgroundOpacity),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: fontSize * 0.4,
            vertical: fontSize * 0.12,
          ),
          child: label,
        ),
      );
    }
    return Semantics(
      liveRegion: true,
      label: text,
      child: ExcludeSemantics(child: label),
    );
  }
}
