import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:release_parser/release_parser.dart' as rp;
import 'package:subtitles/subtitles.dart';

import '../app/providers.dart';
import '../core/db/database.dart';
import '../core/lang.dart';
import '../core/log.dart';
import '../core/settings.dart';
import 'resolver.dart';
import 'sources.dart';
import 'subtitle_option.dart';

/// A subtitle provider the user can turn on in Settings. None is on by
/// default and Kinora ships no keys.
final class ProviderInfo {
  const ProviderInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.keyLabel,
    this.needsKey = true,
    this.supportsLogin = false,
    this.keyHelp,
  });

  final String id;
  final String name;
  final String description;
  final String keyLabel;
  final bool needsKey;
  final bool supportsLogin;

  /// Where to get a key, in words.
  final String? keyHelp;
}

const subtitleProviderCatalog = [
  ProviderInfo(
    id: freeOpenSubtitlesId,
    name: 'OpenSubtitles',
    description:
        'No key needed. The largest library, through Stremio’s free '
        'OpenSubtitles service.',
    keyLabel: '',
    needsKey: false,
  ),
  ProviderInfo(
    id: 'subdl',
    name: 'SubDL',
    description: 'Large library for movies and shows, many languages.',
    keyLabel: 'API key',
    keyHelp: 'subdl.com › Account › API',
  ),
  ProviderInfo(
    id: 'subsource',
    name: 'SubSource',
    description: 'Strong Arabic and community translations.',
    keyLabel: 'API key',
    keyHelp: 'subsource.net › Profile › API',
  ),
  ProviderInfo(
    id: 'wyzie',
    name: 'Wyzie Subs',
    description: 'Searches several subtitle sites at once.',
    keyLabel: 'API key',
    keyHelp: 'sub.wyzie.io › Dashboard',
  ),
  ProviderInfo(
    id: 'opensubtitles',
    name: 'OpenSubtitles.com with your key',
    description: 'Adds matching the exact file by its fingerprint.',
    keyLabel: 'API key',
    supportsLogin: true,
    keyHelp: 'opensubtitles.com › Profile › API consumers',
  ),
  ProviderInfo(
    id: 'jimaku',
    name: 'Jimaku',
    description: 'Japanese subtitles for anime.',
    keyLabel: 'API key',
    keyHelp: 'jimaku.cc › Account',
  ),
];

/// Maps Kinora's parsed release to the subtitles package's view of it.
ReleaseInfo releaseInfoOf(String name) {
  final r = rp.parseRelease(name);
  return ReleaseInfo(
    title: r.title,
    year: r.year,
    season: r.seasons.isEmpty ? null : r.seasons.first,
    episodes: r.episodes,
    group: r.group,
    source: r.source == rp.Source.unknown ? null : r.source.label,
    resolution: r.resolution == rp.Resolution.unknown
        ? null
        : r.resolution.lines,
    videoCodec: r.videoCodec == rp.VideoCodec.unknown
        ? null
        : r.videoCodec.name,
    isPack: r.isSeasonPack || r.isCompleteSeries,
  );
}

/// Every provider the user enabled (with its key), plus subtitle addons.
final subtitleProvidersProvider = FutureProvider<List<SubtitleProvider>>((
  ref,
) async {
  final settings = ref.watch(settingsProvider);
  final keys = ref.watch(secureKeysProvider);
  final http = ref.watch(httpClientProvider);
  final out = <SubtitleProvider>[];
  for (final id in settings.enabledSubtitleProviders) {
    final c = await keys.read(id);
    final info = subtitleProviderCatalog.where((i) => i.id == id).firstOrNull;
    if (info == null || (info.needsKey && c.apiKey.isEmpty)) continue;
    out.add(switch (id) {
      'subdl' => SubdlProvider(apiKey: c.apiKey, client: http),
      'subsource' => SubSourceProvider(apiKey: c.apiKey, client: http),
      'wyzie' => WyzieProvider(apiKey: c.apiKey, client: http),
      'opensubtitles' => OpenSubtitlesProvider(
        apiKey: c.apiKey,
        username: c.username.isEmpty ? null : c.username,
        password: c.password.isEmpty ? null : c.password,
        userAgent: 'Kinora v$kinoraVersion',
        client: http,
      ),
      'jimaku' => JimakuProvider(apiKey: c.apiKey, client: http),
      freeOpenSubtitlesId => StremioSubtitlesProvider(
        url: Uri.parse('https://opensubtitles-v3.strem.io/manifest.json'),
        name: 'OpenSubtitles',
        client: http,
      ),
      // Podnapisi's site is offline (2026); its client stays in the package.
      _ => throw StateError('unknown provider $id'),
    });
  }
  final addons = await ref.watch(enabledAddonsProvider.future);
  final freeOn = out.any((p) => p is StremioSubtitlesProvider);
  for (final a in addons) {
    // The same service installed as an addon would list everything twice.
    if (freeOn && a.transportUrl.host == 'opensubtitles-v3.strem.io') continue;
    if (a.manifest.resources.any((r) => r.name == 'subtitles')) {
      out.add(
        StremioSubtitlesProvider(
          url: a.transportUrl,
          name: a.manifest.name,
          client: http,
        ),
      );
    }
  }
  return out;
});

