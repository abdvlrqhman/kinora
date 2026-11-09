# Kinora

Stream or download movies and shows from torrents and debrid services with one
player, subtitles from many providers in your languages, and casting to your
TV. iPhone and Android. Everything stays on your device: no accounts.

Design: [DESIGN.md](DESIGN.md) · Plan and decisions: [PLAN.md](PLAN.md)

## Install

Download the latest build from **Releases** (or the newest successful
`app` run under **Actions**, artifacts at the bottom).

**Android**: install `Kinora-arm64-v8a-release.apk` (older 32-bit phones:
`Kinora-armeabi-v7a-release.apk`). Updates install over the previous version.

**iPhone**: the build is unsigned. Install `Kinora.ipa` with
[SideStore](https://sidestore.io) (free Apple ID, refreshes itself every 7
days) or any re-signing tool you trust.

## First run

1. Pick your subtitle languages in order (for example Arabic, then English)
   and whether you prefer original audio.
2. Add sources: Kinora ships with none. Paste the manifest URL of any
   Stremio-compatible addon you choose. Cinemeta (catalogs) and OpenSubtitles
   v3 (subtitles) are offered as one-tap suggestions.
3. Optional: turn on subtitle sites (SubDL, SubSource, Wyzie, OpenSubtitles,
   Jimaku) with your own keys. Keys stay in the Keychain/Keystore.

## What it does

- **Best version, explained**: every episode is matched against all your
  sources, checked live with the trackers, scored for your phone (or your TV
  while casting) and for subtitle fit in your languages. The Play button tells
  you what it picked and why.
- **One player for streams and downloads**: any format, audio tracks named by
  language and channels, subtitles grouped by language (tap a language to see
  every subtitle for it), timing, style, night mode, speed, skip intro, next
  episode and an episode list inside the player, picture-in-picture on
  Android. Your audio/subtitle choice is remembered per show and episode,
  streamed or downloaded.
- **Downloads that keep going**: torrents in a foreground service on Android
  and a background session on iPhone; debrid links through the system
  downloader. Episodes you stream to the end are kept as downloads, with their
  best subtitles saved next to them.
- **Cast to your TV**: DLNA (tuned for Samsung), subtitles included, with a
  check that warns when a version can't play on the TV.
- **Storage under your control**: delete any episode, season or show, and
  clear every cache from Settings › Storage.

## Builds

Everything builds in GitHub Actions; no local toolchain or Mac is needed.

| Workflow | What |
|---|---|
| `app` | Analyze + test the app and every package; Android APKs (signed with a fixed key); unsigned iPhone IPA; end-to-end test on an Android emulator; tag `vX.Y.Z` → GitHub Release |
| `engine` | libtorrent 2.1 + OpenSSL + Boost for Android (arm64, armv7, x86_64), iOS (arm64) and Linux, plus a native end-to-end test of the engine |

## Repository

| Path | What |
|---|---|
| `app/` | The Flutter app |
| `packages/engine` | libtorrent session + HTTP range streaming server (C++ with a Dart FFI layer) |
| `packages/stremio` | Stremio addon protocol client and aggregator |
| `packages/swarm` | Magnet links, live tracker scraping, tracker lists |
| `packages/release_parser` | Release-name parser |
| `packages/ranking` | Picks the best version and explains it |
| `packages/subtitles` | Subtitle providers, matching, charsets, formats |
| `packages/dlna` | TV discovery and control (Samsung extensions) |

## Sources

Kinora is a media player and BitTorrent/HTTP client. It ships with no content
sources, stream addons or API keys: you add the addons and provider keys you
choose. You are responsible for what you access and for following the laws
where you live.

## License

GPL-3.0. Third-party components keep their own licenses.
