import 'package:release_parser/release_parser.dart';
import 'package:test/test.dart';

/// One fixture: a real-world release name and the fields it must produce.
/// Only non-null expectations are checked. `year: 0` / `group: ''` mean
/// "must be absent".
final class _Case {
  const _Case(
    this.name, {
    this.title,
    this.year,
    this.seasons,
    this.episodes,
    this.abs,
    this.pack,
    this.complete,
    this.res,
    this.source,
    this.codec,
    this.bit,
    this.hdr,
    this.audio,
    this.atmos,
    this.channels,
    this.langs,
    this.subs,
    this.multi,
    this.dual,
    this.dubbed,
    this.hc,
    this.group,
    this.proper,
    this.repack,
    this.extended,
    this.imax,
    this.threeD,
    this.container,
  });

  final String name;
  final String? title;
  final int? year;
  final List<int>? seasons;
  final List<int>? episodes;
  final int? abs;
  final bool? pack;
  final bool? complete;
  final Resolution? res;
  final Source? source;
  final VideoCodec? codec;
  final int? bit;
  final Set<HdrFormat>? hdr;
  final List<AudioCodec>? audio;
  final bool? atmos;
  final String? channels;
  final Set<String>? langs;
  final Set<String>? subs;
  final bool? multi;
  final bool? dual;
  final bool? dubbed;
  final bool? hc;
  final String? group;
  final bool? proper;
  final bool? repack;
  final bool? extended;
  final bool? imax;
  final bool? threeD;
  final String? container;
}

void _check(_Case c) {
  final r = parseRelease(c.name);
  final why = '$r';
  if (c.title != null) expect(r.title, c.title, reason: why);
  if (c.year != null) expect(r.year, c.year == 0 ? null : c.year, reason: why);
  if (c.seasons != null) expect(r.seasons, c.seasons, reason: why);
  if (c.episodes != null) expect(r.episodes, c.episodes, reason: why);
  if (c.abs != null) expect(r.absoluteEpisode, c.abs, reason: why);
  if (c.pack != null) expect(r.isSeasonPack, c.pack, reason: why);
  if (c.complete != null) expect(r.isCompleteSeries, c.complete, reason: why);
  if (c.res != null) expect(r.resolution, c.res, reason: why);
  if (c.source != null) expect(r.source, c.source, reason: why);
  if (c.codec != null) expect(r.videoCodec, c.codec, reason: why);
  if (c.bit != null) expect(r.bitDepth, c.bit, reason: why);
  if (c.hdr != null) expect(r.hdr, c.hdr, reason: why);
  if (c.audio != null) expect(r.audioCodecs, c.audio, reason: why);
  if (c.atmos != null) expect(r.atmos, c.atmos, reason: why);
  if (c.channels != null) expect(r.channels, c.channels, reason: why);
  if (c.langs != null) expect(r.languages, c.langs, reason: why);
  if (c.subs != null) expect(r.subtitleLanguages, c.subs, reason: why);
  if (c.multi != null) expect(r.multiAudio, c.multi, reason: why);
  if (c.dual != null) expect(r.dualAudio, c.dual, reason: why);
  if (c.dubbed != null) expect(r.dubbed, c.dubbed, reason: why);
  if (c.hc != null) expect(r.hardcodedSubs, c.hc, reason: why);
  if (c.group != null) {
    expect(r.group, c.group!.isEmpty ? null : c.group, reason: why);
  }
  if (c.proper != null) expect(r.proper, c.proper, reason: why);
  if (c.repack != null) expect(r.repack, c.repack, reason: why);
  if (c.extended != null) expect(r.extended, c.extended, reason: why);
  if (c.imax != null) expect(r.imax, c.imax, reason: why);
  if (c.threeD != null) expect(r.threeD, c.threeD, reason: why);
  if (c.container != null) expect(r.container, c.container, reason: why);
}

const _r480 = Resolution.p480;
const _r576 = Resolution.p576;
const _r720 = Resolution.p720;
const _r1080 = Resolution.p1080;
const _r1440 = Resolution.p1440;
const _r2160 = Resolution.p2160;
const _r4320 = Resolution.p4320;
const _h264 = VideoCodec.h264;
const _h265 = VideoCodec.h265;
const _dv = HdrFormat.dolbyVision;
const _hdr10 = HdrFormat.hdr10;
const _hdr10p = HdrFormat.hdr10Plus;

