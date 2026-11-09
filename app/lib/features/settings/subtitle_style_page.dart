import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:subtitles/subtitles.dart' show Language;

import '../../app/providers.dart';
import '../../core/settings.dart';
import '../../ui/tokens.dart';
import 'widgets/settings_ui.dart';

/// Subtitle colors on offer: (ARGB, name).
const subtitleColors = [
  (0xFFF5EEE4, 'Warm white'),
  (0xFFFFFFFF, 'White'),
  (0xFFFFE45E, 'Yellow'),
  (0xFF8BE9FD, 'Cyan'),
  (0xFF9AF29A, 'Green'),
];

String _colorName(int c) =>
    subtitleColors.where((e) => e.$1 == c).firstOrNull?.$2 ?? 'Custom color';

/// "100% size, warm white, outline" for the row that opens this page.
String styleSummary(SubtitleStyle s) => [
  '${(s.scale * 100).round()}% size',
  _colorName(s.color).toLowerCase(),
  if (s.outline) 'outline',
  if (s.backgroundOpacity > 0) 'box',
  if (s.bold) 'bold',
].join(', ');

/// Settings › Languages and subtitles › Subtitle style, with a live preview
/// over a sample frame. Sliders preview while dragging and save on release.
class SubtitleStylePage extends StatelessWidget {
  const SubtitleStylePage({super.key});

  @override
  Widget build(BuildContext context) => const SettingsPage(
    title: 'Subtitle style',
    children: [SubtitleStyleControls()],
  );
}

/// The subtitle look (size, color, box, outline, bold, height) with a live
/// preview. One style for everything you watch: used by Settings and by the
/// player's Audio and subtitles panel.
class SubtitleStyleControls extends ConsumerStatefulWidget {
  const SubtitleStyleControls({super.key});

  @override
  ConsumerState<SubtitleStyleControls> createState() =>
      _SubtitleStyleControlsState();
}

class _SubtitleStyleControlsState extends ConsumerState<SubtitleStyleControls> {
  late SubtitleStyle _style = ref.read(settingsProvider).subtitleStyle;

  void _preview(SubtitleStyle s) => setState(() => _style = s);

