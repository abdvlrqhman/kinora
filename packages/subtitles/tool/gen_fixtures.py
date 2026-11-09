#!/usr/bin/env python3
"""Generates binary test fixtures (charset samples and archives).

Run from the package root: python3 -I tool/gen_fixtures.py
Texts are original sample lines, encoded with Python's codecs.
"""
import io
import json
import os
import zipfile

C = 'test/fixtures/charset'
A = 'test/fixtures/archive'
os.makedirs(C, exist_ok=True)
os.makedirs(A, exist_ok=True)


def srt(lines):
    out = []
    for i, text in enumerate(lines):
        out.append('%d\r\n00:00:%02d,000 --> 00:00:%02d,500\r\n%s\r\n' % (i + 1, i * 3 + 1, i * 3 + 3, text.replace('\n', '\r\n')))
    return '\r\n'.join(out)


SAMPLES = {
    'arabic_1256.srt': ('cp1256', 'ar', ['مرحباً بكم في البرنامج.', 'هل أنت متأكد؟ لا أعرف ماذا أقول...', '- لماذا تأخرت؟\n- كان الطريق مزدحماً جداً.', 'سنلتقي غداً في المدرسة، إن شاء الله.']),
    'persian_1256.srt': ('cp1256', 'fa', ['سلام، حال شما چطور است؟', 'من امروز به کتابخانه رفتم و يک کتاب گرفتم.', 'پدرم ژاکت گرم پوشيد.']),  # cp1256 has no U+06CC
    'russian_1251.srt': ('cp1251', 'ru', ['Привет! Как у тебя дела?', 'Мы встретимся завтра утром у вокзала.', 'Это очень интересная история, правда?']),
    'ukrainian_1251.srt': ('cp1251', 'uk', ['Привіт! Як справи?', 'Ми зустрінемося завтра біля їдальні.']),
    'greek_1253.srt': ('cp1253', 'el', ['Γεια σου! Τι κάνεις σήμερα;', 'Θα συναντηθούμε αύριο το πρωί στο σταθμό.']),
    'hebrew_1255.srt': ('cp1255', 'he', ['שלום! מה שלומך היום?', 'נפגש מחר בבוקר ליד התחנה המרכזית.']),
    'turkish_1254.srt': ('cp1254', 'tr', ['Merhaba! Bugün nasılsın?', 'Yarın sabah istasyonda buluşacağız, değil mi?', 'Şimdi gitmem gerekiyor.']),
    'polish_1250.srt': ('cp1250', 'pl', ['Cześć! Jak się dzisiaj czujesz?', 'Spotkamy się jutro rano na dworcu.', 'Źle się stało, że żółw uciekł.']),
    'czech_1250.srt': ('cp1250', 'cs', ['Ahoj! Jak se dnes máš?', 'Uvidíme se zítra ráno na nádraží.', 'Příliš žluťoučký kůň úpěl ďábelské ódy.']),
    'french_1252.srt': ('cp1252', 'fr', ['Bonjour ! Comment ça va aujourd\'hui ?', 'On se retrouve demain matin à la gare.', 'C\'était très intéressant, n\'est-ce pas ?']),
    'lithuanian_1257.srt': ('cp1257', 'lt', ['Labas! Kaip šiandien sekasi?', 'Susitiksime rytoj ryte prie stoties, ačiū.']),
    'thai_874.srt': ('cp874', 'th', ['สวัสดีครับ วันนี้เป็นอย่างไรบ้าง', 'พรุ่งนี้เช้าเราจะพบกันที่สถานี']),
    'chinese_gbk.srt': ('gbk', 'zh-Hans', ['你好！你今天怎么样？', '我们明天早上在车站见面。', '这是一个非常有意思的故事，对吧？']),
    'chinese_big5.srt': ('big5', 'zh-Hant', ['你好！你今天怎麼樣？', '我們明天早上在車站見面。', '這是一個非常有意思的故事，對吧？']),
    'japanese_sjis.srt': ('cp932', 'ja', ['こんにちは！今日はどうですか？', '明日の朝、駅で会いましょう。', 'これはとても面白い話ですね。']),
    'korean_cp949.srt': ('cp949', 'ko', ['안녕하세요! 오늘 어떠세요?', '내일 아침에 역에서 만나요.', '이것은 정말 재미있는 이야기예요.']),
    'utf8_bom.srt': ('utf-8-sig', 'ar', ['مرحباً بكم', 'Hello there']),
    'utf8_plain.srt': ('utf-8', None, ['Ça marche très bien — merci !', 'Ñandú']),
    'utf16le_bom.srt': ('utf-16-le', 'ru', ['Привет, мир!', 'Hello world']),
    'utf16be_bom.srt': ('utf-16-be', 'he', ['שלום עולם', 'Hello world']),
    'utf16le_nobom.srt': ('utf-16-le', None, ['Hello without a byte order mark', 'Second line here']),
}
expected = {}
for name, (codec, lang, lines) in SAMPLES.items():
    text = srt(lines)
    data = text.encode(codec)
    if codec == 'utf-16-le' and 'nobom' not in name:
        data = b'\xff\xfe' + data
    if codec == 'utf-16-be':
        data = b'\xfe\xff' + data
    open(os.path.join(C, name), 'wb').write(data)
    expected[name] = {'language': lang, 'encoding': codec, 'text': text}
