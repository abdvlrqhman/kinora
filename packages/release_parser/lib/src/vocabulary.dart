// Lower-case token tables used by the parser. Package-private (not exported).
import 'enums.dart';
import 'languages.dart';

/// File extensions treated as a container.
const containers = {
  'mkv', 'mp4', 'avi', 'm4v', 'mov', 'wmv', 'webm', 'flv', 'mpg', 'mpeg', //
  'm2ts', 'iso', 'ts', 'vob', 'ogm',
};

/// Token separators (code units). `-`, `+` and `:` stay inside tokens.
const separators = {
  0x20, 0x09, 0x2E, 0x5F, 0x5B, 0x5D, 0x28, 0x29, 0x7B, 0x7D, 0x2C, 0x7C, //
  0x2F, 0x5C, 0x3B, 0x22, 0x2A, 0x3010, 0x3011, 0x300C, 0x300D,
};

/// Splits compound tokens such as `HINDI-ENG-5.1`.
final compoundSeparator = RegExp('[-+]');

const resolutions = {
  '240p': Resolution.p480, '360p': Resolution.p480, '480p': Resolution.p480, //
  '480i': Resolution.p480, '540p': Resolution.p576, '576p': Resolution.p576,
  '576i': Resolution.p576, '720p': Resolution.p720, '1080p': Resolution.p1080,
  '1080i': Resolution.p1080, '1440p': Resolution.p1440,
  '2160p': Resolution.p2160, '4320p': Resolution.p4320,
};

/// Used only when no explicit `NNNNp` is present.
const implicitResolutions = {
  '4k': Resolution.p2160, 'uhd': Resolution.p2160, '8k': Resolution.p4320, //
  'fhd': Resolution.p1080, 'qhd': Resolution.p1440,
};

/// Maps a line count (or the larger of width/height buckets) to a rung.
Resolution resolutionForLines(int lines) => lines >= 4000
    ? Resolution.p4320
    : lines >= 2000
    ? Resolution.p2160
    : lines >= 1400
    ? Resolution.p1440
    : lines >= 1000
    ? Resolution.p1080
    : lines >= 700
    ? Resolution.p720
    : lines >= 540
    ? Resolution.p576
    : Resolution.p480;

const sources = {
  'remux': Source.remux, 'bdremux': Source.remux, 'bd-remux': Source.remux, //
  'uhdremux': Source.remux,
  'cam': Source.cam, 'camrip': Source.cam, 'cam-rip': Source.cam,
  'hdcam': Source.cam, 'hd-cam': Source.cam, 'hqcam': Source.cam,
  'ts': Source.telesync, 'hdts': Source.telesync, 'hd-ts': Source.telesync,
  'telesync': Source.telesync,
  'pdvd': Source.telesync,
  'tsrip': Source.telesync,
  'ts-rip': Source.telesync, 'hdtsrip': Source.telesync,
  'tc': Source.telecine, 'hdtc': Source.telecine, 'hd-tc': Source.telecine,
  'telecine': Source.telecine,
  'scr': Source.screener,
  'screener': Source.screener,
  'dvdscr': Source.screener,
  'dvdscreener': Source.screener, 'dvd-scr': Source.screener,
  'bdscr': Source.screener, 'webscr': Source.screener,
  'bluray': Source.bluray, 'blu-ray': Source.bluray, 'bdrip': Source.bluray,
  'bd-rip': Source.bluray, 'brrip': Source.bluray, 'br-rip': Source.bluray,
  'bd': Source.bluray, 'bd25': Source.bluray, 'bd50': Source.bluray,
  'webrip': Source.webrip, 'web-rip': Source.webrip, 'webdlrip': Source.webrip,
  'web-dlrip': Source.webrip, 'webcap': Source.webrip,
  'web-dl': Source.webdl, 'webdl': Source.webdl, 'web': Source.webdl,
  'hdrip': Source.hdrip, 'hd-rip': Source.hdrip,
  'hdtv': Source.hdtv, 'pdtv': Source.hdtv, 'sdtv': Source.hdtv,
  'tvrip': Source.hdtv, 'tv-rip': Source.hdtv, 'hdtvrip': Source.hdtv,
  'dsr': Source.hdtv, 'dsrip': Source.hdtv, 'satrip': Source.hdtv,
  'dthrip': Source.hdtv,
  'dvd': Source.dvd, 'dvdrip': Source.dvd, 'dvd-rip': Source.dvd,
  'dvd5': Source.dvd,
  'dvd9': Source.dvd,
  'dvdr': Source.dvd,
  'dvd-r': Source.dvd,
  'ntsc': Source.dvd, 'pal': Source.dvd,
  'amzn': Source.webdl, 'nf': Source.webdl, 'dsnp': Source.webdl,
  'hmax': Source.webdl, 'atvp': Source.webdl, 'hulu': Source.webdl,
  'pcok': Source.webdl, 'pmtp': Source.webdl, 'stan': Source.webdl,
  'crav': Source.webdl,
};

