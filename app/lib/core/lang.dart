/// Language-code helpers for matching player tracks (often ISO 639-2:
/// "ara", "eng", "pob") against the user's preferences (ISO 639-1: "ar").
library;

const _toIso1 = <String, String>{
  'ara': 'ar',
  'eng': 'en',
  'spa': 'es',
  'fre': 'fr',
  'fra': 'fr',
  'ger': 'de',
  'deu': 'de',
  'ita': 'it',
  'por': 'pt',
  'pob': 'pt-BR',
  'pt-br': 'pt-BR',
  'rus': 'ru',
  'jpn': 'ja',
  'kor': 'ko',
  'chi': 'zh',
  'zho': 'zh',
  'tur': 'tr',
  'dut': 'nl',
  'nld': 'nl',
  'pol': 'pl',
  'swe': 'sv',
  'nor': 'no',
  'nob': 'no',
  'dan': 'da',
  'fin': 'fi',
  'gre': 'el',
  'ell': 'el',
  'heb': 'he',
  'hin': 'hi',
  'ind': 'id',
  'may': 'ms',
  'msa': 'ms',
  'tha': 'th',
  'vie': 'vi',
  'ukr': 'uk',
  'cze': 'cs',
  'ces': 'cs',
  'slo': 'sk',
  'slk': 'sk',
  'hun': 'hu',
  'rum': 'ro',
  'ron': 'ro',
  'bul': 'bg',
  'hrv': 'hr',
  'srp': 'sr',
  'slv': 'sl',
  'per': 'fa',
  'fas': 'fa',
  'urd': 'ur',
  'ben': 'bn',
  'tam': 'ta',
  'tel': 'te',
  'mal': 'ml',
  'kan': 'kn',
  'mar': 'mr',
  'cat': 'ca',
  'baq': 'eu',
  'eus': 'eu',
  'glg': 'gl',
  'est': 'et',
  'lav': 'lv',
  'lit': 'lt',
  'ice': 'is',
  'isl': 'is',
  'alb': 'sq',
  'sqi': 'sq',
  'mac': 'mk',
  'mkd': 'mk',
  'bos': 'bs',
  'geo': 'ka',
  'kat': 'ka',
  'arm': 'hy',
  'hye': 'hy',
  'aze': 'az',
  'kaz': 'kk',
  'uzb': 'uz',
  'fil': 'fil',
  'tgl': 'tl',
  'swa': 'sw',
  'amh': 'am',
  'kur': 'ku',
  'pus': 'ps',
};

const _names = <String, String>{
  'ar': 'Arabic',
  'en': 'English',
  'es': 'Spanish',
  'fr': 'French',
  'de': 'German',
  'it': 'Italian',
  'pt': 'Portuguese',
  'pt-BR': 'Portuguese (Brazil)',
  'ru': 'Russian',
  'ja': 'Japanese',
  'ko': 'Korean',
  'zh': 'Chinese',
  'tr': 'Turkish',
  'nl': 'Dutch',
  'pl': 'Polish',
  'sv': 'Swedish',
  'no': 'Norwegian',
  'da': 'Danish',
  'fi': 'Finnish',
  'el': 'Greek',
  'he': 'Hebrew',
  'hi': 'Hindi',
  'id': 'Indonesian',
  'ms': 'Malay',
  'th': 'Thai',
  'vi': 'Vietnamese',
  'uk': 'Ukrainian',
  'cs': 'Czech',
  'sk': 'Slovak',
  'hu': 'Hungarian',
  'ro': 'Romanian',
  'bg': 'Bulgarian',
  'hr': 'Croatian',
  'sr': 'Serbian',
  'sl': 'Slovenian',
  'fa': 'Persian',
  'ur': 'Urdu',
  'bn': 'Bengali',
  'ta': 'Tamil',
  'te': 'Telugu',
  'ml': 'Malayalam',
  'kn': 'Kannada',
  'mr': 'Marathi',
  'ca': 'Catalan',
  'eu': 'Basque',
  'gl': 'Galician',
  'et': 'Estonian',
  'lv': 'Latvian',
  'lt': 'Lithuanian',
  'is': 'Icelandic',
  'sq': 'Albanian',
  'mk': 'Macedonian',
  'bs': 'Bosnian',
  'ka': 'Georgian',
  'hy': 'Armenian',
  'az': 'Azerbaijani',
  'kk': 'Kazakh',
  'uz': 'Uzbek',
  'fil': 'Filipino',
  'tl': 'Tagalog',
  'sw': 'Swahili',
  'am': 'Amharic',
  'ku': 'Kurdish',
  'ps': 'Pashto',
};

/// Normalizes "ara", "AR", "ar-EG", "pob" → "ar", "ar", "ar", "pt-BR".
String? normalizeLang(String? code) {
  if (code == null) return null;
  final c = code.trim().toLowerCase();
  if (c.isEmpty || c == 'und' || c == 'unk' || c == 'mis') return null;
  if (_toIso1.containsKey(c)) return _toIso1[c];
  if (c.length == 2) return c;
  final base = c.split(RegExp('[-_]')).first;
  if (c.startsWith('pt-br') || c == 'pb') return 'pt-BR';
  if (base.length == 2) return base;
  return _toIso1[base] ?? c;
}

/// English name for a normalized code, or the code itself.
String langName(String? code) {
  final n = normalizeLang(code);
  if (n == null) return 'Unknown';
  return _names[n] ?? _names[n.split('-').first] ?? n;
}

/// True when both codes mean the same language ("ara" vs "ar").
bool sameLang(String? a, String? b) {
  final x = normalizeLang(a), y = normalizeLang(b);
  if (x == null || y == null) return false;
  return x == y || x.split('-').first == y.split('-').first;
}

/// 2- and 3-letter forms for mpv's alang/slang lists.
List<String> mpvLangCodes(String code) {
  final n = normalizeLang(code);
  if (n == null) return const [];
  return {
    n,
    for (final e in _toIso1.entries)
      if (e.value == n) e.key,
  }.toList();
}
