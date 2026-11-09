import 'dart:convert';
import 'dart:typed_data';

import 'package:enough_convert/enough_convert.dart' show Big5Codec, GbkCodec;

import 'charset_tables.dart';
import 'language.dart';

/// Text decoded from subtitle bytes and the encoding that was used.
final class DecodedText {
  const DecodedText(this.text, this.encoding);

  /// The text (no BOM).
  final String text;

  /// `utf-8`, `utf-16le`, `utf-16be`, `windows-1256`, `gbk`, `big5`,
  /// `shift_jis` or `cp949` ...
  final String encoding;

  @override
  bool operator ==(Object other) =>
      other is DecodedText && other.text == text && other.encoding == encoding;

  @override
  int get hashCode => Object.hash(text, encoding);

  @override
  String toString() => 'DecodedText($encoding, ${text.length} chars)';
}

/// Every legacy encoding [decodeSubtitleBytes] can pick.
const legacyEncodings = [
  'windows-1252',
  'windows-1250',
  'windows-1251',
  'windows-1253',
  'windows-1254',
  'windows-1255',
  'windows-1256',
  'windows-1257',
  'windows-1258',
  'windows-874',
  'gbk',
  'big5',
  'shift_jis',
  'cp949',
];

/// Decodes subtitle bytes to text.
///
/// Order: BOM (UTF-8/16LE/16BE), BOM-less UTF-16, strict UTF-8, then the
/// legacy code page for [language] (Arabic/Persian -> windows-1256, Hebrew ->
/// 1255, Cyrillic -> 1251, Greek -> 1253, Turkish -> 1254, Central European
/// -> 1250, Baltic -> 1257, Vietnamese -> 1258, Thai -> 874, Chinese ->
/// GBK/Big5, Japanese -> Shift_JIS, Korean -> CP949, else 1252). When the hint
/// is missing or the hinted page decodes to implausible text, every legacy
/// page is scored by how many decoded letters belong to its expected script
/// and the best one wins.
DecodedText decodeSubtitleBytes(List<int> bytes, {Language? language}) {
  final b = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  if (b.length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) {
    return DecodedText(
      utf8.decode(b.sublist(3), allowMalformed: true),
      'utf-8',
    );
  }
  if (b.length >= 2 && b[0] == 0xFF && b[1] == 0xFE) {
    return DecodedText(_utf16(b, 2, littleEndian: true), 'utf-16le');
  }
  if (b.length >= 2 && b[0] == 0xFE && b[1] == 0xFF) {
    return DecodedText(_utf16(b, 2, littleEndian: false), 'utf-16be');
  }
  final bomless = _sniffUtf16(b);
  if (bomless != null) {
    return DecodedText(
      _stripBom(_utf16(b, 0, littleEndian: bomless)),
      bomless ? 'utf-16le' : 'utf-16be',
    );
  }
  try {
    return DecodedText(_stripBom(utf8.decode(b)), 'utf-8');
  } on FormatException {
    // not UTF-8: fall through to legacy code pages
  }
  final hinted = codePagesFor(language);
  final first = decodeWith(hinted.first, b);
  if (language != null && scoreDecoding(first, hinted.first) >= 0.5) {
    return DecodedText(first, hinted.first);
  }
  var best = DecodedText(first, hinted.first);
  var bestScore = scoreDecoding(first, hinted.first);
  for (final enc in [...hinted.skip(1), ...legacyEncodings]) {
    if (enc == hinted.first) continue;
    final text = decodeWith(enc, b);
    final score = scoreDecoding(text, enc);
    if (score > bestScore + 0.01) {
      best = DecodedText(text, enc);
      bestScore = score;
    }
  }
  return best;
}

