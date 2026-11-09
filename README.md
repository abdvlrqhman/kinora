# Kinora

Stream or download movies and series from torrents and debrid services, with one
player for both, casting to DLNA TVs (Samsung tuned), and subtitles from many
providers. iPhone + Android, built with Flutter. Everything stays on the device.

Status: early development. Design: [PLAN.md](PLAN.md).

## Builds

Everything is built by GitHub Actions — no local toolchain needed.

| Workflow | What |
|---|---|
| `engine` | libtorrent + OpenSSL + Boost static libs for Android (arm64, armv7) and iOS (arm64) |
| `app` | analyze + test, Android APKs (arm64, armv7), unsigned iPhone IPA; tag `vX.Y.Z` → GitHub Release |
| `bootstrap` | one-time Flutter project generation |

## Sources

Kinora is a media player and BitTorrent/HTTP client. It ships with no content
sources, addons or API keys: you add the Stremio-compatible addons and provider
keys you choose in Settings. You are responsible for what you access and for
following the laws where you live.

## License

GPL-3.0. Third-party components keep their own licenses.
