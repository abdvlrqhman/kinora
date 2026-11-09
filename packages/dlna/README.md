# dlna

Pure-Dart DLNA/UPnP casting for Kinora (PLAN.md §8). The TV pulls the video
straight from the app's stream server; this package finds the TV, tells it what
to play, and decides whether a release will play on it.

- **Discovery**: SSDP M-SEARCH (MediaRenderer:1 + `ssdp:all`, three rounds) and
  NOTIFY listening (`DlnaDiscovery.discover`). The fallback without multicast is
  `DlnaDiscovery.probeSubnet`, which probes known description URLs on every host
  of the subnet (Samsung Tizen `:9197/dmr` first, then Samsung 2013–15
  `:7676/smp_N_`, Samsung 2010–12 `:52235/dmr/SamsungMRDesc.xml`,
  `:49152/description.xml`, Sonos `:1400`, `:8080`).
- **Reconnect**: save `DlnaDevice.toJson()`, then call
  `DlnaDiscovery.refresh(DlnaDevice.fromJson(json))`.
- **Control**: `DlnaRenderer` loads media (DIDL-Lite with Samsung
  `sec:CaptionInfoEx` subtitles, with a minimal-DIDL retry). It also handles
  play/pause/stop, seek, volume, mute, position, transport state and sink
  protocols. `watch()` polls the TV and reports `RendererUnreachable` when the
  TV goes away.
- **Stream server**: `dlnaStreamHeaders(mimeType:, captionSrt:)` returns the
  `contentFeatures.dlna.org`, `transferMode.dlna.org`, `CaptionInfo.sec` and
  `Accept-Ranges` headers. Samsung asks for them with `getcaptionInfo.sec: 1`.
- **Playability**: `CastProfile.samsungFullHdTizen`, `CastProfile.genericDlna`
  and `CastProfile.fromSinkProtocols(...)` each give a profile whose
  `canPlay(MediaTraits)` returns a `CastCheck` with reasons.

```dart
final discovery = DlnaDiscovery();
final tv = await discovery.discover(interfaceAddress: wifiIp).first;
final renderer = DlnaRenderer(tv);
await renderer.load(
  Uri.parse('http://$wifiIp:8090/s/<infohash>/0'),
  title: 'Show · S01E01',
  mimeType: CastContainer.mkv.mimeTypeFor(await renderer.sinkProtocols()),
  sizeBytes: 1400000000,
  duration: const Duration(minutes: 42),
  subtitleSrt: Uri.parse('http://$wifiIp:8090/sub/1.srt'),
);
renderer.watch().listen(print);
```

Errors are sealed `DlnaException` subtypes:

- `DlnaUnreachableException`: the TV is off or offline, or the request timed out.
- `DlnaSoapFault`: a UPnP `errorCode` and `errorDescription`.
- `DlnaHttpException`
- `DlnaProtocolException`

## Platform notes

- **Android**: hold a `WifiManager.MulticastLock` while discovering. Without
  it, incoming SSDP packets are dropped.
- **iOS**: multicast needs the `com.apple.developer.networking.multicast`
  entitlement. Without it `discover` emits a `DlnaUnreachableException`, so
  use `probeSubnet`. Both need `NSLocalNetworkUsageDescription` (the Local
  Network permission prompt).

## Development

```sh
source ../../.env.dev
dart format . && dart analyze --fatal-infos && dart test
```

Tests run offline. They use an in-process fake Samsung DMR (HTTP description +
SOAP endpoints) and a fake SSDP responder on 127.0.0.1.

## Still to verify on the real TV (Samsung 5 Series 43")

- The description URL is `:9197/dmr`, and the SSDP response matches the fixture.
- Subtitles show via `sec:CaptionInfoEx` and the `CaptionInfo.sec` header.
  Check which of the two is required, and that a URL with a query string works.
- MKV MIME type: `video/x-matroska` vs `video/x-mkv`. `mimeTypeFor` picks from
  the TV's sink list.
- `Seek` in `H:MM:SS`. Does the TV ignore seeks while `TRANSITIONING`?
- `Play` right after `SetAVTransportURI`. Does the TV need the 701 retry?
- Whether `SetAVTransportURI` works while something is already playing.
- Profile entries: HEVC Main10 over DLNA, XviD AVI, Opus/Vorbis in MKV, HDR
  input on the FHD panel, and the bitrate ceiling for 1080p remuxes.
