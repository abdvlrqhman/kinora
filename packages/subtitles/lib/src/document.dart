import 'package:collection/collection.dart';

import 'models.dart';

const _eq = DeepCollectionEquality();

/// One timed subtitle line.
///
/// [text] is normalized: lines joined by `\n`, inline styling as SRT-style
/// tags (`<i>`, `<b>`, `<u>`, `<font color=...>`), possibly `{\anN}`
/// positioning. Cues parsed from ASS/SSA also keep the original event fields
/// in [assFields] so they can be written back with full styling.
final class Cue {
  const Cue({
    required this.start,
    required this.end,
    required this.text,
    this.assFields,
  });

  final Duration start;
  final Duration end;
  final String text;

  /// Original ASS/SSA `Dialogue:` fields (Text last), when parsed from ASS.
  final List<String>? assFields;

  Duration get duration => end - start;

  Cue copyWith({Duration? start, Duration? end, String? text}) => Cue(
    start: start ?? this.start,
    end: end ?? this.end,
    text: text ?? this.text,
    assFields: assFields,
  );

  @override
  bool operator ==(Object other) =>
      other is Cue &&
      other.start == start &&
      other.end == end &&
      other.text == text &&
      _eq.equals(other.assFields, assFields);

  @override
  int get hashCode => Object.hash(start, end, text, _eq.hash(assFields));

  @override
  String toString() =>
      'Cue(${formatSrtTime(start)} --> ${formatSrtTime(end)} '
      '"${text.replaceAll('\n', r'\n')}")';
}

/// Parsed subtitle: cues sorted by start time, plus ASS header data.
final class SubtitleDocument {
  SubtitleDocument({
    required List<Cue> cues,
    required this.sourceFormat,
    this.assHeader,
    this.assEventFormat,
  }) : cues = List<Cue>.unmodifiable(_sorted(cues));

  // Stable: cues starting together keep their file order (ASS layers).
  static List<Cue> _sorted(List<Cue> cues) {
    final list = [...cues];
    mergeSort(list, compare: (Cue a, Cue b) => a.start.compareTo(b.start));
    return list;
  }

  final List<Cue> cues;

  /// Format the document was parsed from.
  final SubtitleFormat sourceFormat;

  /// ASS/SSA sections before `[Events]` (script info, styles), verbatim.
  final String? assHeader;

  /// ASS/SSA `[Events]` `Format:` field names.
  final List<String>? assEventFormat;

  /// Moves every cue by [offset]; cues pushed entirely before 0 are dropped.
  SubtitleDocument shift(Duration offset) => _map(
    (c) => c.end + offset <= Duration.zero
        ? null
        : c.copyWith(start: _max0(c.start + offset), end: c.end + offset),
  );

  /// Multiplies every timestamp by [factor] (e.g. `25 / 23.976` to fix a
  /// subtitle made for 23.976 fps playing against a 25 fps video).
  SubtitleDocument scale(double factor) =>
      _map((c) => c.copyWith(start: c.start * factor, end: c.end * factor));

  /// Applies [transform] to the text of every cue (e.g. `fixRtl`), including
  /// the raw ASS text kept for [toAss].
  SubtitleDocument mapText(String Function(String text) transform) => _map((c) {
    final f = c.assFields;
    return Cue(
      start: c.start,
      end: c.end,
      text: transform(c.text),
      assFields: f == null || f.isEmpty
          ? f
          : [
              ...f.take(f.length - 1),
              transform(f.last.replaceAll(r'\N', '\n')).replaceAll('\n', r'\N'),
            ],
    );
  });

  SubtitleDocument _map(Cue? Function(Cue) f) => SubtitleDocument(
    cues: [...cues.map(f).nonNulls],
    sourceFormat: sourceFormat,
    assHeader: assHeader,
    assEventFormat: assEventFormat,
  );

  /// SubRip text (CRLF line endings) for TVs and simple players. ASS
  /// override blocks are removed; `<i>/<b>/<u>/<font>` tags are kept.
  String toSrt() {
    final out = StringBuffer();
    var n = 0;
    for (final c in cues) {
      final text = _lines(stripAssTags(c.text));
      if (text.isEmpty) continue;
      out
        ..write('${++n}\r\n')
        ..write('${formatSrtTime(c.start)} --> ${formatSrtTime(c.end)}\r\n')
        ..write(text.join('\r\n'))
        ..write('\r\n\r\n');
    }
    return out.toString();
  }

  /// WebVTT text. Only `<i>/<b>/<u>` tags survive; text is entity-escaped.
  String toVtt() {
    final out = StringBuffer('WEBVTT\n\n');
    for (final c in cues) {
      final text = _lines(_vttText(stripAssTags(c.text)));
      if (text.isEmpty) continue;
      out
        ..write('${_vttTime(c.start)} --> ${_vttTime(c.end)}\n')
        ..write(text.join('\n'))
        ..write('\n\n');
    }
    return out.toString();
  }

