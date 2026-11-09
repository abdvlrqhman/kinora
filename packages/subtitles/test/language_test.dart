import 'package:subtitles/subtitles.dart';
import 'package:test/test.dart';

void main() {
  group('Language.parse', () {
    final cases = {
      // ISO 639-1, 639-2/B, 639-2/T, names
      'ar': 'ar', 'ara': 'ar', 'Arabic': 'ar', 'ARABIC': 'ar', 'ar-SA': 'ar',
      'en': 'en', 'eng': 'en', 'English': 'en', 'en-US': 'en',
      'English (US)': 'en', 'fre': 'fr', 'fra': 'fr', 'ger': 'de', 'deu': 'de',
      'gre': 'el', 'ell': 'el', 'Greek': 'el', 'cze': 'cs', 'ces': 'cs',
      'dut': 'nl', 'nld': 'nl', 'rum': 'ro', 'ron': 'ro', 'mac': 'mk',
      'per': 'fa', 'fas': 'fa', 'fa': 'fa', 'farsi': 'fa',
      'farsi_persian': 'fa', 'Persian': 'fa', 'heb': 'he', 'iw': 'he',
      // Portuguese
      'pob': 'pt-BR', 'pt-br': 'pt-BR', 'pt_BR': 'pt-BR', 'BR_PT': 'pt-BR',
      'brazilian_portuguese': 'pt-BR', 'Portuguese (Brazil)': 'pt-BR',
      'pt': 'pt', 'por': 'pt', 'pt-PT': 'pt', 'pm': 'pt',
      // Chinese
      'zh': 'zh-Hans', 'chi': 'zh-Hans', 'zho': 'zh-Hans', 'zh-cn': 'zh-Hans',
      'chs': 'zh-Hans', 'chinese_bg_code': 'zh-Hans', 'ZH': 'zh-Hans',
      'zh-tw': 'zh-Hant', 'zht': 'zh-Hant', 'zh-HK': 'zh-Hant',
      'big_5_code': 'zh-Hant', 'ZH_BG': 'zh-Hant', 'zh-TW': 'zh-Hant',
      'ze': 'ze', 'chinese_bilingual': 'ze', 'zh-ca': 'yue',
      'chinese_cantonese': 'yue',
      // Serbian / Montenegrin
      'sr': 'sr', 'srp': 'sr', 'scc': 'sr', 'sr-latn': 'sr-Latn',
      'sr_cyrl': 'sr-Cyrl', 'SR_CYRL': 'sr-Cyrl', 'me': 'cnr',
      'montenegrin': 'cnr',
      // Spanish
      'es': 'es', 'spa': 'es', 'sp': 'es', 'spanish_spain': 'es',
      'es-419': 'es-419', 'es-MX': 'es-419', 'ea': 'es-419', 'spl': 'es-419',
      'Latino': 'es-419', 'spanish_latin_america': 'es-419',
      // Misc quirks
      'nb': 'no', 'nob': 'no', 'nor': 'no', 'Norwegian': 'no', 'nn': 'nn',
      'in': 'id', 'jw': 'jv', 'pr': 'prs', 'dari': 'prs', 'at': 'ast',
      'ma': 'mni', 'sy': 'syr', 'tp': 'tok', 'espranto': 'eo',
      'gaelician': 'gl', 'FR_CA': 'fr-CA', 'french_canada': 'fr-CA',
      'arb': 'ar', 'cmn': 'zh-Hans', 'zsm': 'ms', 'tl': 'tl', 'fil': 'fil',
      'ckb': 'ckb', 'sorani': 'ckb', 'yue': 'yue', 'ga': 'ga', 'gaa': 'gaa',
    };
    cases.forEach((input, code) {
      test('$input -> $code', () => expect(Language.parse(input)?.code, code));
    });

    test('unknown and empty input', () {
      expect(Language.parse(null), isNull);
      expect(Language.parse(''), isNull);
      expect(Language.parse('  '), isNull);
      expect(Language.parse('xx'), isNull);
      expect(Language.parse('klingonese'), isNull);
    });
  });

  test('every listed language parses back to itself by code and name', () {
    expect(Language.all.length, greaterThan(400));
    for (final l in Language.all) {
      expect(Language.parse(l.code), l, reason: l.code);
      // Codes win over names: "Ga" is Irish's code, not the Ga language.
      final clash = Language.all.any(
        (o) => o != l && o.code == l.englishName.toLowerCase(),
      );
      if (!clash) {
        expect(Language.parse(l.englishName), l, reason: l.englishName);
      }
    }
  });

  test('list is sorted, unique, with native names', () {
    final codes = Language.all.map((l) => l.code).toList();
    expect(codes.toSet().length, codes.length);
    final names = Language.all.map((l) => l.englishName.toLowerCase()).toList();
    expect(names, [...names]..sort());
    expect(Language.of('ar').nativeName, 'العربية');
    expect(Language.of('ja').nativeName, '日本語');
    expect(Language.of('zh-Hant').englishName, 'Chinese (Traditional)');
  });

  test('value semantics and helpers', () {
    expect(Language.of('AR'), Language.parse('arabic'));
    expect(Language.of('ar').hashCode, Language.parse('ara').hashCode);
    expect(Language.of('pt-BR').baseCode, 'pt');
    expect(Language.of('ar').isRightToLeft, isTrue);
    expect(Language.of('fa').isRightToLeft, isTrue);
    expect(Language.of('he').isRightToLeft, isTrue);
    expect(Language.of('ur').isRightToLeft, isTrue);
    expect(Language.of('en').isRightToLeft, isFalse);
    expect(Language.of('ar').toString(), 'Language(ar)');
    expect(() => Language.of('nope'), throwsArgumentError);
  });

  test('provider code mappings', () {
    expect(toOpenSubtitlesCode(Language.of('pt-BR')), 'pt-br');
    expect(toOpenSubtitlesCode(Language.of('pt')), 'pt-pt');
    expect(toOpenSubtitlesCode(Language.of('zh-Hant')), 'zh-tw');
    expect(toOpenSubtitlesCode(Language.of('es-419')), 'ea');
    expect(toOpenSubtitlesCode(Language.of('cnr')), 'me');
    expect(toOpenSubtitlesCode(Language.of('ar')), 'ar');
    expect(toOpenSubtitlesCode(Language.of('gaa')), isNull);
    expect(toSubdlCode(Language.of('pt-BR')), 'BR_PT');
    expect(toSubdlCode(Language.of('zh-Hant')), 'ZH_BG');
    expect(toSubdlCode(Language.of('ar')), 'AR');
    expect(toSubdlCode(Language.of('gaa')), isNull);
    expect(subSourceNames(Language.of('fa')), ['farsi_persian']);
    expect(
      subSourceNames(Language.of('zh-Hans')),
      containsAll(['chinese', 'chinese_simplified', 'chinese_bg_code']),
    );
    expect(subSourceNames(Language.of('es-419')), ['spanish_latin_america']);
    expect(toPodnapisiCode(Language.of('sr-Latn')), 'sr-latn');
    // Every SubSource name maps to a language.
    for (final n in subSourceLanguages) {
      expect(Language.parse(n), isNotNull, reason: n);
    }
  });
}
