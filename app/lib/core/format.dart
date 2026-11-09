/// Human-readable numbers for the UI. Plain, compact, no trailing zeros.
abstract final class Fmt {
  static const _units = ['B', 'KB', 'MB', 'GB', 'TB'];

  /// 1536 → "1.5 KB", 734003200 → "700 MB", 2147483648 → "2 GB".
  static String bytes(int b) {
    if (b < 1024) return '$b B';
    var v = b.toDouble();
    var i = 0;
    while (v >= 1024 && i < _units.length - 1) {
      v /= 1024;
      i++;
    }
    final s = v >= 100 || v == v.roundToDouble()
        ? v.round().toString()
        : v.toStringAsFixed(1);
    return '$s ${_units[i]}';
  }

  /// Bytes per second → "3.4 MB/s".
  static String speed(int bytesPerSecond) => '${bytes(bytesPerSecond)}/s';

  /// 6720 s → "1h 52m", 300 s → "5m", 42 s → "42s".
  static String duration(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
    if (h > 0) return m == 0 ? '${h}h' : '${h}h ${m}m';
    if (m > 0) return '${m}m';
    return '${s}s';
  }

  /// Player timecode: 1:02:03 or 2:03.
  static String timecode(Duration d) {
    final neg = d.isNegative;
    final a = d.abs();
    final h = a.inHours, m = a.inMinutes % 60, s = a.inSeconds % 60;
    final mm = h > 0 ? m.toString().padLeft(2, '0') : '$m';
    final out = '${h > 0 ? '$h:' : ''}$mm:${s.toString().padLeft(2, '0')}';
    return neg ? '-$out' : out;
  }

  /// "S1 E3" style episode label.
  static String episode(int season, int episode) => 'S$season E$episode';
}
