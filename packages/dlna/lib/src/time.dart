final _dlnaTime = RegExp(
  r'^\s*\+?(\d+):(\d{1,2}):(\d{1,2})(?:\.(\d+)(?:/(\d+))?)?\s*$',
);

/// Parses a UPnP/DLNA time value: `H+:MM:SS`, `H+:MM:SS.F+` (decimal
/// fraction) or `H+:MM:SS.F0/F1` (rational fraction).
///
/// Returns null for `NOT_IMPLEMENTED`, empty and malformed values.
Duration? parseDlnaTime(String? text) {
  final match = text == null ? null : _dlnaTime.firstMatch(text);
  if (match == null) return null;
  var micros =
      (int.parse(match[1]!) * 3600 +
          int.parse(match[2]!) * 60 +
          int.parse(match[3]!)) *
      Duration.microsecondsPerSecond;
  final fraction = match[4];
  final denominator = match[5];
  if (fraction != null && denominator != null) {
    final d = int.parse(denominator);
    if (d == 0) return null;
    micros += int.parse(fraction) * Duration.microsecondsPerSecond ~/ d;
  } else if (fraction != null) {
    micros += int.parse(fraction.padRight(6, '0').substring(0, 6));
  }
  return Duration(microseconds: micros);
}

/// Formats [value] as `H:MM:SS`, or `H:MM:SS.mmm` when [withMillis] is true
/// (the form used in DIDL-Lite `res@duration`). Negative values become zero.
String formatDlnaTime(Duration value, {bool withMillis = false}) {
  final d = value.isNegative ? Duration.zero : value;
  String two(int n) => n.toString().padLeft(2, '0');
  final base =
      '${d.inHours}:${two(d.inMinutes.remainder(60))}:'
      '${two(d.inSeconds.remainder(60))}';
  if (!withMillis) return base;
  return '$base.${d.inMilliseconds.remainder(1000).toString().padLeft(3, '0')}';
}
