import 'document.dart';
import 'errors.dart';
import 'models.dart';

final _newline = RegExp(r'\r\n|\r|\n');
const _ts = r'(?:\d+:)?\d{1,2}:\d{1,2}(?:[,.:]\d{1,3})?';
final _timing = RegExp('^\\s*($_ts)\\s*-+>\\s*($_ts)');
final _microDvdLine = RegExp(r'^\{(\d+)\}\{(\d*)\}(.*)$');
final _mpl2Line = RegExp(r'^\[(\d+)\]\[(\d*)\](.*)$');

/// Detects the format from the text itself (not the file extension).
/// Returns null for unknown/unsupported content (SAMI, TTML, binary ...).
SubtitleFormat? detectFormat(String text) {
  final head = text.length > 20000 ? text.substring(0, 20000) : text;
  final trimmed = head.replaceFirst('\uFEFF', '').trimLeft();
  if (trimmed.startsWith('WEBVTT')) return SubtitleFormat.webvtt;
  final lower = head.toLowerCase();
  if (lower.contains('[script info]') ||
      (lower.contains('[events]') && lower.contains('dialogue:'))) {
    if (lower.contains('[v4 styles]') ||
        RegExp(r'scripttype:\s*v4\.00\s*$', multiLine: true).hasMatch(lower)) {
      return SubtitleFormat.ssa;
    }
    return SubtitleFormat.ass;
  }
  final lines = trimmed.split(_newline).take(200).toList();
  final firstLine = lines.firstWhere(
    (l) => l.trim().isNotEmpty,
    orElse: () => '',
  );
  if (_microDvdLine.hasMatch(firstLine.trim())) return SubtitleFormat.microDvd;
  if (_mpl2Line.hasMatch(firstLine.trim())) return SubtitleFormat.mpl2;
  if (lines.any(_timing.hasMatch)) return SubtitleFormat.srt;
  return null;
}

/// Parses subtitle [text] into a [SubtitleDocument].
///
/// [format] defaults to [detectFormat]. [fps] is needed for MicroDVD files
/// that don't declare it (default 23.976). Tolerates BOMs, CRLF, missing
/// indices or blank lines, overlapping and unsorted cues. Throws
/// [SubtitleFormatException] for unknown content or zero cues.
SubtitleDocument parseSubtitle(
  String text, {
  SubtitleFormat? format,
  double? fps,
}) {
  final src = text.replaceFirst('\uFEFF', '');
  final f = format ?? detectFormat(src);
  if (f == null) {
    throw const SubtitleFormatException('unrecognized subtitle format');
  }
  final doc = switch (f) {
    SubtitleFormat.srt => _parseSrt(src, vtt: false),
    SubtitleFormat.webvtt => _parseSrt(src, vtt: true),
    SubtitleFormat.ass || SubtitleFormat.ssa => _parseAss(src, f),
    SubtitleFormat.microDvd => _parseMicroDvd(src, fps),
    SubtitleFormat.mpl2 => _parseMpl2(src),
  };
  if (doc.cues.isEmpty) {
    throw SubtitleFormatException('no cues found in ${f.name} subtitle');
  }
  return doc;
}

/// Parses `[hh:]mm:ss[,.:]fff`; fractions shorter than 3 digits are
/// fractions of a second (`1,5` = 1.5 s).
Duration? parseTimestamp(String s) {
  final m = RegExp(r'^(?:(\d+):)?(\d{1,2}):(\d{1,2})(?:([,.:])(\d{1,3}))?$')
      .firstMatch(s.trim());
  if (m == null) return null;
  final h = int.tryParse(m.group(1) ?? '') ?? 0;
  final min = int.parse(m.group(2)!);
  final sec = int.parse(m.group(3)!);
  final frac = m.group(5);
  final ms = frac == null ? 0 : int.parse(frac.padRight(3, '0'));
  return Duration(hours: h, minutes: min, seconds: sec, milliseconds: ms);
}