const movies = [
  _Case(
    'The.Matrix.1999.1080p.BluRay.x264.DTS-HD.MA.5.1-FGT',
    title: 'The Matrix',
    year: 1999,
    res: _r1080,
    source: Source.bluray,
    codec: _h264,
    audio: [AudioCodec.dtsHd],
    channels: '5.1',
    group: 'FGT',
    seasons: [],
    episodes: [],
  ),
  _Case(
    'Inception.2010.2160p.UHD.BluRay.REMUX.HDR.HEVC.DTS-HD.MA.5.1-FGT',
    title: 'Inception',
    year: 2010,
    res: _r2160,
    source: Source.remux,
    codec: _h265,
    hdr: {_hdr10},
    audio: [AudioCodec.dtsHd],
  ),
  _Case(
    'Oppenheimer.2023.1080p.WEB-DL.DDP5.1.Atmos.H.264-FLUX',
    title: 'Oppenheimer',
    year: 2023,
    res: _r1080,
    source: Source.webdl,
    codec: _h264,
    audio: [AudioCodec.eac3],
    atmos: true,
    channels: '5.1',
    group: 'FLUX',
  ),
  _Case(
    'Dune.Part.Two.2024.2160p.WEB-DL.DDP5.1.Atmos.DV.HDR.H.265-FLUX',
    title: 'Dune Part Two',
    year: 2024,
    res: _r2160,
    hdr: {_dv, _hdr10},
    codec: _h265,
    group: 'FLUX',
  ),
  _Case(
    'Interstellar.2014.IMAX.2160p.UHD.BluRay.x265.10bit.HDR.DTS-HD.MA.5.1-SWTYBLZ',
    title: 'Interstellar',
    imax: true,
    bit: 10,
    codec: _h265,
    hdr: {_hdr10},
  ),
  _Case(
    'Parasite.2019.KOREAN.1080p.BluRay.x264.DTS-FGT',
    title: 'Parasite',
    langs: {'ko'},
    audio: [AudioCodec.dts],
    group: 'FGT',
  ),
  _Case(
    'Joker.2019.1080p.WEBRip.x264.AAC5.1-[YTS.MX]',
    title: 'Joker',
    source: Source.webrip,
    audio: [AudioCodec.aac],
    channels: '5.1',
    group: 'YTS.MX',
  ),
  _Case(
    'Joker (2019) [1080p] [WEBRip] [5.1] [YTS.MX]',
    title: 'Joker',
    year: 2019,
    res: _r1080,
    source: Source.webrip,
    channels: '5.1',
    group: 'YTS.MX',
  ),
  _Case(
    'Avengers.Endgame.2019.1080p.BluRay.x264-SPARKS',
    title: 'Avengers Endgame',
    group: 'SPARKS',
  ),
  _Case(
    'Avengers Endgame (2019) [2160p] [4K] [WEB] [5.1] [YTS.MX]',
    res: _r2160,
    source: Source.webdl,
  ),
  _Case(
    'The Shawshank Redemption (1994) (1080p BluRay x265 10bit Tigole)',
    title: 'The Shawshank Redemption',
    year: 1994,
    bit: 10,
    codec: _h265,
  ),
  _Case(
    'Se7en.1995.REMASTERED.1080p.BluRay.x264-SADPANDA',
    title: 'Se7en',
    year: 1995,
  ),
  _Case(
    '1917.2019.2160p.UHD.BluRay.REMUX.HDR.HEVC.TrueHD.Atmos.7.1-EPSiLON',
    title: '1917',
    year: 2019,
    source: Source.remux,
    audio: [AudioCodec.trueHd],
    atmos: true,
    channels: '7.1',
    group: 'EPSiLON',
  ),
  _Case('1917.1080p.WEB-DL.H264', title: '1917', year: 0, res: _r1080),
  _Case(
    'Blade.Runner.2049.2017.1080p.BluRay.x264.DTS-HD.MA.7.1-FGT',
    title: 'Blade Runner 2049',
    year: 2017,
    channels: '7.1',
  ),
  _Case(
    'Blade.Runner.2049.1080p.BluRay.x264-SPARKS',
    title: 'Blade Runner 2049',
    year: 0,
  ),
  _Case(
    '2001.A.Space.Odyssey.1968.2160p.UHD.BluRay.x265.10bit.HDR.DTS-HD.MA.5.1-SWTYBLZ',
    title: '2001 A Space Odyssey',
    year: 1968,
  ),
  _Case(
    'Wonder.Woman.1984.2020.1080p.WEBRip.x265-RARBG',
    title: 'Wonder Woman 1984',
    year: 2020,
    group: 'RARBG',
  ),
  _Case('2012.2009.1080p.BluRay.x264-METiS', title: '2012', year: 2009),
  _Case(
    'Blade Runner 2049 (2017) 2160p UHD BluRay x265 10bit HDR DTS-HD MA 7.1 - SWTYBLZ',
    title: 'Blade Runner 2049',
    year: 2017,
    group: 'SWTYBLZ',
    audio: [AudioCodec.dtsHd],
  ),
  _Case(
    'Barbie.2023.HDCAM.c1nem4.x264-SUNSCREEN',
    title: 'Barbie',
    source: Source.cam,
    group: 'SUNSCREEN',
  ),
  _Case(
    'Barbie 2023 HDTS 1080p x264 AAC - HushRips',
    source: Source.telesync,
    group: 'HushRips',
  ),
  _Case(
    'Mufasa.The.Lion.King.2024.TC.x264-RiPRG',
    title: 'Mufasa The Lion King',
    source: Source.telecine,
  ),
  _Case('Napoleon.2023.1080p.SCR.x264-RiPRG', source: Source.screener),
  _Case(
    'Gladiator.II.2024.1080p.DVDSCR.x264-GROUP',
    title: 'Gladiator II',
    source: Source.screener,
  ),
  _Case(
    'Deadpool.and.Wolverine.2024.1080p.CAMRip.V2.x264',
    title: 'Deadpool and Wolverine',
    source: Source.cam,
  ),
  _Case('Venom.The.Last.Dance.2024.HDTC.1080p.x264', source: Source.telecine),
  _Case(
    'Oppenheimer.2023.HDTS.1080p.x264.AAC-ExKinoRay',
    source: Source.telesync,
    group: 'ExKinoRay',
  ),
  _Case(
    'Old.Movie.1985.DVDRip.XviD-BiPOLAR',
    year: 1985,
    source: Source.dvd,
    codec: VideoCodec.xvid,
  ),
  _Case(
    'Casablanca.1942.720p.BluRay.x264-AMIABLE',
    title: 'Casablanca',
    year: 1942,
    res: _r720,
  ),
  _Case(
    'Avatar.The.Way.of.Water.2022.3D.HSBS.1080p.BluRay.x264-HDH',
    title: 'Avatar The Way of Water',
    threeD: true,
  ),
  _Case(
    'Gravity.2013.3D.1080p.BluRay.Half-OU.DTS.x264-HDMaNiAcS',
    threeD: true,
    audio: [AudioCodec.dts],
  ),
  _Case(
    'The.Lord.of.the.Rings.The.Fellowship.of.the.Ring.2001.EXTENDED.1080p.BluRay.x264-SiNNERS',
    title: 'The Lord of the Rings The Fellowship of the Ring',
    extended: true,
  ),
  _Case(
    'Movie.2019.PROPER.1080p.WEB-DL.DD5.1.H264-FGT',
    proper: true,
    repack: false,
    audio: [AudioCodec.ac3],
    channels: '5.1',
  ),
  _Case(
    'Movie.2019.REPACK.1080p.BluRay.x264-GROUP',
    repack: true,
    proper: false,
  ),
  _Case('The.Dark.Knight.2008.IMAX.1080p.BluRay.x264', imax: true),
  _Case(
    'Spider-Man.Across.the.Spider-Verse.2023.1080p.WEBRip.x265.10bit.AAC5.1-RARBG',
    title: 'Spider-Man Across the Spider-Verse',
    bit: 10,
  ),
  _Case(
    'Everything.Everywhere.All.at.Once.2022.1080p.AV1.OPUS.5.1-GROUP',
    codec: VideoCodec.av1,
    audio: [AudioCodec.opus],
  ),
  _Case(
    'Big.Buck.Bunny.2008.1080p.VP9.Opus',
    codec: VideoCodec.vp9,
    audio: [AudioCodec.opus],
  ),
  _Case(
    'Lawrence.of.Arabia.1962.1080p.BluRay.REMUX.VC-1.DTS-HD.MA.5.1-GROUP',
    title: 'Lawrence of Arabia',
    source: Source.remux,
    codec: VideoCodec.vc1,
  ),
  _Case(
    'Classic.Film.1960.DVD9.MPEG-2.AC3.2.0-GROUP',
    source: Source.dvd,
    codec: VideoCodec.mpeg2,
    audio: [AudioCodec.ac3],
    channels: '2.0',
  ),
  _Case(
    'Movie.2020.1080p.BluRay.FLAC.2.0.x264-GROUP',
    audio: [AudioCodec.flac],
    channels: '2.0',
  ),
  _Case(
    'Movie.2021.2160p.UHD.BluRay.REMUX.DV.HDR10+.HEVC.DTS-X.7.1-GROUP',
    hdr: {_dv, _hdr10p},
    audio: [AudioCodec.dtsX],
  ),
  _Case(
    'Movie.2021.2160p.BluRay.REMUX.HEVC.DTS:X.7.1-GROUP',
    audio: [AudioCodec.dtsX],
    channels: '7.1',
  ),
  _Case(
    'Movie.2022.1080p.BluRay.LPCM.2.0.AVC-GROUP',
    audio: [AudioCodec.pcm],
    codec: _h264,
  ),
  _Case('Movie.2018.720p.HDTV.MP3.x264', audio: [AudioCodec.mp3]),
  _Case('Movie.2023.2160p.HLG.WEB-DL.HEVC', hdr: {HdrFormat.hlg}, res: _r2160),
  _Case(
    'Movie 2023 2160p DoVi HDR10 WEB-DL HEVC DDP Atmos',
    hdr: {_dv, _hdr10},
    audio: [AudioCodec.eac3],
    atmos: true,
  ),
  _Case('Movie.2023.1080p.WEB-DL.Hi10P.AAC', bit: 10),
  _Case(
    'Movie.2024.1080p.WEB-DL.E-AC-3.5.1.x264',
    audio: [AudioCodec.eac3],
    channels: '5.1',
  ),
  _Case(
    'Arrival.2016.1080p.BluRay.x264.TrueHD.7.1.Atmos-FGT',
    audio: [AudioCodec.trueHd],
    atmos: true,
    channels: '7.1',
  ),
  _Case(
    'Movie.2019.1080p.AMZN.WEB-DL.DDP2.0.H.264-NTG',
    source: Source.webdl,
    channels: '2.0',
  ),
  _Case(
    'Movie.2019.1080p.NF.WEBRip.DD+5.1.x264-GROUP',
    source: Source.webrip,
    audio: [AudioCodec.eac3],
    channels: '5.1',
  ),
  _Case('Movie.2019.720p.BluRay.x264.AAC-ETRG', audio: [AudioCodec.aac]),
  _Case('Movie.2019.1080p.BluRay.6CH.x265.HEVC-PSA', channels: '5.1'),
  _Case('Movie (2019) 1080p BluRay 8CH x265 HEVC-PSA', channels: '7.1'),
  _Case(
    'Deadpool.2016.1080p.BluRay.DTS-ES.AC3.x264-3Li',
    audio: [AudioCodec.dts, AudioCodec.ac3],
    group: '3Li',
  ),
  _Case(
    'Mad.Max.Fury.Road.2015.1080p.BluRay.DDPA5.1.x264-GROUP',
    audio: [AudioCodec.eac3],
    atmos: true,
    channels: '5.1',
  ),
  _Case('Movie.2010.1920x1080.BluRay.x264', res: _r1080),
  _Case('Movie 2010 3840x1600 HEVC', res: _r2160),
  _Case('Movie.2019.480p.DVDRip.x264', res: _r480),
  _Case('Movie.2019.576p.PAL.DVDRip.x264', res: _r576, source: Source.dvd),
  _Case('Movie.2019.8K.WEB-DL.HEVC', res: _r4320),
  _Case('Movie.2019.1440p.WEB-DL.HEVC', res: _r1440),
  _Case('Movie.2019.UHD.BluRay.x265', res: _r2160),
  _Case('Movie.2005.DVDRip.XviD.AC3-BiA.avi', container: 'avi', group: 'BiA'),
  _Case('Movie.2019.1080p.HDTV.H264.ts', container: 'ts'),
  _Case('Movie.2019.1080p.WEBRip.x264.mkv', container: 'mkv', group: ''),
  _Case('Movie.2019.1080p.WEB-DL.H264-GRP.mp4', container: 'mp4', group: 'GRP'),
  _Case('Opus.2025.1080p.WEB-DL.x264', title: 'Opus', year: 2025),
  _Case(
    'A.Complete.Unknown.2024.1080p.WEB-DL.x264',
    title: 'A Complete Unknown',
    complete: false,
  ),
  _Case(
    "Charlotte's.Web.2006.1080p.BluRay.x264",
    title: "Charlotte's Web",
    source: Source.bluray,
  ),
  _Case(
    'Cam.2018.1080p.NF.WEB-DL.DD5.1.x264-NTG',
    title: 'Cam',
    source: Source.webdl,
  ),
  _Case(
    'Movie.2023.COMPLETE.UHD.BLURAY-GROUP',
    complete: false,
    source: Source.bluray,
  ),
  _Case(
    'www.1TamilMV.cz - Kalki 2898 AD (2024) Telugu TRUE WEB-DL - 1080p - AVC - (DD+5.1 - 640Kbps & AAC) - 5.6GB - ESub.mkv',
    title: 'Kalki 2898 AD',
    year: 2024,
    langs: {'te'},
    subs: {'en'},
    group: '',
  ),
  _Case(
    '[ www.Torrenting.com ] - Movie.2019.1080p.WEB-DL.H264-GRP',
    title: 'Movie',
    group: 'GRP',
  ),
  _Case(
    'www.TamilBlasters.cafe - Leo (2023) Tamil HQ HDRip - 1080p - x264 - (DD+5.1 - 192Kbps & AAC) - 2.5GB - ESub.mkv',
    title: 'Leo',
    source: Source.hdrip,
    langs: {'ta'},
    audio: [AudioCodec.eac3, AudioCodec.aac],
  ),
  _Case('S.W.A.T.2017.S07E01.1080p.WEB.h264-ETHEL', title: 'SWAT', year: 2017),
  _Case(
    'A.I.Artificial.Intelligence.2001.1080p.BluRay.x264',
    title: 'AI Artificial Intelligence',
    year: 2001,
  ),
  _Case('Movie.2019.1280x720.WEB.x264', res: _r720),
  _Case('Movie.2019.7680x4320.HEVC', res: _r4320),
  _Case('Movie.2019.2560x1440.HEVC', res: _r1440),
  _Case(
    'Movie.2019.1080p.WEB-DL.Dolby.Digital.Plus.5.1.H264',
    audio: [AudioCodec.eac3],
    channels: '5.1',
  ),
  _Case(
    'Movie.2019.1080p.BluRay.Dolby.Digital.2.0.x264',
    audio: [AudioCodec.ac3],
  ),
];

