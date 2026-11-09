import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import '../../../app/providers.dart';
import '../../../core/settings.dart';
import '../../../ui/tokens.dart';
import '../../../ui/widgets/media.dart';

/// Renders the current subtitle lines with the user's style. Kinora draws
/// subtitles itself (not libass) so every script, including Arabic and
/// Hebrew, uses the system's fonts and bidi shaping.
class SubtitleOverlay extends ConsumerWidget {
  const SubtitleOverlay({
    super.key,
    required this.player,
    required this.clearance,
    this.belowCenter = 0,
    this.rightCover = 0,
  });

  final Player player;

  /// Space the controls take at the bottom while visible; lines stay above.
  final double clearance;

  /// While the controls show: how far below the screen's middle the lines
  /// must stay (the play row's half-height). Large lines scale down to fit
  /// instead of sliding behind it.
  final double belowCenter;

  /// Width a side panel covers on the right: lines center in the rest, so
  /// they stay readable (and show style changes) while it's open.
  final double rightCover;

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
            final bottom = math.max(
              c.maxHeight * style.bottomMargin,
              clearance,
            );
            Widget text = MediaQuery.withNoTextScaling(
              child: _Lines(lines: lines, style: style, fontSize: size),
            );
            // Only where a full line fits (tablets, tall windows): on a
            // landscape phone the gap is a few points, and unreadably small
            // lines would be worse than the controls (which hide in 3 s)
            // briefly covering them.
            final room = c.maxHeight / 2 - belowCenter - bottom;
            if (belowCenter > 0 && room >= size * 1.4) {
              text = ConstrainedBox(
                constraints: BoxConstraints(maxHeight: room),
                child: FittedBox(fit: BoxFit.scaleDown, child: text),
              );
            }
            return Padding(
              padding: EdgeInsets.only(
                left: c.maxWidth * 0.08,
                right: math.max(c.maxWidth * 0.08, rightCover + KSpace.x3),
                bottom: bottom,
              ),
              // The style sets the size (as in its preview), not the system
              // text size.
              child: Align(alignment: Alignment.bottomCenter, child: text),
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
    // One Text per line, each with its own direction: an English line under
    // an Arabic one stays left to right.
    Widget line(String text) {
      final dir = contentDir(text);
      return Stack(
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
    }

    Widget label = Column(
      mainAxisSize: MainAxisSize.min,
      children: [for (final l in lines) line(l)],
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
      label: lines.join('\n'),
      child: ExcludeSemantics(child: label),
    );
  }
}
