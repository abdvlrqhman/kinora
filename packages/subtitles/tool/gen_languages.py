#!/usr/bin/env python3
"""Generates lib/src/language_data.dart.

Sources: Debian iso-codes (ISO 639-2 / 639-3 JSON) for codes and names, Babel
(CLDR) for English display names and native names, plus hand-written provider
quirks below. Run:
  python3 -I tool/gen_languages.py > lib/src/language_data.dart
"""
import json
import re
from babel import Locale

ISO2 = json.load(open('/usr/share/iso-codes/json/iso_639-2.json'))['639-2']
ISO3 = {x['alpha_3']: x for x in json.load(open('/usr/share/iso-codes/json/iso_639-3.json'))['639-3']}

SPECIAL = {'mis', 'mul', 'und', 'zxx'}
KEEP_COLLECTIVE = {'wen'}

# Generic code -> canonical code when the generic one is folded into a variant.
FOLD = {'zh': 'zh-Hans', 'nb': 'no'}

# Hand-defined variants: code, English, native, aliases.
VARIANTS = [
    ('pt-BR', 'Portuguese (Brazil)', 'Português (Brasil)',
     ['pob', 'pb', 'pt-br', 'br-pt', 'brazilian portuguese', 'portuguese (brazil)', 'portuguese brazil',
      'portuguese-br', 'brazilian', 'portuguese (br)']),
    ('zh-Hans', 'Chinese (Simplified)', '中文 (简体)',
     ['zh', 'chi', 'zho', 'chinese', 'zh-cn', 'zh-hans', 'zh-sg', 'chs', 'cmn', 'chinese simplified',
      'chinese (simplified)', 'simplified chinese', 'chinese bg code', 'gb', 'mandarin', 'mandarin chinese']),
    ('zh-Hant', 'Chinese (Traditional)', '中文 (繁體)',
     ['zh-tw', 'zh-hk', 'zh-mo', 'zh-hant', 'zht', 'cht', 'big5', 'big 5 code', 'zh-bg', 'chinese traditional',
      'chinese (traditional)', 'traditional chinese']),
    ('ze', 'Chinese (Bilingual)', '中英双语',
     ['zhe', 'chinese bilingual', 'chinese (bilingual)', 'zh-en', 'chinese english']),
    ('yue', 'Cantonese', '粵語', ['zh-ca', 'zh-yue', 'chinese cantonese', 'cantonese', 'yue chinese']),
    ('sr-Latn', 'Serbian (Latin)', 'Srpski (latinica)',
     ['sr-latn', 'srp-latn', 'serbian latin', 'serbian (latin)', 'sr-latin']),
    ('sr-Cyrl', 'Serbian (Cyrillic)', 'Српски (ћирилица)',
     ['sr-cyrl', 'srp-cyrl', 'serbian cyrillic', 'serbian (cyrillic)', 'sr-cyrillic']),
    ('es-419', 'Spanish (Latin America)', 'Español (Latinoamérica)',
     ['es-la', 'es-mx', 'es-ar', 'es-co', 'es-cl', 'es-us', 'ea', 'spl', 'latino', 'spanish (latin america)',
      'spanish latin america', 'latin american spanish', 'spanish (latam)', 'spanish latam']),
    ('fr-CA', 'French (Canada)', 'Français (Canada)', ['fr-ca', 'french canada', 'french (canada)', 'canadian french']),
    ('prs', 'Dari', 'دری', ['pr', 'dari', 'fa-af', 'dari persian']),
    ('ckb', 'Central Kurdish', 'کوردیی ناوەندی', ['sorani', 'kurdish sorani', 'central kurdish']),
    ('ext', 'Extremaduran', 'Estremeñu', ['ex', 'extremaduran']),
    ('syl', 'Sylheti', 'ꠍꠤꠟꠐꠤ', ['sylheti']),
    ('tok', 'Toki Pona', 'Toki pona', ['tp', 'toki pona']),
]