/// The search engine over the enabled providers (null when none).
final subtitleSearchProvider = FutureProvider<SubtitleSearch?>((ref) async {
  final providers = await ref.watch(subtitleProvidersProvider.future);
  if (providers.isEmpty) return null;
  final s = ref.watch(settingsProvider);
  return SubtitleSearch(
    providers: providers,
    matcher: SubtitleMatcher(
      parser: releaseInfoOf,
      prefs: SubtitlePrefs(
        languages: [for (final l in s.subtitleLanguages) Language.of(l)],
        preferHearingImpaired: s.preferHearingImpaired,
      ),
    ),
    providerTimeout: const Duration(seconds: 12),
    cache: SubtitleCache(ref.watch(pathsProvider).subtitles),
  );
});

/// All subtitles for one movie/episode in the user's languages (cached a
/// few minutes; shared by ranking, the player and downloads).
final videoSubtitlesProvider = FutureProvider.autoDispose
    .family<SubtitleSearchUpdate?, VideoRef>((ref, video) async {
      final keep = ref.keepAlive();
      final timer = Timer(const Duration(minutes: 5), keep.close);
      ref.onDispose(timer.cancel);
      final search = await ref.watch(subtitleSearchProvider.future);
      final langs = ref.read(settingsProvider).subtitleLanguages;
      if (search == null || langs.isEmpty) return null;
      return search.searchAll(_query(video, langs));
    });

SubtitleQuery _query(VideoRef v, List<String> langs) {
  final isEp = v.season != null && v.episode != null;
  final id = v.mediaId;
  return SubtitleQuery(
    type: isEp ? MediaType.episode : MediaType.movie,
    imdbId: id.startsWith('tt') ? id : null,
    kitsuId: id.startsWith('kitsu:')
        ? int.tryParse(id.substring(6).split(':').first)
        : null,
    season: v.season,
    episode: v.episode,
    languages: [for (final l in langs) Language.of(l)],
  );
}

/// Subtitle fit for the resolver: for each release, the best match in each
/// language among this video's subtitles.
final subtitleFitOverride = subtitleFitProvider.overrideWith(
  (ref) => (video, releaseNames) async {
    final update = await ref.read(videoSubtitlesProvider(video).future);
    final search = await ref.read(subtitleSearchProvider.future);
    if (update == null || search == null) return const {};
    final out = <String, Map<String, double>>{};
    for (final e in releaseNames.entries) {
      final info = releaseInfoOf(e.value);
      final perLang = <String, double>{};
      update.byLanguage.forEach((lang, subs) {
        var best = 0.0;
        for (final s in subs.take(40)) {
          final f = search.matcher.fit(s.result, info);
          if (f > best) best = f;
        }
        if (best > 0) perLang[normalizeLang(lang.code) ?? lang.code] = best;
      });
      out[e.key] = perLang;
    }
    return out;
  },
);

/// Turns this video's subtitles into player options, ranked against the
/// release actually playing. Files load only when picked.
final class PlayerSubtitles {
  PlayerSubtitles(this._ref);
  final Ref _ref;

  Future<List<SubtitleOption>> optionsFor(
    VideoRef video, {
    String? releaseName,
  }) async {
    final update = await _ref.read(videoSubtitlesProvider(video).future);
    final search = await _ref.read(subtitleSearchProvider.future);
    if (update == null || search == null) return const [];
    final info = releaseName == null ? null : releaseInfoOf(releaseName);
    final query = _query(video, _ref.read(settingsProvider).subtitleLanguages);
    final out = <SubtitleOption>[];
    update.byLanguage.forEach((lang, subs) {
      final rated = [
        for (final s in subs)
          (
            sub: s,
            fit: info == null
                ? s.fit
                : search.matcher.fit(s.result, info, query: query),
          ),
      ]..sort((a, b) => b.fit.compareTo(a.fit));
      for (final r in rated.take(60)) {
        final res = r.sub.result;
        out.add(
          SubtitleOption(
            id: 'ext:${res.key}',
            language: normalizeLang(lang.code) ?? lang.code,
            label:
                res.releaseNames.firstOrNull ??
                res.fileName ??
                lang.englishName,
            detail: _providerName(res.providerId, search.providers),
            hearingImpaired: res.hearingImpaired,
            forced: res.forced,
            fit: r.fit,
            provider: res.providerId,
            load: () => _materialize(search, res, query),
          ),
        );
      }
    });
    return out;
  }