json.dump(expected, open(os.path.join(C, 'expected.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)


def zbytes(entries):
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, 'w', zipfile.ZIP_DEFLATED) as z:
        for n, d in entries:
            z.writestr(n, d)
    return buf.getvalue()


ep = lambda n: srt(['Episode %d line one' % n, 'Episode %d line two' % n]).encode()
open(os.path.join(A, 'season_pack.zip'), 'wb').write(zbytes([
    ('Show.S01E01.1080p.WEB-DL-GRP.srt', ep(1)),
    ('Show.S01E02.1080p.WEB-DL-GRP.srt', ep(2)),
    ('Show.S01E02.1080p.WEB-DL-GRP.forced.srt', srt(['[SIGN]']).encode()),
    ('Show.S01E03.1080p.WEB-DL-GRP.srt', ep(3)),
    ('readme.nfo', b'Ripped by GRP'),
    ('subs/Show.S02E02.srt', ep(22)),
]))
open(os.path.join(A, 'multi_language.zip'), 'wb').write(zbytes([
    ('Movie.2010.1080p.BluRay.en.srt', srt(['Hello']).encode()),
    ('Movie.2010.1080p.BluRay.ar.srt', srt(['مرحبا']).encode('cp1256')),
    ('Movie.2010.1080p.BluRay.ar.forced.srt', srt(['لافتة']).encode('cp1256')),
    ('Movie.2010.1080p.BluRay.ar.SDH.srt', srt(['[موسيقى] مرحبا']).encode('cp1256')),
    ('info.txt', b'not a subtitle'),
]))
open(os.path.join(A, 'nested.zip'), 'wb').write(zbytes([
    ('inner.zip', zbytes([('Show.S01E05.srt', ep(5))])),
]))
open(os.path.join(A, 'vobsub.zip'), 'wb').write(zbytes([
    ('movie.idx', b'# VobSub index file, v7'),
    ('movie.sub', b'\x00\x00\x01\xba' + b'\x00' * 60),
    ('movie.ass', '[Script Info]\nScriptType: v4.00+\n\n[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\nDialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,Hi\n'.encode()),
]))
open(os.path.join(A, 'no_subtitles.zip'), 'wb').write(zbytes([('readme.nfo', b'nothing'), ('notes.txt', b'nothing')]))
open(os.path.join(A, 'mpl2_txt.zip'), 'wb').write(zbytes([
    ('notes.txt', b'Ripped by someone. Enjoy!'),
    ('Movie.2010.txt', b'[10][25]Hello|/world\n[30][45]Second\n'),
]))
open(os.path.join(A, 'fake.rar'), 'wb').write(b'Rar!\x1a\x07\x01\x00' + b'\x00' * 32)
print('ok')
