import 'dart:convert';
import 'dart:typed_data';

import 'package:subtitles/subtitles.dart';
import 'package:test/test.dart';

import 'helpers.dart';

SubtitleDownload dl(String fixtureName) => SubtitleDownload(
  bytes: fixtureBytes('archive/$fixtureName'),
  fileName: fixtureName,
);

void main() {
  test('archiveKind from magic bytes', () {
    expect(archiveKind(fixtureBytes('archive/season_pack.zip')), 'zip');
    expect(archiveKind(fixtureBytes('archive/fake.rar')), 'rar');
    expect(archiveKind([0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C, 0, 4]), '7z');
    expect(archiveKind([0x1F, 0x8B, 8]), 'gzip');
    expect(archiveKind(utf8.encode('1\n00:00:01,000')), isNull);
    expect(archiveKind(const []), isNull);
  });

  test('plain subtitle passes through', () {
    final bytes = Uint8List.fromList(
      utf8.encode('1\n00:00:01,000 --> 00:00:02,000\nx\n'),
    );
    final f = extractSubtitle(
      SubtitleDownload(bytes: bytes, fileName: 'a.srt'),
    );
    expect(f, SubtitleFile('a.srt', bytes));
  });

  group('season pack', () {
    test(
      'picks the wanted episode, not forced, skips .nfo and other seasons',
      () {
        final f = extractSubtitle(dl('season_pack.zip'), season: 1, episode: 2);
        expect(f.fileName, 'Show.S01E02.1080p.WEB-DL-GRP.srt');
        expect(utf8.decode(f.bytes), contains('Episode 2 line one'));
      },
    );
    test('forced variant when asked', () {
      final f = extractSubtitle(
        dl('season_pack.zip'),
        season: 1,
        episode: 2,
        forced: true,
      );
      expect(f.fileName, 'Show.S01E02.1080p.WEB-DL-GRP.forced.srt');
    });
    test('missing episode is a typed error', () {
      expect(
        () => extractSubtitle(dl('season_pack.zip'), season: 1, episode: 9),
        throwsA(
          isA<SubtitleArchiveException>().having(
            (e) => e.unsupportedFormat,
            'unsupported',
            isNull,
          ),
        ),
      );
    });
    test('other season entry is skipped', () {
      final f = extractSubtitle(dl('season_pack.zip'), season: 2, episode: 2);
      expect(f.fileName, 'subs/Show.S02E02.srt');
    });
  });

  test('prefers the language, then non-forced, then HI preference', () {
    final ar = extractSubtitle(
      dl('multi_language.zip'),
      language: Language.of('ar'),
    );
    expect(ar.fileName, 'Movie.2010.1080p.BluRay.ar.srt');
    final arHi = extractSubtitle(
      dl('multi_language.zip'),
      language: Language.of('ar'),
      hearingImpaired: true,
    );
    expect(arHi.fileName, 'Movie.2010.1080p.BluRay.ar.SDH.srt');
    final en = extractSubtitle(
      dl('multi_language.zip'),
      language: Language.of('en'),
    );
    expect(en.fileName, 'Movie.2010.1080p.BluRay.en.srt');
  });

  test('nested zip, VobSub skipped, nothing usable, RAR unsupported', () {
    expect(
      extractSubtitle(dl('nested.zip'), episode: 5).fileName,
      'Show.S01E05.srt',
    );
    expect(extractSubtitle(dl('vobsub.zip')).fileName, 'movie.ass');
    expect(
      () => extractSubtitle(dl('no_subtitles.zip')),
      throwsA(isA<SubtitleArchiveException>()),
    );
    expect(
      () => extractSubtitle(dl('fake.rar')),
      throwsA(
        isA<SubtitleArchiveException>()
            .having((e) => e.unsupportedFormat, 'format', 'rar')
            .having((e) => e.message, 'message', contains('RAR')),
      ),
    );
    final corrupt = Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, 1, 2, 3]);
    expect(
      () =>
          extractSubtitle(SubtitleDownload(bytes: corrupt, fileName: 'x.zip')),
      throwsA(isA<SubtitleArchiveException>()),
    );
  });

  test('.txt notes are skipped but MPL2 .txt subtitles are found', () {
    final f = extractSubtitle(dl('mpl2_txt.zip'));
    expect(f.fileName, 'Movie.2010.txt');
    expect(
      parseSubtitle(utf8.decode(f.bytes)).sourceFormat,
      SubtitleFormat.mpl2,
    );
  });

  test('languageFromFileName', () {
    Language? l(String n) => languageFromFileName(n);
    expect(l('Show.S01E01.ar.srt')?.code, 'ar');
    expect(l('Show.S01E01.ARA.srt')?.code, 'ar');
    expect(l('Movie_eng.srt')?.code, 'en');
    expect(l('Movie.2010.Arabic.srt')?.code, 'ar');
    expect(l('Movie.2010.en.forced.srt')?.code, 'en');
    expect(l('Movie.2010.pob.srt')?.code, 'pt-BR');
    expect(l('[English] Frieren - 05.ass')?.code, 'en');
    expect(l('Iron.Man.srt'), isNull);
    expect(l('Empire.of.the.Sun.srt'), isNull);
    expect(l('Breaking.Bad.S01E01.HI.srt'), isNull);
    expect(l('Pilot.srt'), isNull);
  });
}
