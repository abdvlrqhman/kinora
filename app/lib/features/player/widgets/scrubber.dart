import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/format.dart';
import '../../../ui/tint.dart';
import '../../../ui/tokens.dart';

/// Seek bar: played (accent), ready to play (lamp, faint) and, for
/// torrents, how much of the file is on the device (fainter).
class Scrubber extends StatefulWidget {
  const Scrubber({
    super.key,
    required this.position,
    required this.duration,
    required this.buffered,
    required this.onSeek,
    this.downloaded,
    this.onScrubbing,
  });

  final Duration position;
  final Duration duration;

  /// End of what the player has buffered.
  final Duration buffered;

  /// 0..1 of the file on disk (torrents only).
  final double? downloaded;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<bool>? onScrubbing;

  @override
  State<Scrubber> createState() => _ScrubberState();
}

class _ScrubberState extends State<Scrubber> {
  double? _drag;

  double get _total => widget.duration.inMilliseconds.toDouble();

  double _fraction(Duration d) =>
      _total <= 0 ? 0 : (d.inMilliseconds / _total).clamp(0, 1);

  void _update(Offset local, double width) {
    setState(() => _drag = (local.dx / width).clamp(0, 1));
  }

  void _end() {
    final f = _drag;
    if (f == null) return;
    widget.onSeek(Duration(milliseconds: (f * _total).round()));
    widget.onScrubbing?.call(false);
    setState(() => _drag = null);
  }

  @override
  Widget build(BuildContext context) {
    final accent = KinoraTint.of(context);
    final played = _drag ?? _fraction(widget.position);
    final shown = _drag == null
        ? widget.position
        : Duration(milliseconds: (played * _total).round());
    final remaining = widget.duration - shown;
    return Semantics(
      slider: true,
      label: 'Playback position',
      value: '${Fmt.timecode(shown)} of ${Fmt.timecode(widget.duration)}',
      increasedValue: Fmt.timecode(shown + const Duration(seconds: 10)),
      decreasedValue: Fmt.timecode(shown - const Duration(seconds: 10)),
      onIncrease: () =>
          widget.onSeek(widget.position + const Duration(seconds: 10)),
      onDecrease: () =>
          widget.onSeek(widget.position - const Duration(seconds: 10)),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(Fmt.timecode(shown), style: KType.tabular(KType.label)),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: (d) {
                  widget.onScrubbing?.call(true);
                  HapticFeedback.selectionClick();
                  _update(d.localPosition, c.maxWidth);
                },
                onHorizontalDragUpdate: (d) =>
                    _update(d.localPosition, c.maxWidth),
                onHorizontalDragEnd: (_) => _end(),
                onTapDown: (d) => _update(d.localPosition, c.maxWidth),
                onTapUp: (_) => _end(),
                child: SizedBox(
                  height: 44,
                  child: CustomPaint(
                    painter: _BarPainter(
                      played: played,
                      buffered: _fraction(widget.buffered),
                      downloaded: widget.downloaded,
                      accent: accent,
                      active: _drag != null,
                    ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 72,
            child: Text(
              '-${Fmt.timecode(remaining.isNegative ? Duration.zero : remaining)}',
              textAlign: TextAlign.end,
              style: KType.tabular(KType.label.copyWith(color: KColors.haze)),
            ),
          ),
        ],
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.played,
    required this.buffered,
    required this.downloaded,
    required this.accent,
    required this.active,
  });

  final double played;
  final double buffered;
  final double? downloaded;
  final Color accent;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final h = active ? 6.0 : 4.0;
    final y = size.height / 2;
    final r = Radius.circular(h / 2);
    RRect bar(double from, double to) => RRect.fromLTRBR(
      size.width * from,
      y - h / 2,
      size.width * to,
      y + h / 2,
      r,
    );
    canvas
      ..drawRRect(
        bar(0, 1),
        Paint()..color = KColors.lamp.withValues(alpha: 0.16),
      )
      ..drawRRect(
        bar(0, downloaded ?? 0),
        Paint()..color = KColors.lamp.withValues(alpha: 0.12),
      )
      ..drawRRect(
        bar(0, buffered),
        Paint()..color = KColors.lamp.withValues(alpha: 0.32),
      )
      ..drawRRect(bar(0, played), Paint()..color = accent)
      ..drawCircle(
        Offset(size.width * played, y),
        active ? 9 : 7,
        Paint()..color = KColors.lamp,
      );
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.played != played ||
      old.buffered != buffered ||
      old.downloaded != downloaded ||
      old.accent != accent ||
      old.active != active;
}
