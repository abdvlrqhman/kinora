# Kinora — design plan (v3, 2026-11-09)

Torrent + debrid streaming/downloading app for **iPhone and Android**, modeled on
[donbytyqi/scenebox](https://github.com/donbytyqi/scenebox) but rebuilt with better methods.
Everything is local (no accounts). Public repo `abdvlrqhman/kinora`; everything is built by GitHub Actions (no local or Mac builds). English UI.
SceneBox's license forbids reuse: nothing is copied, only the architecture idea.

## 1. Locked decisions

| Area | Choice | Why |
|---|---|---|
| UI | Flutter (one codebase, iOS + Android) | Only option that ships both without a Mac; Android builds/tests on this server, iOS on GitHub macOS runners |
| Torrent engine | Own Flutter FFI plugin over **libtorrent 2.1.2** built with vcpkg in CI (C API + native HTTP stream server) | Best peer connectivity available. `libtorrent_flutter` was evaluated: its source repo and prebuilt-binary releases are gone (404), so it can't build |
| Player | **media_kit** (libmpv + libass) | Every codec/container, full ASS styling, all mpv properties (sub/audio delay, filters, track metadata, chapters, cache tuning) |
| HTTPS / debrid downloads | **background_downloader** | URLSession background on iOS, WorkManager/UIDT on Android, pause/resume, stall detection; maintained (9.6.6, Nov 2026) |
| Liquid glass | `liquid_glass_renderer` (shader-based) + blur fallback on weak GPUs | Real refraction look on both platforms |
| State / DB | Riverpod, drift (SQLite), flutter_secure_storage for keys | Local-first, typed, testable |
| Casting | Own pure-Dart DLNA package (SSDP + AVTransport SOAP) with Samsung extensions | TV pulls straight from the app's stream server |
| Distribution | iOS: unsigned IPA, signed on-device by SideStore (iPhone is on iOS 27.2, TrollStore can't install there); Android: per-ABI APKs signed with a fixed release key. Both from GitHub Releases | |

## 2. Data flow

```
Addons you add (catalog/meta/stream/subtitles)    TMDB · Cinemeta · Kitsu · Trakt(opt)
              │                                               │
   SourceHub: parallel query → parse → episode-validate → dedupe
              │
   Ranker: live swarm scrape + subtitle fit + device/TV playability + debrid cache
              │  "Best" (with reasons) / full list
     ┌────────┴──────────┐
 libtorrent session    debrid HTTPS
 (deadline window)        │
     └────────┬───────────┘
   Native stream server  http://<lan-ip>:<port>/s/<infohash>/<file>  (+ /sub/<id>.srt)
     ┌────────┼─────────────┬───────────────┐
  Player     Downloads     Samsung TV       Storage manager
 (media_kit) (same session) (DLNA)          (delete anything)
```

Stream, download and cast are one URL from one server. "Keep it" turns a running
stream into a download without re-downloading.

## 3. Better than SceneBox (method by method)

| SceneBox | Ours |
|---|---|
| uTP, UPnP, NAT-PMP, LSD all **off**; 150 connections | uTP + TCP, UPnP/NAT-PMP port mapping, LSD, PEX, DHT on; per-torrent connection cap tuned for mobile; encryption allowed (not forced) |
| DHT bootstraps from scratch every launch | DHT state + session state persisted → peers found in seconds on next launch |
| Static tracker list | Tracker list refreshed daily (best-of lists) + trackers merged from every release sharing the infohash |
| Seeders read from addon emoji text (stale, cached) | **Live UDP tracker scrape (BEP 15)**: up to ~70 infohashes per packet across several trackers, ~1 s, real seeders/leechers right now |
| Fixed 96 MB read-ahead | Read-ahead sized from bitrate (size ÷ duration) × target seconds, bounded by free space |
| Index pieces fetched on demand | First + last pieces get top deadline at start (MP4 moov / MKV cues) — same pieces give the OpenSubtitles file hash for exact subtitle matches |
| Work starts on Play | Warm start: opening an episode pre-resolves releases, scrapes swarms, fetches torrent metadata for the top pick; next episode pre-warms near the end credits |
| Stream server in Swift on main app | Stream server inside the native engine (C++, zero Dart copies, keeps serving the TV while the UI is backgrounded) |
| 17 fixed subtitle languages, one provider | All ISO-639 languages, 7+ providers, ranked per release (see §5) |

## 4. "Best release" per episode

1. Gather releases from all enabled addons in parallel (per-addon timeout, health tracked).
2. Parse every name (resolution, source, codec, HDR/DV, audio codec/channels/languages, group, size, season/episode/pack).
3. **Validate the episode**: reject wrong season/episode; for packs, resolve the exact file index (from addon `fileIdx`, else metadata file list).
4. Live swarm scrape + debrid cache check.
5. Subtitle fit: query subtitle providers once per episode, match subtitle release names / file hash to each release, in your language order.
6. Device fit: decodable on this phone (HEVC 10-bit, DV profile, AV1), and castable to your TV when a TV is selected.
7. Score → **Best** with one-line reasons ("1080p WEB-DL · 214 seeds · Arabic subs match · plays on TV"). One tap plays it; the full list stays one tap away with filters.

Scoring weights live in one tested module (`ranking/`), with fixtures of real release names.

## 5. Subtitles

- **Providers**: embedded tracks, OpenSubtitles v3 addon, OpenSubtitles.com REST (hash match), SubDL, SubSource, Wyzie (aggregator), Podnapisi, Jimaku (anime), any Stremio subtitle addon you add, local file.
- **None enabled by default, no keys in the app or repo.** Providers are a registry; the user enables each one and enters its own key in Settings (stored in Keychain/Keystore).
- **Picker**: languages with counts → tap a language → all its subtitles, embedded first, then ranked by hash match > release-name match > rating/downloads; tags for SDH/HI, forced, source, FPS.
- **Auto**: your language order (e.g. Arabic → English); forced-only when audio already matches.
- **Best fit, always**: a subtitle must be for this exact episode (season/episode parsed from its name, wrong ones rejected) and is ranked by file-hash match > same release group + source + resolution > same FPS > duration within tolerance > rating/downloads. Before showing it as "matched", the first lines are checked against speech/embedded-subtitle timing; out-of-sync ones are auto-shifted or ranked down.
- **Remembers your choice (stream and downloaded alike)**: memory is keyed by show + episode, never by file, so it is the same whether the episode streams or plays from a download.
  - Per show: last audio language, subtitle language, variant (SDH/forced/normal), style, and offset tendency. Every next episode applies them, picking the best-fit subtitle *in that language* for its own release.
  - Per episode: the exact audio track and subtitle file chosen, restored on resume.
  - Downloads fetch best-fit subtitles for your languages (plus the remembered one) next to the video, so offline playback uses the same choice.
- **Fixes**: charset detection (Windows-1256 Arabic etc.) → UTF-8; RTL punctuation fix; ASS kept styled; "sync to this line"; auto-align an external subtitle to an embedded track's timing.
- **Style**: size, font, color, outline, background box, position, per-language memory.
- Optional later: AI translation into a missing language.

## 6. Player (one player for stream and downloads)

Audio tracks named "Arabic · E-AC3 5.1"; preferred/original-audio auto-pick; audio delay; night mode (dynamic range compression) and boost; speed; zoom/crop/aspect; chapters; PiP; gestures (seek, volume, brightness); lock-screen/notification controls; sleep timer; skip intro/recap/credits (chapters + community timestamps); Up Next countdown; continue watching; screenshot.

**Episodes inside the player**: a Next episode button (and Up Next countdown near the credits, with the next episode's best release resolved and pre-buffered in the background); an episode panel in the player to jump to any episode or season without leaving playback; previous episode too. Switching keeps the remembered audio/subtitle choice and saves progress of the one you left.

## 7. Background downloads (researched)

**Android**
- Torrents: foreground service with a progress notification (pause/resume/stop actions), partial wake lock + Wi-Fi lock while active, battery-optimization exemption prompt, resume data saved every 30 s, auto-resume on boot / network return.
- `dataSync` foreground services are capped at 6 h per 24 h for apps targeting Android 15+ ([docs](https://developer.android.com/develop/background-work/services/fgs/timeout)). Since the app is sideloaded (not Play), use `specialUse` type for long torrent sessions, handle `onTimeout()` anyway.
- Debrid/HTTPS: background_downloader → user-initiated data transfer jobs on Android 14+ ([UIDT](https://developer.android.com/develop/background-work/background-tasks/uidt)).

**iOS**
- Debrid/HTTPS: background `URLSession` (continues after the app is suspended or killed). Most reliable path on iPhone.
- Torrents: iOS suspends apps after ~30 s. Proven sideload approach (iTorrent, actively maintained): opt-in audio keep-alive + optional location keep-alive services. On iOS 26+ also `BGContinuedProcessingTask` (user-started, system progress UI; community reports it can expire early, so it's a bonus, not the base).
- Honest limit: torrent downloads on iPhone stay best-effort in background; debrid downloads are solid.

**Streams that finish become downloads**: when a streamed episode/movie is 100% on the device (watched or just fully buffered), it is moved into Downloads automatically (no re-download), registered with its show/episode, and its best-fit subtitles for your languages are saved next to it. On by default; Settings › Downloads has the switch. Streams that didn't finish follow the stream-cache rule (deleted when you leave, or kept N hours).

**Both**: queue with Wi-Fi-only, storage cap, free-space guard, per-file priorities, auto-download next episode, auto-delete watched (opt-in).

## 8. Samsung TV casting

- Discovery: SSDP multicast; fallback unicast probe of the subnet for Samsung's DMR description (needed on iOS if the multicast entitlement isn't available; TrollStore builds get the entitlement).
- Control: AVTransport (SetAVTransportURI, Play/Pause/Seek/Stop, GetPositionInfo polling) + RenderingControl (volume).
- Subtitles: Samsung `CaptionInfo.sec` header + `sec:CaptionInfoEx` in DIDL-Lite, served as SRT from our server.
- Playability: per-model codec table; ranking prefers castable releases while a TV is selected.
- Target TV: Samsung 5 Series 43" (Full HD). Cast profile: ≤1080p, H.264 first (HEVC 8-bit second), no 10-bit/HDR/DV, audio AAC/AC3/E-AC3/MP3 (no DTS/TrueHD), SRT subtitles. Verify on the TV in Phase 4.

## 9. Local data & storage

- SQLite: library, watch progress, downloads, settings, addon list, ranking cache.
- Storage screen: size per show / season / episode, delete any; caches by type (stream buffer, subtitles, metadata, images, logs) with sizes and one-tap clear; auto-clean rules.
- Backup: export/import a JSON file (move to a new phone without accounts).
- Diagnostics stay on device; "Export diagnostics" button. No telemetry.

## 10. Netflix-level UX

Profiles (avatars, kids mode, PIN), billboard with muted trailer, rows (Continue, Top 10, Trending, Because you watched, New episodes, your own), My List, smart downloads, shuffle "Play something", first-run wizard (languages → addons → optional debrid/TMDB keys → find TV), Arabic RTL + English UI.

## 11. Repo layout & engineering

```
app/                       Flutter app (features/, services/, core/)
packages/engine/           FFI plugin: libtorrent C API + stream server (C++)
packages/dlna/             pure Dart: SSDP, SOAP, Samsung extras
packages/release_parser/   pure Dart, heavy fixture tests
packages/subtitles/        providers, charset, matching, sync
.github/workflows/         ci (analyze+test) · engine (libtorrent per ABI, cached) · android (APKs) · ios (IPA + .tipa) · release (on tag)
```
Lints strict, unit tests per package, golden tests for key screens, integration test for search → play.

## 12. Phases

| # | Milestone | Estimate |
|---|---|---|
| 0 | Public repo, monorepo, CI green, libtorrent built for Android ABIs + iOS, glass design kit | 3–4 days |
| 1 | Search → Best release → plays (torrent + debrid) on both phones | ~1.5 weeks |
| 2 | Full player + subtitles system | ~1.5 weeks |
| 3 | Downloads (background both platforms), Keep it, storage manager | ~1 week |
| 4 | Samsung TV casting | ~1 week |
| 5 | Netflix-level home, profiles, Trakt, polish, backup | ~1.5 weeks |

Total ≈ 7–9 weeks. Device testing is the bottleneck.

## 13. Answers (2026-11-09)

- iPhone on iOS 27.2 → SideStore install; `BGContinuedProcessingTask` available.
- UI: English. Subtitle/audio language order: set by the user on first run (nothing preset).
- TV: Samsung 5 Series 43".
- Keys: user-entered only (SubSource, SubDL, Wyzie available for dev tests in gitignored `.env.local`).
- Name: Kinora, bundle/application id `io.github.abdvlrqhman.kinora`.

## 14. Status (2026-11-09)

Built and verified in CI on every push:

| Area | State | Verified by |
|---|---|---|
| Engine (libtorrent 2.1.2, range server, claims, move, per-file progress) | done | native E2E on Linux (seed → magnet → byte-exact ranges → move → resume) |
| Sources (Stremio addons), resolver (live scrape, subtitle fit, ranking) | done | unit tests + emulator E2E |
| Player (mpv, own RTL subtitle rendering, tracks by language, sync, speed, night mode, chapters skip, next/prev/Up Next, versions, PiP on Android, audio focus/interruptions) | done | emulator E2E (plays from a live swarm, subtitles render, next episode) |
| Subtitles (SubDL, SubSource, Wyzie, OpenSubtitles, Jimaku, Stremio addons; charset, ads, RTL, matching) | done | 287 package tests, live provider tests run once with real keys |
| Downloads (torrent + debrid, background, claims for season packs, free-space guard, completed streams kept) | done | emulator E2E (both streamed episodes kept; an explicit download of its own torrent lands in Downloads and plays offline) |
| Casting (DLNA, Samsung profile, captions, pick a TV before playing, keep-alive) | done | emulator E2E: a fake Samsung TV on :9197 is added by address, receives the stream URL, pulls the whole video over the Wi-Fi address with DLNA headers, and fetches the captions; real TV not yet tried |
| Liquid glass | done | real glass only with Vulkan/Metal; a launch that draws nothing switches to frosted (unit test); the emulator E2E runs the same launch check |
| UI (Home, Search, Title, Onboarding, Settings, Downloads, Player) | done, polishing | widget tests + golden screenshots reviewed by a design judge |

Reviews applied: code review (25 findings), QA journeys (30), UX (30).

Decided against:
- Trakt sync: needs an account, and Kinora has none by design (everything local).

Not built yet (not requested; candidates for later):
- Profiles / kids mode: sources carry no reliable maturity ratings to filter by.
- AI subtitle translation: needs a cloud key or a large on-device model.
- iOS picture-in-picture: needs AVPlayer; mpv renders into a Flutter texture.

After a restart: torrent downloads continue when Kinora opens (they need the
app running). On Android a notification says how many are waiting; HTTP
downloads continue on their own through the system download services.