/// When several sources appear, the earliest in this list wins.
const sourcePriority = [
  Source.remux,
  Source.cam,
  Source.telesync,
  Source.telecine,
  Source.screener, //
  Source.bluray, Source.webrip, Source.webdl, Source.hdrip, Source.hdtv,
  Source.dvd,
];

/// Bare `WEB` and streaming-service tags lose to any explicit source.
const lowPriorityWeb = {
  'web',
  'amzn',
  'nf',
  'dsnp',
  'hmax',
  'atvp',
  'hulu',
  'pcok',
  'pmtp',
  'stan', //
  'crav',
};

/// Short tags that only count when written in upper case ("The Cam Girl").
const strictCase = {'cam', 'ts', 'tc', 'scr', 'dv', 'hc', 'pal', 'bd'};

const codecs = {
  'x264': VideoCodec.h264, 'h264': VideoCodec.h264, 'avc': VideoCodec.h264, //
  'x265': VideoCodec.h265, 'h265': VideoCodec.h265, 'hevc': VideoCodec.h265,
  'av1': VideoCodec.av1, 'vp9': VideoCodec.vp9, 'vc1': VideoCodec.vc1,
  'vc-1': VideoCodec.vc1, 'mpeg2': VideoCodec.mpeg2, 'mpeg-2': VideoCodec.mpeg2,
  'xvid': VideoCodec.xvid, 'divx': VideoCodec.xvid,
};

/// When several codecs appear, the earliest in this list wins.
const codecPriority = [
  VideoCodec.av1, VideoCodec.h265, VideoCodec.h264, VideoCodec.vc1, //
  VideoCodec.vp9, VideoCodec.mpeg2, VideoCodec.xvid,
];

const bitDepths = {
  '8bit': 8,
  '8-bit': 8,
  '10bit': 10,
  '10-bit': 10,
  '10bits': 10,
  '12bit': 12, //
  '12-bit': 12, 'hi10': 10, 'hi10p': 10,
};

const hdrFormats = {
  'hdr': HdrFormat.hdr10, 'hdr10': HdrFormat.hdr10, //
  'hdr10+': HdrFormat.hdr10Plus, 'hdr10plus': HdrFormat.hdr10Plus,
  'hdr+': HdrFormat.hdr10Plus,
  'dv': HdrFormat.dolbyVision, 'dovi': HdrFormat.dolbyVision,
  'dolbyvision': HdrFormat.dolbyVision, 'hlg': HdrFormat.hlg,
};

const audioCodecs = {
  'truehd': AudioCodec.trueHd, 'true-hd': AudioCodec.trueHd, //
  'dtsx': AudioCodec.dtsX, 'dts-x': AudioCodec.dtsX, 'dts:x': AudioCodec.dtsX,
  'dts-hd': AudioCodec.dtsHd, 'dtshd': AudioCodec.dtsHd,
  'dts-hdma': AudioCodec.dtsHd, 'dts-ma': AudioCodec.dtsHd,
  'dtsma': AudioCodec.dtsHd, 'dts-hd-ma': AudioCodec.dtsHd,
  'dts': AudioCodec.dts, 'dts-es': AudioCodec.dts,
  'eac3': AudioCodec.eac3, 'e-ac3': AudioCodec.eac3, 'e-ac-3': AudioCodec.eac3,
  'eac-3': AudioCodec.eac3, 'ddp': AudioCodec.eac3, 'dd+': AudioCodec.eac3,
  'ddpa': AudioCodec.eac3,
  'ac3': AudioCodec.ac3, 'ac-3': AudioCodec.ac3, 'dd': AudioCodec.ac3,
  'dolby digital': AudioCodec.ac3,
  'aac': AudioCodec.aac, 'aac-lc': AudioCodec.aac, 'he-aac': AudioCodec.aac,
  'flac': AudioCodec.flac, 'opus': AudioCodec.opus, 'mp3': AudioCodec.mp3,
  'pcm': AudioCodec.pcm, 'lpcm': AudioCodec.pcm,
};

const channelWords = {'2ch': '2.0', '6ch': '5.1', '7ch': '6.1', '8ch': '7.1'};

/// Boolean tags.
enum Flag {
  proper,
  repack,
  extended,
  imax,
  threeD,
  multi,
  dual,
  dubbed,
  hardcoded, //
  complete,
  completeSeries,
}

const flags = {
  'proper': Flag.proper, 'repack': Flag.repack, 'repack2': Flag.repack, //
  'rerip': Flag.repack, 'extended': Flag.extended, 'imax': Flag.imax,
  '3d': Flag.threeD, 'hsbs': Flag.threeD, 'h-sbs': Flag.threeD,
  'sbs': Flag.threeD, 'half-sbs': Flag.threeD, 'hou': Flag.threeD,
  'h-ou': Flag.threeD, 'half-ou': Flag.threeD,
  'multi': Flag.multi, 'multi-audio': Flag.multi, 'multiaudio': Flag.multi,
  'multilang': Flag.multi, 'multi-lang': Flag.multi,
  'dual': Flag.dual, 'dual-audio': Flag.dual, 'dualaudio': Flag.dual,
  'dubbed': Flag.dubbed, 'dub': Flag.dubbed, 'dublado': Flag.dubbed,
  'pldub': Flag.dubbed,
  'hc': Flag.hardcoded, 'hcsub': Flag.hardcoded, 'hcsubs': Flag.hardcoded,
  'hc-sub': Flag.hardcoded, 'hc-subs': Flag.hardcoded,
  'hardsub': Flag.hardcoded, 'hardsubs': Flag.hardcoded,
  'hardcoded': Flag.hardcoded, 'korsub': Flag.hardcoded,
  'kor-sub': Flag.hardcoded,
  'complete': Flag.complete, 'integrale': Flag.completeSeries,
  'intégrale': Flag.completeSeries,
};