/// Legacy code pages to try for [language], most likely first.
List<String> codePagesFor(Language? language) {
  final code = language?.code;
  if (code == null) return const ['windows-1252'];
  if (code == 'sr-Cyrl') return const ['windows-1251'];
  if (code == 'zh-Hant' || code == 'yue') return const ['big5', 'gbk'];
  return switch (language!.baseCode) {
    'ar' ||
    'fa' ||
    'ur' ||
    'prs' ||
    'ckb' ||
    'ps' ||
    'ug' ||
    'sd' => const ['windows-1256'],
    'he' || 'yi' => const ['windows-1255'],
    'ru' ||
    'uk' ||
    'bg' ||
    'be' ||
    'mk' ||
    'kk' ||
    'ky' ||
    'tg' ||
    'mn' => const ['windows-1251'],
    'sr' => const ['windows-1250', 'windows-1251'],
    'el' => const ['windows-1253'],
    'tr' || 'az' => const ['windows-1254'],
    'pl' ||
    'cs' ||
    'sk' ||
    'hu' ||
    'ro' ||
    'hr' ||
    'sl' ||
    'bs' ||
    'sq' ||
    'cnr' => const ['windows-1250'],
    'lt' || 'lv' || 'et' => const ['windows-1257'],
    'vi' => const ['windows-1258'],
    'th' => const ['windows-874'],
    'zh' => const ['gbk', 'big5'],
    'ja' => const ['shift_jis'],
    'ko' => const ['cp949'],
    _ => const ['windows-1252'],
  };
}

/// Decodes [bytes] with a legacy [encoding] from [legacyEncodings].
/// Undecodable bytes become U+FFFD.
String decodeWith(String encoding, Uint8List bytes) =>
    _stripBom(switch (encoding) {
      // shortcut: GBK covers GB18030's 2-byte range; its rare 4-byte sequences
      // become U+FFFD. Add a GB18030 table if such files show up.
      'gbk' => const GbkCodec(allowInvalid: true).decode(bytes),
      'big5' => const Big5Codec(allowInvalid: true).decode(bytes),
      'shift_jis' => _cp932(bytes),
      'cp949' => _cp949(bytes),
      _ => _singleByte(singleByteTables[encoding]!, bytes),
    });

String _stripBom(String s) => s.startsWith('\uFEFF') ? s.substring(1) : s;

String _singleByte(String table, Uint8List bytes) {
  final units = Uint16List(bytes.length);
  for (var i = 0; i < bytes.length; i++) {
    final c = bytes[i];
    units[i] = c < 0x80 ? c : table.codeUnitAt(c - 0x80);
  }
  return String.fromCharCodes(units);
}

String _utf16(Uint8List b, int start, {required bool littleEndian}) {
  final n = (b.length - start) ~/ 2;
  final units = Uint16List(n);
  for (var i = 0; i < n; i++) {
    final lo = b[start + 2 * i], hi = b[start + 2 * i + 1];
    units[i] = littleEndian ? lo | hi << 8 : hi | lo << 8;
  }
  return String.fromCharCodes(units);
}

/// true = UTF-16LE, false = UTF-16BE, null = not UTF-16.
bool? _sniffUtf16(Uint8List b) {
  final n = b.length < 2000 ? b.length & ~1 : 2000;
  if (n < 8) return null;
  var evenZero = 0, oddZero = 0;
  for (var i = 0; i < n; i += 2) {
    if (b[i] == 0) evenZero++;
    if (b[i + 1] == 0) oddZero++;
  }
  final pairs = n / 2;
  if (oddZero > pairs * 0.3 && evenZero < pairs * 0.05) return true;
  if (evenZero > pairs * 0.3 && oddZero < pairs * 0.05) return false;
  return null;
}

String _cp932(Uint8List b) {
  final out = StringBuffer();
  for (var i = 0; i < b.length; i++) {
    final c = b[i];
    if (c < 0x80) {
      out.writeCharCode(c);
    } else if (c >= 0xA1 && c <= 0xDF) {
      out.writeCharCode(0xFF61 + c - 0xA1); // half-width katakana
    } else if (((c >= 0x81 && c <= 0x9F) || (c >= 0xE0 && c <= 0xFC)) &&
        i + 1 < b.length &&
        b[i + 1] >= 0x40 &&
        b[i + 1] <= 0xFC) {
      final row = c < 0xA0 ? c - 0x81 : c - 0xE0 + 31;
      out.writeCharCode(cp932Rows[row].codeUnitAt(b[++i] - 0x40));
    } else {
      out.writeCharCode(0xFFFD);
    }
  }
  return out.toString();
}

