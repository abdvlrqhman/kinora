import 'document.dart';

/// Promotional lines subtitle sites inject (not translator credits).
final _ad = RegExp(
  [
    r'advertise your product or brand here',
    r'support us and become vip member',
    r'remove all ads from',
    r'please rate this subtitle',
    r'help other users to choose the best subtitles',
    r'(www\.)?opensubtitles\.(org|com)',
    r'(www\.)?subdl\.com',
    r'(www\.)?subsource\.net',
    r'(www\.)?addic7ed\.com',
    r'(www\.)?podnapisi\.net',
    r'wyzie',
    r'osdb\.link',
    r'api\.opensubtitles',
  ].join('|'),
  caseSensitive: false,
);

/// Removes cues that are only site advertising. A cue that mixes an ad with
/// real dialogue keeps the dialogue lines.
SubtitleDocument removeAds(SubtitleDocument doc) {
  final cues = <Cue>[];
  var changed = false;
  for (final c in doc.cues) {
    final lines = c.text.split('\n');
    final kept = lines.where((l) => !_ad.hasMatch(l)).toList();
    if (kept.length == lines.length) {
      cues.add(c);
      continue;
    }
    changed = true;
    final text = kept.join('\n').trim();
    if (text.isNotEmpty) cues.add(c.copyWith(text: text));
  }
  if (!changed) return doc;
  return SubtitleDocument(
    cues: cues,
    sourceFormat: doc.sourceFormat,
    assHeader: doc.assHeader,
    assEventFormat: doc.assEventFormat,
  );
}
