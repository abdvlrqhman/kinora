import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Severity of a log line.
enum LogLevel { debug, info, warn, error }

/// One log line.
final class LogLine {
  const LogLine(this.time, this.level, this.tag, this.message);
  final DateTime time;
  final LogLevel level;
  final String tag;
  final String message;

  @override
  String toString() =>
      '${time.toIso8601String()} ${level.name.padRight(5)} [$tag] $message';
}

/// App log: a ring buffer for the diagnostics screen plus a rotating file.
/// Nothing leaves the device unless the user exports it. Never log secrets.
abstract final class Log {
  static final _lines = ListQueue<LogLine>();
  static const _max = 2000;
  static IOSink? _sink;
  static File? _file;
  static int _written = 0;

  /// Starts writing to `<dir>/kinora.log` (rotates at 1 MB).
  static void attach(Directory dir) {
    _file = File('${dir.path}/kinora.log');
    if (_file!.existsSync() && _file!.lengthSync() > 1 << 20) {
      _file!.renameSync('${dir.path}/kinora.1.log');
    }
    // Lives for the whole app run; flushed on every 1 MB and by [flush].
    // ignore: close_sinks
    _sink = _file!.openWrite(mode: FileMode.append);
  }

  /// Flushes the log file (call when the app goes to the background).
  static Future<void> flush() async => _sink?.flush();

  static List<LogLine> get lines => List.unmodifiable(_lines);

  static void d(String tag, String message) =>
      _add(LogLevel.debug, tag, message);
  static void i(String tag, String message) =>
      _add(LogLevel.info, tag, message);
  static void w(String tag, String message) =>
      _add(LogLevel.warn, tag, message);
  static void e(String tag, String message, [Object? error, StackTrace? st]) =>
      _add(
        LogLevel.error,
        tag,
        error == null ? message : '$message: $error\n${st ?? ''}',
      );

  static final _url = RegExp(r'(https?://[^/\s]+)(/[^\s]*)');
  static final _secretish = RegExp(r'[A-Za-z0-9_\-]{32,}');
  static final _infoHash = RegExp(r'^[0-9a-f]{40}$');

  /// Hides what may be a key: addon config paths (they can hold debrid
  /// keys) and long opaque tokens. Info-hashes stay readable.
  static String redact(String s) => s
      .replaceAllMapped(_url, (m) {
        final path = m[2]!;
        final opaque = path.length > 48 || _secretish.hasMatch(path);
        return opaque ? '${m[1]}/…' : m[0]!;
      })
      .replaceAllMapped(
        _secretish,
        (m) => _infoHash.hasMatch(m[0]!) ? m[0]! : '…',
      );

  static void _add(LogLevel level, String tag, String message) {
    final line = LogLine(DateTime.now(), level, tag, redact(message));
    _lines.addLast(line);
    while (_lines.length > _max) {
      _lines.removeFirst();
    }
    if (kDebugMode) debugPrint(line.toString());
    final sink = _sink;
    if (sink != null && level != LogLevel.debug) {
      sink.writeln(line);
      _written += message.length;
      if (_written > 1 << 20) {
        _written = 0;
        unawaited(sink.flush());
      }
    }
  }

  /// Everything in the buffer as text (for "Copy diagnostics").
  static String dump() => _lines.join('\n');
}
