import 'package:collection/collection.dart';

/// Parses a release or file name. The app injects its full parser; this
/// package ships [parseReleaseName] as a fallback.
typedef ReleaseNameParser = ReleaseInfo Function(String name);

/// Where a release's video came from, grouped by timing compatibility:
/// releases of the same family usually share subtitle timings.
enum SourceFamily { web, bluray, dvd, tv, cam, unknown }

/// Facts parsed from a release name.
final class ReleaseInfo {
  const ReleaseInfo({
    this.title,
    this.year,
    this.season,
    this.episodes = const [],
    this.group,
    this.source,
    this.resolution,
    this.videoCodec,
    this.isPack = false,
  });

  final String? title;
  final int? year;
  final int? season;

  /// Episode numbers (several for multi-episode files, empty for packs).
  final List<int> episodes;

  /// Release group, e.g. `NTb`.
  final String? group;

  /// Source token, e.g. `webdl`, `webrip`, `bluray`, `remux`, `hdtv`, `dvd`.
  final String? source;

  /// Vertical resolution, e.g. 1080.
  final int? resolution;

  /// e.g. `h264`, `h265`, `av1`, `xvid`.
  final String? videoCodec;

  /// A season (or multi-season) pack.
  final bool isPack;

  /// Timing family of [source].
  SourceFamily get family => sourceFamilyOf(source);

  @override
  bool operator ==(Object other) =>
      other is ReleaseInfo &&
      other.title == title &&
      other.year == year &&
      other.season == season &&
      const ListEquality<int>().equals(other.episodes, episodes) &&
      other.group == group &&
      other.source == source &&
      other.resolution == resolution &&
      other.videoCodec == videoCodec &&
      other.isPack == isPack;

  @override
  int get hashCode => Object.hash(
    title,
    year,
    season,
    const ListEquality<int>().hash(episodes),
    group,
    source,
    resolution,
    videoCodec,
    isPack,
  );

  @override
  String toString() =>
      'ReleaseInfo(${[?title, ?year, if (season != null) 'S$season', if (episodes.isNotEmpty) 'E${episodes.join('-')}', if (isPack) 'pack', ?source, if (resolution != null) '${resolution}p', ?videoCodec, if (group != null) '-$group'].join(' ')})';
}

/// Maps a source token (any spelling: `WEB-DL`, `BDRip`, `HDTV`) to a family.
SourceFamily sourceFamilyOf(String? source) {
  if (source == null) return SourceFamily.unknown;
  final s = source.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
  if (s.startsWith('web') || _streamingTags.contains(s)) {
    return SourceFamily.web;
  }
  if (s.contains('bluray') ||
      s.startsWith('bd') ||
      s.startsWith('br') ||
      s == 'remux' ||
      s == 'uhd') {
    return SourceFamily.bluray;
  }
  if (s.contains('dvd')) return SourceFamily.dvd;
  if (s.contains('tv') || s == 'dsr' || s == 'dsrip' || s == 'satrip') {
    return SourceFamily.tv;
  }
  if (s.contains('cam') || s == 'ts' || s == 'tc' || s.startsWith('tele')) {
    return SourceFamily.cam;
  }
  return SourceFamily.unknown;
}

const _streamingTags = {
  'amzn',
  'nf',
  'dsnp',
  'hmax',
  'max',
  'atvp',
  'hulu',
  'pcok',
  'pmtp',
  'itunes',
  'stan',
  'crav',
  'netflix',
};

