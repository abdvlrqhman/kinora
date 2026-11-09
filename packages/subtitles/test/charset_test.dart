import 'dart:convert';
import 'dart:typed_data';

import 'package:subtitles/subtitles.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  final expected = (fixtureJson('charset/expected.json')! as Map)
      .cast<String, Map<String, Object?>>();

  String stripBom(String s) => s.replaceFirst('\uFEFF', '');

  group('decodes every fixture with its language hint', () {
    for (final MapEntry(key: name, value: e) in expected.entries) {
      test(name, () {
        final hint = Language.parse(e['language'] as String?);
        final decoded = decodeSubtitleBytes(
          fixtureBytes('charset/$name'),
          language: hint,
        );
        expect(decoded.text, stripBom(e['text']! as String));
      });
    }
  });

  group('detects the code page without a hint', () {
    const expectations = {
      'arabic_1256.srt': 'windows-1256',
      'persian_1256.srt': 'windows-1256',
      'russian_1251.srt': 'windows-1251',
      'ukrainian_1251.srt': 'windows-1251',
      'greek_1253.srt': 'windows-1253',
      'hebrew_1255.srt': 'windows-1255',
      'turkish_1254.srt': 'windows-1254',
      'polish_1250.srt': 'windows-1250',
      'czech_1250.srt': 'windows-1250',
      'french_1252.srt': 'windows-1252',
      'lithuanian_1257.srt': 'windows-1257',
      'thai_874.srt': 'windows-874',
      'chinese_gbk.srt': 'gbk',
      'chinese_big5.srt': 'big5',
      'japanese_sjis.srt': 'shift_jis',
      'korean_cp949.srt': 'cp949',
      'utf8_bom.srt': 'utf-8',
      'utf8_plain.srt': 'utf-8',
      'utf16le_bom.srt': 'utf-16le',
      'utf16be_bom.srt': 'utf-16be',
      'utf16le_nobom.srt': 'utf-16le',
    };
    expectations.forEach((name, encoding) {
      test('$name -> $encoding', () {
        final decoded = decodeSubtitleBytes(fixtureBytes('charset/$name'));
        expect(decoded.encoding, encoding);
        expect(decoded.text, stripBom(expected[name]!['text']! as String));
      });
    });
  });

  test('Arabic windows-1256 subtitle decodes to readable Arabic SRT', () {
    final decoded = decodeSubtitleBytes(
      fixtureBytes('charset/arabic_1256.srt'),
      language: Language.of('ar'),
    );
    expect(decoded.encoding, 'windows-1256');
    final doc = parseSubtitle(decoded.text);
    expect(doc.cues, hasLength(4));
    expect(doc.cues.first.text, 'مرحباً بكم في البرنامج.');
    expect(doc.cues[2].text, '- لماذا تأخرت؟\n- كان الطريق مزدحماً جداً.');
  });

  test('a wrong hint is overridden when the text is implausible', () {
    // Russian bytes, but the provider said Arabic.
    final decoded = decodeSubtitleBytes(
      fixtureBytes('charset/russian_1251.srt'),
      language: Language.of('ar'),
    );
    expect(decoded.encoding, 'windows-1251');
    expect(decoded.text, contains('Привет'));
  });

  test('UTF-8 always wins when valid, whatever the hint', () {
    final bytes = utf8.encode('1\n00:00:01,000 --> 00:00:02,000\nمرحبا\n');
    final decoded = decodeSubtitleBytes(bytes, language: Language.of('ru'));
    expect(decoded.encoding, 'utf-8');
    expect(decoded.text, contains('مرحبا'));
  });

  test('BOM is stripped and empty input is fine', () {
    expect(decodeSubtitleBytes(const [0xEF, 0xBB, 0xBF, 0x41]).text, 'A');
    expect(decodeSubtitleBytes(const []).text, '');
    expect(decodeSubtitleBytes(const [0xFF, 0xFE, 0x41, 0x00]).text, 'A');
    expect(decodeSubtitleBytes(const [0xFE, 0xFF, 0x00, 0x41]).text, 'A');
  });

  test('truncated multi-byte sequences become U+FFFD instead of throwing', () {
    final sjis = decodeWith('shift_jis', Uint8List.fromList([0x41, 0x82]));
    expect(sjis, 'A�');
    final kr = decodeWith('cp949', Uint8List.fromList([0xB0]));
    expect(kr, '�');
    expect(decodeWith('windows-1252', Uint8List.fromList([0x81])), '�');
  });

  test('code pages per language', () {
    expect(codePagesFor(Language.of('ar')), ['windows-1256']);
    expect(codePagesFor(Language.of('fa')), ['windows-1256']);
    expect(codePagesFor(Language.of('he')), ['windows-1255']);
    expect(codePagesFor(Language.of('bg')), ['windows-1251']);
    expect(codePagesFor(Language.of('sr-Cyrl')), ['windows-1251']);
    expect(codePagesFor(Language.of('el')), ['windows-1253']);
    expect(codePagesFor(Language.of('tr')), ['windows-1254']);
    expect(codePagesFor(Language.of('hu')), ['windows-1250']);
    expect(codePagesFor(Language.of('lv')), ['windows-1257']);
    expect(codePagesFor(Language.of('vi')), ['windows-1258']);
    expect(codePagesFor(Language.of('th')), ['windows-874']);
    expect(codePagesFor(Language.of('zh-Hans')), ['gbk', 'big5']);
    expect(codePagesFor(Language.of('zh-Hant')), ['big5', 'gbk']);
    expect(codePagesFor(Language.of('ja')), ['shift_jis']);
    expect(codePagesFor(Language.of('ko')), ['cp949']);
    expect(codePagesFor(Language.of('de')), ['windows-1252']);
    expect(codePagesFor(null), ['windows-1252']);
  });

  test('scoreDecoding prefers the right script', () {
    final bytes = fixtureBytes('charset/arabic_1256.srt');
    final right = scoreDecoding(
      decodeWith('windows-1256', bytes),
      'windows-1256',
    );
    final wrong = scoreDecoding(
      decodeWith('windows-1252', bytes),
      'windows-1252',
    );
    expect(right, greaterThan(0.8));
    expect(wrong, lessThan(right));
  });
}
