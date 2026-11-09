import 'package:http/http.dart' as http;

import '../cancel.dart';
import '../errors.dart';
import '../language.dart';
import '../models.dart';
import '../provider_http.dart';
import 'common.dart';

/// Any Stremio subtitles addon, e.g. `https://opensubtitles-v3.strem.io`.
///
/// Calls `/subtitles/{type}/{id}/{extra}.json` with `videoHash`,
/// `videoSize` and `filename` extras. Ids: `tt0903747` (movie),
/// `tt0903747:1:1` (episode) or `kitsu:{id}:{episode}`. Language filtering
/// happens client-side. Extra fields of the OpenSubtitles v3 addon
/// (release name, FPS, season/episode) are used when present.
final class StremioSubtitlesProvider implements SubtitleProvider {
  /// [url] is the addon's manifest URL or base URL.
  StremioSubtitlesProvider({
    required Uri url,
    String? name,
    http.Client? client,
    Duration timeout = const Duration(seconds: 15),
    Clock? clock,
    Sleep? sleep,
  }) : _base = _baseOf(url),
       displayName = name ?? url.host,
       _http = ProviderHttp(
         providerId: 'stremio:${url.host}',
         client: client,
         timeout: timeout,
         maxConcurrent: 2,
         clock: clock,
         sleep: sleep,
       );

  final Uri _base;
  final ProviderHttp _http;

  @override
  final String displayName;

  static Uri _baseOf(Uri url) {
    var path = url.path;
    if (path.endsWith('/manifest.json')) {
      path = path.substring(0, path.length - '/manifest.json'.length);
    }
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return url.replace(path: path);
  }

  @override
  String get id => _http.providerId;

  @override
  bool get requiresKey => false;

  @override
  Set<ProviderCapability> get capabilities => const {
    ProviderCapability.imdbSearch,
    ProviderCapability.kitsuSearch,
    ProviderCapability.hashSearch,
    ProviderCapability.movieSupport,
    ProviderCapability.tvSupport,
  };

  @override
  Future<List<SubtitleResult>> search(
    SubtitleQuery query, {
    CancelToken? cancel,
  }) async {
    final videoId = _videoId(query);
    if (videoId == null) return const [];
    final type = query.isEpisode ? 'series' : 'movie';
    final extra = [
      if (query.fileHash != null) 'videoHash=${_enc(query.fileHash!)}',
      if (query.fileSize != null) 'videoSize=${query.fileSize}',
      if (query.releaseNames.isNotEmpty)
        'filename=${_enc(query.releaseNames.first)}',
    ].join('&');
    final path = [
      _base.path,
      'subtitles',
      type,
      _enc(videoId),
      // Keys/values are already encoded; "=" and "&" stay literal.
      if (extra.isNotEmpty) extra else null,
    ].nonNulls.join('/');
    final json = asJsonMap(
      await _http.json(
        'GET',
        // Build the path by hand: Uri would re-encode the "%".
        Uri.parse('${_base.origin}$path.json'),
        cancel: cancel,
      ),
      id,
    );
    final out = <SubtitleResult>[];
    final seen = <String>{};
    for (final s in jsonObjects(json.list('subtitles'))) {
      final r = _parse(s, query);
      if (r != null &&
          seen.add(r.id) &&
          wantedLanguage(r.language, query.languages)) {
        out.add(r);
      }
    }
    return out;
  }

  // Stremio encodes path segments with encodeURIComponent rules.
  static String _enc(String s) => Uri.encodeComponent(s);

  String? _videoId(SubtitleQuery q) {
    if (q.isEpisode) {
      if (q.season == null || q.episode == null) return null;
      if (q.imdbId != null) return '${q.imdbId}:${q.season}:${q.episode}';
      if (q.kitsuId != null) return 'kitsu:${q.kitsuId}:${q.episode}';
      return null;
    }
    return q.imdbId ?? (q.kitsuId == null ? null : 'kitsu:${q.kitsuId}');
  }

  SubtitleResult? _parse(Map<String, Object?> s, SubtitleQuery query) {
    final url = s.str('url');
    final language = Language.parse(s.str('lang'));
    if (url == null || language == null) return null;
    final subId = s.str('id') ?? url;
    final release = s.str('movieReleaseName');
    final fileName = s.str('subtitleFileName');
    final fpsMilli = s.integer('fpsMilli');
    final season = s.integer('season');
    final episode = s.integer('episode');
    final label = s.str('label');
    return SubtitleResult(
      providerId: id,
      id: subId,
      language: language,
      releaseNames: [?release, if (release == null) ?label],
      fileName: fileName,
      fps: fpsMilli == null || fpsMilli <= 0 ? null : fpsMilli / 1000,
      format: SubtitleFormat.fromName(fileName) ?? SubtitleFormat.srt,
      // shortcut: OpenSubtitles v3 marks matches in "m" ("i" = by IMDb id);
      // "h" for hash matches is inferred, undocumented. Verify with a real
      // file hash before relying on it.
      matchedHash: s.str('m') == 'h' ? query.fileHash?.toLowerCase() : null,
      season: season == null || season <= 0 ? null : season,
      episodeFrom: episode == null || episode <= 0 ? null : episode,
      episodeTo: episode == null || episode <= 0 ? null : episode,
      payload: {'url': url},
    );
  }

  @override
  Future<SubtitleDownload> download(
    SubtitleResult result, {
    CancelToken? cancel,
  }) {
    final url = result.payload['url'];
    if (url is! String) {
      throw SubtitleResponseException('missing url', providerId: id);
    }
    return fetchFile(
      _http,
      Uri.parse(url),
      fallbackName: result.fileName ?? '${result.id}.srt',
      cancel: cancel,
    );
  }
}