SubtitleDocument _parseSrt(String src, {required bool vtt}) {
  final cues = <Cue>[];
  Duration? start, end;
  var buf = <String>[];
  var closed = false; // VTT: a blank line ends the cue text

  void flush({required bool beforeTiming}) {
    if (start == null) return;
    var lines = [...buf];
    while (lines.isNotEmpty && lines.last.trim().isEmpty) {
      lines.removeLast();
    }
    // A number right before the next timing line is that cue's index.
    if (beforeTiming &&
        lines.isNotEmpty &&
        RegExp(r'^\d+$').hasMatch(lines.last.trim())) {
      lines.removeLast();
    }
    lines = [
      for (final l in lines)
        if (l.trim().isNotEmpty) l.trimRight(),
    ];
    final text = vtt ? _vttToTags(lines.join('\n')) : lines.join('\n');
    final s = start, e = end!;
    if (text.trim().isNotEmpty && e >= s) {
      cues.add(Cue(start: s, end: e, text: text));
    }
  }

  for (final line in src.split(_newline)) {
    final m = _timing.firstMatch(line);
    final s = m == null ? null : parseTimestamp(m.group(1)!);
    final e = m == null ? null : parseTimestamp(m.group(2)!);
    if (s != null && e != null) {
      if (vtt) {
        // VTT cue ids are arbitrary text: drop whatever followed the blank.
        if (closed) buf = _untilBlank(buf);
        flush(beforeTiming: false);
      } else {
        flush(beforeTiming: true);
      }
      start = s;
      end = e;
      buf = [];
      closed = false;
    } else if (start != null) {
      if (vtt && line.trim().isEmpty) closed = true;
      buf.add(line);
    }
  }
  if (vtt && closed) buf = _untilBlank(buf);
  flush(beforeTiming: false);
  return SubtitleDocument(
    cues: cues,
    sourceFormat: vtt ? SubtitleFormat.webvtt : SubtitleFormat.srt,
  );
}

List<String> _untilBlank(List<String> lines) {
  final i = lines.indexWhere((l) => l.trim().isEmpty);
  return i < 0 ? lines : lines.sublist(0, i);
}

String _vttToTags(String text) => text
    .replaceAll(RegExp(r'<(?!/?(?:i|b|u)>)[^>]*>', caseSensitive: false), '')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&lrm;', '\u200E')
    .replaceAll('&rlm;', '\u200F')
    .replaceAll('&amp;', '&');

SubtitleDocument _parseAss(String src, SubtitleFormat f) {
  final lines = src.split(_newline);
  final eventsAt = lines.indexWhere(
    (l) => l.trim().toLowerCase() == '[events]',
  );
  final header = eventsAt < 0
      ? null
      : lines.sublist(0, eventsAt).join('\n').trim();
  var format = const [
    'Layer',
    'Start',
    'End',
    'Style',
    'Name',
    'MarginL',
    'MarginR',
    'MarginV',
    'Effect',
    'Text',
  ];
  final cues = <Cue>[];
  var inEvents = false;
  for (final raw in lines) {
    final line = raw.trim();
    if (line.startsWith('[') && line.endsWith(']')) {
      inEvents = line.toLowerCase() == '[events]';
      continue;
    }
    if (!inEvents) continue;
    final colon = line.indexOf(':');
    if (colon < 0) continue;
    final kind = line.substring(0, colon).trim().toLowerCase();
    final rest = line.substring(colon + 1).trimLeft();
    if (kind == 'format') {
      format = [for (final p in rest.split(',')) p.trim()];
      continue;
    }
    if (kind != 'dialogue') continue;
    final fields = _splitFields(rest, format.length);
    if (fields.length != format.length) continue;
    final si = _indexOf(format, 'start'), ei = _indexOf(format, 'end');
    final s = si < 0 ? null : parseTimestamp(fields[si]);
    final e = ei < 0 ? null : parseTimestamp(fields[ei]);
    if (s == null || e == null) continue;
    final raw0 = fields.last;
    if (RegExp(r'\{[^}]*\\p[1-9]').hasMatch(raw0)) continue; // vector drawing
    final text = assToTags(raw0);
    if (text.trim().isEmpty) continue;
    cues.add(Cue(start: s, end: e, text: text, assFields: fields));
  }
  return SubtitleDocument(
    cues: cues,
    sourceFormat: f,
    assHeader: header,
    assEventFormat: format,
  );
}

int _indexOf(List<String> format, String name) =>
    format.indexWhere((f) => f.toLowerCase() == name);

List<String> _splitFields(String s, int count) {
  final out = <String>[];
  var rest = s;
  for (var i = 0; i < count - 1; i++) {
    final c = rest.indexOf(',');
    if (c < 0) return out;
    out.add(rest.substring(0, c).trim());
    rest = rest.substring(c + 1);
  }
  out.add(rest);
  return out;
}