  void _save(SubtitleStyle s) {
    _preview(s);
    unawaited(
      ref
          .read(settingsProvider.notifier)
          .update((a) => a.copyWith(subtitleStyle: s)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _style;
    final first = ref.watch(settingsProvider).primaryLanguage;
    final rtl =
        first != null && (Language.parse(first)?.isRightToLeft ?? false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            KSpace.margin,
            KSpace.x2,
            KSpace.margin,
            KSpace.x2,
          ),
          child: SubtitlePreview(style: s, rtl: rtl),
        ),
        _SliderRow(
          label: 'Size',
          valueText: '${(s.scale * 100).round()}%',
          value: s.scale,
          min: 0.6,
          max: 2,
          divisions: 14,
          onChanged: (v) => _preview(_style.copyWith(scale: v)),
          onChangeEnd: (v) => _save(_style.copyWith(scale: v)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            KSpace.margin,
            KSpace.x3,
            KSpace.margin,
            0,
          ),
          child: Semantics(
            header: true,
            child: Text('Color', style: KType.title),
          ),
        ),
        _Swatches(
          value: s.color,
          onChanged: (c) => _save(_style.copyWith(color: c)),
        ),
        _SliderRow(
          label: 'Background box',
          valueText: s.backgroundOpacity == 0
              ? 'Off'
              : '${(s.backgroundOpacity * 100).round()}%',
          value: s.backgroundOpacity,
          min: 0,
          max: 1,
          divisions: 10,
          onChanged: (v) => _preview(_style.copyWith(backgroundOpacity: v)),
          onChangeEnd: (v) => _save(_style.copyWith(backgroundOpacity: v)),
        ),
        SwitchRow(
          label: 'Outline',
          detail: 'A dark edge keeps text readable on bright scenes.',
          value: s.outline,
          onChanged: (v) => _save(_style.copyWith(outline: v)),
        ),
        SwitchRow(
          label: 'Bold',
          value: s.bold,
          onChanged: (v) => _save(_style.copyWith(bold: v)),
        ),
        _SliderRow(
          label: 'Height above the bottom',
          valueText: '${(s.bottomMargin * 100).round()}%',
          value: s.bottomMargin,
          min: 0.02,
          max: 0.2,
          divisions: 9,
          onChanged: (v) => _preview(_style.copyWith(bottomMargin: v)),
          onChangeEnd: (v) => _save(_style.copyWith(bottomMargin: v)),
        ),
        const SizedBox(height: KSpace.x3),
        ActionRow(
          icon: Icons.restart_alt_rounded,
          label: 'Reset to default',
          onTap: s == const SubtitleStyle()
              ? null
              : () => _save(const SubtitleStyle()),
        ),
      ],
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.valueText,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final String label;
  final String valueText;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      KSpace.margin,
      KSpace.x3,
      KSpace.margin,
      0,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExcludeSemantics(
          child: Row(
            children: [
              Expanded(child: Text(label, style: KType.title)),
              Text(
                valueText,
                style: KType.tabular(KType.body.copyWith(color: KColors.haze)),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 44,
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            label: valueText,
            semanticFormatterCallback: (_) => '$label $valueText',
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
      ],
    ),
  );
}

class _Swatches extends StatelessWidget {
  const _Swatches({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      KSpace.margin,
      KSpace.x2,
      KSpace.margin,
      KSpace.x2,
    ),
    child: Wrap(
      spacing: KSpace.x3,
      runSpacing: KSpace.x3,
      children: [
        for (final (argb, name) in subtitleColors)
          Semantics(
            container: true,
            button: true,
            selected: argb == value,
            inMutuallyExclusiveGroup: true,
            label: name,
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(argb),
              child: SizedBox.square(
                dimension: 48,
                child: Center(
                  child: AnimatedContainer(
                    duration: reduceMotion(context)
                        ? Duration.zero
                        : KMotion.fast,
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Color(argb),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: argb == value
                            ? KColors.lamp
                            : const Color(0x00000000),
                        width: 3,
                        strokeAlign: BorderSide.strokeAlignOutside,
                      ),
                    ),
                    child: argb == value
                        ? const Icon(
                            Icons.check_rounded,
                            color: KColors.blackout,
                            size: 22,
                          )
                        : null,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// The style drawn over a sample frame at a phone's landscape proportions,
/// so size and position match what the player shows. Only the bottom of the
/// frame is shown, at 1:1, so the text appears at its real size (scaled
/// down only when its lines are wider than the screen).
class SubtitlePreview extends StatelessWidget {
  const SubtitlePreview({super.key, required this.style, this.rtl = false});

  final SubtitleStyle style;
  final bool rtl;

  static const _frame = Size(844, 390);

  @override
  Widget build(BuildContext context) {
    final fontSize = (_frame.height * 0.052).clamp(15.0, 44.0) * style.scale;
    final text = rtl
        ? 'لم يغادر حارس المنارة الجزيرة قط.\nكان ينتظر سفينة لن تعود.'
        : 'The keeper never left the island.\nHe was waiting for a ship.';
    final lines = text.split('\n');
    var widest = 0.0;
    for (final line in lines) {
      final painter = TextPainter(
        text: TextSpan(
          text: line,
          style: TextStyle(
            fontFamily: KType.text,
            fontSize: fontSize,
            fontWeight: style.bold ? FontWeight.w700 : FontWeight.w600,
            fontVariations: [FontVariation.weight(style.bold ? 700 : 600)],
          ),
        ),
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      )..layout();
      widest = math.max(widest, painter.width);
      painter.dispose();
    }
    final textHeight = lines.length * fontSize * 1.25 + fontSize * 0.3;
    return LayoutBuilder(
      builder: (context, c) {
        final cropWidth = math.min(
          _frame.width,
          math.max(c.maxWidth, widest + fontSize + KSpace.section),
        );
        final cropHeight = math.min(
          _frame.height,
          math.max(
            150.0,
            _frame.height * style.bottomMargin + textHeight + KSpace.x4,
          ),
        );
        final scale = c.maxWidth / cropWidth;
        return Semantics(
          // Its own node: read as one image, not merged with the controls.
          container: true,
          label: 'Preview of your subtitle style',
          image: true,
          excludeSemantics: true,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(KRadius.still),
            child: SizedBox(
              width: c.maxWidth,
              height: cropHeight * scale,
              child: FittedBox(
                child: SizedBox(
                  width: cropWidth,
                  height: cropHeight,
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.bottomCenter,
                      minWidth: _frame.width,
                      maxWidth: _frame.width,
                      minHeight: _frame.height,
                      maxHeight: _frame.height,
                      child: MediaQuery.withNoTextScaling(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            const CustomPaint(painter: _ScenePainter()),
                            Padding(
                              padding: EdgeInsets.only(
                                left: _frame.width * 0.08,
                                right: _frame.width * 0.08,
                                bottom: _frame.height * style.bottomMargin,
                              ),
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: _StyledLines(
                                  text: text,
                                  style: style,
                                  fontSize: fontSize,
                                  rtl: rtl,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// shortcut: mirrors the player's private subtitle line renderer
// (features/player/widgets/subtitle_overlay.dart); share it once the player
// exposes one.
class _StyledLines extends StatelessWidget {
  const _StyledLines({
    required this.text,
    required this.style,
    required this.fontSize,
    required this.rtl,
  });

  final String text;
  final SubtitleStyle style;
  final double fontSize;
  final bool rtl;

  @override
  Widget build(BuildContext context) {
    final dir = rtl ? TextDirection.rtl : TextDirection.ltr;
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
    return label;
  }
}

/// A dusk shoreline: dark sky, a bright horizon and pale sand, so the
/// preview shows the style against both dark and light areas.
class _ScenePainter extends CustomPainter {
  const _ScenePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final sky = Rect.fromLTWH(0, 0, w, h * 0.58);
    canvas.drawRect(
      sky,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF141B2E), Color(0xFF5B4A6B), Color(0xFFF2B27A)],
          stops: [0, 0.6, 1],
        ).createShader(sky),
    );
    canvas.drawCircle(
      Offset(w * 0.68, h * 0.56),
      h * 0.11,
      Paint()..color = const Color(0xFFFFE2B0),
    );
    final sea = Rect.fromLTWH(0, h * 0.56, w, h * 0.16);
    canvas.drawRect(
      sea,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFC98E6A), Color(0xFF2F3B52)],
        ).createShader(sea),
    );
    final sand = Path()
      ..moveTo(0, h * 0.74)
      ..quadraticBezierTo(w * 0.4, h * 0.68, w, h * 0.76)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(sand, Paint()..color = const Color(0xFFE3CFAE));
    final hill = Path()
      ..moveTo(0, h * 0.56)
      ..quadraticBezierTo(w * 0.12, h * 0.38, w * 0.3, h * 0.56)
      ..close();
    canvas.drawPath(hill, Paint()..color = const Color(0xFF1B1626));
  }

  @override
  bool shouldRepaint(_ScenePainter old) => false;
}
