# stremio

Pure-Dart client for the [Stremio addon protocol](https://github.com/Stremio/stremio-addon-sdk/tree/master/docs).
Kinora ships no content sources; users paste addon URLs and this package talks to them.

```dart
final client = AddonClient(userAgent: 'Kinora/1.0.0', cache: ResponseCache());
final addon = await client.fetchManifest(Uri.parse('stremio://v3-cinemeta.strem.io/manifest.json'));
final meta = await client.meta(addon, 'series', 'tt0903747');

final aggregator = AddonAggregator(client);
final query = aggregator.streams(installedAddons, 'series', 'tt0903747:1:1');
query.results.listen((r) => print('${r.addon.manifest.name}: ${r.items.length}')); // as they arrive
final all = await query.merged; // de-duplicated by infoHash+fileIdx / URL
```

- `parseAddonUrl` accepts `stremio://`, `https://…/manifest.json` or a base URL; config path segments are kept.
- Requests: per-attempt timeout, bounded retries with backoff on 429/5xx/timeouts, one retry with a browser
  User-Agent on 403, cancellation via a `Future<void> cancel`. Errors are the sealed `StremioException` family.
- `DebridKeyRejectedException` when a debrid addon only returns "invalid key" placeholders.
- `AddonAggregator.health` gives last latency, consecutive failures and last error per addon.
- `ResponseCache`: in-memory TTL cache (injectable clock); streams are cached at most 5 minutes.

Tests run offline against fixtures recorded from Cinemeta, Kitsu and OpenSubtitles v3; torrent/debrid
stream fixtures are written from the protocol docs.
