# release_parser

Pure-Dart parser for torrent / debrid release names and Stremio addon stream
texts. No dependencies, no I/O.

```dart
import 'package:release_parser/release_parser.dart';

final r = parseRelease('Show.S01E02.1080p.WEB-DL.DDP5.1.Atmos.DV.HDR.H.265-FLUX.mkv');
r.title;        // Show
r.seasons;      // [1]
r.episodes;     // [2]
r.quality;      // 1080p WEB-DL
r.hdr;          // {dolbyVision, hdr10}
r.audioCodecs;  // [eac3]
r.group;        // FLUX
r.container;    // mkv

// One Stremio stream object (Torrentio, Knightcrawler, Comet, MediaFusion,
// StremThru, Jackettio, Peerflix, Orion layouts).
final s = parseAddonStream(
  name: '[RD+] Torrentio\n4k DV | HDR',
  title: 'Movie.2024.2160p.WEB-DL.DDP5.1.DV.HDR.H.265-GROUP\n'
      '👤 245 💾 15.2 GB ⚙️ ThePirateBay\nMulti Audio / 🇬🇧 / 🇫🇷',
  filename: null, // behaviorHints.filename when present
);
s.seeders;       // 245
s.sizeBytes;     // 16320875725
s.provider;      // ThePirateBay
s.languages;     // {en, fr}
s.debridCached;  // true

coversEpisode(r, season: 1, episode: 2); // true (also for packs / ranges)
```

## API

- `ParsedRelease parseRelease(String name)` — never throws.
- `ParsedRelease parseAddonStream({String? name, String? title, String? description, String? filename})`
  — release name is `filename` ?? the first video-file line ?? the `📄` line ??
  the first plain line; tags missing from it are filled from the other lines
  and the addon name; size / seeders / provider / flag languages / debrid
  cache state come from the emoji (`💾 👤 ⚙️ 🔎 🔍 🔗 ☁️ 🌐 👂 💬`) or
  `Size:` / `Seeders:` / `Source:` / `Languages:` lines.
- `bool coversEpisode(ParsedRelease r, {required int season, required int episode, int? absoluteEpisode})`
  — exact episode, multi-episode files, season packs / ranges, complete
  series, absolute-numbered anime. `r.hasEpisodeInfo` tells "unknown" from
  "wrong".
- `String languageName(String code)` — `ar` → `Arabic`.
- Enums: `Resolution`, `Source`, `VideoCodec`, `HdrFormat`, `AudioCodec`.

`ParsedRelease` fields: `raw, title, year, seasons, episodes, absoluteEpisode,
isSeasonPack, isCompleteSeries, resolution, source, videoCodec, bitDepth, hdr,
audioCodecs, atmos, channels, languages, subtitleLanguages, multiAudio,
dualAudio, dubbed, hardcodedSubs, group, proper, repack, extended, imax,
threeD, container, sizeBytes, seeders, provider, debridCached` plus
`quality`, `hasEpisodeInfo`, `isTenBit`.

## How it works

One pass over separator-split tokens with table lookups (`src/vocabulary.dart`),
so 1,000 names parse in ~12 ms on the VM. The title ends at the first tag;
a year right before that tag is the release year, so `Blade Runner 2049 2017`
and `1917 2019` keep their numbers. Short ambiguous tags (`CAM`, `TS`, `DV`,
`HC`, 3-letter language codes) only count in scene upper case, and an
episode title after `S01E05` is skipped, so `The Cam Girl` is not a camrip.

## Limitations

- Daily shows (`2024.01.15`), `Part 1/2` and multi-season files
  (`S01E10-S02E01`) are not parsed as episodes.
- Absolute anime numbers need an anime-style name (`[Group] Title - 05`);
  mapping them to season/episode needs metadata (pass `absoluteEpisode`).
- Language detection is word-based; words in episode titles that are also
  language names after the first tag can be misread.
