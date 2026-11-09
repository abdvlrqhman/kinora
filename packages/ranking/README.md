# ranking

Scores the stream candidates for one movie / episode and picks **Best**, with
plain-English reasons ("1080p WEB-DL · 214 seeds · Arabic subtitles match ·
Plays on TV") and warnings ("Few seeds", "DTS audio won't play on TV",
"Large for your connection"). Pure Dart; depends only on `release_parser`.

```dart
import 'package:ranking/ranking.dart';
import 'package:release_parser/release_parser.dart';

final ranked = rank(
  [
    Candidate(
      id: 'abc…:3',
      release: parseAddonStream(name: s.name, title: s.title, filename: s.filename),
      addonId: 'torrentio',
      live: SwarmHealth(seeders: 214, leechers: 30, measuredAt: DateTime.now()),
      subtitleFit: {'ar': 0.95},
    ),
    // …
  ],
  RankPrefs(
    device: DeviceCaps(hdr10: true),
    castTarget: samsungTv, // optional
    subtitleLanguages: ['ar', 'en'],
    maxResolution: Resolution.p1080,
    bandwidthBytesPerSec: 3e6,
    runtimeMinutes: 60,
    originalLanguage: 'en',
  ),
  episode: const EpisodeRef(season: 1, episode: 3),
);
final best = ranked.first; // check best.isRejected when everything failed
print(best.summary);
```

## API

- `List<RankedCandidate> rank(List<Candidate> candidates, RankPrefs prefs, {EpisodeRef? episode, RankWeights weights = RankWeights.standard})`
- Inputs: `Candidate`, `SwarmHealth`, `DeviceCaps` (empty `audio` /
  `containers` = anything), `RankPrefs`, `EpisodeRef` (`absolute` for anime).
- Output: `RankedCandidate { candidate, score, reasons, warnings, rejected,
  isRejected, summary }` with `RankReason` / `RankWarning` (`kind` enum +
  `label`) and `RejectReason`.
- `RankWeights`: every weight, threshold and penalty in one documented const
  object (`RankWeights.standard`).

## Rules

Gates, each applied only when something passing it survives (otherwise the
candidate is kept with a warning and a penalty):

1. wrong season / episode → rejected (names without numbers: warning);
2. not decodable on the phone (resolution, HEVC / 10-bit HEVC, AV1,
   DV-only without HDR10 fallback, main audio codec, container);
3. not playable on the cast target (same checks);
4. CAM / TS / TC / SCR.

Score = `0.35·availability + 0.30·quality + 0.15·audio + 0.15·subtitles +
bonuses − penalties`:

- availability: debrid-cached / direct = 1; else log-scaled seeds saturating
  at 100, live scrape preferred (addon counts × 0.85);
- quality: resolution fit to min(preference, phone, TV) (over the limit ranks
  below under it) + source (remux > bluray > web-dl > webrip > hdrip > hdtv >
  dvd > pre-release); HDR / DV bonus only on a capable screen;
- bitrate (size ÷ runtime): penalised above 80 % of the bandwidth, when
  suspiciously small for the resolution, and in data-saver mode;
- audio: position of the best preferred language (empty = original);
  unwanted dubs warned;
- subtitles: best `subtitleFit` (or subtitles named in the release) in the
  preferred order, first language weighted most; unwanted hardsubs penalised;
- packs (swarm only) −0.05, PROPER / REPACK +0.02.

Ties break on availability, then resolution, then `Candidate.id`.

## Limitations

- `SwarmHealth.measuredAt` is not aged; drop stale scrapes before ranking.
- The cast check uses the release's first audio codec as the default track.
- H.264 10-bit (Hi10P anime) and VP9 / VC-1 are assumed decodable.