/// Single tokens naming a subtitle language.
const subtitleWords = {
  'esub': 'en', 'esubs': 'en', 'engsub': 'en', 'engsubs': 'en', //
  'eng-sub': 'en', 'eng-subs': 'en', 'vostfr': 'fr', 'subfrench': 'fr',
  'korsub': 'ko', 'kor-sub': 'ko',
};

/// Words that turn the language before (or after) them into a subtitle
/// language: "Eng Subs", "Sub ITA", "Multi Subs".
const subtitleMarkers = {
  'sub', 'subs', 'subtitle', 'subtitles', 'subbed', 'legendado', 'legendas', //
};

/// "Multi-Subs" and friends: subtitles only, never multi audio.
const multiSubWords = {
  'msub', 'msubs', 'multi-subs', 'multisub', 'multisubs', 'multi-sub', //
};

/// Two-word tags → the single token they stand for.
const bigrams = {
  'web dl': 'web-dl', 'web rip': 'webrip', 'blu ray': 'bluray', //
  'hd rip': 'hdrip', 'hd cam': 'hdcam', 'hd ts': 'hdts', 'hd tc': 'hdtc',
  'dvd rip': 'dvdrip', 'h 264': 'h264', 'h 265': 'h265', 'x 264': 'x264',
  'x 265': 'x265', '8 bit': '8bit', '10 bit': '10bit', '10 bits': '10bit',
  '12 bit': '12bit', 'dolby vision': 'dolbyvision', 'hdr10 plus': 'hdr10+',
  'dolby digital': 'dolby digital', 'dolby atmos': 'atmos',
  'dts hd': 'dts-hd', 'dts x': 'dtsx', 'dts ma': 'dts-hd', 'true hd': 'truehd',
  'dual audio': 'dual-audio', 'multi audio': 'multi-audio', 'aac lc': 'aac',
  'real proper': 'proper', 'all seasons': 'integrale',
};

/// Words after "complete" that make it a pack marker.
const completeKinds = {
  'series', 'collection', 'boxset', 'box', 'season', 'seasons', //
};

/// Words after "complete" that mean a full disc image.
const discWords = {'bluray', 'blu-ray', 'uhd', 'bd', 'dvd', 'bdmv', 'iso'};

/// Tags with no field of their own that still end a title when upper case.
const _titleOnly = {
  'unrated', 'uncut', 'remastered', 'internal', 'limited', 'readnfo', //
  'nordic', 'hybrid',
};

/// Every known single-token tag.
final Set<String> vocabulary = {
  ...resolutions.keys, ...implicitResolutions.keys, ...sources.keys, //
  ...codecs.keys, ...bitDepths.keys, ...hdrFormats.keys, ...audioCodecs.keys,
  ...channelWords.keys, ...flags.keys, ...subtitleWords.keys,
  ...subtitleMarkers, ...multiSubWords, 'atmos', ..._titleOnly,
};

/// Tags that only end a title when upper case (scene style).
const weakWords = {
  'cam', 'ts', 'tc', 'scr', 'bd', 'pal', 'ntsc', 'web', 'amzn', 'nf', 'dsnp', //
  'hmax', 'atvp', 'hulu', 'pcok', 'pmtp', 'stan', 'crav', 'dv', 'hc', 'dd',
  'proper', 'repack', 'repack2', 'rerip', 'extended', 'imax', 'unrated',
  'uncut', 'remastered', 'dubbed', 'dub', 'dual', 'multi', 'complete',
  'internal', 'limited', 'readnfo', 'nordic', 'hybrid', 'sub', 'subs',
  'subbed', 'subtitle', 'subtitles', 'legendado', 'legendas', '3d', 'sbs',
  'hsbs', 'hou', 'esub', 'esubs', 'vostfr', 'dublado', 'pldub', 'atmos',
  'msub', 'msubs', 'multi-subs', 'multisub', 'multisubs', 'multi-sub',
  'opus', 'flac', 'avc', 'mp3', 'pcm', 'dsr', 'hlg',
};

/// Words that look like a trailing `-GROUP` but are not one.
const notGroups = {
  'dl',
  'rip',
  'hd',
  'ma',
  'es',
  'en',
  'lc',
  'eng',
  'ita',
  'mkv',
  'mp4',
  'avi', //
};

/// Whether every `-`-separated part is a two-letter language code (`ES-EN`).
bool isCodeList(String g) {
  final parts = g.split('-');
  return parts.length > 1 &&
      parts.every((p) => p.length == 2 && isoCodes.contains(p.toLowerCase()));
}
