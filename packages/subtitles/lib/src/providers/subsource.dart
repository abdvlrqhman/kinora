import 'package:http/http.dart' as http;

import '../cancel.dart';
import '../errors.dart';
import '../language.dart';
import '../models.dart';
import '../provider_http.dart';
import 'common.dart';

/// SubSource (`api.subsource.net/api/v1`). Needs the user's API key (free:
/// 60 requests/min). Two steps: find the title (each TV season is its own
/// title), then list its subtitles. Downloads are ZIPs, often whole seasons.
final class SubSourceProvider implements SubtitleProvider {
  SubSourceProvider({
    required this.apiKey,
    this.maxPages = 2,
    Uri? baseUrl,
    http.Client? client,
    Duration timeout = const Duration(seconds: 15),
    Clock? clock,
    Sleep? sleep,
  }) : _base = baseUrl ?? Uri.parse('https://api.subsource.net/api/v1'),
       _http = ProviderHttp(
         providerId: 'subsource',
         client: client,
         timeout: timeout,
         maxConcurrent: 2,
         clock: clock,
         sleep: sleep,
       );

  final String apiKey;

  /// Result pages fetched per search (100 results per page).
  final int maxPages;
  final Uri _base;
  final ProviderHttp _http;

  @override
  String get id => 'subsource';

  @override
  String get displayName => 'SubSource';

  @override
  bool get requiresKey => true;

  @override
  Set<ProviderCapability> get capabilities => const {
    ProviderCapability.imdbSearch,
    ProviderCapability.textSearch,
    ProviderCapability.movieSupport,
    ProviderCapability.tvSupport,
  };

  Map<String, String> get _headers => {
    'X-API-Key': apiKey,
    'Accept': 'application/json',
  };

  Uri _url(String path, Map<String, String> params) =>
      _base.replace(path: '${_base.path}$path', queryParameters: params);

  @override
  Future<List<SubtitleResult>> search(
    SubtitleQuery query, {
    CancelToken? cancel,
  }) async {
    final names = {for (final l in query.languages) ...subSourceNames(l)};
    if (query.languages.isNotEmpty && names.isEmpty) return const [];
    final title = await _findTitle(query, cancel);
    if (title == null) return const [];
    final movieId = title.integer('movieId')!;
    final out = <SubtitleResult>[];
    for (var page = 1; page <= maxPages; page++) {
      final json = asJsonMap(
        await _http.json(
          'GET',
          _url('/subtitles', {
            'movieId': '$movieId',
            if (names.isNotEmpty) 'language': names.join(','),
            'limit': '100',
            if (page > 1) 'page': '$page',
          }),
          headers: _headers,
          cancel: cancel,
        ),
        id,
      );
      for (final s in jsonObjects(json.list('data'))) {
        final r = _parse(s, title.integer('season'));
        if (r != null && wantedLanguage(r.language, query.languages)) {
          out.add(r);
        }
      }
      if (page >= (json.obj('pagination').integer('pages') ?? 1)) break;
    }
    return out;
  }

  Future<Map<String, Object?>?> _findTitle(
    SubtitleQuery query,
    CancelToken? cancel,
  ) async {
    Future<List<Map<String, Object?>>> find(Map<String, String> p) async {
      final json = asJsonMap(
        await _http.json(
          'GET',
          _url('/movies/search', p),
          headers: _headers,
          cancel: cancel,
        ),
        id,
      );
      return [
        for (final t in jsonObjects(json.list('data')))
          if (t.integer('movieId') != null) t,
      ];
    }

    final season = query.isEpisode ? query.season : null;
    final common = {
      'type': query.isEpisode ? 'series' : 'movie',
      if (season != null) 'season': '$season',
    };
    var found = query.imdbId == null
        ? <Map<String, Object?>>[]
        : await find({'searchType': 'imdb', 'imdb': query.imdbId!, ...common});
    if (found.isEmpty && query.title != null) {
      found = await find({
        'searchType': 'text',
        'q': query.title!,
        if (query.year != null && !query.isEpisode) 'year': '${query.year}',
        ...common,
      });
      if (query.imdbId != null) {
        found = [
          for (final t in found)
            if (t.str('imdbId') == null || t.str('imdbId') == query.imdbId) t,
        ];
      }
    }
    bool isSeries(Map<String, Object?> t) =>
        (t.str('type') ?? '').toLowerCase().contains('series');
    for (final t in found) {
      if (query.isEpisode) {
        if (isSeries(t) && (season == null || t.integer('season') == season)) {
          return t;
        }
      } else if (!isSeries(t)) {
        return t;
      }
    }
    return null;
  }