  /// Downloads, fixes the charset and writes a UTF-8 file mpv can read.
  Future<String?> _materialize(
    SubtitleSearch search,
    SubtitleResult res,
    SubtitleQuery query,
  ) async {
    try {
      final loaded = await search.load(res, query: query);
      final dir = _ref.read(pathsProvider).subtitles;
      final isAss =
          loaded.document.sourceFormat == SubtitleFormat.ass ||
          loaded.document.sourceFormat == SubtitleFormat.ssa;
      final file = File(
        p.join(
          dir.path,
          'play-${SubtitleCache.keyFor(res)}.${isAss ? 'ass' : 'srt'}',
        ),
      );
      // The folder may have been cleared (Settings › Storage, or iOS).
      await file.parent.create(recursive: true);
      await file.writeAsString(
        isAss ? loaded.document.toAss() : loaded.document.toSrt(),
        encoding: utf8,
      );
      return file.path;
    } on SubtitleException catch (e) {
      Log.w('subtitles', 'load failed ${res.providerId}: $e');
      return null;
    }
  }

  /// Saves the best subtitle per language next to a downloaded video and
  /// returns what was saved (for offline playback).
  Future<List<Map<String, String>>> saveForDownload(
    VideoRef video, {
    required String releaseName,
    required String videoPath,
    List<String> extraLanguages = const [],
  }) async {
    final update = await _ref.read(videoSubtitlesProvider(video).future);
    final search = await _ref.read(subtitleSearchProvider.future);
    if (update == null || search == null) return const [];
    final query = _query(video, _ref.read(settingsProvider).subtitleLanguages);
    final info = releaseInfoOf(releaseName);
    final wanted = {
      ..._ref.read(settingsProvider).subtitleLanguages,
      ...extraLanguages,
    };
    final saved = <Map<String, String>>[];
    final base = p.withoutExtension(videoPath);
    for (final entry in update.byLanguage.entries) {
      final code = normalizeLang(entry.key.code) ?? entry.key.code;
      if (!wanted.any((w) => sameLang(w, code))) continue;
      final ranked =
          entry.value
              .map((s) => (s, search.matcher.fit(s.result, info, query: query)))
              .where((x) => x.$2 > 0)
              .toList()
            ..sort((a, b) => b.$2.compareTo(a.$2));
      // One that fails to load (a pack without this episode): the next best.
      for (final (best, _) in ranked.take(3)) {
        try {
          final loaded = await search.load(best.result, query: query);
          final path = '$base.$code.srt';
          // The torrent may not have created its folder yet.
          await File(path).parent.create(recursive: true);
          await File(path)
              .writeAsString(loaded.document.toSrt(), encoding: utf8);
          saved.add({
            'lang': code,
            'path': path,
            'label': best.result.releaseNames.firstOrNull ?? code,
          });
          break;
        } on SubtitleException catch (e) {
          Log.w('subtitles', 'save for download failed ($code): $e');
        }
      }
    }
    return saved;
  }

  /// How to line the subtitle at [path] up with the one at [reference]
  /// (both files Kinora wrote), or null when they don't match well enough
  /// or the result would run past the video's [duration].
  Future<SubtitleSync?> lineUp(
    String path,
    String reference, {
    required Duration duration,
    required String referenceName,
  }) async {
    final s = await Isolate.run(() {
      final own = _read(path).cues;
      final ref = _read(reference).cues;
      final found = confidentSync(own, ref);
      if (found == null) return null;
      final fixed = SubtitleDocument(
        cues: own,
        sourceFormat: SubtitleFormat.srt,
      ).scale(found.scale).shift(found.offset);
      if (duration > Duration.zero &&
          checkTiming(fixed.cues, duration).exceedsDuration) {
        return null;
      }
      return (offset: found.offset, scale: found.scale);
    });
    return s == null
        ? null
        : (offset: s.offset, scale: s.scale, reference: referenceName);
  }

