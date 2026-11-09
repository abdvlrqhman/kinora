import 'dart:convert';

import 'package:http/http.dart' as http;

import '../cancel.dart';
import '../errors.dart';
import '../language.dart';
import '../models.dart';
import '../provider_http.dart';
import 'common.dart';

/// OpenSubtitles.com REST API v1 (`api.opensubtitles.com/api/v1`).
///
/// Needs the user's API key; optional username/password login raises the
/// daily download quota (anonymous: 5/day per IP). Searches by IMDb/TMDB id
/// plus `moviehash` for exact file matches. Rate limit 5 req/s per IP.
final class OpenSubtitlesProvider implements SubtitleProvider {
  OpenSubtitlesProvider({
    required this.apiKey,
    this.username,
    this.password,
    this.userAgent = defaultUserAgent,
    this.maxPages = 2,
    Uri? baseUrl,
    http.Client? client,
    Duration timeout = const Duration(seconds: 15),
    Clock? clock,
    Sleep? sleep,
  }) : _base = baseUrl ?? Uri.parse('https://api.opensubtitles.com/api/v1'),
       _http = ProviderHttp(
         providerId: 'opensubtitles',
         client: client,
         timeout: timeout,
         maxConcurrent: 2,
         minInterval: const Duration(milliseconds: 220),
         clock: clock,
         sleep: sleep,
       );

  final String apiKey;
  final String? username;
  final String? password;

  /// Must be `AppName vX.Y.Z` or the API answers 403.
  final String userAgent;

  /// Result pages fetched per search (60 results per page).
  final int maxPages;

  Uri _base;
  final ProviderHttp _http;
  String? _token;
  DateTime? _tokenExpiry;
  Future<void>? _login;

  @override
  String get id => 'opensubtitles';

  @override
  String get displayName => 'OpenSubtitles.com';

  @override
  bool get requiresKey => true;

  @override
  Set<ProviderCapability> get capabilities => const {
    ProviderCapability.hashSearch,
    ProviderCapability.imdbSearch,
    ProviderCapability.tmdbSearch,
    ProviderCapability.movieSupport,
    ProviderCapability.tvSupport,
  };

