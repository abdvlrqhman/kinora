import 'package:http/http.dart' as http;

import '../cancel.dart';
import '../errors.dart';
import '../language.dart';
import '../models.dart';
import '../provider_http.dart';
import 'common.dart';

/// SubDL (`api.subdl.com/api/v1`). Needs the user's API key (free: 2,000
/// requests/day). Downloads are ZIPs from `dl.subdl.com`.
final class SubdlProvider implements SubtitleProvider {
  SubdlProvider({
    required this.apiKey,
    this.maxPages = 3,
    Uri? apiUrl,
    Uri? downloadUrl,
    http.Client? client,
    Duration timeout = const Duration(seconds: 15),
    Clock? clock,
    Sleep? sleep,
  }) : _api = apiUrl ?? Uri.parse('https://api.subdl.com/api/v1/subtitles'),
       _dl = downloadUrl ?? Uri.parse('https://dl.subdl.com'),
       _http = ProviderHttp(
         providerId: 'subdl',
         client: client,
         timeout: timeout,
         maxConcurrent: 2,
         clock: clock,
         sleep: sleep,
       );

  final String apiKey;

  /// Result pages fetched per search (30 results per page).
  final int maxPages;
  final Uri _api;
  final Uri _dl;
  final ProviderHttp _http;

  @override
  String get id => 'subdl';

  @override
  String get displayName => 'SubDL';

  @override
  bool get requiresKey => true;

  @override
  Set<ProviderCapability> get capabilities => const {
    ProviderCapability.imdbSearch,
    ProviderCapability.tmdbSearch,
    ProviderCapability.textSearch,
    ProviderCapability.movieSupport,
    ProviderCapability.tvSupport,
  };

  @override
  Future<List<SubtitleResult>> search(
    SubtitleQuery query, {
    CancelToken? cancel,
  }) async {
    final langs = {for (final l in query.languages) ?toSubdlCode(l)};
    if (query.languages.isNotEmpty && langs.isEmpty) return const [];
    final params = <String, String>{
      'api_key': apiKey,
      if (query.imdbId != null)
        'imdb_id': query.imdbId!
      else if (query.tmdbId != null)
        'tmdb_id': '${query.tmdbId}'
      else if (query.title != null)
        // SubDL rejects <>{}[]'"`´’;\/ in names.
        'film_name': query.title!.replaceAll(
          RegExp('[<>{}\\[\\]\'"`´’;\\\\/]'),
          ' ',
        ),
      'type': query.isEpisode ? 'tv' : 'movie',
      if (query.isEpisode && query.season != null)
        'season_number': '${query.season}',
      if (query.isEpisode && query.episode != null)
        'episode_number': '${query.episode}',
      if (!query.isEpisode && query.year != null) 'year': '${query.year}',
      if (langs.isNotEmpty) 'languages': langs.join(','),
      'subs_per_page': '30',
      'releases': '1',
      'comment': '1',
    };
    final out = <SubtitleResult>[];
    for (var page = 1; page <= maxPages; page++) {
      final res = await _http.send(
        'GET',
        _api.replace(
          queryParameters: {...params, if (page > 1) 'page': '$page'},
        ),
        headers: const {'Accept': 'application/json'},
        cancel: cancel,
        passStatuses: const {400, 404},
      );
      final json = asJsonMap(_http.decodeJson(res), id);
      if (json['status'] != true) {
        final error = json.str('error') ?? 'HTTP ${res.statusCode}';
        // "can't find movie or tv" and friends = no results.
        if (RegExp(
          r"can't find|not found|no subtitles",
          caseSensitive: false,
        ).hasMatch(error)) {
          break;
        }
        if (RegExp('api.?key|auth', caseSensitive: false).hasMatch(error)) {
          throw SubtitleAuthException(error, providerId: id);
        }
        throw SubtitleResponseException(error, providerId: id);
      }
      for (final s in jsonObjects(json.list('subtitles'))) {
        final r = _parse(s);
        if (r != null && wantedLanguage(r.language, query.languages)) {
          out.add(r);
        }
      }
      if (page >= (json.integer('totalPages') ?? 1)) break;
    }
    return out;
  }