const languages = [
  _Case(
    'Dune.Part.Two.2024.MULTi.VFF.2160p.WEB-DL.HDR10+.DV.EAC3.Atmos.H265-TFA',
    title: 'Dune Part Two',
    multi: true,
    langs: {'fr'},
    hdr: {_hdr10p, _dv},
  ),
  _Case(
    'Le.Comte.de.Monte-Cristo.2024.TRUEFRENCH.1080p.WEB-DL.EAC3.5.1.H264-FW',
    title: 'Le Comte de Monte-Cristo',
    langs: {'fr'},
    channels: '5.1',
  ),
  _Case(
    'Asterix.2023.FRENCH.1080p.WEB.H264-FiDELiO',
    langs: {'fr'},
    source: Source.webdl,
  ),
  _Case('Amelie.FRENCH.2001.1080p.BluRay.x264', title: 'Amelie', year: 2001),
  _Case('Movie.2023.VF2.1080p.WEB-DL.x264-GROUP', langs: {'fr'}),
  _Case('Movie.2023.VFQ.1080p.WEB-DL.x264-GROUP', langs: {'fr'}),
  _Case(
    'Some.Movie.2022.VOSTFR.1080p.WEB.x264',
    langs: <String>{},
    subs: {'fr'},
  ),
  _Case(
    'Movie.2021.iTALiAN.1080p.WEBRip.x264-Dr4gon',
    langs: {'it'},
    group: 'Dr4gon',
  ),
  _Case(
    'Movie.2021.ITA.ENG.1080p.BluRay.x264-MIRCrew',
    langs: {'it', 'en'},
    group: 'MIRCrew',
  ),
  _Case(
    'Movie.2022.GERMAN.DL.1080p.BluRay.x264-DETAiLS',
    langs: {'de'},
    group: 'DETAiLS',
  ),
  _Case(
    'Movie.2022.German.AC3.1080p.WEBRip.x264-HQXD',
    langs: {'de'},
    audio: [AudioCodec.ac3],
  ),
  _Case(
    'Movie 2021 Hindi Dubbed 1080p WEB-DL x264',
    langs: {'hi'},
    dubbed: true,
  ),
  _Case(
    'Movie (2021) Dual Audio [Hindi-English] 720p BluRay x264 ESubs',
    langs: {'hi', 'en'},
    dual: true,
    subs: {'en'},
  ),
  _Case(
    'Deadpool 2016 x264 720p BluRay Eng Subs Dual Audio Hindi 5 1 English 5 1 Downloadhub',
    langs: {'hi', 'en'},
    subs: {'en'},
    dual: true,
    group: '',
  ),
  _Case(
    'Deadpool (2016) 720p BluRay x264 [Dual Audio] [Hindi (Line Audio) - English] ESubs - Downloadhub',
    langs: {'hi', 'en'},
    dual: true,
    subs: {'en'},
    group: 'Downloadhub',
  ),
  _Case(
    'Deadpool (2016) 2160p [4K] BluRay SDR [HINDI-ENG-5.1] 10bit HEVC - PeruGuy.mkv',
    langs: {'hi', 'en'},
    channels: '5.1',
    bit: 10,
    group: 'PeruGuy',
    hdr: <HdrFormat>{},
  ),
  _Case('Pushpa.The.Rule.2024.Telugu.1080p.WEB-DL.DD+5.1.x264', langs: {'te'}),
  _Case('KGF.Chapter.2.2022.Kannada.1080p.WEB-DL.x264', langs: {'kn'}),
  _Case('Movie.2023.Malayalam.1080p.WEB-DL.x264', langs: {'ml'}),
  _Case('Movie.2022.SPANISH.1080p.WEB-DL.x264', langs: {'es'}),
  _Case(
    'Movie (2022) [1080p] Latino Castellano Ingles [Dual Audio]',
    langs: {'es', 'en'},
    dual: true,
  ),
  _Case(
    'Movie.2022.1080p.WEB-DL.Dual.Latino.Ingles.x264',
    langs: {'es', 'en'},
    dual: true,
  ),
  _Case(
    'Deadpool [4K UHD 2160p HEVC X265][DTS 5.1 Castellano DTS 5.1-Ingles+Subs][ES-EN]',
    title: 'Deadpool',
    langs: {'es', 'en'},
    audio: [AudioCodec.dts],
  ),
  _Case('Movie.2023.PORTUGUESE.1080p.WEB-DL.x264', langs: {'pt'}),
  _Case('Movie.2023.1080p.WEB-DL.DUAL.PT-BR.x264', langs: {'pt'}, dual: true),
  _Case('Filme.2023.1080p.WEB-DL.DUBLADO.x264', langs: {'pt'}, dubbed: true),
  _Case('Movie.2023.RUSSIAN.1080p.WEB-DL.x264', langs: {'ru'}),
  _Case('Movie.2023.1080p.BluRay.Rus.Eng.x264', langs: {'ru', 'en'}),
  _Case(
    'Your.Name.2016.JAPANESE.1080p.BluRay.x264.DTS-WiKi',
    title: 'Your Name',
    langs: {'ja'},
  ),
  _Case(
    'Squid.Game.S02E01.KOREAN.1080p.NF.WEB-DL.DDP5.1.Atmos.H.264-FLUX',
    title: 'Squid Game',
    langs: {'ko'},
    seasons: [2],
    episodes: [1],
  ),
  _Case('Movie.2023.TURKISH.1080p.WEB-DL.x264', langs: {'tr'}),
  _Case('Dizi.S01E01.1080p.WEB-DL.Turkce', langs: {'tr'}),
  _Case('Movie.2023.ARABIC.1080p.WEB-DL.x264', langs: {'ar'}),
  _Case('Movie 2023 1080p WEB-DL Arabic Sub', langs: <String>{}, subs: {'ar'}),
  _Case(
    'Movie.2023.1080p.WEB-DL.AAC.2.0.Arabic.Subbed',
    langs: <String>{},
    subs: {'ar'},
  ),
  _Case(
    'Movie.2023.1080p.WEB-DL.Sub.ITA.x264',
    langs: <String>{},
    subs: {'it'},
  ),
  _Case('Movie.2019.CHINESE.1080p.WEBRip.x264', langs: {'zh'}),
  _Case('Movie.2019.PLDUB.1080p.WEB-DL.x264', langs: {'pl'}, dubbed: true),
  _Case(
    'Movie.2020.NORDiC.1080p.WEB-DL.H.264-RAPiDCOWS',
    langs: <String>{},
    title: 'Movie',
  ),
  _Case('Movie.2020.1080p.WEB-DL.Multi.Audio.DDP5.1', multi: true),
  _Case('Movie.2020.1080p.BluRay.Dual-Audio.x264', dual: true),
  _Case(
    'Movie.2020.1080p.WEB-DL.Eng.Subs.x264',
    langs: <String>{},
    subs: {'en'},
  ),
  _Case(
    'Movie 2020 1080p WEBRip x264 [MSubs]',
    multi: false,
    langs: <String>{},
  ),
  _Case(
    'X-Men Complete 13 Movie Collection Sci-Fi 2000 - 2020 Eng Rus Multi-Subs 1080p [H264-mp4]',
    multi: false,
    langs: {'en', 'ru'},
    res: _r1080,
  ),
  _Case(
    'Parasite.2019.KORSUB.HDRip.x264-STUTTERSHIT',
    hc: true,
    subs: {'ko'},
    langs: <String>{},
  ),
  _Case('Movie.2020.HC.HDRip.x264', hc: true, source: Source.hdrip),
  _Case('Movie 2020 1080p HDRip HC-ESub x264', hc: true, subs: {'en'}),
  _Case(
    'Movie.2020.720p.HDCAM.HQ.Hindi.Dubbed',
    source: Source.cam,
    langs: {'hi'},
    dubbed: true,
  ),
  _Case(
    'Reacher.S03E07.Si.va.a.Los.Angeles.ITA.ENG.2160p.AMZN.WEB-DL.DDP5.1.DV.HDR.H.265-MeM.GP.mkv',
    title: 'Reacher',
    seasons: [3],
    episodes: [7],
    langs: {'it', 'en'},
    group: 'MeM.GP',
    hdr: {_dv, _hdr10},
  ),
  _Case(
    'Sherlock S01 E01 BluRay 1080p English DD 5.1 x264 ESub - mkvCinemas.mkv',
    title: 'Sherlock',
    seasons: [1],
    episodes: [1],
    langs: {'en'},
    subs: {'en'},
    group: 'mkvCinemas',
  ),
];