final _ext = RegExp(
  r'\.(srt|ass|ssa|vtt|sub|idx|txt|mkv|mp4|avi|m4v|ts|zip|rar|7z|nfo)$',
  caseSensitive: false,
);
final _sxe = RegExp(
  r'\bS(\d{1,2})[ ._-]?E(\d{1,4})(?![\dp])'
  r'((?:\s?-\s?E?\d{1,4}(?![\dp])|\s?E\d{1,4}(?![\dp]))*)',
  caseSensitive: false,
);
final _nxn = RegExp(r'\b(\d{1,2})x(\d{2,3})\b', caseSensitive: false);
final _seasonEpisodeWords = RegExp(
  r'\bseason[ ._-]?(\d{1,2})[ ._-]*(?:episode|ep)[ ._-]?(\d{1,4})\b',
  caseSensitive: false,
);
final _seasonOnly = RegExp(
  r'\b(?:S(\d{1,2})(?!\d|[ ._-]?E\d)|season[ ._-]?(\d{1,2}))\b',
  caseSensitive: false,
);
final _multiSeason = RegExp(
  r'\bS(\d{1,2})[ ._]?-[ ._]?S(\d{1,2})\b|\bseasons?[ ._]?(\d{1,2})[ ._]?-[ ._]?(\d{1,2})\b',
  caseSensitive: false,
);
final _animeEpisode = RegExp(r'\s-\s(\d{1,4})(?:v\d)?(?=\s|$|\[|\()');
final _episodeWord = RegExp(
  r'\b(?:episode|ep)[ ._]?(\d{1,4})\b',
  caseSensitive: false,
);
final _year = RegExp(r'(?<![0-9])(19[0-9]{2}|20[0-9]{2})(?![0-9p])');
final _resolution = RegExp(
  r'\b(2160|1080|720|576|540|480|360)[pi]\b|\b(4k|uhd)\b',
  caseSensitive: false,
);
final _sources = <(RegExp, String)>[
  (RegExp(r'\bremux\b', caseSensitive: false), 'remux'),
  (
    RegExp(
      r'\b(blu-?ray|bdrip|brrip|bd-?rip|bd25|bd50|bdmv|bd|uhd-?bluray)\b',
      caseSensitive: false,
    ),
    'bluray',
  ),
  (RegExp(r'\bweb-?dl\b', caseSensitive: false), 'webdl'),
  (RegExp(r'\bweb-?rip\b', caseSensitive: false), 'webrip'),
  (RegExp(r'\bweb\b', caseSensitive: false), 'web'),
  (
    RegExp(
      r'\b(amzn|nf|dsnp|hmax|atvp|hulu|pcok|pmtp|netflix|itunes)\b',
      caseSensitive: false,
    ),
    'web',
  ),
  (
    RegExp(
      r'\b(hdtv|pdtv|sdtv|dsr|dsrip|tvrip|satrip|hdtvrip|dvb)\b',
      caseSensitive: false,
    ),
    'hdtv',
  ),
  (
    RegExp(r'\b(dvdrip|dvd-?r|dvd5|dvd9|dvd|dvdscr)\b', caseSensitive: false),
    'dvd',
  ),
  (
    RegExp(
      r'\b(cam|hdcam|camrip|ts|hdts|telesync|tc|telecine)\b',
      caseSensitive: false,
    ),
    'cam',
  ),
];
final _codecs = <(RegExp, String)>[
  (RegExp(r'\b([xh][ .]?264|avc)\b', caseSensitive: false), 'h264'),
  (RegExp(r'\b([xh][ .]?265|hevc)\b', caseSensitive: false), 'h265'),
  (RegExp(r'\bav1\b', caseSensitive: false), 'av1'),
  (RegExp(r'\b(xvid|divx)\b', caseSensitive: false), 'xvid'),
  (RegExp(r'\bvp9\b', caseSensitive: false), 'vp9'),
];
const _notGroups = {
  'dl',
  'rip',
  'hd',
  'ray',
  'ma',
  'x',
  'sdh',
  'cc',
  'hi',
  'dts',
  'audio',
  'sub',
  'subs',
  'eng',
  'en',
  'forced',
  'srt',
  'dub',
  'dubbed',
  'ac3',
  'aac',
  'es',
  'ar',
  'fr',
  'de',
  'it',
  'pt',
  'ru',
  'he',
  'fa',
  'tr',
  'nl',
  'pl',
};

