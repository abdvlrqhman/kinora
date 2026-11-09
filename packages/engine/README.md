# kinora_engine

libtorrent 2.1 session + local HTTP range server, as a Flutter FFI plugin.

- `src/kinora_engine.{h,cpp}` — C API (bencoded inputs, JSON outputs). One
  session, an alert thread that caches status and a per-piece bitfield, and a
  small HTTP/1.1 server: each connection moves a window of piece deadlines
  along its read position and streams pieces straight from disk.
- `lib/` — Dart API: `KinoraEngine.start(...)`, `add`, `files`, `statuses`,
  `events`, `openStream` → `StreamHandle.uri()`, `serveFile`, `dispose`.
- Native libs come from the `engine` CI workflow (vcpkg, pinned baseline and
  NDK). `tool/fetch_prebuilt.sh` downloads them for local builds.
- Tests: `flutter test` runs the Dart layer; with `KINORA_ENGINE_LIB` set to a
  host build it also runs `test/native_e2e_test.dart` (seed + magnet download +
  byte-exact range streaming + fast-resume over loopback).