const tv = [
  _Case(
    'The.Office.US.S05E14.720p.HDTV.x264-CTU[rarbg]',
    title: 'The Office US',
    seasons: [5],
    episodes: [14],
    source: Source.hdtv,
    group: 'CTU',
    pack: false,
  ),
  _Case(
    'Game.of.Thrones.S08E06.The.Iron.Throne.1080p.AMZN.WEB-DL.DDP5.1.H.264-GoT',
    title: 'Game of Thrones',
    seasons: [8],
    episodes: [6],
    group: 'GoT',
  ),
  _Case(
    'Breaking.Bad.S05E16.Felina.1080p.BluRay.x264-ROVERS',
    title: 'Breaking Bad',
    seasons: [5],
    episodes: [16],
  ),
  _Case(
    'Friends.1x05.The.One.With.The.East.German.Laundry.Detergent.DVDRip.XviD-SAiNTS',
    title: 'Friends',
    seasons: [1],
    episodes: [5],
    langs: <String>{},
    source: Source.dvd,
  ),
  _Case(
    'The Simpsons 35x01 720p HDTV x264',
    title: 'The Simpsons',
    seasons: [35],
    episodes: [1],
  ),
  _Case('Show.Name.1x01-02.720p.HDTV', episodes: [1, 2]),
  _Case(
    'Show.Name.S01E01E02.1080p.WEB.H264-GGEZ',
    title: 'Show Name',
    seasons: [1],
    episodes: [1, 2],
  ),
  _Case(
    'Show.Name.S02E01-E03.720p.WEB-DL.AAC2.0.H.264-NTb',
    seasons: [2],
    episodes: [1, 2, 3],
    channels: '2.0',
  ),
  _Case('Show.Name.S03E09-10.1080p.WEB.h264-GRP', episodes: [9, 10]),
  _Case(
    'Show.Name.S01.1080p.WEB-DL.DDP5.1.H.264-NTb',
    seasons: [1],
    episodes: [],
    pack: true,
    complete: false,
  ),
  _Case(
    'Stranger.Things.S04.COMPLETE.2160p.NF.WEB-DL.DDP5.1.Atmos.DV.HDR.H.265-FLUX',
    title: 'Stranger Things',
    seasons: [4],
    pack: true,
    complete: false,
  ),
  _Case(
    'Breaking Bad S01-S05 Complete Series 1080p BluRay x265 10bit AAC 5.1-Silence',
    title: 'Breaking Bad',
    seasons: [1, 2, 3, 4, 5],
    pack: true,
    complete: true,
    group: 'Silence',
  ),
  _Case(
    'Friends.Complete.Series.1080p.BluRay.x265-GROUP',
    title: 'Friends',
    seasons: [],
    complete: true,
  ),
  _Case(
    'The.Sopranos.Season.1-6.Complete.1080p.BluRay.x264',
    title: 'The Sopranos',
    seasons: [1, 2, 3, 4, 5, 6],
    complete: true,
  ),
  _Case(
    'Show Name Season 1 1080p WEB-DL',
    title: 'Show Name',
    seasons: [1],
    pack: true,
  ),
  _Case(
    'Show Name Season 2 Episode 5 720p HDTV',
    seasons: [2],
    episodes: [5],
    pack: false,
  ),
  _Case(
    'The Wire Seasons 1 - 5 1080p BluRay',
    title: 'The Wire',
    seasons: [1, 2, 3, 4, 5],
  ),
  _Case('Show.Name.S01-S03.1080p.WEB-DL', seasons: [1, 2, 3], pack: true),
  _Case('Show Name S01-03 1080p WEB-DL', seasons: [1, 2, 3]),
  _Case('Show Name S01 - S02 720p', seasons: [1, 2]),
  _Case(
    'Doctor.Who.2005.S13E01.1080p.WEB-DL.AAC2.0.H.264-NTb',
    title: 'Doctor Who',
    year: 2005,
    seasons: [13],
    episodes: [1],
  ),
  _Case(
    'The.Last.of.Us.S01E03.Long.Long.Time.2160p.HMAX.WEB-DL.DDP5.1.Atmos.DV.HDR.H.265-FLUX',
    title: 'The Last of Us',
    episodes: [3],
    res: _r2160,
  ),
  _Case(
    'House.of.the.Dragon.S02E08.1080p.WEB.H264-SuccessfulCrab',
    title: 'House of the Dragon',
    group: 'SuccessfulCrab',
  ),
  _Case(
    'The.Boys.S04E01.Department.of.Dirty.Tricks.1080p.AMZN.WEB-DL.DDP5.1.H.264-FLUX',
    title: 'The Boys',
    seasons: [4],
    episodes: [1],
  ),
  _Case(
    'Shogun.2024.S01E10.A.Dream.of.a.Dream.2160p.DSNP.WEB-DL.DDP5.1.DV.HDR.H.265-NTb',
    title: 'Shogun',
    year: 2024,
    episodes: [10],
  ),
  _Case('9-1-1.S07E01.720p.HDTV.x264-SYNCOPY', title: '9-1-1', seasons: [7]),
  _Case('The.100.S07E16.1080p.WEB.H264-GGEZ', title: 'The 100'),
  _Case('24.S01E01.720p.BluRay.x264', title: '24', seasons: [1]),
  _Case(
    'Show.Name.S01E05.REPACK.1080p.WEB.H264-GRP',
    repack: true,
    episodes: [5],
  ),
  _Case(
    'Show Name - S01E05 - Episode Title [1080p]',
    title: 'Show Name',
    episodes: [5],
  ),
  _Case(
    'Show.Name.Saison.2.FRENCH.1080p.WEB.x264',
    seasons: [2],
    langs: {'fr'},
  ),
  _Case('Serie.Temporada.1.Completa.1080p', seasons: [1]),
  _Case(
    'Shingeki no Kyojin 2nd Season [BD 1080p]',
    title: 'Shingeki no Kyojin',
    seasons: [2],
    source: Source.bluray,
  ),
  _Case('Show.Name.E05.1080p.WEB', episodes: [5], seasons: [], abs: 5),
  _Case(
    'Show Name (2019) S01 1080p WEBRip x265',
    year: 2019,
    seasons: [1],
    pack: true,
  ),
  _Case('Show.Name.S01.E01.1080p.WEB', seasons: [1], episodes: [1]),
  _Case(
    'Show.Name.S01.COMPLETE.720p.HDTV.x264',
    seasons: [1],
    pack: true,
    complete: false,
  ),
  _Case(
    'The.Office.US.Complete.Series.S01-S09.1080p.BluRay',
    title: 'The Office US',
    seasons: [1, 2, 3, 4, 5, 6, 7, 8, 9],
    complete: true,
  ),
  _Case(
    'Avatar The Last Airbender (2005) Complete Series 1080p',
    title: 'Avatar The Last Airbender',
    complete: true,
  ),
  _Case('Seinfeld Complete', title: 'Seinfeld', complete: true),
  _Case(
    'Les.Simpson.Integrale.FRENCH.720p.HDTV',
    title: 'Les Simpson',
    complete: true,
    langs: {'fr'},
  ),
  _Case('Show Name All Seasons 1080p', title: 'Show Name', complete: true),
  _Case(
    'show.name.s01e05.the.cam.girl.1080p.web.h264-ggez',
    title: 'show name',
    source: Source.webdl,
    episodes: [5],
  ),
  _Case('Show.S01E03.The.Cam.Girl.1080p.WEB-DL', source: Source.webdl),
  _Case(
    'The.Mandalorian.S03.2160p.DSNP.WEB-DL.DDP5.1.Atmos.DV.HDR.H.265-FLUX',
    title: 'The Mandalorian',
    seasons: [3],
    pack: true,
  ),
  _Case(
    'Stranger Things Season 4 Complete 1080p NF WEB-DL',
    seasons: [4],
    complete: false,
  ),
  _Case('Show.Name.S01E01v2.1080p.WEB', episodes: [1]),
];

