import 'language_data.dart';

/// A subtitle language with a canonical, BCP-47-like [code].
///
/// Canonical codes are ISO 639-1 where one exists (`ar`, `en`), otherwise
/// ISO 639-2/T or 639-3 (`fil`, `yue`), plus the variants subtitle providers
/// keep apart: `pt-BR`, `zh-Hans`, `zh-Hant`, `sr-Latn`, `sr-Cyrl`, `es-419`,
/// `fr-CA` and `ze` (Chinese/English bilingual, OpenSubtitles' code).
///
/// Two languages are equal when their codes are equal.
final class Language implements Comparable<Language> {
  const Language._(this.code, this.englishName, this.nativeName);

  /// Canonical code, e.g. `ar`, `pt-BR`, `zh-Hant`.
  final String code;

  /// English display name, e.g. `Arabic`.
  final String englishName;

  /// Name in the language itself, e.g. `العربية`.
  final String nativeName;

  /// Every known language, sorted by [englishName] (for a settings picker).
  static final List<Language> all = List.unmodifiable([
    for (final (code, en, native) in languageTable)
      Language._(code, en, native),
  ]);

  static final Map<String, Language> _byCode = {
    for (final l in all) l.code.toLowerCase(): l,
  };

  /// Looks up a language by canonical [code] (case-insensitive) or throws.
  static Language of(String code) =>
      parse(code) ?? (throw ArgumentError.value(code, 'code', 'unknown'));

  /// Tolerant parse of a code or name from any provider.
  ///
  /// Accepts ISO 639-1, 639-2/B, 639-2/T, common 639-3 codes, English names,
  /// and provider quirks (`pob`, `pt_br`, `BR_PT`, `zht`, `chi`, `ze`, `me`,
  /// `spl`, `ea`, `farsi_persian`, `big_5_code`, `ar-SA`, `English (US)` ...).
  /// Unknown region/script subtags fall back to the base language. Returns
  /// null when nothing matches.
  static Language? parse(String? input) {
    if (input == null) return null;
    final s = input.trim().toLowerCase();
    if (s.isEmpty) return null;
    final dashed = s.replaceAll('_', '-');
    final spaced = s.replaceAll('_', ' ');
    for (final key in [s, dashed, spaced]) {
      final hit = _lookup(key);
      if (hit != null) return hit;
    }
    // Strip region/script subtags: "ar-sa" -> "ar", "en-us" -> "en".
    final base = RegExp(r'^([a-z]{2,3})[-_ ]').firstMatch(s);
    if (base != null) {
      final hit = _lookup(base.group(1)!);
      if (hit != null) return hit;
    }
    // Names with qualifiers: "English (US)", "arabic.srt" style leftovers.
    final word = RegExp(r'^[a-z]+').firstMatch(spaced)?.group(0);
    if (word != null && word.length > 3) return _lookup(word);
    return null;
  }

  static Language? _lookup(String key) {
    final direct = _byCode[key];
    if (direct != null) return direct;
    final alias = languageAliases[key];
    return alias == null ? null : _byCode[alias.toLowerCase()];
  }

  /// The ISO 639-1 / base subtag (`pt` for `pt-BR`, `zh` for `zh-Hant`).
  String get baseCode => code == 'ze' ? 'zh' : code.split('-').first;

  /// Whether text in this language is written right-to-left.
  bool get isRightToLeft => _rtl.contains(baseCode);

  static const _rtl = {
    'ar',
    'fa',
    'he',
    'ur',
    'yi',
    'ps',
    'prs',
    'ckb',
    'sd',
    'ug',
    'dv',
    'syr',
  };

  @override
  int compareTo(Language other) => englishName.compareTo(other.englishName);

  @override
  bool operator ==(Object other) => other is Language && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => 'Language($code)';
}
