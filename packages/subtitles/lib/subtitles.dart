/// Subtitles for Kinora: providers, search + ranking ("best fit" per
/// release), language normalization, charset decoding, format parsing and
/// conversion, timing checks, archives, file hash and an on-disk cache.
///
/// Pure Dart. No provider is enabled by default and no API keys ship with
/// it: every provider takes the user's own credentials.
library;

export 'src/archive.dart'
    show SubtitleFile, archiveKind, extractSubtitle, languageFromFileName;
export 'src/cache.dart' show SubtitleCache;
export 'src/cancel.dart' show CancelToken;
export 'src/charset.dart'
    show
        DecodedText,
        codePagesFor,
        decodeSubtitleBytes,
        decodeWith,
        legacyEncodings,
        scoreDecoding;
export 'src/document.dart'
    show
        Cue,
        SubtitleDocument,
        formatAssTime,
        formatSrtTime,
        plainText,
        stripAssTags;
export 'src/errors.dart';
export 'src/hash.dart' show osHash, osHashChunkSize;
export 'src/language.dart' show Language;
export 'src/matcher.dart' show MatchTier, RankedSubtitle, SubtitleMatcher;
export 'src/models.dart';
export 'src/parsers.dart'
    show assToTags, detectFormat, parseSubtitle, parseTimestamp;
export 'src/provider_http.dart' show Clock, ProviderHttp, Sleep;
export 'src/providers/common.dart' show defaultUserAgent;
export 'src/providers/jimaku.dart' show JimakuProvider;
export 'src/providers/opensubtitles.dart'
    show OpenSubtitlesProvider, toOpenSubtitlesCode;
export 'src/providers/podnapisi.dart' show PodnapisiProvider, toPodnapisiCode;
export 'src/providers/stremio.dart' show StremioSubtitlesProvider;
export 'src/providers/subdl.dart' show SubdlProvider, toSubdlCode;
export 'src/providers/subsource.dart'
    show SubSourceProvider, subSourceLanguages, subSourceNames;
export 'src/providers/wyzie.dart' show WyzieProvider;
export 'src/release.dart'
    show
        ReleaseInfo,
        ReleaseNameParser,
        SourceFamily,
        parseReleaseName,
        sourceFamilyOf;
export 'src/rtl.dart' show RtlMarks, fixRtl;
export 'src/search.dart'
    show
        LoadedSubtitle,
        ProviderState,
        ProviderStatus,
        SubtitleSearch,
        SubtitleSearchUpdate;
export 'src/timing.dart'
    show SyncSuggestion, TimingReport, checkTiming, estimateSync, fpsScales;