const anime = [
  _Case(
    '[Group] Title 01 ~ 12 [1080p]',
    title: 'Title',
    episodes: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
    pack: true,
  ),
  _Case(
    '[SubsPlease] Jujutsu Kaisen - 05 (1080p) [A1B2C3D4].mkv',
    title: 'Jujutsu Kaisen',
    seasons: [],
    episodes: [5],
    abs: 5,
    group: 'SubsPlease',
    res: _r1080,
    container: 'mkv',
  ),
  _Case(
    '[HorribleSubs] One Piece - 1071 [1080p].mkv',
    title: 'One Piece',
    abs: 1071,
    group: 'HorribleSubs',
  ),
  _Case(
    '[SubsPlease] Spy x Family S2 - 05 (1080p) [ABCDEF12].mkv',
    title: 'Spy x Family',
    seasons: [2],
    episodes: [5],
  ),
  _Case(
    '[Erai-raws] Kimetsu no Yaiba - 05v2 [1080p][Multiple Subtitle].mkv',
    title: 'Kimetsu no Yaiba',
    episodes: [5],
    group: 'Erai-raws',
  ),
  _Case(
    '[DB] Kimetsu no Yaiba - 01-26 [Dual Audio 10bit 1080p][HEVC-x265]',
    title: 'Kimetsu no Yaiba',
    pack: true,
    dual: true,
    bit: 10,
    codec: _h265,
  ),
  _Case(
    '[SubsPlease] Frieren (01-28) (1080p) [Batch]',
    title: 'Frieren',
    pack: true,
  ),
  _Case(
    '[Judas] Vinland Saga - S02E05 [1080p][HEVC x265 10bit][Multi-Subs].mkv',
    title: 'Vinland Saga',
    seasons: [2],
    episodes: [5],
    multi: false,
    bit: 10,
  ),
  _Case(
    '[ASW] Dandadan - 12 [1080p HEVC x265 10Bit][AAC]',
    title: 'Dandadan',
    abs: 12,
    audio: [AudioCodec.aac],
  ),
  _Case(
    '[EMBER] Chainsaw Man (2022) (Season 1) [BDRip] [1080p Dual Audio HEVC 10 bits DDP]',
    title: 'Chainsaw Man',
    year: 2022,
    seasons: [1],
    pack: true,
    source: Source.bluray,
    dual: true,
    bit: 10,
    audio: [AudioCodec.eac3],
  ),
  _Case(
    '[Anime Time] Naruto Shippuden (001-500) [Dual Audio][1080p][HEVC 10bit x265][AAC][Eng Sub]',
    title: 'Naruto Shippuden',
    group: 'Anime Time',
    pack: true,
    dual: true,
    subs: {'en'},
    langs: <String>{},
  ),
  _Case(
    '[Yameii] Oshi no Ko - 11 [English Dub] [CR WEB-DL 1080p] [0A1B2C3D]',
    title: 'Oshi no Ko',
    abs: 11,
    dubbed: true,
    langs: {'en'},
    source: Source.webdl,
  ),
  _Case(
    '[SubsPlease] Bleach - Sennen Kessen-hen - Soukoku-tan - 01 (1080p) [12345678].mkv',
    title: 'Bleach - Sennen Kessen-hen - Soukoku-tan',
    abs: 1,
  ),
  _Case('One Piece Episode 1071 1080p', title: 'One Piece', abs: 1071),
  _Case(
    '[Golumpa] Attack on Titan - 87 (Shingeki no Kyojin) [FuniDub 1080p x264 AAC]',
    title: 'Attack on Titan',
    abs: 87,
  ),
  _Case(
    '[Erai-raws] Shingeki no Kyojin - The Final Season - 28 [1080p][ABCD1234]',
    abs: 28,
  ),
];