  Map<String, String> get _headers => {
    'Api-Key': apiKey,
    'User-Agent': userAgent,
    'Accept': '*/*',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  @override
  Future<List<SubtitleResult>> search(
    SubtitleQuery query, {
    CancelToken? cancel,
  }) async {
    final langs = {
      for (final l in query.languages) ?toOpenSubtitlesCode(l),
    }.toList()..sort();
    if (query.languages.isNotEmpty && langs.isEmpty) return const [];
    await _ensureLogin(cancel);
    // Sorted, lowercase, no defaults, no "tt"/leading zeros: avoids redirects.
    final params = <String, String>{
      if (query.isEpisode) ...{
        if (query.episode != null) 'episode_number': '${query.episode}',
        if (query.imdbNumber != null)
          'parent_imdb_id': '${query.imdbNumber}'
        else if (query.tmdbId != null)
          'parent_tmdb_id': '${query.tmdbId}',
        if (query.season != null) 'season_number': '${query.season}',
      } else if (query.imdbNumber != null)
        'imdb_id': '${query.imdbNumber}'
      else if (query.tmdbId != null)
        'tmdb_id': '${query.tmdbId}',
      if (langs.isNotEmpty) 'languages': langs.join(','),
      if (query.fileHash != null) 'moviehash': query.fileHash!.toLowerCase(),
      if (query.imdbNumber == null &&
          query.tmdbId == null &&
          query.title != null)
        'query': query.title!.toLowerCase(),
      if (query.isEpisode) 'type': 'episode' else 'type': 'movie',
    };
    final out = <SubtitleResult>[];
    for (var page = 1; page <= maxPages; page++) {
      final p = {...params, if (page > 1) 'page': '$page'};
      final sorted = Map.fromEntries(
        p.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
      );
      final json = asJsonMap(
        await _http.json(
          'GET',
          _base.replace(
            path: '${_base.path}/subtitles',
            queryParameters: sorted,
          ),
          headers: _headers,
          cancel: cancel,
        ),
        id,
      );
      for (final item in jsonObjects(json.list('data'))) {
        final r = _parse(item, query);
        if (r != null && wantedLanguage(r.language, query.languages)) {
          out.add(r);
        }
      }
      if (page >= (json.integer('total_pages') ?? 1)) break;
    }
    return out;
  }

  SubtitleResult? _parse(Map<String, Object?> item, SubtitleQuery query) {
    final a = item.obj('attributes');
    // shortcut: multi-CD subtitles (nb_cd > 1, old split AVIs) use CD 1 only.
    final files = jsonObjects(a.list('files')).toList();
    final fileId = files.firstOrNull?.integer('file_id');
    final language = Language.parse(a.str('language'));
    if (fileId == null || language == null) return null;
    final f = a.obj('feature_details');
    final release = a.str('release');
    return SubtitleResult(
      providerId: id,
      id: a.str('subtitle_id') ?? item.str('id') ?? '$fileId',
      language: language,
      releaseNames: [?release],
      fileName: files.first.str('file_name'),
      hearingImpaired: a.flag('hearing_impaired'),
      forced: a.flag('foreign_parts_only'),
      machineTranslated:
          a.flag('machine_translated') || a.flag('ai_translated'),
      fps: parseFps(a['fps']),
      rating: a.number('ratings'),
      downloads: a.integer('download_count'),
      uploadDate: a.date('upload_date'),
      format: SubtitleFormat.srt,
      matchedHash: (a.flag('moviehash_match') || item.flag('moviehash_match'))
          ? query.fileHash?.toLowerCase()
          : null,
      comments: a.str('comments'),
      season: f.integer('season_number'),
      episodeFrom: f.integer('episode_number'),
      episodeTo: f.integer('episode_number'),
      payload: {'file_id': fileId},
    );
  }

  @override
  Future<SubtitleDownload> download(
    SubtitleResult result, {
    CancelToken? cancel,
  }) async {
    final fileId = result.payload['file_id'];
    if (fileId is! int) {
      throw SubtitleResponseException('missing file_id', providerId: id);
    }
    await _ensureLogin(cancel);
    final res = await _http.send(
      'POST',
      _base.replace(path: '${_base.path}/download'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: {'file_id': fileId},
      cancel: cancel,
      passStatuses: const {406},
    );
    if (res.statusCode == 406) {
      // Quota exhausted ("remaining": -1), invalid file id or invalid token.
      final body = asJsonMap(_http.decodeJson(res), id);
      final message = body.str('message') ?? 'HTTP 406';
      if ((body.integer('remaining') ?? 0) < 0 ||
          body.str('reset_time_utc') != null) {
        throw SubtitleQuotaException(
          message,
          providerId: id,
          resetAt: body.date('reset_time_utc'),
        );
      }
      if (message.toLowerCase().contains('token')) {
        _token = null;
        throw SubtitleAuthException(message, providerId: id);
      }
      throw SubtitleHttpException(message, providerId: id, statusCode: 406);
    }
    final json = asJsonMap(_http.decodeJson(res), id);
    final link = json.str('link');
    if (link == null) {
      throw SubtitleResponseException('no download link', providerId: id);
    }
    return fetchFile(
      _http,
      Uri.parse(link),
      fallbackName: json.str('file_name') ?? '${result.id}.srt',
      format: SubtitleFormat.srt,
      cancel: cancel,
    );
  }

  Future<void> _ensureLogin(CancelToken? cancel) async {
    if (username == null || password == null) return;
    final expiry = _tokenExpiry;
    if (_token != null && expiry != null && _http.clock().isBefore(expiry)) {
      return;
    }
    await (_login ??= _doLogin(cancel).whenComplete(() => _login = null));
  }

  Future<void> _doLogin(CancelToken? cancel) async {
    final Object? raw;
    try {
      raw = await _http.json(
        'POST',
        _base.replace(path: '${_base.path}/login'),
        headers: {
          'Api-Key': apiKey,
          'User-Agent': userAgent,
          'Content-Type': 'application/json',
        },
        body: {'username': username, 'password': password},
        cancel: cancel,
      );
    } on SubtitleHttpException catch (e) {
      throw SubtitleAuthException('login failed: ${e.message}', providerId: id);
    }
    final json = asJsonMap(raw, id);
    final token = json.str('token');
    if (token == null) {
      throw SubtitleAuthException('login returned no token', providerId: id);
    }
    _token = token;
    _tokenExpiry =
        _jwtExpiry(token) ?? _http.clock().add(const Duration(hours: 23));
    final host = json.str('base_url');
    if (host != null && host != _base.host) _base = _base.replace(host: host);
  }

  DateTime? _jwtExpiry(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      final exp = payload is Map ? payload['exp'] : null;
      if (exp is! int) return null;
      return DateTime.fromMillisecondsSinceEpoch(
        exp * 1000,
        isUtc: true,
      ).subtract(const Duration(minutes: 5));
    } on FormatException {
      return null;
    }
  }
}

/// Our language -> OpenSubtitles.com code (`pt-br`, `zh-cn`, `ea` ...), or
/// null when OpenSubtitles has no such language.
String? toOpenSubtitlesCode(Language l) => switch (l.code) {
  'pt' => 'pt-pt',
  'pt-BR' => 'pt-br',
  'zh-Hans' => 'zh-cn',
  'zh-Hant' => 'zh-tw',
  'yue' => 'zh-ca',
  'ze' => 'ze',
  'es-419' => 'ea',
  'cnr' => 'me',
  'prs' => 'pr',
  'ast' => 'at',
  'mni' => 'ma',
  'syr' => 'sy',
  'ext' => 'ex',
  'sat' => 'sx',
  'tok' => 'tp',
  'sr-Latn' || 'sr-Cyrl' => 'sr',
  'fr-CA' => 'fr',
  final c when c.length == 2 => c,
  _ => null,
};