  /// A copy of the subtitle at [path] with [sync] applied, in Kinora's
  /// subtitle folder (never beside a downloaded video).
  Future<String> corrected(String path, SubtitleSync sync) {
    final dir = _ref.read(pathsProvider).subtitles.path;
    return Isolate.run(() {
      final doc = _read(path).scale(sync.scale).shift(sync.offset);
      final ass = p.extension(path) == '.ass';
      final out = File(
        p.join(
          dir,
          'synced-${p.basenameWithoutExtension(path)}.${ass ? 'ass' : 'srt'}',
        ),
      );
      out.parent.createSync(recursive: true);
      out.writeAsStringSync(ass ? doc.toAss() : doc.toSrt(), encoding: utf8);
      return out.path;
    });
  }

  static SubtitleDocument _read(String path) =>
      parseSubtitle(File(path).readAsStringSync());

  /// What was decided for subtitle [subtitleId] of video [videoId]: lined
  /// up ([sync]), or kept as it is after an Undo ([sync] null). Null when
  /// nothing was decided yet.
  Future<({SubtitleSync? sync})?> storedSync(
    String videoId,
    String subtitleId,
  ) async {
    final db = _ref.read(databaseProvider);
    final row =
        await (db.select(db.keyValues)
              ..where((t) => t.key.equals(_syncKey(videoId, subtitleId))))
            .getSingleOrNull();
    if (row == null) return null;
    try {
      final j = jsonDecode(row.value) as Map<String, Object?>;
      if (j['off'] == true) return (sync: null);
      return (
        sync: (
          offset: Duration(milliseconds: j['o']! as int),
          scale: (j['s']! as num).toDouble(),
          reference: j['ref'] as String? ?? '',
        ),
      );
    } on Object {
      return null;
    }
  }

  /// Remembers [sync] for this subtitle of this video (null: Undo).
  Future<void> saveSync(String videoId, String subtitleId, SubtitleSync? sync) {
    final db = _ref.read(databaseProvider);
    return db
        .into(db.keyValues)
        .insertOnConflictUpdate(
          KeyValuesCompanion.insert(
            key: _syncKey(videoId, subtitleId),
            value: jsonEncode(
              sync == null
                  ? {'off': true}
                  : {
                      'o': sync.offset.inMilliseconds,
                      's': sync.scale,
                      'ref': sync.reference,
                    },
            ),
          ),
        );
  }

  static String _syncKey(String videoId, String subtitleId) =>
      'subsync:$videoId:$subtitleId';

  /// The source's name as people know it ("OpenSubtitles", an add-on's
  /// own name), never an internal id like `stremio:<host>`.
  static String _providerName(String id, List<SubtitleProvider> providers) =>
      subtitleProviderCatalog.where((i) => i.id == id).firstOrNull?.name ??
      providers.where((p) => p.id == id).firstOrNull?.displayName ??
      'A subtitle add-on';
}

final playerSubtitlesProvider = Provider<PlayerSubtitles>(PlayerSubtitles.new);

/// A subtitle's timing lined up with another subtitle of the same video
/// ([reference], by name): its corrected copy's times are scale × own +
/// offset.
typedef SubtitleSync = ({Duration offset, double scale, String reference});

/// Close enough not to bother moving (a translation's own timing style).
bool nearlyInSync(SubtitleSync s) =>
    s.offset.inMilliseconds.abs() < 700 && (s.scale - 1).abs() < 0.0005;

/// "Subtitles moved 2.4 s later" for [s].
String syncSummary(SubtitleSync s) {
  if ((s.scale - 1).abs() >= 0.0005) {
    return 'Subtitles matched to this video’s speed';
  }
  final sec = (s.offset.inMilliseconds.abs() / 1000).toStringAsFixed(1);
  return 'Subtitles moved $sec s ${s.offset.isNegative ? 'earlier' : 'later'}';
}

/// What to line [active] up against: other text subtitles for this video,
/// best fit first. [auto] (unasked): only when [active] isn't made for
/// this version itself, and only against ones that are, from sites
/// without a daily download limit.
List<SubtitleOption> syncReferences(
  List<SubtitleOption> all,
  SubtitleOption active, {
  required bool auto,
  Set<String> skip = const {},
}) {
  const madeForIt = 0.85;
  if (auto && (active.fit ?? 0) >= madeForIt) return const [];
  return [
    for (final s in all)
      if (s.track == null &&
          (s.uri != null || s.load != null) &&
          s.id != active.id &&
          s.label != active.label &&
          !s.forced &&
          !skip.contains(s.id) &&
          (!auto ||
              ((s.fit ?? 0) >= madeForIt && s.provider != 'opensubtitles')))
        s,
  ]..sort((a, b) => (b.fit ?? 0).compareTo(a.fit ?? 0));
}
