# swarm

Pure-Dart BitTorrent helpers for Kinora.

```dart
final magnet = Magnet.parse('magnet:?xt=urn:btih:…&dn=…&tr=…'); // hex or base32 → lowercase hex
final link = Magnet(infoHash: hash, name: 'Release', trackers: trackers).toString();

final trackers = await TrackerList(cacheFile: File('$cacheDir/trackers.txt')).load();
final stats = await TrackerScraper().scrape(hashes, trackers: trackers); // ≤ 2.5 s
print(stats[hash]?.seeders);
```

- `Magnet`: BEP 9 (`xt=urn:btih:` hex/base32, `urn:btmh:` v2, `dn`, `tr`, `xl`, `ws`, `x.pe`),
  `MagnetFormatException` on bad input.
- `TrackerScraper`: UDP trackers per BEP 15 (≤74 hashes per packet, one retransmit, connection ids reused
  for a minute, IPv4/IPv6) and HTTP(S) trackers via `/announce` → `/scrape` (bencoded). All trackers run
  concurrently; results are merged by max per field and returned at the deadline even if some trackers are
  still silent. Never throws.
- `TrackerList`: downloads ngosang's `trackers_best.txt` (injectable source), caches it in a file for 24 h,
  falls back to the stale cache and then to `defaultTrackers` when offline.

Tests use an in-process fake UDP tracker and a fake HTTP tracker on loopback; no network needed.
