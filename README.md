<p align="center">
  <img src="docs/banner.png" alt="Kinora: stream or download movies and shows, with subtitles in your languages, on your phone and on your TV." width="100%">
</p>

<p align="center">
  <a href="https://github.com/abdvlrqhman/kinora/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/abdvlrqhman/kinora?color=B48CFF&labelColor=17141B&label=release"></a>
  <a href="https://github.com/abdvlrqhman/kinora/actions/workflows/app.yml"><img alt="Build and end-to-end tests" src="https://github.com/abdvlrqhman/kinora/actions/workflows/app.yml/badge.svg?branch=main"></a>
  <img alt="iPhone and Android" src="https://img.shields.io/badge/iPhone%20%26%20Android-17141B?logo=flutter&logoColor=B48CFF">
  <a href="LICENSE"><img alt="License: GPL-3.0" src="https://img.shields.io/github/license/abdvlrqhman/kinora?color=17141B&labelColor=17141B"></a>
</p>

<p align="center">
  <a href="https://github.com/abdvlrqhman/kinora/releases/latest/download/Kinora.ipa"><b>Download for iPhone</b></a>
  &nbsp;&nbsp;&nbsp;
  <a href="https://github.com/abdvlrqhman/kinora/releases/latest/download/Kinora-arm64-v8a-release.apk"><b>Download for Android</b></a>
</p>

Kinora plays movies and shows from torrents and debrid services in one player.
For every episode it picks the best version for your screen and your
subtitle languages, and says why. It casts to your TV, keeps what you watch
as downloads, and keeps everything on your phone: no accounts, no tracking.

<p align="center">
  <img src="docs/screens.png" alt="Five Kinora screens: Home with Continue watching, a show's episodes, the list of versions with the best one explained, Downloads, and casting to a TV." width="100%">
</p>

## What it does

- **The best version, explained.** Every episode is matched against all your
  sources and checked live with the trackers. It's then scored for your
  phone, or for your TV while casting, and for subtitles in your languages.
  The Play button says what it picked and why, and every other version is
  one tap away.
- **One player for streams and downloads.** It plays any format, names audio
  tracks by language and channels, and groups subtitles by language. You get
  timing, style, speed, skip intro, next episode and an episode list.
  Swipe for brightness and volume, pinch to zoom, and use picture-in-picture
  on Android. Your audio and subtitle choice is remembered for each show.
- **Subtitles from many sites.** OpenSubtitles works without a key; SubDL,
  SubSource, Wyzie and Jimaku take your own. Lines can be synced with one
  tap: "Line is spoken now".
- **Downloads that keep going.** Torrents keep downloading with the screen
  off, and debrid links go through the system downloader. Episodes you
  stream to the end are kept as downloads, with their best subtitles.
- **Cast to your TV.** DLNA, tuned for Samsung, with subtitles. Kinora warns
  you before casting a version the TV can't play, and rides out Wi-Fi
  hiccups.
- **Liquid Glass.** Real refracting glass on phones that draw with Metal or
  Vulkan, frosted glass on the others.
- **Updates in the app.** Kinora tells you when a new version is out and
  shows what changed. You can turn this off in Settings › About.

## Install

**Android 8 or later**