# Extra aliases onto existing codes (provider quirks, deprecated codes, 639-3 members).
EXTRA = {
    'pt': ['pt-pt', 'pm', 'portuguese (portugal)', 'portuguese portugal', 'european portuguese'],
    'es': ['sp', 'es-es', 'spanish spain', 'spanish (spain)', 'castilian', 'european spanish'],
    'fr': ['fr-fr', 'french france', 'french (france)'],
    'en': ['english (us)', 'english (uk)'],
    'cnr': ['me', 'montenegrin'],
    'ar': ['arb', 'arz', 'ary', 'apc', 'ajp', 'acm', 'afb', 'ayl', 'aeb', 'arq', 'acq', 'apd', 'ar-sa', 'ar-eg'],
    'fa': ['farsi', 'farsi persian', 'farsi/persian', 'pes', 'persian', 'iranian persian'],
    'he': ['iw'],
    'sr': ['scc'],
    'hr': ['scr'],
    'id': ['in'],
    'yi': ['ji', 'ydd'],
    'jv': ['jw'],
    'ro': ['mo', 'moldavian', 'moldovan'],
    'no': ['nb', 'nob', 'norwegian bokmal', 'norwegian bokmål', 'bokmal', 'bokmål'],
    'ms': ['zsm'],
    'et': ['ekk'],
    'lv': ['lvs'],
    'sw': ['swh'],
    'uz': ['uzn'],
    'az': ['azj', 'azb', 'az-az', 'az-zb'],
    'mn': ['khk'],
    'mg': ['plt'],
    'qu': ['quz'],
    'om': ['gaz'],
    'ne': ['npi'],
    'or': ['ory', 'odia'],
    'ps': ['pbu', 'pushto'],
    'ku': ['kmr', 'kurmanji'],
    'ast': ['at'],
    'mni': ['ma'],
    'syr': ['sy'],
    'sat': ['sx', 'santli'],
    'gl': ['gaelician'],
    'gd': ['gaelic', 'scottish gaelic'],
    'eo': ['espranto'],
    'se': ['northen sami', 'northern sami'],
    'si': ['sinhalese'],
    'wen': ['sorbian'],
    'el': ['greek'],
    'km': ['khmer', 'cambodian'],
    'ky': ['kyrgyz', 'kirghiz'],
    'tl': ['tagalog'],
    'fil': ['filipino', 'pilipino'],
    'ug': ['uyghur', 'uighur'],
    'pa': ['punjabi', 'panjabi'],
    'nl': ['flemish', 'nl-be'],
    'ca': ['valencian'],
    'dv': ['maldivian', 'dhivehi'],
    'kl': ['greenlandic'],
    'ht': ['haitian creole'],
    'hy': ['armenian'],
}

SCRIPTS_CAP = True


def cldr(code, in_locale):
    try:
        loc = Locale.parse(code.replace('-', '_'))
        if loc.language != code.split('-')[0]:  # Babel aliases e.g. tl -> fil, cnr -> sr
            return None
        name = loc.get_display_name(in_locale)
        return name
    except Exception:
        return None


def cap(s):
    return s[:1].upper() + s[1:] if s else s


EN_NAMES = Locale('en').languages  # CLDR names, also for codes without locale data
CODES = {}  # canonical -> its own ISO codes
entries = {}   # canonical -> [english, native, set(aliases)]
order = []

for x in ISO2:
    a3 = x['alpha_3']
    name = x['name']
    if a3 in SPECIAL or a3.startswith('q') and 'qaa' <= a3 <= 'qtz':
        continue
    if name.endswith(' languages') and a3 not in KEEP_COLLECTIVE:
        continue
    code = x.get('alpha_2', a3)
    canonical = FOLD.get(code, code)
    aliases = {code, a3}
    if 'bibliographic' in x:
        aliases.add(x['bibliographic'])
    CODES.setdefault(canonical, set()).update(aliases)
    for part in name.split(';'):
        part = part.strip().lower()
        if part:
            aliases.add(part)
            if '(' in part:  # "Occitan (post 1500)" -> "occitan"
                aliases.add(part.split('(')[0].strip())
    if canonical != code:
        entries.setdefault(canonical, [None, None, set()])[2].update(aliases)
        continue
    en = cldr(code, 'en') or EN_NAMES.get(code) if code != 'wen' else 'Sorbian'
    if not en or en.lower() == code:
        en = re.sub(r'\s*\(.*?\)', '', name.split(';')[0]).strip()
    native = cldr(code, code) or en
    entries[canonical] = [en, cap(native), aliases]
    order.append(canonical)

for code, en, native, aliases in VARIANTS:
    prev = entries.get(code, [None, None, set()])
    entries[code] = [en, native, prev[2] | set(aliases) | {code.lower()}]
    if code not in order:
        order.append(code)

for code, aliases in EXTRA.items():
    entries[code][2].update(aliases)

# Every alias must point at exactly one canonical code. Codes (and the
# hand-written quirks) win over ISO names, e.g. "ga" is Irish, not the Ga language.
owner = {}
hand = {c: set(al) for c, _, _, al in VARIANTS}
for c, al in EXTRA.items():
    hand.setdefault(c, set()).update(al)


for pass_ in ('code', 'name'):
    for code in order:
        names = set(entries[code][2]) | {entries[code][0].lower()}
        for a in sorted(names):
            a = a.lower().replace('_', ' ')
            primary = a in CODES.get(code, ()) or a in hand.get(code, ()) or a == code.lower()
            if (pass_ == 'code') != primary:
                continue
            if a in owner and owner[a] != code:
                if pass_ == 'code':
                    raise SystemExit('alias %r claimed by %s and %s' % (a, owner[a], code))
                continue
            owner[a] = code


def q(s):
    return "'" + s.replace('\\', '\\\\').replace("'", "\\'").replace('$', '\\$') + "'"


print('// GENERATED by tool/gen_languages.py. Do not edit.')
print()
print('/// (code, English name, native name) for every supported language.')
print('const List<(String, String, String)> languageTable = [')
for code in sorted(order, key=lambda c: entries[c][0].lower()):
    en, native, _ = entries[code]
    print('  (%s, %s, %s),' % (q(code), q(en), q(native)))
print('];')
print()
print('/// Lowercase alias (codes and names, "_" folded to " ") -> canonical code.')
print('const Map<String, String> languageAliases = {')
for a in sorted(owner):
    if a != owner[a].lower():
        print('  %s: %s,' % (q(a), q(owner[a])))
print('};')
