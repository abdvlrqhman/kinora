import 'package:http/http.dart' as http;

import '../cancel.dart';
import '../errors.dart';
import '../language.dart';
import '../models.dart';
import '../provider_http.dart';
import 'common.dart';

/// Podnapisi.net public JSON search (no key). One request per language.
///
/// Note: the site was offline (NXDOMAIN) as of 2026-11; searches then fail
/// with [SubtitleNetworkException] and the orchestrator reports it.
final class PodnapisiProvider implements SubtitleProvider {
  PodnapisiProvider({
    this.userAgent = defaultUserAgent,
    Uri? baseUrl,
    http.Client? client,
    Duration timeout = const Duration(seconds: 15),
    Clock? clock,
    Sleep? sleep,
  }) : _base = baseUrl ?? Uri.parse('https://www.podnapisi.net'),
       _http = ProviderHttp(
         providerId: 'podnapisi',
         client: client,
         timeout: timeout,
         maxConcurrent: 2,
         clock: clock,
         sleep: sleep,
       );

  final String userAgent;
  final Uri _base;
  final ProviderHttp _http;

  @override
  String get id => 'podnapisi';

  @override
  String get displayName => 'Podnapisi';

  @override
  bool get requiresKey => false;

  @override
  Set<ProviderCapability> get capabilities => const {
    ProviderCapability.textSearch,
    ProviderCapability.movieSupport,
    ProviderCapability.tvSupport,
  };

  @override
  Future<List<SubtitleResult>> search(
    SubtitleQuery query, {
    CancelToken? cancel,
  }) async {
    final title = query.title;
    if (title == null) return const [];
    final List<String?> langs = query.languages.isEmpty
        ? const [null]
        : {for (final l in query.languages) ?toPodnapisiCode(l)}.toList();
    if (langs.isEmpty) return const [];
    final out = <SubtitleResult>[];
    final seen = <String>{};
    // shortcut: first result page per language only (50 results).
    for (final lang in langs) {
      final url = _base.replace(
        path: '/subtitles/search/advanced',
        queryParameters: {
          'keywords': title,
          if (query.year != null) 'year': '${query.year}',
          if (query.isEpisode && query.season != null)
            'seasons': '${query.season}',
          if (query.isEpisode && query.episode != null)
            'episodes': '${query.episode}',
          'language': ?lang,
          'movie_type': query.isEpisode
              ? ['tv-series', 'mini-series']
              : ['movie'],
        },
      );
      final json = asJsonMap(
        await _http.json(
          'GET',
          url,
          headers: {'User-Agent': userAgent},
          cancel: cancel,
        ),
        id,
      );
      for (final s in jsonObjects(json.list('data'))) {
        final r = _parse(s, query);
        if (r != null &&
            seen.add(r.id) &&
            wantedLanguage(r.language, query.languages)) {
          out.add(r);
        }
      }
    }
    return out;
  }

  SubtitleResult? _parse(Map<String, Object?> s, SubtitleQuery query) {
    final subId = s.str('id');
    final language = Language.parse(s.str('language'));
    if (subId == null || language == null) return null;
    final movie = s.obj('movie');
    if (query.isEpisode && movie.str('type') == 'movie') return null;
    final ep = movie.obj('episode_info');
    final flags = {for (final f in s.list('flags')) '$f'};
    return SubtitleResult(
      providerId: id,
      id: subId,
      language: language,
      releaseNames: {
        for (final r in [...s.list('releases'), ...s.list('custom_releases')])
          if ('$r'.trim().isNotEmpty) '$r'.trim(),
      }.toList(),
      hearingImpaired: flags.contains('hearing_impaired'),
      forced: flags.contains('foreign_only'),
      machineTranslated: flags.contains('machine_translated'),
      fps: parseFps(s['fps']),
      downloads: s.obj('stats').integer('downloads'),
      uploadDate: s.date('created'),
      comments: s.str('notes'),
      season: ep.integer('season'),
      episodeFrom: ep.integer('episode'),
      episodeTo: ep.integer('episode'),
      payload: const {},
    );
  }

  @override
  Future<SubtitleDownload> download(
    SubtitleResult result, {
    CancelToken? cancel,
  }) => fetchFile(
    _http,
    _base.replace(
      path: '/subtitles/${Uri.encodeComponent(result.id)}/download',
      queryParameters: {'container': 'zip'},
    ),
    headers: {'User-Agent': userAgent},
    fallbackName: '${result.id}.zip',
    cancel: cancel,
  );
}

/// Our language -> Podnapisi code (lowercase IETF: `en`, `pt-br`, `sr-latn`).
String? toPodnapisiCode(Language l) => switch (l.code) {
  'pt-BR' => 'pt-br',
  'sr-Latn' => 'sr-latn',
  'sr-Cyrl' || 'sr' => 'sr',
  'zh-Hans' || 'zh-Hant' => 'zh',
  final c when c.length == 2 => c,
  _ => null,
};
