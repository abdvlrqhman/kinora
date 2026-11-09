import 'package:subtitles/subtitles.dart';
import 'package:test/test.dart';

void main() {
  test('drops ad-only cues and ad lines, keeps dialogue and credits', () {
    final doc = parseSubtitle('''
1
00:00:01,000 --> 00:00:03,000
Advertise your product or brand here
contact www.OpenSubtitles.org today

2
00:00:04,000 --> 00:00:06,000
Where were you last night?

3
00:00:07,000 --> 00:00:09,000
I was home.
Support us and become VIP member

4
00:00:10,000 --> 00:00:12,000
Translated by Sara
''');
    final clean = removeAds(doc);
    expect(clean.cues.map((c) => c.text), [
      'Where were you last night?',
      'I was home.',
      'Translated by Sara',
    ]);
  });

  test('untouched documents are returned as is', () {
    final doc = parseSubtitle('1\n00:00:01,000 --> 00:00:02,000\nHello\n');
    expect(identical(removeAds(doc), doc), isTrue);
  });
}