  SubtitleResult? _parse(Map<String, Object?> s) {
    final url = s.str('url');
    final language =
        Language.parse(s.str('language')) ?? Language.parse(s.str('lang'));
    if (url == null || language == null) return null;
    // SubDL echoes our key in `url`; never keep it in results.
    final path = Uri.parse(url).replace(queryParameters: const {}).path;
    final nativeId = RegExp(r'/subtitle/([^/?]+?)(?:\.zip)?$').firstMatch(path);
    final releases = [
      for (final r in s.list('releases'))
        if ('$r'.trim().isNotEmpty) '$r'.trim(),
    ];
    final releaseName = s.str('release_name');
    if (releaseName != null && !releases.contains(releaseName)) {
      releases.insert(0, releaseName);
    }
    final author = s.str('author') ?? '';
    final from = s.integer('episode_from') ?? s.integer('episode');
    final to = s.integer('episode_end');
    return SubtitleResult(
      providerId: id,
      id: nativeId?.group(1) ?? path,
      language: language,
      releaseNames: releases,
      fileName: s.str('name'),
      hearingImpaired: s.flag('hi'),
      machineTranslated:
          s.flag('ai_translated') || author.toUpperCase() == 'SUBDL AI',
      fps: parseFps(s['fps']),
      comments: s.str('comment'),
      season: s.integer('season'),
      episodeFrom: from,
      episodeTo: to == null || to == 0 ? from : to,
      isSeasonPack: s.flag('full_season'),
      payload: {'path': path},
    );
  }

  @override
  Future<SubtitleDownload> download(
    SubtitleResult result, {
    CancelToken? cancel,
  }) {
    final path = result.payload['path'];
    if (path is! String) {
      throw SubtitleResponseException('missing path', providerId: id);
    }
    return fetchFile(
      _http,
      _dl.replace(path: path, queryParameters: {'api_key': apiKey}),
      fallbackName: '${result.id}.zip',
      cancel: cancel,
    );
  }
}

/// Our language -> SubDL code (`AR`, `BR_PT`, `ZH_BG` ...), or null when
/// SubDL lacks it.
String? toSubdlCode(Language l) {
  final special = switch (l.code) {
    'pt-BR' => 'BR_PT',
    'zh-Hans' => 'ZH',
    'zh-Hant' => 'ZH_BG',
    'sr-Cyrl' => 'SR_CYRL',
    'fr-CA' => 'FR_CA',
    'mni' => 'MNI',
    _ => null,
  };
  if (special != null) return special;
  final c = l.code.toUpperCase();
  return _subdlCodes.contains(c) ? c : null;
}

const _subdlCodes = {
  'AR',
  'DA',
  'NL',
  'EN',
  'FA',
  'FI',
  'FR',
  'GA',
  'EU',
  'GL',
  'ID',
  'IT',
  'NO',
  'RO',
  'ES',
  'SV',
  'VI',
  'SQ',
  'AZ',
  'BE',
  'BN',
  'BS',
  'BG',
  'MY',
  'CA',
  'HR',
  'CS',
  'EO',
  'ET',
  'KA',
  'DE',
  'EL',
  'KL',
  'HE',
  'HI',
  'HU',
  'IS',
  'JA',
  'JV',
  'KO',
  'KU',
  'LV',
  'LT',
  'MK',
  'MS',
  'ML',
  'MN',
  'PL',
  'PT',
  'RU',
  'SR',
  'SI',
  'SK',
  'SL',
  'SU',
  'TL',
  'TA',
  'TE',
  'TH',
  'TR',
  'UK',
  'UR',
  'HY',
  'KK',
  'KY',
  'KM',
  'KN',
};