String _cp949(Uint8List b) {
  final out = StringBuffer();
  for (var i = 0; i < b.length; i++) {
    final c = b[i];
    if (c < 0x80) {
      out.writeCharCode(c);
    } else if (c >= 0x81 &&
        c <= 0xFE &&
        i + 1 < b.length &&
        b[i + 1] >= 0x41 &&
        b[i + 1] <= 0xFE) {
      out.writeCharCode(cp949Rows[c - 0x81].codeUnitAt(b[++i] - 0x41));
    } else {
      out.writeCharCode(0xFFFD);
    }
  }
  return out.toString();
}

// ---------------------------------------------------------------------------
// Plausibility scoring.

enum _Script {
  latin,
  cyrillic,
  greek,
  hebrew,
  arabic,
  thai,
  han,
  japanese,
  hangul,
}

_Script _scriptOf(String encoding) => switch (encoding) {
  'windows-1251' => _Script.cyrillic,
  'windows-1253' => _Script.greek,
  'windows-1255' => _Script.hebrew,
  'windows-1256' => _Script.arabic,
  'windows-874' => _Script.thai,
  'gbk' || 'big5' => _Script.han,
  'shift_jis' => _Script.japanese,
  'cp949' => _Script.hangul,
  _ => _Script.latin,
};

/// Frequent non-ASCII letters per encoding's typical languages.
const Map<String, String> _common = {
  'windows-1252': 'éèàçêôâîûùëïüöäßñáíóúãõåøæœ',
  'windows-1250': 'ąęłśżźćńčřšžěůőűășțşţáéíóúý',
  'windows-1254': 'çğıöşüİĞŞ',
  'windows-1257': 'ąčęėįšųūžāēīņļķģõäöü',
  'windows-1258': 'ăâđêôơư\u0300\u0301\u0303\u0309\u0323',
  // Top letters only: they separate real text from other scripts' bytes.
  'windows-1251': 'оеаинтсрвлкмі',
  'windows-1253': 'αοειτνσυρπκμληςάέίό',
  'windows-1255': 'יוהאלמתרבשנ',
  'windows-1256': 'اليمنوهتربعد',
  'windows-874': 'านรอกเงมยลวดทสต่้ิีั',
  'gbk': '的是不了在人有我他这个们中来上大为和国地到以说时要就出会可也你对生能而子那得于着下自之年过发后作里用道行所然家种事成方多经么去法学如都同现当没动面起看定天分还进好小部其些主样理心她本前开但因只从想实',
  'big5': '的是不了在人有我他這個們中來上大為和國地到以說時要就出會可也你對生能而子那得於著下自之年過發後作裡用道行所然家種事成方多經麼去法學如都同現當沒動面起看定天分還進好小部其些主樣理心她本前開但因只從想實',
  'shift_jis': 'のにはをたがでてとしれさいるかなすもこあっうよ一人日私彼',
  'cp949': '이다는의에가을고하지서도한로기나리게으있사아요그거어해',
};

final _letter = RegExp(r'\p{L}', unicode: true);
final _upper = RegExp(r'\p{Lu}', unicode: true);
final _lower = RegExp(r'\p{Ll}', unicode: true);
final _mark = RegExp(r'\p{M}', unicode: true);

