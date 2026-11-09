# End-to-end tests

`app_test.dart` runs the real app on a device or emulator. Inside the app
process it starts a fake Stremio source, a fake BitTorrent tracker and a
second engine session that seeds a 14-second test episode. The test then:

1. adds the source by its manifest URL, sees its catalog on Home;
2. resolves and ranks the episode's versions;
3. plays S1 E1 from the torrent stream and checks the video advances;
4. loads the source's English subtitle and checks a line renders;
5. switches to the next episode inside the player (subtitle choice follows);
6. closes the player and checks the fully downloaded stream was kept in
   Downloads.

CI runs it on an Android emulator (`e2e-android` job). Locally:
`flutter test integration_test/app_test.dart -d <device>` (needs the engine
libraries: `packages/engine/tool/fetch_prebuilt.sh`).

`support/fixtures.dart` embeds the test media (generated with ffmpeg:
`testsrc2` 192x108 at 15 fps, a 440 Hz sine, H.264 + AAC in Matroska).
