/// How [fixRtl] marks right-to-left lines.
enum RtlMarks {
  /// Wrap each line in RIGHT-TO-LEFT EMBEDDING (U+202B) ... POP DIRECTIONAL
  /// FORMATTING (U+202C). Works in most players and TVs.
  embedding,

  /// Put RIGHT-TO-LEFT MARK (U+200F) at both ends of each line. Lighter; good
  /// for renderers that ignore embeddings.
  rlm,
}

const _rle = '\u202B', _pdf = '\u202C', _rlm = '\u200F';
final _rtlLetter = RegExp(r'[\u0590-\u08FF\uFB1D-\uFDFF\uFE70-\uFEFF]');
final _leadingPunct = RegExp(r'^([.,!?؟،…:;]+)(\s*)');
final _leadingTags = RegExp(r'^((?:\{\\[^}]*\}|<[^>]+>)*)');

/// Fixes punctuation that renders on the wrong side in Arabic, Hebrew,
/// Persian and Urdu lines by forcing a right-to-left base direction.
///
/// Only lines containing RTL letters are touched, already-marked lines are
/// left alone (idempotent). With [moveLeadingPunctuation], lines that were
/// "pre-reversed" for LTR players (`.مرحبا`) get their leading punctuation
/// moved to the logical end first.
String fixRtl(
  String text, {
  RtlMarks marks = RtlMarks.embedding,
  bool moveLeadingPunctuation = false,
}) => text
    .split('\n')
    .map((line) {
      if (!_rtlLetter.hasMatch(line)) return line;
      final tags = _leadingTags.firstMatch(line)!.group(1)!;
      var body = line.substring(tags.length);
      if (body.startsWith(_rle) || body.startsWith(_rlm)) return line;
      if (moveLeadingPunctuation) {
        final p = _leadingPunct.firstMatch(body);
        if (p != null &&
            p.end < body.length &&
            _rtlLetter.hasMatch(body[p.end])) {
          body = '${body.substring(p.end)}${p.group(1)}';
        }
      }
      return switch (marks) {
        RtlMarks.embedding => '$tags$_rle$body$_pdf',
        RtlMarks.rlm => '$tags$_rlm$body$_rlm',
      };
    })
    .join('\n');
