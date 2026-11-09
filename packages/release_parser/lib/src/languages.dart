/// English names of the ISO 639-1 codes this package can emit.
const Map<String, String> _names = {
  'ar': 'Arabic',
  'bg': 'Bulgarian',
  'bn': 'Bengali',
  'cs': 'Czech',
  'da': 'Danish',
  'de': 'German',
  'el': 'Greek',
  'en': 'English',
  'es': 'Spanish',
  'et': 'Estonian',
  'fa': 'Persian',
  'fi': 'Finnish',
  'fr': 'French',
  'he': 'Hebrew',
  'hi': 'Hindi',
  'hr': 'Croatian',
  'hu': 'Hungarian',
  'id': 'Indonesian',
  'it': 'Italian',
  'ja': 'Japanese',
  'kn': 'Kannada',
  'ko': 'Korean',
  'lt': 'Lithuanian',
  'lv': 'Latvian',
  'ml': 'Malayalam',
  'ms': 'Malay',
  'nl': 'Dutch',
  'no': 'Norwegian',
  'pl': 'Polish',
  'pt': 'Portuguese',
  'ro': 'Romanian',
  'ru': 'Russian',
  'sk': 'Slovak',
  'sl': 'Slovenian',
  'sr': 'Serbian',
  'sv': 'Swedish',
  'ta': 'Tamil',
  'te': 'Telugu',
  'th': 'Thai',
  'tr': 'Turkish',
  'uk': 'Ukrainian',
  'ur': 'Urdu',
  'vi': 'Vietnamese',
  'zh': 'Chinese',
};

/// English display name for an ISO 639-1 [code] (e.g. `ar` → `Arabic`).
///
/// Unknown codes are returned upper-cased.
String languageName(String code) =>
    _names[code.toLowerCase()] ?? code.toUpperCase();

/// Language words seen in release names → ISO 639-1. Only full words and
/// well-established scene tags; 3-letter codes that are common English words
/// (`fin`, `dan`, `per`, `tel`, ...) are left out on purpose.
const Map<String, String> releaseLanguageWords = {
  'english': 'en', 'eng': 'en', 'ingles': 'en', 'inglés': 'en', //
  'anglais': 'en',
  'french': 'fr', 'francais': 'fr', 'français': 'fr', 'truefrench': 'fr',
  'vff': 'fr', 'vfq': 'fr', 'vfi': 'fr', 'vf2': 'fr', 'vf': 'fr', 'fre': 'fr',
  'fra': 'fr',
  'spanish': 'es', 'espanol': 'es', 'español': 'es', 'castellano': 'es',
  'latino': 'es', 'spa': 'es', 'esp': 'es', 'lat': 'es',
  'portuguese': 'pt', 'portugues': 'pt', 'português': 'pt', 'pt-br': 'pt',
  'ptbr': 'pt', 'brazilian': 'pt', 'dublado': 'pt', 'por': 'pt',
  'italian': 'it', 'italiano': 'it', 'ita': 'it',
  'german': 'de', 'deutsch': 'de', 'ger': 'de', 'deu': 'de',
  'russian': 'ru', 'rus': 'ru',
  'japanese': 'ja', 'jpn': 'ja', 'jap': 'ja',
  'korean': 'ko', 'kor': 'ko',
  'chinese': 'zh', 'mandarin': 'zh', 'cantonese': 'zh', 'chi': 'zh',
  'hindi': 'hi', 'hin': 'hi',
  'arabic': 'ar', 'ara': 'ar',
  'turkish': 'tr', 'turkce': 'tr', 'türkçe': 'tr', 'tur': 'tr',
  'tamil': 'ta', 'telugu': 'te', 'malayalam': 'ml', 'kannada': 'kn',
  'bengali': 'bn', 'urdu': 'ur',
  'polish': 'pl', 'pol': 'pl', 'pldub': 'pl',
  'dutch': 'nl', 'flemish': 'nl',
  'swedish': 'sv', 'swe': 'sv', 'norwegian': 'no', 'danish': 'da',
  'finnish': 'fi',
  'ukrainian': 'uk', 'ukr': 'uk', 'czech': 'cs', 'cze': 'cs',
  'hungarian': 'hu', 'hun': 'hu', 'romanian': 'ro', 'greek': 'el',
  'hebrew': 'he', 'heb': 'he', 'persian': 'fa', 'farsi': 'fa', 'thai': 'th',
  'vietnamese': 'vi', 'indonesian': 'id', 'malay': 'ms', 'bulgarian': 'bg',
  'serbian': 'sr', 'croatian': 'hr', 'slovak': 'sk', 'slovenian': 'sl',
  'lithuanian': 'lt', 'latvian': 'lv', 'estonian': 'et',
};

/// Two-letter codes accepted in upper-case code lists such as `[ES-EN]`
/// or `👂EN FR ES`.
const Set<String> isoCodes = {
  'ar', 'de', 'en', 'es', 'fr', 'hi', 'it', 'ja', 'ko', 'nl', 'pl', 'pt', //
  'ru', 'sv', 'tr', 'uk', 'zh', 'he', 'cs', 'hu', 'ro', 'el', 'th', 'vi',
};

/// Country (flag emoji) → main language. Torrentio uses 🇬🇧 for English,
/// 🇲🇽 for Latino Spanish, 🇮🇳 for Indian languages and 🇸🇦 for Arabic.
const Map<String, String> countryLanguages = {
  'GB': 'en', 'US': 'en', 'AU': 'en', 'CA': 'en', 'NZ': 'en', 'IE': 'en', //
  'FR': 'fr', 'BE': 'fr',
  'ES': 'es', 'MX': 'es', 'AR': 'es', 'CO': 'es', 'CL': 'es',
  'PT': 'pt', 'BR': 'pt',
  'IT': 'it', 'DE': 'de', 'AT': 'de', 'RU': 'ru', 'JP': 'ja', 'KR': 'ko',
  'CN': 'zh', 'TW': 'zh', 'HK': 'zh', 'IN': 'hi', 'PK': 'ur',
  'SA': 'ar', 'AE': 'ar', 'EG': 'ar', 'MA': 'ar', 'IQ': 'ar', 'SY': 'ar',
  'TR': 'tr', 'NL': 'nl', 'PL': 'pl', 'UA': 'uk', 'SE': 'sv', 'NO': 'no',
  'DK': 'da', 'FI': 'fi', 'CZ': 'cs', 'SK': 'sk', 'SI': 'sl', 'HU': 'hu',
  'RO': 'ro', 'BG': 'bg', 'RS': 'sr', 'HR': 'hr', 'GR': 'el', 'IL': 'he',
  'IR': 'fa', 'TH': 'th', 'VN': 'vi', 'ID': 'id', 'MY': 'ms', 'LT': 'lt',
  'LV': 'lv', 'EE': 'et',
};