1. Download [`Kinora-arm64-v8a-release.apk`](https://github.com/abdvlrqhman/kinora/releases/latest/download/Kinora-arm64-v8a-release.apk).
   For an older 32-bit phone, download
   [`Kinora-armeabi-v7a-release.apk`](https://github.com/abdvlrqhman/kinora/releases/latest/download/Kinora-armeabi-v7a-release.apk)
   instead.
2. Open it and allow installs from your browser when Android asks.

Updates install over the previous version and keep your data.

**iPhone with iOS 15 or later**

The iPhone build is unsigned, so it installs through
[SideStore](https://sidestore.io) with your own free Apple ID.

1. Set up SideStore on your iPhone (see its guide).
2. Download [`Kinora.ipa`](https://github.com/abdvlrqhman/kinora/releases/latest/download/Kinora.ipa)
   and open it with SideStore.
3. When Kinora offers an update, tap **Update with SideStore**.

Apps installed with a free Apple ID run for 7 days at a time, and SideStore
refreshes them. If Kinora stops opening, open SideStore and refresh it.

Every release is listed on the [Releases](https://github.com/abdvlrqhman/kinora/releases)
page, with what changed.

## First run

1. Pick your subtitle languages in order (for example Arabic, then English),
   and whether you prefer the original audio.
2. Add your sources. Kinora comes with none: paste the manifest link of any
   Stremio-compatible addon you choose. Cinemeta (catalogs) and OpenSubtitles
   (subtitles) are offered as one-tap suggestions.
3. Optional:
   - Add your own keys for more subtitle sites.
   - Add a TMDB key for cast, photos and "More like this".

   Keys stay in the phone's Keychain or Keystore.

## Privacy

Kinora has no accounts, no analytics and no ads. It only connects to:

- the sources and subtitle sites you add;
- TMDB, if you add a key;
- the torrent swarm, plus a public tracker list it refreshes daily;
- GitHub, once per launch, to check for a new version (you can turn this
  off).

Logs stay on your phone. **Settings › Diagnostics › Copy diagnostics** gives
you a copy to share, with keys and addon links left out.

## Questions

<details>
<summary><b>Kinora doesn't find my TV</b></summary>

- Put the phone on the same Wi-Fi as the TV.
- On iPhone, allow Kinora in **Settings › Privacy & Security › Local
  Network**.
- Still not listed? Enter the TV's address in the cast picker. The TV shows
  it in its network settings.
</details>

<details>
<summary><b>The TV stops or says the video can't play</b></summary>

- Keep the phone on Wi-Fi while casting: the TV plays from the phone.
- Kinora reloads the video on the TV if the TV's player fails. If it keeps
  failing, choose another version: the version list marks the ones the TV
  can play.
</details>

<details>
<summary><b>Downloads stopped after I restarted my phone</b></summary>

Open Kinora once: unfinished torrent downloads need the app running. On
Android, a notification tells you how many are waiting.
</details>

<details>
<summary><b>Where are my downloads?</b></summary>

- **iPhone:** in the Files app, under On My iPhone › Kinora.
- **Both:** Kinora's Downloads tab lists them by show and season. You can
  delete any episode, season or show, and clear every cache in Settings ›
  Storage.
</details>

<details>
<summary><b>The glass looks frosted, not like liquid glass</b></summary>

Real liquid glass needs a phone that draws with Metal (every supported
iPhone) or Vulkan. **Settings › Diagnostics** says which one your phone
uses, and **Try liquid glass again** tests it once more.
</details>

<details>
<summary><b>Subtitles are out of sync</b></summary>

In the player, open **Audio and subtitles**, wait for the line to be said,
and tap **Line is spoken now**. Hold − or + to move the subtitles a whole
second.
</details>

## Build it yourself

Everything builds in GitHub Actions, so you don't need a Mac or a local
toolchain. Fork the repo, and the `app` workflow builds the APKs and the IPA
and runs every test, including the end-to-end tests on an Android emulator
and an iPhone simulator.

To work locally you need [Flutter 3.47.7](https://docs.flutter.dev/install).

```sh
cd app
flutter pub get
flutter analyze
flutter test        # unit, widget and screen (golden) tests
```

A device build also needs the engine's libtorrent libraries. Download them
from a recent `app` or `engine` run. If they have expired after 7 days, run
the `engine` workflow on your fork first. Then unpack them where the app
expects them:

```sh
gh run download <run-id> -n libtorrent-arm64-android -D packages/engine/prebuilt/arm64-android
gh run download <run-id> -n libtorrent-arm64-ios     -D packages/engine/ios/prebuilt
```

| Workflow | What it does |
|---|---|
| `app` | Analyzes and tests the app and every package. Builds the Android APKs and the unsigned iPhone IPA, and runs the end-to-end test on an Android emulator and an iPhone simulator. Tagging `vX.Y.Z` publishes a release. |
| `engine` | Builds libtorrent 2.1 with OpenSSL and Boost for Android, iPhone (and its simulator) and Linux, then runs a native end-to-end test of the engine. |
| `glass` | Checks that real liquid glass draws on an iPhone simulator. |

## Repository

| Path | What |
|---|---|
| [`app/`](app) | The Flutter app |
| [`packages/engine`](packages/engine) | libtorrent session and HTTP range streaming server (C++ with a Dart FFI layer) |
| [`packages/stremio`](packages/stremio) | Stremio addon protocol client and aggregator |
| [`packages/swarm`](packages/swarm) | Magnet links, live tracker scraping, tracker lists |
| [`packages/release_parser`](packages/release_parser) | Release-name parser |
| [`packages/ranking`](packages/ranking) | Picks the best version and explains it |
| [`packages/subtitles`](packages/subtitles) | Subtitle sites, matching, charsets, formats |
| [`packages/dlna`](packages/dlna) | TV discovery and control (Samsung extensions) |
| [`DESIGN.md`](DESIGN.md) | The design system: colors, type, glass, motion |
| [`PLAN.md`](PLAN.md) | Architecture and the decisions behind it |

## Contributing

Bug reports, ideas and pull requests are welcome. See
[CONTRIBUTING.md](CONTRIBUTING.md). To report a security problem, see
[SECURITY.md](SECURITY.md) and don't open a public issue.

## Sources and the law

Kinora is a media player and a BitTorrent and HTTP client. It comes with no
content, no stream addons and no API keys: you add the addons and keys you
choose. You are responsible for what you access, and for following the laws
where you live.

## License and credits

Kinora is free software under the [GPL-3.0](LICENSE). Third-party components
keep their own licenses.

Built with [Flutter](https://flutter.dev),
[libtorrent](https://libtorrent.org), [mpv](https://mpv.io) (through
[media_kit](https://github.com/media-kit/media-kit)) and
[liquid_glass_renderer](https://pub.dev/packages/liquid_glass_renderer).
Type: [Big Shoulders Display](https://fonts.google.com/specimen/Big+Shoulders)
and [Figtree](https://fonts.google.com/specimen/Figtree), both under the SIL
Open Font License.

Powered by [Spacie](https://spacie.net).
