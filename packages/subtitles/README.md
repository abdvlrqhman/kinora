# subtitles

The pure-Dart subtitle engine for Kinora (no Flutter). It covers:

- searching seven kinds of provider in parallel;
- picking the **best-fitting** subtitle per language for each release;
- language normalization;
- charset decoding;
- format parsing and conversion;
- timing and sync checks;
- archive extraction;
- the OpenSubtitles file hash;
- an on-disk cache.

No provider is enabled by default and **no API keys ship with this package**.
Every provider takes the user's own credentials. The app keeps them in secure
storage.

## Providers

| Class | Key | Notes |
|---|---|---|
| `OpenSubtitlesProvider` | API key (+ optional login) | REST v1. Hash search (`moviehash`). Logging in raises the download quota. A 406 response becomes `SubtitleQuotaException(resetAt)`. |
| `SubdlProvider` | API key | Downloads are ZIPs. The key SubDL echoes in its URLs is stripped from results. |
| `SubSourceProvider` | API key | Looks up the title first (one per TV season), then lists its subtitles. Downloads are ZIPs, often a whole season. |
| `WyzieProvider` | API key | Aggregates other providers. Its results are deduped against them by release + language + HI. |
| `PodnapisiProvider` | none | Public JSON search. **The site was offline (NXDOMAIN) in Nov 2026.** |
| `JimakuProvider` | API key | Anime, mostly Japanese. The language is read from the file name. |
| `StremioSubtitlesProvider` | none | Any Stremio subtitles addon, e.g. `https://opensubtitles-v3.strem.io`. |

Shared behaviour, via `ProviderHttp`:
- you can inject an `http.Client`, a clock and a sleep function;
- each request has its own timeout;
- 429, 5xx and network errors are retried a bounded number of times with exponential backoff;
- `Retry-After` and `x-ratelimit-reset-after` headers, and SubSource's `retryAfter` body field, are honoured;
- each provider has a concurrency limit and a minimum spacing between requests;
- every call can be cancelled with a `CancelToken`;
- every failure is a typed `SubtitleException`, a sealed hierarchy.

## Usage

```dart
final search = SubtitleSearch(
  providers: [
    SubdlProvider(apiKey: subdlKey),
    StremioSubtitlesProvider(url: Uri.parse('https://opensubtitles-v3.strem.io/manifest.json')),
  ],
  matcher: SubtitleMatcher(parser: myReleaseParser), // app's parser; built-in fallback otherwise
  cache: SubtitleCache(subtitleCacheDir),
);

final query = SubtitleQuery(
  type: MediaType.episode,
  imdbId: 'tt0903747', season: 1, episode: 1,
  languages: [Language.of('ar'), Language.of('en')],
  releaseNames: ['Breaking.Bad.S01E01.720p.BluRay.x264-DEMAND'],
  fileHash: osHash(size, head64k, tail64k),
  fileSize: size, fps: 23.976, durationSec: 3480,
);

await for (final update in search.search(query)) {
  update.counts;        // {Arabic: 17, English: 13}: the picker's language list
  update.byLanguage;    // tap a language -> every subtitle, best fit first
  update.providers;     // pending / done / failed / timedOut per provider
}

final loaded = await search.load(best.result, query: query); // download + unzip + charset + parse
final srtForTv = loaded.document.mapText(fixRtl).toSrt();
```

To rank releases, call `SubtitleMatcher.bestPerLanguage(results, releaseInfo)` for
each candidate release. It returns `Map<Language, RankedSubtitle>`, where
`.fit` is a score from 0 to 1.

### What "best fit" means

`SubtitleMatcher` rejects subtitles made for a different episode. It checks
provider metadata first, then every release name and the file name. A season
pack that contains the episode is kept and flagged `seasonPack`. For movies it
rejects a different year, or a TV episode. A different title only counts
against a subtitle, because titles get localized ("Origen" is Inception in
Spanish).

Subtitles that pass are ranked in this order:

1. file-hash match
2. same release group + source family + resolution
3. same group
4. same source family (WEB, BluRay, DVD, TV and CAM have different timings)
5. same FPS
6. rating and downloads

Some things lower the score:
- **Machine translation** costs about two tiers.
- **HI and forced** are soft preferences (`SubtitlePrefs`), not filters. A forced-only subtitle falls below every full subtitle unless you ask for forced.
- **Uncertain matches** take a small penalty: a season pack, or an episode that couldn't be verified.

Each `RankedSubtitle` carries `tier` and `reasons`, for example
`same release (DEMAND)`, `same FPS`, `machine translated`.

## Text

| API | What it does |
|---|---|
| `decodeSubtitleBytes(bytes, language:)` | Checks for a BOM (UTF-8, UTF-16LE, UTF-16BE), then UTF-16 without a BOM, then strict UTF-8. After that it tries the language's legacy code page: Arabic and Persian use 1256, Hebrew 1255, Cyrillic 1251, Greek 1253, Turkish 1254, Central European 1250, Baltic 1257, Vietnamese 1258, Thai 874, Chinese GBK or Big5, Japanese Shift_JIS, Korean CP949, and everything else 1252. If there is no hint, or the hinted page decodes to implausible text, it scores every candidate page instead. |
| `parseSubtitle(text)` | Reads SRT, WebVTT, ASS/SSA, MicroDVD and MPL2, detecting the format from the content. It tolerates broken files. |
| `SubtitleDocument` | Converts with `toSrt()` (CRLF, for TVs), `toVtt()` and `toAss()`, which keeps the original styles. Also has `shift`, `scale` and `mapText`. |
| `fixRtl` | Adds RLE/PDF or RLM marks to Arabic, Hebrew, Persian and Urdu lines. Can optionally move punctuation that was pre-reversed for LTR players. |
| `checkTiming` | Compares the subtitle's length with the video's. |
| `estimateSync(sub, reference)` | Cross-correlates cue start times against a reference track, such as an embedded one. Returns an offset, an FPS scale (23.976↔25/24) and a confidence. |
| `extractSubtitle(download, season:, episode:, language:)` | Opens ZIPs, nested ZIPs and gzip, and picks the right file. Throws a clear `SubtitleArchiveException` for RAR and 7z. |
| `SubtitleCache(dir)` | Stores raw and converted files. Has `sizeBytes()`, `clear()` and `prune(maxAge:)`. |

## Development

```sh
source ../../.env.dev
dart format . && dart analyze --fatal-infos && dart test   # offline, recorded fixtures
set -a; source ../../.env.local; set +a; dart test -P live # real providers, keys from env
```

The live tests read these environment variables:
- `SUBDL_API_KEY`
- `SUBSOURCE_API_KEY`
- `WYZIE_API_KEY`
- `OPENSUBTITLES_API_KEY`, plus `OPENSUBTITLES_USERNAME` and `OPENSUBTITLES_PASSWORD` if you want to log in
- `JIMAKU_API_KEY`

A provider whose key is missing is skipped.

Generated files and how to rebuild them:

| File | Generated by | Source |
|---|---|---|
| `lib/src/charset_tables.dart` | `tool/gen_charset_tables.py` | Python codecs |
| `lib/src/language_data.dart` | `tool/gen_languages.py` | Debian `iso-codes` (ISO 639-2/3) and Babel (CLDR names) |
| binary test fixtures | `tool/gen_fixtures.py` | — |

Recorded provider responses in `test/fixtures/providers` have had keys and
tokens scrubbed.
