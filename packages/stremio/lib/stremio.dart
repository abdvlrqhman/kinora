/// Client for the Stremio addon protocol: manifests, catalogs, metadata,
/// streams and subtitles from user-installed addons, plus parallel
/// aggregation with health tracking.
library;

export 'src/addon.dart' show Addon, parseAddonUrl;
export 'src/aggregator.dart'
    show AddonAggregator, AddonHealth, AddonResult, AggregatedQuery;
export 'src/cache.dart' show ResponseCache;
export 'src/client.dart' show AddonClient, kinoraUserAgent;
export 'src/errors.dart';
export 'src/manifest.dart'
    show AddonManifest, CatalogExtra, ManifestCatalog, ManifestResource;
export 'src/meta.dart' show Episode, MetaDetail, MetaLink, MetaPreview;
export 'src/stream.dart' show StreamItem, dedupeStreams, isDebridKeyRejection;
export 'src/subtitle.dart' show SubtitleItem;
export 'src/video_id.dart' show VideoId;