void main() {
  for (final (label, cases) in [
    ('movies', movies),
    ('languages', languages),
    ('tv', tv),
    ('anime', anime),
  ]) {
    group(label, () {
      for (final c in cases) {
        test(c.name, () => _check(c));
      }
    });
  }

  test('fixture count', () {
    expect(
      movies.length + languages.length + tv.length + anime.length,
      greaterThanOrEqualTo(150),
    );
  });

  group('edge cases', () {
    test('empty and plain names', () {
      expect(parseRelease('').title, '');
      expect(parseRelease('   ').hasEpisodeInfo, isFalse);
      final plain = parseRelease('Just A Title');
      expect(plain.title, 'Just A Title');
      expect(plain.resolution, Resolution.unknown);
      expect(plain.quality, '');
    });

    test('raw is kept verbatim', () {
      const name = '  Movie.2019.1080p.WEB-DL.mkv ';
      expect(parseRelease(name).raw, name);
    });

    test('quality label', () {
      expect(
        parseRelease('Movie.2019.1080p.WEB-DL.x264').quality,
        '1080p WEB-DL',
      );
      expect(parseRelease('Movie.2019.2160p.BluRay.REMUX').quality, '4K REMUX');
    });

    test('isTenBit', () {
      expect(parseRelease('Movie.2019.1080p.x265.10bit').isTenBit, isTrue);
      expect(parseRelease('Movie.2019.2160p.HDR.x265').isTenBit, isTrue);
      expect(parseRelease('Movie.2019.1080p.x264').isTenBit, isFalse);
    });

    test('value equality and toString', () {
      const name =
          'Show.S01E02.1080p.WEB-DL.DDP5.1.Atmos.DV.HDR.H.265-FLUX.mkv';
      final a = parseRelease(name), b = parseRelease(name);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(parseRelease('Show.S01E03.1080p.WEB-DL.mkv')));
      expect(a.toString(), contains('1080p WEB-DL'));
      expect(a.toString(), contains('-FLUX'));
      expect(a.seasons, isA<List<int>>());
      expect(() => a.seasons.add(3), throwsUnsupportedError);
      expect(a.hdr.clear, throwsUnsupportedError);
    });

    test('toString lists every set flag', () {
      final r = ParsedRelease(
        raw: 'x',
        title: 'X',
        year: 2020,
        seasons: [1],
        episodes: [2],
        absoluteEpisode: 2,
        isSeasonPack: true,
        isCompleteSeries: true,
        bitDepth: 10,
        atmos: true,
        channels: '5.1',
        languages: {'en'},
        subtitleLanguages: {'ar'},
        multiAudio: true,
        dualAudio: true,
        dubbed: true,
        hardcodedSubs: true,
        proper: true,
        repack: true,
        extended: true,
        imax: true,
        threeD: true,
        container: 'mkv',
        sizeBytes: 10,
        seeders: 3,
        provider: 'P',
        debridCached: false,
      );
      expect(
        r.toString(),
        allOf([
          contains('abs 2'),
          contains('pack'),
          contains('complete'),
          contains('10bit'),
          contains('Atmos'),
          contains('subs ar'),
          contains('multi'),
          contains('dual'),
          contains('dub'),
          contains('HC'),
          contains('PROPER'),
          contains('REPACK'),
          contains('EXTENDED'),
          contains('IMAX'),
          contains('3D'),
          contains('.mkv'),
          contains('10B'),
          contains('3 seeds'),
          contains('via P'),
          contains('uncached'),
        ]),
      );
    });

    test('enum helpers', () {
      expect(Source.cam.isPreRelease, isTrue);
      expect(Source.screener.isPreRelease, isTrue);
      expect(Source.webdl.isPreRelease, isFalse);
      expect(AudioCodec.dtsX.isDts, isTrue);
      expect(AudioCodec.eac3.isDts, isFalse);
      expect(Resolution.p2160.label, '4K');
      expect(Resolution.p1080.lines, 1080);
      expect(VideoCodec.h265.label, 'HEVC');
      expect(HdrFormat.dolbyVision.label, 'DV');
    });

    test('languageName', () {
      expect(languageName('ar'), 'Arabic');
      expect(languageName('EN'), 'English');
      expect(languageName('xx'), 'XX');
    });
  });

  test('parses 1,000 names well under 50 ms', () {
    final names = [
      for (final list in [movies, languages, tv, anime])
        for (final c in list) c.name,
    ];
    final batch = [for (var i = 0; i < 1000; i++) names[i % names.length]];
    // Warm up the JIT, then take the best of a few runs.
    for (final n in batch) {
      parseRelease(n);
    }
    var best = Duration.zero;
    for (var run = 0; run < 5; run++) {
      final sw = Stopwatch()..start();
      for (final n in batch) {
        parseRelease(n);
      }
      sw.stop();
      if (run == 0 || sw.elapsed < best) best = sw.elapsed;
    }
    expect(best, lessThan(const Duration(milliseconds: 50)));
  });
}
