import 'package:http/http.dart' as http;

import '../archive.dart';
import '../cancel.dart';
import '../errors.dart';
import '../language.dart';
import '../models.dart';
import '../provider_http.dart';
import 'common.dart';

/// Jimaku (`jimaku.cc/api`): anime subtitles, mostly Japanese. Needs the
/// user's key (sent raw in `Authorization`). Files carry no language, so it
/// is read from the file name (default Japanese).
final class JimakuProvider implements SubtitleProvider {
  JimakuProvider({
    required this.apiKey,
    this.userAgent = defaultUserAgent,
    Uri? baseUrl,
    http.Client? client,
    Duration timeout = const Duration(seconds: 15),
    Clock? clock,
    Sleep? sleep,
  }) : _base = baseUrl ?? Uri.parse('https://jimaku.cc/api'),
       _http = ProviderHttp(
         providerId: 'jimaku',
         client: client,
         timeout: timeout,
         maxConcurrent: 2,
         clock: clock,
         sleep: sleep,
       );

  final String apiKey;
  final String userAgent;
  final Uri _base;
  final ProviderHttp _http;

  static final _japanese = Language.of('ja');

  @override
  String get id => 'jimaku';

  @override
  String get displayName => 'Jimaku';

  @override
  bool get requiresKey => true;

  @override
  Set<ProviderCapability> get capabilities => const {
    ProviderCapability.tmdbSearch,
    ProviderCapability.textSearch,
    ProviderCapability.movieSupport,
    ProviderCapability.tvSupport,
    ProviderCapability.animeOnly,
  };

  Map<String, String> get _headers => {
    'Authorization': apiKey,
    'User-Agent': userAgent,
    'Accept': 'application/json',
  };

  @override
  Future<List<SubtitleResult>> search(
    SubtitleQuery query, {
    CancelToken? cancel,
  }) async {
    final params = query.tmdbId != null
        ? {'tmdb_id': '${query.isEpisode ? 'tv' : 'movie'}:${query.tmdbId}'}
        : query.title != null
        ? {'query': query.title!}
        : null;
    if (params == null) return const [];
    final entries = await _http.json(
      'GET',
      _base.replace(
        path: '${_base.path}/entries/search',
        queryParameters: params,
      ),
      headers: _headers,
      cancel: cancel,
    );
    if (entries is! List) {
      throw SubtitleResponseException('expected a JSON list', providerId: id);
    }
    // shortcut: takes the top entry; text searches for ambiguous titles may
    // need the app to pass a TMDB id.
    final entry = jsonObjects(entries).firstOrNull;
    final entryId = entry?.integer('id');
    if (entryId == null) return const [];
    final files = await _http.json(
      'GET',
      _base.replace(
        path: '${_base.path}/entries/$entryId/files',
        queryParameters: {
          if (query.isEpisode && query.episode != null)
            'episode': '${query.episode}',
        },
      ),
      headers: _headers,
      cancel: cancel,
    );
    if (files is! List) {
      throw SubtitleResponseException('expected a JSON list', providerId: id);
    }
    return [
      for (final f in jsonObjects(files))
        if (_parse(f, entry!) case final r?
            when wantedLanguage(r.language, query.languages))
          r,
    ];
  }

  SubtitleResult? _parse(Map<String, Object?> f, Map<String, Object?> entry) {
    final url = f.str('url');
    final name = f.str('name');
    if (url == null || name == null) return null;
    final isArchive = RegExp(
      r'\.(zip|rar|7z)$',
      caseSensitive: false,
    ).hasMatch(name);
    return SubtitleResult(
      providerId: id,
      id: '${entry.integer('id')}/$name',
      language: languageFromFileName(name) ?? _japanese,
      releaseNames: [name.replaceFirst(RegExp(r'\.[^.]+$'), '')],
      fileName: name,
      uploadDate: f.date('last_modified'),
      format: SubtitleFormat.fromName(name),
      isSeasonPack: isArchive,
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
    final uri = Uri.parse(url);
    return fetchFile(
      _http,
      uri,
      // Never send the key to a host other than Jimaku's own.
      headers: {
        'User-Agent': userAgent,
        if (uri.host == _base.host) 'Authorization': apiKey,
      },
      fallbackName: result.fileName ?? 'subtitle.srt',
      format: result.format,
      cancel: cancel,
    );
  }
}