  SubtitleResult? _parse(Map<String, Object?> s, int? season) {
    final subId = s.integer('subtitleId');
    final language = Language.parse(s.str('language'));
    if (subId == null || language == null) return null;
    final rating = s.obj('rating');
    final total = rating.integer('total') ?? 0;
    final production = (s.str('productionType') ?? '').toLowerCase();
    return SubtitleResult(
      providerId: id,
      id: '$subId',
      language: language,
      releaseNames: [
        for (final r in s.list('releaseInfo'))
          if ('$r'.trim().isNotEmpty) '$r'.trim(),
      ],
      hearingImpaired: s.flag('hearingImpaired'),
      forced: s.flag('foreignParts'),
      machineTranslated:
          production.contains('machine') || production.contains('ai'),
      fps: parseFps(s['framerate']),
      rating: total > 0 ? (rating.integer('good') ?? 0) / total * 10 : null,
      downloads: s.integer('downloads'),
      uploadDate: s.date('createdAt'),
      comments: s.str('commentary'),
      season: season,
      payload: const {},
    );
  }

  @override
  Future<SubtitleDownload> download(
    SubtitleResult result, {
    CancelToken? cancel,
  }) {
    if (int.tryParse(result.id) == null) {
      throw SubtitleResponseException('bad subtitle id', providerId: id);
    }
    return fetchFile(
      _http,
      _url('/subtitles/${result.id}/download', const {}),
      headers: {'X-API-Key': apiKey},
      fallbackName: '${result.id}.zip',
      cancel: cancel,
    );
  }
}

/// SubSource's language names (`arabic`, `farsi_persian`, ...).
const subSourceLanguages = [
  'english',
  'farsi_persian',
  'arabic',
  'bengali',
  'indonesian',
  'abkhazian',
  'afrikaans',
  'albanian',
  'amharic',
  'aragonese',
  'armenian',
  'assamese',
  'asturian',
  'azerbaijani',
  'basque',
  'belarusian',
  'big_5_code',
  'bosnian',
  'brazilian_portuguese',
  'breton',
  'bulgarian',
  'burmese',
  'catalan',
  'chinese',
  'chinese_cantonese',
  'chinese_simplified',
  'chinese_traditional',
  'chinese_bg_code',
  'chinese_bilingual',
  'croatian',
  'czech',
  'danish',
  'dari',
  'dutch',
  'espranto',
  'estonian',
  'extremaduran',
  'filipino',
  'finnish',
  'french',
  'french_canada',
  'french_france',
  'gaelic',
  'gaelician',
  'georgian',
  'german',
  'greek',
  'greenlandic',
  'hebrew',
  'hindi',
  'hungarian',
  'icelandic',
  'igbo',
  'interlingua',
  'irish',
  'italian',
  'japanese',
  'kannada',
  'kazakh',
  'khmer',
  'korean',
  'kurdish',
  'kyrgyz',
  'latvian',
  'lithuanian',
  'luxembourgish',
  'macedonian',
  'malay',
  'malayalam',
  'manipuri',
  'marathi',
  'mongolian',
  'montenegrin',
  'navajo',
  'nepali',
  'northen_sami',
  'norwegian',
  'occitan',
  'odia',
  'pashto',
  'polish',
  'portuguese',
  'pushto',
  'romanian',
  'russian',
  'santli',
  'serbian',
  'sindhi',
  'sinhala',
  'sinhalese',
  'slovak',
  'slovenian',
  'somali',
  'sorbian',
  'spanish',
  'spanish_latin_america',
  'spanish_spain',
  'swahili',
  'swedish',
  'sylheti',
  'syriac',
  'tagalog',
  'tamil',
  'tatar',
  'telugu',
  'tetum',
  'thai',
  'toki_pona',
  'turkish',
  'turkmen',
  'ukrainian',
  'urdu',
  'uzbek',
  'vietnamese',
  'welsh',
];

final Map<Language, List<String>> _subSourceByLanguage = () {
  final map = <Language, List<String>>{};
  for (final name in subSourceLanguages) {
    final l = Language.parse(name);
    if (l != null) map.putIfAbsent(l, () => []).add(name);
  }
  return map;
}();

/// SubSource names to request for [l] (e.g. zh-Hans -> chinese,
/// chinese_simplified, chinese_bg_code); empty when unsupported.
List<String> subSourceNames(Language l) => _subSourceByLanguage[l] ?? const [];
