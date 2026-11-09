import 'package:subtitles/subtitles.dart';
import 'package:test/test.dart';

Duration ms(int v) => Duration(milliseconds: v);

void main() {
  group('detectFormat', () {
    test('by content, not extension', () {
      expect(
        detectFormat('WEBVTT\n\n00:01.000 --> 00:02.000\nHi'),
        SubtitleFormat.webvtt,
      );
      expect(detectFormat('\uFEFFWEBVTT - title\n'), SubtitleFormat.webvtt);
      expect(
        detectFormat('[Script Info]\nScriptType: v4.00+\n'),
        SubtitleFormat.ass,
      );
      expect(
        detectFormat('[Script Info]\nScriptType: v4.00\n[V4 Styles]\n'),
        SubtitleFormat.ssa,
      );
      expect(
        detectFormat('{1}{1}23.976\n{10}{50}Hello'),
        SubtitleFormat.microDvd,
      );
      expect(detectFormat('[10][50]Hello|World'), SubtitleFormat.mpl2);
      expect(
        detectFormat('1\n00:00:01,000 --> 00:00:02,000\nHi\n'),
        SubtitleFormat.srt,
      );
      expect(
        detectFormat('\n\n00:00:01.000 --> 00:00:02.000\nno index\n'),
        SubtitleFormat.srt,
      );
      expect(detectFormat('<SAMI><BODY>'), isNull);
      expect(detectFormat('just some text'), isNull);
    });
  });

  group('SRT', () {
    test('Windows line endings, BOM, tags', () {
      final doc = parseSubtitle(
        '\uFEFF1\r\n00:00:01,000 --> 00:00:02,500\r\n<i>Hello</i>\r\nworld\r\n\r\n'
        '2\r\n00:00:03,000 --> 00:00:04,000\r\n{\\an8}<b>Top</b>\r\n\r\n',
      );
      expect(doc.sourceFormat, SubtitleFormat.srt);
      expect(doc.cues, [
        Cue(start: ms(1000), end: ms(2500), text: '<i>Hello</i>\nworld'),
        Cue(start: ms(3000), end: ms(4000), text: '{\\an8}<b>Top</b>'),
      ]);
    });

    test('missing indices and missing blank lines', () {
      final doc = parseSubtitle(
        '00:00:01,000 --> 00:00:02,000\nFirst\n'
        '00:00:03,000 --> 00:00:04,000\nSecond\n2\n'
        '00:00:05,000 --> 00:00:06,000\nThird\n',
      );
      expect(doc.cues.map((c) => c.text), ['First', 'Second', 'Third']);
    });

    test('numeric text lines are kept, only the index goes', () {
      final doc = parseSubtitle(
        '1\n00:00:01,000 --> 00:00:02,000\n1984\n\n'
        '2\n00:00:03,000 --> 00:00:04,000\n42\n\n',
      );
      expect(doc.cues.map((c) => c.text), ['1984', '42']);
    });

    test('malformed timestamps, positions and garbage', () {
      final doc = parseSubtitle(
        'garbage before\n\n'
        '1\n0:0:1,5 --> 0:0:2.25 X1:100 X2:200\nShort fractions\n\n'
        '2\n00:00:03:500 --> 00:00:04:000\nColon millis\n\n'
        '3\n00:00:05,000 -> 00:00:06,000\nSingle arrow\n\n'
        '4\n00:00:07,000 --> 00:00:08,000\n\n\n'
        '5\n00:00:09,000 --> 00:00:10,000\nAfter empty cue\n',
      );
      expect(
        doc.cues.map((c) => (c.start.inMilliseconds, c.end.inMilliseconds)),
        [(1500, 2250), (3500, 4000), (5000, 6000), (9000, 10000)],
      );
      expect(doc.cues.first.text, 'Short fractions');
    });

    test('overlapping and unsorted cues are kept, sorted by start', () {
      final doc = parseSubtitle(
        '1\n00:00:05,000 --> 00:00:08,000\nLater\n\n'
        '2\n00:00:01,000 --> 00:00:06,000\nEarlier, overlapping\n\n'
        '3\n00:00:02,000 --> 00:00:03,000\nInside\n',
      );
      expect(doc.cues.map((c) => c.text), [
        'Earlier, overlapping',
        'Inside',
        'Later',
      ]);
    });

    test('hours beyond 99 and long texts', () {
      final doc = parseSubtitle('1\n100:00:00,000 --> 100:00:01,000\nx\n');
      expect(doc.cues.single.start, const Duration(hours: 100));
    });

    test('empty or cue-less input throws a typed error', () {
      expect(() => parseSubtitle(''), throwsA(isA<SubtitleFormatException>()));
      expect(
        () => parseSubtitle('1\n00:00:01,000 --> 00:00:02,000\n\n'),
        throwsA(isA<SubtitleFormatException>()),
      );
    });
  });

  group('WebVTT', () {
    test('header, NOTE/STYLE blocks, ids, settings, entities, tags', () {
      final doc = parseSubtitle(
        'WEBVTT - Example\nKind: captions\n\n'
        'STYLE\n::cue { color: yellow }\n\n'
        'NOTE this is a comment\nspanning lines\n\n'
        'intro\n00:01.000 --> 00:02.500 align:start position:10%\n'
        '<v Bob>Hello &amp; <c.yellow>welcome</c></v>\n<i>there</i> &lt;3\n\n'
        'NOTE between cues\n\n'
        '00:00:03.000 --> 00:00:04.000\nSecond\n',
      );
      expect(doc.sourceFormat, SubtitleFormat.webvtt);
      expect(doc.cues, [
        Cue(
          start: ms(1000),
          end: ms(2500),
          text: 'Hello & welcome\n<i>there</i> <3',
        ),
        Cue(start: ms(3000), end: ms(4000), text: 'Second'),
      ]);
    });
  });

  group('ASS/SSA', () {
    const ass =
        '[Script Info]\n'
        'Title: Test\nScriptType: v4.00+\n\n'
        '[V4+ Styles]\n'
        'Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding\n'
        'Style: Default,Arial,20,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,2,2,2,10,10,10,1\n'
        'Style: Sign,Arial,20,&H0000FFFF,&H000000FF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,2,2,8,10,10,10,1\n\n'
        '[Events]\n'
        'Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n'
        'Dialogue: 0,0:00:05.00,0:00:07.50,Default,,0,0,0,,{\\i1}Hello{\\i0}, world\\Nsecond line\n'
        'Comment: 0,0:00:06.00,0:00:07.00,Default,,0,0,0,,ignored\n'
        'Dialogue: 1,0:00:01.10,0:00:03.00,Sign,,0,0,0,,{\\an8\\b1\\c&H00FF00&}SIGN{\\b0}\n'
        'Dialogue: 0,0:00:02.00,0:00:03.00,Default,,0,0,0,,{\\p1}m 0 0 l 100 0 100 100{\\p0}\n'
        'Dialogue: 0,0:00:08.00,0:00:09.00,Default,,0,0,0,,Commas, in, text\\hhere\n';

    test('parses events, keeps styling info, strips tags to SRT style', () {
      final doc = parseSubtitle(ass);
      expect(doc.sourceFormat, SubtitleFormat.ass);
      expect(doc.cues.map((c) => c.text), [
        '{\\an8}<b>SIGN</b>',
        '<i>Hello</i>, world\nsecond line',
        'Commas, in, text here',
      ]);
      expect(doc.cues.first.start, ms(1100));
      expect(doc.assHeader, contains('Style: Sign,Arial'));
      expect(doc.assEventFormat, hasLength(10));
    });

    test('toAss keeps header, styles and fields; applies shifts', () {
      final out = parseSubtitle(ass).shift(ms(1000)).toAss();
      expect(out, startsWith('[Script Info]'));
      expect(out, contains('Style: Sign,Arial'));
      expect(
        out,
        contains(
          'Dialogue: 1,0:00:02.10,0:00:04.00,Sign,,0,0,0,,{\\an8\\b1\\c&H00FF00&}SIGN{\\b0}',
        ),
      );
      // Round trip.
      expect(parseSubtitle(out).cues.length, 3);
    });

    test('toSrt strips ASS styling', () {
      final srt = parseSubtitle(ass).toSrt();
      expect(srt, contains('<i>Hello</i>, world\r\nsecond line'));
      expect(srt, isNot(contains('{')));
      expect(
        srt,
        startsWith('1\r\n00:00:01,100 --> 00:00:03,000\r\n<b>SIGN</b>'),
      );
    });

    test('SSA v4 files', () {
      final doc = parseSubtitle(
        '[Script Info]\nScriptType: v4.00\n\n[V4 Styles]\nFormat: Name\nStyle: Default\n\n'
        '[Events]\nFormat: Marked, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n'
        'Dialogue: Marked=0,0:00:01.00,0:00:02.00,Default,,0000,0000,0000,,Old style\n',
      );
      expect(doc.sourceFormat, SubtitleFormat.ssa);
      expect(doc.cues.single.text, 'Old style');
      expect(doc.toAss(), contains('Dialogue: Marked=0,0:00:01.00,0:00:02.00'));
    });
  });

  group('MicroDVD', () {
    test('declared fps, styles, pipes', () {
      final doc = parseSubtitle(
        '{1}{1}25.000\n{25}{50}{y:i}Hello|world\n{75}{100}Plain\n',
      );
      expect(doc.sourceFormat, SubtitleFormat.microDvd);
      expect(
        doc.cues.first,
        Cue(start: ms(1000), end: ms(2000), text: '<i>Hello</i>\nworld'),
      );
      final all = parseSubtitle('{25}{50}{Y:i}Hello|world\n');
      expect(all.cues.single.text, '<i>Hello</i>\n<i>world</i>');
      expect(doc.cues.last.start, ms(3000));
    });

    test('fps from caller when not declared, default 23.976', () {
      final given = parseSubtitle('{240}{480}Hi\n', fps: 24);
      expect(given.cues.single.start, ms(10000));
      final fallback = parseSubtitle('{23976}{24000}Hi\n');
      expect(fallback.cues.single.start, ms(1000000));
    });
  });

  test('MPL2', () {
    final doc = parseSubtitle('[10][25]Hello|/italic line\n[30][]open end\n');
    expect(doc.sourceFormat, SubtitleFormat.mpl2);
    expect(
      doc.cues.first,
      Cue(start: ms(1000), end: ms(2500), text: 'Hello\n<i>italic line</i>'),
    );
    expect(doc.cues.last.end, ms(6000));
  });

  group('conversion', () {
    final doc = parseSubtitle(
      '1\n00:00:01,000 --> 00:00:02,000\n<i>A & B</i> <font color="red">red</font>\n\n'
      '2\n00:00:03,000 --> 00:00:04,000\n{\\an8}Top\n',
    );

    test('toVtt escapes and keeps only i/b/u', () {
      expect(
        doc.toVtt(),
        'WEBVTT\n\n'
        '00:00:01.000 --> 00:00:02.000\n<i>A &amp; B</i> red\n\n'
        '00:00:03.000 --> 00:00:04.000\nTop\n\n',
      );
      expect(parseSubtitle(doc.toVtt()).cues.first.text, '<i>A & B</i> red');
    });

    test('toSrt keeps SRT tags, drops ASS blocks', () {
      expect(
        doc.toSrt(),
        '1\r\n00:00:01,000 --> 00:00:02,000\r\n<i>A & B</i> <font color="red">red</font>\r\n\r\n'
        '2\r\n00:00:03,000 --> 00:00:04,000\r\nTop\r\n\r\n',
      );
    });

    test('toAss from SRT converts tags', () {
      final ass = doc.toAss();
      expect(ass, contains('[V4+ Styles]'));
      expect(
        ass,
        contains(
          r'Dialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,{\i1}A & B{\i0} red',
        ),
      );
      expect(parseSubtitle(ass).cues.first.text, '<i>A & B</i> red');
    });

    test('shift drops cues pushed before zero and clamps starts', () {
      final shifted = doc.shift(ms(-1500));
      expect(shifted.cues.map((c) => (c.start, c.end)), [
        (Duration.zero, ms(500)),
        (ms(1500), ms(2500)),
      ]);
      expect(doc.shift(ms(-5000)).cues, isEmpty);
    });

    test('scale for FPS conversion', () {
      final scaled = doc.scale(25 / 23.976);
      expect(scaled.cues.last.start.inMilliseconds, 3128);
    });

    test('plainText and mapText', () {
      expect(plainText('{\\an8}<i>Hi</i> <b>there</b>'), 'Hi there');
      final upper = doc.mapText((t) => t.toUpperCase());
      expect(upper.cues.last.text, '{\\AN8}TOP');
    });

    test('value semantics', () {
      final a = parseSubtitle('1\n00:00:01,000 --> 00:00:02,000\nX\n');
      final b = parseSubtitle('1\n00:00:01,000 --> 00:00:02,000\nX\n');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.toString(), 'SubtitleDocument(srt, 1 cues)');
      expect(a.cues.single.toString(), contains('00:00:01,000'));
    });
  });

  test('timestamps', () {
    expect(
      parseTimestamp('01:02:03,456'),
      const Duration(hours: 1, minutes: 2, seconds: 3, milliseconds: 456),
    );
    expect(
      parseTimestamp('02:03.4'),
      const Duration(minutes: 2, seconds: 3, milliseconds: 400),
    );
    expect(parseTimestamp('0:00:01.50'), ms(1500));
    expect(parseTimestamp('nope'), isNull);
    expect(
      formatSrtTime(const Duration(hours: 1, milliseconds: 5)),
      '01:00:00,005',
    );
    expect(
      formatAssTime(const Duration(minutes: 1, milliseconds: 1234)),
      '0:01:01.23',
    );
  });

  group('fixRtl', () {
    test('wraps RTL lines with embedding marks, leaves LTR alone', () {
      expect(fixRtl('مرحبا.\nHello.'), '\u202Bمرحبا.\u202C\nHello.');
    });
    test('keeps leading tags outside the marks and is idempotent', () {
      final once = fixRtl('<i>شالوم!</i>');
      expect(once, '<i>\u202Bشالوم!</i>\u202C');
      final hebrew = fixRtl('{\\an8}שלום!');
      expect(hebrew, '{\\an8}\u202Bשלום!\u202C');
      expect(fixRtl(hebrew), hebrew);
    });
    test('RLM mode and moving pre-reversed punctuation', () {
      expect(fixRtl('سلام', marks: RtlMarks.rlm), '\u200Fسلام\u200F');
      expect(
        fixRtl('.مرحبا بك', moveLeadingPunctuation: true),
        '\u202Bمرحبا بك.\u202C',
      );
      expect(
        fixRtl('- مرحبا', moveLeadingPunctuation: true),
        '\u202B- مرحبا\u202C',
      );
    });
    test('applies to a whole document via mapText (including ASS text)', () {
      final doc = parseSubtitle(
        '[Script Info]\nScriptType: v4.00+\n\n[Events]\n'
        'Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n'
        'Dialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,مرحبا.\\Nسلام!\n',
      ).mapText(fixRtl);
      expect(doc.cues.single.text, '\u202Bمرحبا.\u202C\n\u202Bسلام!\u202C');
      expect(doc.toAss(), contains('\u202Bمرحبا.\u202C\\N\u202Bسلام!\u202C'));
    });
  });
}