bool _inScript(int r, _Script s) => switch (s) {
  _Script.latin =>
    (r >= 0xC0 && r <= 0x24F && r != 0xD7 && r != 0xF7) ||
        (r >= 0x1E00 && r <= 0x1EFF) ||
        (r >= 0x300 && r <= 0x36F),
  _Script.cyrillic => r >= 0x400 && r <= 0x4FF,
  _Script.greek => r >= 0x370 && r <= 0x3FF,
  _Script.hebrew => r >= 0x5B0 && r <= 0x5F4,
  _Script.arabic =>
    (r >= 0x600 && r <= 0x6FF) ||
        (r >= 0xFB50 && r <= 0xFDFF) ||
        (r >= 0xFE70 && r <= 0xFEFF),
  _Script.thai => r >= 0xE00 && r <= 0xE7F,
  _Script.han => _isHan(r) || _isCjkPunct(r),
  _Script.japanese =>
    _isHan(r) || _isCjkPunct(r) || (r >= 0x3040 && r <= 0x30FF),
  _Script.hangul =>
    (r >= 0xAC00 && r <= 0xD7A3) ||
        (r >= 0x3130 && r <= 0x318F) ||
        _isHan(r) ||
        _isCjkPunct(r),
};

bool _isHan(int r) => r >= 0x4E00 && r <= 0x9FFF;
bool _isCjkPunct(int r) =>
    (r >= 0x3000 && r <= 0x303F) || (r >= 0xFF00 && r <= 0xFFEF);

/// How plausible [text] is as a decoding with [encoding]: about 1.0 when every
/// non-ASCII character is a common letter of the expected script, lower or
/// negative for replacement chars, C1 controls, letters of other scripts,
/// mixed scripts or case inside a word, symbols glued inside words, and (for
/// Latin pages) long words with no ASCII letter at all, which is what other
/// scripts look like when decoded as Latin ("ùìåí").
double scoreDecoding(String text, String encoding) {
  final script = _scriptOf(encoding);
  final common = (_common[encoding] ?? '').runes.toSet();
  var total = 0;
  var good = 0.0, bad = 0.0;
  // Per-word state.
  var letters = 0, asciiLetters = 0;
  var prevLetter = false, prevLower = false, prevLatin = false;
  var pendingSymbol = false;

  void endWord() {
    if (script == _Script.latin && letters >= 3 && asciiLetters == 0) {
      bad += 2.0 * letters;
    }
    letters = 0;
    asciiLetters = 0;
    prevLetter = false;
  }

  for (final r in text.runes) {
    final ch = String.fromCharCode(r);
    final ascii = r < 0x80;
    final asciiLetter = ascii && (r | 0x20) >= 0x61 && (r | 0x20) <= 0x7A;
    if (!ascii) total++;
    if (!ascii && (r == 0xFFFD || r <= 0x9F)) {
      bad += 4;
      endWord();
      pendingSymbol = false;
      continue;
    }
    final isLetter =
        asciiLetter || (!ascii && (_letter.hasMatch(ch) || _mark.hasMatch(ch)));
    if (!isLetter) {
      if (!ascii && _isCjkPunct(r) && script.index >= _Script.han.index) {
        good += 1;
      }
      // A symbol glued between letters ("pi³kny") is a decode error.
      pendingSymbol =
          prevLetter && !ascii && r != 0xA0 && r != 0x2019 && r != 0x2018;
      endWord();
      continue;
    }
    if (pendingSymbol) bad += 1;
    pendingSymbol = false;
    final latin = asciiLetter || _inScript(r, _Script.latin);
    // Mixed scripts inside one word ("Kaip рiandien").
    if (prevLetter && prevLatin != latin) bad += 1;
    if (!ascii) {
      if (_inScript(r, script)) {
        good += common.contains(r) ? 2 : 1;
      } else {
        bad += 1;
      }
      // Mixed case inside a word ("ÇáÚÑÈíÉ") is typical of a wrong page.
      if (prevLetter && prevLower && _upper.hasMatch(ch)) bad += 1;
    }
    prevLower = ascii ? r >= 0x61 : _lower.hasMatch(ch);
    prevLatin = latin;
    prevLetter = true;
    letters++;
    if (asciiLetter) asciiLetters++;
  }
  endWord();
  if (total == 0) return 1;
  return (good - bad) / (2 * total);
}