  /// ASS text. Documents parsed from ASS/SSA keep their header, styles and
  /// per-event fields; others get a default style with tags converted.
  String toAss() {
    final format = assEventFormat;
    final out = StringBuffer();
    if (assHeader != null && format != null) {
      final si = format.indexWhere((f) => f.toLowerCase() == 'start');
      final ei = format.indexWhere((f) => f.toLowerCase() == 'end');
      out
        ..write(assHeader!.trimRight())
        ..write('\n\n[Events]\nFormat: ${format.join(', ')}\n');
      for (final c in cues) {
        final fields = [...?c.assFields];
        if (fields.length != format.length) {
          fields
            ..clear()
            ..addAll(_defaultFields(format, c));
        }
        fields[si] = formatAssTime(c.start);
        fields[ei] = formatAssTime(c.end);
        out.write('Dialogue: ${fields.join(',')}\n');
      }
      return out.toString();
    }
    out.write(_defaultAssHeader);
    for (final c in cues) {
      out.write(
        'Dialogue: 0,${formatAssTime(c.start)},${formatAssTime(c.end)},'
        'Default,,0,0,0,,${_htmlToAss(c.text)}\n',
      );
    }
    return out.toString();
  }

  @override
  bool operator ==(Object other) =>
      other is SubtitleDocument &&
      other.sourceFormat == sourceFormat &&
      other.assHeader == assHeader &&
      _eq.equals(other.assEventFormat, assEventFormat) &&
      _eq.equals(other.cues, cues);

  @override
  int get hashCode => Object.hash(
    sourceFormat,
    assHeader,
    _eq.hash(assEventFormat),
    _eq.hash(cues),
  );

  @override
  String toString() =>
      'SubtitleDocument(${sourceFormat.name}, ${cues.length} cues)';
}

Duration _max0(Duration d) => d.isNegative ? Duration.zero : d;

List<String> _lines(String text) => [
  for (final l in text.split('\n'))
    if (l.trim().isNotEmpty) l.trimRight(),
];

/// Removes ASS override blocks like `{\an8}` or `{\i1\c&H00FF00&}`.
String stripAssTags(String text) => text.replaceAll(RegExp(r'\{\\[^}]*\}'), '');

/// Removes every markup tag (`<...>` and `{\...}`), leaving plain text.
String plainText(String text) =>
    stripAssTags(text).replaceAll(RegExp(r'</?[a-zA-Z][^>]*>'), '');

String _two(int n) => n.toString().padLeft(2, '0');

/// `HH:MM:SS,mmm`
String formatSrtTime(Duration d) {
  final ms = _max0(d).inMilliseconds;
  return '${_two(ms ~/ 3600000)}:${_two(ms ~/ 60000 % 60)}:'
      '${_two(ms ~/ 1000 % 60)},${(ms % 1000).toString().padLeft(3, '0')}';
}

String _vttTime(Duration d) => formatSrtTime(d).replaceFirst(',', '.');

/// `H:MM:SS.cc`
String formatAssTime(Duration d) {
  final cs = (_max0(d).inMilliseconds + 5) ~/ 10;
  return '${cs ~/ 360000}:${_two(cs ~/ 6000 % 60)}:'
      '${_two(cs ~/ 100 % 60)}.${_two(cs % 100)}';
}

String _vttText(String text) {
  final keep = RegExp(r'</?(i|b|u)>', caseSensitive: false);
  final buf = StringBuffer();
  var last = 0;
  for (final m in RegExp(r'<[^>]*>').allMatches(text)) {
    buf.write(_escape(text.substring(last, m.start)));
    if (keep.hasMatch(m.group(0)!)) buf.write(m.group(0)!.toLowerCase());
    last = m.end;
  }
  buf.write(_escape(text.substring(last)));
  return buf.toString();
}

String _escape(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

String _htmlToAss(String text) => text
    .replaceAllMapped(
      RegExp(r'<(/?)(i|b|u)>', caseSensitive: false),
      (m) => '{\\${m.group(2)!.toLowerCase()}${m.group(1)!.isEmpty ? 1 : 0}}',
    )
    .replaceAll(RegExp(r'</?[a-zA-Z][^>]*>'), '')
    .replaceAll('\n', r'\N');

List<String> _defaultFields(List<String> format, Cue c) => [
  for (final f in format)
    switch (f.toLowerCase()) {
      'text' => _htmlToAss(c.text),
      'style' => 'Default',
      'layer' || 'marginl' || 'marginr' || 'marginv' => '0',
      'marked' => 'Marked=0',
      _ => '',
    },
];

const _defaultAssHeader = '''[Script Info]
ScriptType: v4.00+
PlayResX: 1920
PlayResY: 1080
WrapStyle: 0
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,Arial,64,&H00FFFFFF,&H000000FF,&H00000000,&H80000000,0,0,0,0,100,100,0,0,1,3,1,2,60,60,50,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
''';