/// Converts ASS text to normalized cue text: `\N` -> newline, italic/bold/
/// underline overrides -> tags, every other override block removed, except
/// `{\anN}` positioning which SRT players also understand.
String assToTags(String ass) {
  final open = <String>[];
  final out = ass.replaceAllMapped(RegExp(r'\{([^}]*)\}'), (m) {
    final block = m.group(1)!;
    final buf = StringBuffer();
    final an = RegExp(r'\\an([1-9])').firstMatch(block);
    if (an != null) buf.write('{\\an${an.group(1)}}');
    for (final t in RegExp(r'\\([ibu])(\d+)').allMatches(block)) {
      final tag = t.group(1)!;
      final on = t.group(2) != '0';
      if (on && !open.contains(tag)) {
        open.add(tag);
        buf.write('<$tag>');
      } else if (!on && open.contains(tag)) {
        open.remove(tag);
        buf.write('</$tag>');
      }
    }
    return buf.toString();
  });
  final closing = open.reversed.map((t) => '</$t>').join();
  return '$out$closing'
      .replaceAll(RegExp(r'\\[Nn]'), '\n')
      .replaceAll(r'\h', ' ')
      .split('\n')
      .map((l) => l.trim())
      .join('\n')
      .trim();
}

SubtitleDocument _parseMicroDvd(String src, double? fps) {
  var rate = fps ?? 23.976;
  final cues = <Cue>[];
  var first = true;
  for (final raw in src.split(_newline)) {
    final m = _microDvdLine.firstMatch(raw.trim());
    if (m == null) continue;
    final a = int.parse(m.group(1)!);
    final b = int.tryParse(m.group(2)!);
    final body = m.group(3)!;
    if (first) {
      first = false;
      final declared = double.tryParse(body.trim());
      if (a <= 1 && (b ?? 0) <= 1 && declared != null && declared > 0) {
        if (fps == null) rate = declared;
        continue;
      }
    }
    final start = _frames(a, rate);
    final end = b == null
        ? start + const Duration(seconds: 3)
        : _frames(b, rate);
    // Upper-case codes ({Y:i}) at the start style every line; lower-case
    // ones ({y:i}) only their own line.
    final global =
        RegExp(r'^(\{[A-Z]:[^}]*\})+').firstMatch(body)?.group(0) ?? '';
    final text = _pipeLines(body.substring(global.length), (line) {
      var italic = false, bold = false;
      final clean = '$global$line'.replaceAllMapped(
        RegExp(r'\{([a-zA-Z]):([^}]*)\}'),
        (c) {
          if (c.group(1)!.toLowerCase() == 'y') {
            italic |= c.group(2)!.contains('i');
            bold |= c.group(2)!.contains('b');
          }
          return '';
        },
      );
      var t = clean.trim();
      if (bold) t = '<b>$t</b>';
      if (italic) t = '<i>$t</i>';
      return t;
    });
    if (text.isNotEmpty) cues.add(Cue(start: start, end: end, text: text));
  }
  return SubtitleDocument(cues: cues, sourceFormat: SubtitleFormat.microDvd);
}

Duration _frames(int frames, double fps) =>
    Duration(microseconds: (frames / fps * 1e6).round());

SubtitleDocument _parseMpl2(String src) {
  final cues = <Cue>[];
  for (final raw in src.split(_newline)) {
    final m = _mpl2Line.firstMatch(raw.trim());
    if (m == null) continue;
    final start = Duration(milliseconds: int.parse(m.group(1)!) * 100);
    final b = int.tryParse(m.group(2)!);
    final end = b == null
        ? start + const Duration(seconds: 3)
        : Duration(milliseconds: b * 100);
    final text = _pipeLines(
      m.group(3)!,
      (l) => l.startsWith('/') ? '<i>${l.substring(1).trim()}</i>' : l.trim(),
    );
    if (text.isNotEmpty) cues.add(Cue(start: start, end: end, text: text));
  }
  return SubtitleDocument(cues: cues, sourceFormat: SubtitleFormat.mpl2);
}

String _pipeLines(String body, String Function(String) line) =>
    body.split('|').map(line).where((l) => l.isNotEmpty).join('\n');