/// Built-in fallback release-name parser: good enough for tests and for
/// subtitle names; the app injects a stronger one.
ReleaseInfo parseReleaseName(String name) {
  var n = name.split(RegExp(r'[\\/]')).last.trim();
  while (_ext.hasMatch(n)) {
    n = n.replaceFirst(_ext, '');
  }
  final spaced = n.replaceAll(RegExp(r'[._]'), ' ');

  int? season;
  var episodes = <int>[];
  var isPack = false;
  int? cut; // where the title ends

  void at(int index) => cut = cut == null || index < cut! ? index : cut;

  final multi = _multiSeason.firstMatch(spaced);
  final sxe = _sxe.firstMatch(spaced);
  if (sxe != null) {
    season = int.parse(sxe.group(1)!);
    final first = int.parse(sxe.group(2)!);
    episodes = [first];
    final tail = sxe.group(3) ?? '';
    final more = RegExp(r'(-)?\s?E?(\d{1,4})', caseSensitive: false);
    for (final m in more.allMatches(tail)) {
      final e = int.parse(m.group(2)!);
      if (e <= episodes.last || e > episodes.last + 50) break;
      if (m.group(1) != null) {
        episodes.addAll([for (var i = episodes.last + 1; i <= e; i++) i]);
      } else {
        episodes.add(e);
      }
    }
    at(sxe.start);
  } else if (_seasonEpisodeWords.firstMatch(spaced) case final m?) {
    season = int.parse(m.group(1)!);
    episodes = [int.parse(m.group(2)!)];
    at(m.start);
  } else if (_nxn.firstMatch(spaced) case final m?) {
    season = int.parse(m.group(1)!);
    episodes = [int.parse(m.group(2)!)];
    at(m.start);
  } else if (multi != null) {
    isPack = true;
    at(multi.start);
  } else if (_seasonOnly.firstMatch(spaced) case final m?) {
    final all = {
      for (final s in _seasonOnly.allMatches(spaced))
        int.parse(s.group(1) ?? s.group(2)!),
    };
    // "S01.S02.S03" is a multi-season pack: season unknown.
    season = all.length == 1 ? all.first : null;
    isPack = true;
    at(m.start);
  } else if (_animeEpisode.firstMatch(spaced) case final m?) {
    episodes = [int.parse(m.group(1)!)];
    at(m.start);
  } else if (_episodeWord.firstMatch(spaced) case final m?) {
    episodes = [int.parse(m.group(1)!)];
    at(m.start);
  }
  final complete = RegExp(
    r'\bcomplete\b',
    caseSensitive: false,
  ).firstMatch(spaced);
  if (complete != null && episodes.isEmpty) {
    isPack = true;
    at(complete.start);
  }

  int? year;
  // Last year-looking number that isn't at the very start (titles like 1917).
  for (final m in _year.allMatches(spaced)) {
    if (m.start == 0 && sxe == null) continue;
    year = int.parse(m.group(1)!);
    at(m.start);
  }

  int? resolution;
  final res = _resolution.firstMatch(spaced);
  if (res != null) {
    resolution = res.group(1) != null ? int.parse(res.group(1)!) : 2160;
    at(res.start);
  }

  String? source;
  for (final (re, token) in _sources) {
    final m = re.firstMatch(spaced);
    if (m != null) {
      source = token;
      at(m.start);
      break;
    }
  }

  String? codec;
  for (final (re, token) in _codecs) {
    final m = re.firstMatch(spaced);
    if (m != null) {
      codec = token;
      at(m.start);
      break;
    }
  }

  final group = _group(n);
  var title = spaced.substring(0, cut ?? spaced.length);
  title = title
      .replaceFirst(RegExp(r'^\s*\[[^\]]*\]\s*'), '')
      .replaceAll(RegExp(r'[\[\](){}]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'[\s,:;-]+$'), '')
      .trim();

  return ReleaseInfo(
    title: title.isEmpty ? null : title,
    year: year,
    season: season,
    episodes: episodes,
    group: group,
    source: source,
    resolution: resolution,
    videoCodec: codec,
    isPack: isPack,
  );
}

String? _group(String n) {
  final fansub = RegExp(r'^\s*\[([^\]]+)\]').firstMatch(n);
  if (fansub != null) return fansub.group(1)!.trim();
  // "...x265-YAWNTiC_eng SDH", "...-NTb[rarbg]", "...WEB-DL" (no group).
  final stripped = n.replaceAll(RegExp(r'\[[^\]]*\]\s*$'), '');
  for (final m in RegExp(
    r'-([A-Za-z0-9]+)',
  ).allMatches(stripped).toList().reversed) {
    final g = m.group(1)!;
    final lower = g.toLowerCase();
    if (_notGroups.contains(lower) ||
        !RegExp('[a-z]', caseSensitive: false).hasMatch(g) ||
        RegExp(r'^(e\d+|s\d+|\d+p|x26[45]|h26[45])$').hasMatch(lower)) {
      continue;
    }
    return g;
  }
  return null;
}
