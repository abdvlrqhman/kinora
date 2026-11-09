import 'package:http/http.dart' as http;

import '../cancel.dart';
import '../errors.dart';
import '../language.dart';
import '../models.dart';
import '../provider_http.dart';
import 'common.dart';

/// Wyzie Subs (`sub.wyzie.io`), an aggregator of other sources. Needs the
/// user's key (free: 1,000 requests/day, a few sources, an advert cue in the
/// first seconds of each file). Results overlap other providers; the
/// orchestrator dedupes them by release + language + HI.
final class WyzieProvider implements SubtitleProvider {
  WyzieProvider({
    required this.apiKey,
    this.sources,
    Uri? baseUrl,
    http.Client? client,
    Duration timeout = const Duration(seconds: 20),
    Clock? clock,
    Sleep? sleep,
  }) : _base = baseUrl ?? Uri.parse('https://sub.wyzie.io'),
       _http = ProviderHttp(
         providerId: 'wyzie',
         client: client,
         timeout: timeout,
         maxConcurrent: 2,
         clock: clock,
         sleep: sleep,
       );

  final String apiKey;

  /// Source codenames (`charlie`, `all` ...); null = Wyzie's default.
  final List<String>? sources;
  final Uri _base;
  final ProviderHttp _http;

  @override
  String get id => 'wyzie';

  @override
  String get displayName => 'Wyzie Subs';

  @override
  bool get requiresKey => true;

  @override
  Set<ProviderCapability> get capabilities => const {
    ProviderCapability.imdbSearch,
    ProviderCapability.tmdbSearch,
    ProviderCapability.kitsuSearch,
    ProviderCapability.hashSearch,
    ProviderCapability.movieSupport,
    ProviderCapability.tvSupport,
    ProviderCapability.aggregator,
  };

  @override
  Future<List<SubtitleResult>> search(
    SubtitleQuery query, {
    CancelToken? cancel,
  }) async {
    final langs = {for (final l in query.languages) l.baseCode};
    final idParam = query.imdbId != null
        ? {'id': query.imdbId!}
        : query.tmdbId != null
        ? {'id': '${query.tmdbId}'}
        : query.kitsuId != null
        ? {'kitsu': '${query.kitsuId}'}
        : null;
    if (idParam == null) return const [];
    final res = await _http.send(
      'GET',
      _base.replace(
        path: '/search',
        queryParameters: {
          ...idParam,
          if (query.isEpisode &&
              query.season != null &&
              query.episode != null) ...{
            'season': '${query.season}',
            'episode': '${query.episode}',
          },
          if (langs.isNotEmpty) 'language': langs.join(','),
          if (query.fileHash != null) 'hash': query.fileHash!,
          if (sources != null) 'source': sources!.join(','),
          'key': apiKey,
        },
      ),
      headers: const {'Accept': 'application/json'},
      cancel: cancel,
      passStatuses: const {404},
    );
    if (res.statusCode == 404) return const []; // "No subtitles found"
    final json = _http.decodeJson(res);
    if (json is! List) {
      throw SubtitleResponseException('expected a JSON list', providerId: id);
    }
    return [
      for (final s in jsonObjects(json))
        if (_parse(s, query) case final r?
            when wantedLanguage(r.language, query.languages))
          r,
    ];
  }

  SubtitleResult? _parse(Map<String, Object?> s, SubtitleQuery query) {
    final url = s.str('url');
    final subId = s.str('id');
    final language = Language.parse(s.str('language'));
    if (url == null || subId == null || language == null) return null;
    final release = s.str('release');
    final releases = [
      for (final r in s.list('releases'))
        if ('$r'.trim().isNotEmpty && !_isFileName('$r')) '$r'.trim(),
    ];
    if (release != null && !releases.contains(release)) {
      releases.insert(0, release);
    }
    final format = SubtitleFormat.fromName(s.str('format'));
    final match = s.obj('match');
    final hashMatched =
        query.fileHash != null &&
        (match.list('reasons').any((r) => '$r'.toLowerCase().contains('hash')));
    return SubtitleResult(
      providerId: id,
      id: subId,
      language: language,
      releaseNames: releases,
      fileName: s.str('fileName'),
      hearingImpaired: s.flag('isHearingImpaired'),
      machineTranslated: s.flag('ai') || s.str('source') == 'ai',
      downloads: s.integer('downloadCount'),
      format: format,
      matchedHash: hashMatched ? query.fileHash!.toLowerCase() : null,
      payload: {'url': url, 'source': s.str('source')},
    );
  }

  static bool _isFileName(String s) =>
      RegExp(r'\.(srt|ass|ssa|vtt|sub)$', caseSensitive: false).hasMatch(s);

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
      fallbackName:
          result.fileName ??
          '${result.id}.${result.format?.extension ?? 'srt'}',
      format: result.format,
      cancel: cancel,
    );
  }
}
