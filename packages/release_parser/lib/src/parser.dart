import 'dart:math' as math;

import 'enums.dart';
import 'languages.dart';
import 'parsed_release.dart';
import 'vocabulary.dart';

/// Latest plausible release year; later 4-digit numbers are title words
/// ("Blade Runner 2049").
final int _maxYear = DateTime.now().year + 1;

final _siteRe = RegExp(
  r'^(?:\[\s*)?www\.[^\s\]]+(?:\s*\])?\s*[-–:]?\s*'
  r'|^\[\s*[\w-]+\.(?:com|org|net|to|io|me|cc|tv|xyz|ws|club|info|cafe|mx|se|nz|pw|in|lol|li|vip)\s*\]\s*[-–]?\s*',
  caseSensitive: false,
);
final _leadingBracketRe = RegExp(r'^\[([^\]]+)\]\s*[-_.]?\s*');
final _hashRe = RegExp(r'\s*\[[0-9A-Fa-f]{8}\]');
final _trailingBracketGroupRe = RegExp(
  r'\s*\[([A-Za-z0-9][\w.\-]{0,23})\]\s*$',
);
final _acronymRe = RegExp(r'(?<![A-Za-z0-9])(?:[A-Z]\.){2,}[A-Z]?(?![a-z0-9])');
final _sxeRe = RegExp(
  r'^s(\d{1,2})-?e(\d{1,4})((?:-?e\d{1,4}|-\d{1,4})*)(?:v\d)?$',
);
final _xRe = RegExp(r'^(\d{1,2})x(\d{2,3})(?:-(?:\d{1,2}x)?(\d{2,3}))?$');
final _seasonRangeRe = RegExp(r'^s(\d{1,2})-s?(\d{1,2})$');
final _groupPartRe = RegExp('[ .]');
final _episodeRe = RegExp(r'^ep?(\d{1,4})(?:v\d)?$');

const _seasonWords = {
  'season',
  'seasons',
  'saison',
  'temporada',
  'stagione',
  'staffel',
  'series', //
};
const _rangeWords = {'-', '~', 'to', '&', 'and'};

/// Parses one release name: a torrent title or a file name
/// (`Movie.2024.2160p.WEB-DL.DDP5.1.DV.HDR.H.265-GROUP.mkv`).
///
/// Never throws; anything not recognised is left unknown.
ParsedRelease parseRelease(String name) {
  var s = name.trim();

  String? container;
  final cut = math.max(s.lastIndexOf('.'), s.lastIndexOf(' '));
  if (cut > 0 && s.length - cut <= 5) {
    final ext = s.substring(cut + 1);
    final lower = ext.toLowerCase();
    final ok = s[cut] == '.'
        ? containers.contains(lower) && ext != 'TS'
        : ext == 'mkv' || ext == 'mp4' || ext == 'avi';
    if (ok) {
      container = lower;
      s = s.substring(0, cut).trimRight();
    }
  }

  if (s.startsWith('[') || s.startsWith('www.') || s.startsWith('WWW.')) {
    s = s.replaceFirst(_siteRe, '');
  }
  String? group;
  if (s.startsWith('[')) {
    final lead = _leadingBracketRe.firstMatch(s);
    if (lead != null && _plausibleGroup(lead[1]!.trim(), leading: true)) {
      group = lead[1]!.trim();
      s = s.substring(lead.end);
    }
  }
  var anime = group != null;
  if (s.contains('[')) {
    final before = s.length;
    s = s.replaceAll(_hashRe, '');
    anime = anime || s.length != before;
  }
  if (group == null) {
    final dash = _trailingDashGroup(s);
    if (dash != null && _plausibleGroup(dash.$2)) {
      group = dash.$2;
      s = s.substring(0, dash.$1);
    } else if (s.endsWith(']')) {
      final bracket = _trailingBracketGroupRe.firstMatch(s);
      if (bracket != null && _plausibleGroup(bracket[1]!)) {
        group = bracket[1];
        s = s.substring(0, bracket.start);
      }
    }
  }
  if (_hasAcronym(s)) {
    s = s.replaceAllMapped(_acronymRe, (m) {
      final a = m[0]!;
      return a.endsWith('.')
          ? '${a.replaceAll('.', '')}.'
          : a.replaceAll('.', '');
    });
  }

  final toks = _tokenize(s);
  final low = [for (final t in toks) t.toLowerCase()];
  final n = toks.length;
  final caseless = s == s.toLowerCase();

  // Anime: "Title - 05", "Title - 01-12", "Title 01 ~ 12".
  var animeAt = n;
  final animeEpisodes = <int>{};
  var batch = false;
  if (anime) {
    for (var i = 1; i < n && animeAt == n; i++) {
      final t = low[i];
      final next = i + 1 < n ? low[i + 1] : '';
      if (t == '-' && _animeNumber(next) != null) {
        animeEpisodes.add(_animeNumber(next)!);
        animeAt = i;
      } else if (_numberRange(t == '-' ? next : t) case (final a, final b)) {
        batch = _addRange(animeEpisodes, a, b);
        animeAt = i;
      } else if (_animeNumber(t) != null &&
          (next == '~' || next == '-') &&
          i + 2 < n &&
          _animeNumber(low[i + 2]) != null) {
        batch = _addRange(
          animeEpisodes,
          _animeNumber(t)!,
          _animeNumber(low[i + 2])!,
        );
        animeAt = i;
      }
    }
  }

  // The title ends at the first tag; a year just before that tag belongs to
  // the release, not the title ("Blade Runner 2049 2017 1080p").
  var hardEnd = n;
  if (n > 0 && _episodeMarker(low[0])) {
    hardEnd = 0;
  } else {
    for (var i = 1; i < n; i++) {
      if (_isTag(toks, low, i)) {
        hardEnd = i;
        break;
      }
    }
  }
  hardEnd = math.min(hardEnd, animeAt);
  int? year;
  var titleEnd = hardEnd;
  for (var i = 1; i < n; i++) {
    final y = _year(low[i]);
    if (y == null) continue;
    if (i < hardEnd) {
      year = y;
      titleEnd = i;
    } else {
      year ??= y;
      break;
    }
  }

  // Seasons / episodes.
  final seasons = <int>{};
  final episodes = <int>{};
  var episodeTitleFrom = -1;
  for (var i = titleEnd; i < n; i++) {
    final t = low[i];
    final next = i + 1 < n ? low[i + 1] : '';
    if (_sxe(t, seasons, episodes) || _xFormat(t, seasons, episodes)) {
      episodeTitleFrom = i + 1;
      break;
    }
    final season = _seasonToken(t);
    if (season != null) {
      final ep = _episodeToken(next);
      if (ep != null) {
        seasons
          ..clear()
          ..add(season);
        episodes.add(ep);
        episodeTitleFrom = i + 2;
        break;
      }
      final to = i + 2 < n && (next == '-' || next == '~')
          ? _seasonToken(low[i + 2])
          : null;
      if (to != null) {
        _addRange(seasons, season, to);
        i += 2;
      } else {
        seasons.add(season);
      }
    } else if ((t.startsWith('s') && t.contains('-')
            ? _seasonRangeRe.firstMatch(t)
            : null)
        case final m?) {
      _addRange(seasons, int.parse(m[1]!), int.parse(m[2]!));
    } else if (_seasonWords.contains(t) && _small(next) != null) {
      final a = _small(next)!;
      final to = i + 3 < n && _rangeWords.contains(low[i + 2])
          ? _small(low[i + 3])
          : null;
      if (to != null) {
        _addRange(seasons, a, to);
        i += 3;
      } else {
        seasons.add(a);
        i += 1;
      }
    } else if (_seasonWords.contains(t) && _numberRange(next) != null) {
      final (a, b) = _numberRange(next)!;
      _addRange(seasons, a, b);
      i += 1;
    } else if (next == 'season' && _ordinal(t) != null) {
      seasons.add(_ordinal(t)!);
      i += 1;
    } else if (episodes.isEmpty && _episodeToken(t) != null) {
      episodes.add(_episodeToken(t)!);
      episodeTitleFrom = i + 1;
    } else if (episodes.isEmpty &&
        (t == 'episode' || t == 'ep') &&
        _small(next, 4) != null) {
      episodes.add(_small(next, 4)!);
      episodeTitleFrom = i + 2;
      i += 1;
    }
  }
  if (episodes.isEmpty && animeEpisodes.isNotEmpty) {
    episodes.addAll(animeEpisodes);
  } else {
    batch = false;
  }

  // Everything after the episode marker up to the next tag is an episode
  // title ("S03E07 The Cam Girl 1080p") and must not be read as tags.
  var skipTo = episodeTitleFrom;
  if (episodeTitleFrom >= 0) {
    while (skipTo < n && !_isTag(toks, low, skipTo)) {
      skipTo++;
    }
  }

  final d = _Details(caseless);
  for (var i = titleEnd; i < n; i++) {
    if (i == episodeTitleFrom) i = skipTo;
    if (i >= n) break;
    i += d.read(toks, low, i);
  }

  var titleTokens = toks.sublist(0, titleEnd);
  while (titleTokens.isNotEmpty && _isPunct(titleTokens.last)) {
    titleTokens = titleTokens.sublist(0, titleTokens.length - 1);
  }
  var trailingComplete = false;
  if (titleTokens.length > 1 && titleTokens.last.toLowerCase() == 'complete') {
    trailingComplete = true;
    titleTokens = titleTokens.sublist(0, titleTokens.length - 1);
  }
  while (titleTokens.isNotEmpty && _isPunct(titleTokens.first)) {
    titleTokens = titleTokens.sublist(1);
  }

  final isCompleteSeries =
      d.completeSeries ||
      ((d.complete || trailingComplete) &&
          seasons.length != 1 &&
          episodes.isEmpty);
  final sortedSeasons = seasons.toList()..sort();
  final sortedEpisodes = episodes.toList()..sort();
  return ParsedRelease(
    raw: name,
    title: titleTokens.join(' '),
    year: year,
    seasons: sortedSeasons,
    episodes: sortedEpisodes,
    absoluteEpisode: seasons.isEmpty && episodes.length == 1
        ? episodes.first
        : null,
    isSeasonPack: (seasons.isNotEmpty && episodes.isEmpty) || batch,
    isCompleteSeries: isCompleteSeries,
    resolution: d.resolution ?? d.implicitResolution ?? Resolution.unknown,
    source: d.source,
    videoCodec: d.codec,
    bitDepth: d.bitDepth,
    hdr: d.hdr,
    audioCodecs: d.audio,
    atmos: d.atmos,
    channels: d.channels,
    languages: {
      for (final (code, at) in d.languages)
        if (!d.subtitleAt.contains(at)) code,
    },
    subtitleLanguages: {
      ...d.subtitleLanguages,
      for (final (code, at) in d.languages)
        if (d.subtitleAt.contains(at)) code,
    },
    multiAudio: d.multiAt.any((at) => !d.subtitleAt.contains(at)),
    dualAudio: d.dual,
    dubbed: d.dubbed,
    hardcodedSubs: d.hardcoded,
    group: group,
    proper: d.proper,
    repack: d.repack,
    extended: d.extended,
    imax: d.imax,
    threeD: d.threeD,
    container: container,
  );
}

/// Accumulates tags found after the title.
final class _Details {
  _Details(this.caseless);

  final bool caseless;
  Resolution? resolution;
  Resolution? implicitResolution;
  Source source = Source.unknown;
  int _sourceRank = 1 << 30;
  VideoCodec codec = VideoCodec.unknown;
  int? bitDepth;
  final hdr = <HdrFormat>{};
  final audio = <AudioCodec>[];
  bool atmos = false;
  String? channels;
  final languages = <(String, int)>[];
  final subtitleLanguages = <String>{};
  final subtitleAt = <int>{};
  final multiAt = <int>{};
  bool dual = false, dubbed = false, hardcoded = false;
  bool proper = false, repack = false, extended = false, imax = false;
  bool threeD = false, complete = false, completeSeries = false;
  int _lastLanguageAt = -2;

  /// Reads the tag at [i] (plus a following word for two-word tags) and
  /// returns how many extra tokens were consumed.
  int read(List<String> toks, List<String> low, int i) {
    final t = low[i];
    final next = i + 1 < low.length ? low[i + 1] : '';
    final pair = bigrams['$t $next'];
    if (pair != null) {
      if (pair == 'dolby digital' &&
          i + 2 < low.length &&
          low[i + 2] == 'plus') {
        _addAudio(AudioCodec.eac3);
        return 2;
      }
      _word(pair, pair, i);
      return 1;
    }
    // "COMPLETE.UHD.BLURAY" is a full disc, not a pack.
    if (t == 'complete' && discWords.contains(next)) return 0;
    if (t == 'complete' && completeKinds.contains(next)) {
      completeSeries = !next.startsWith('season');
      complete = true;
      return 1;
    }
    if (subtitleMarkers.contains(t)) {
      if (_lastLanguageAt == i - 1) {
        subtitleAt.add(i - 1);
      } else if (multiAt.contains(i - 1)) {
        subtitleAt.add(i - 1);
      } else if (releaseLanguageWords[next] case final code?) {
        subtitleLanguages.add(code);
        return 1;
      }
      return 0;
    }
    // "DDP5 1" (Orion strips the dot) → DD+ 5.1.
    if (_audioWithChannels(t) case (final codec, final ch)
        when ch.length == 1) {
      _addAudio(codec);
      if (next == '0' || next == '1') {
        channels ??= '$ch.$next';
        return 1;
      }
      return 0;
    }
    _word(toks[i], t, i);
    return 0;
  }

  void _word(String original, String t, int at) {
    var hit = false;
    if (resolutions[t] case final r?) {
      resolution ??= r;
      hit = true;
    } else if (implicitResolutions[t] case final r?) {
      implicitResolution ??= r;
      hit = true;
    } else if (_widthHeight(t) case final r?) {
      resolution ??= r;
      hit = true;
    }
    final strictOk =
        caseless ||
        !strictCase.contains(t) ||
        original == original.toUpperCase();
    if (sources[t] case final src? when strictOk) {
      final rank = lowPriorityWeb.contains(t)
          ? 100
          : sourcePriority.indexOf(src);
      if (rank < _sourceRank) {
        _sourceRank = rank;
        source = src;
      }
      hit = true;
    }
    if (codecs[t] case final c?) {
      if (codec == VideoCodec.unknown ||
          codecPriority.indexOf(c) < codecPriority.indexOf(codec)) {
        codec = c;
      }
      hit = true;
    }
    if (bitDepths[t] case final b?) {
      bitDepth ??= b;
      hit = true;
    }
    if (hdrFormats[t] case final h? when strictOk) {
      hdr.add(h);
      hit = true;
    }
    if (audioCodecs[t] case final a?) {
      _addAudio(a);
      hit = true;
    }
    if (t == 'atmos' || t == 'ddpa') {
      atmos = true;
      hit = true;
    }
    if (channelWords[t] case final ch?) {
      channels ??= ch;
      hit = true;
    } else if (_isChannels(t)) {
      channels ??= t;
      hit = true;
    } else if (_audioWithChannels(t) case (final codec, final ch)) {
      _addAudio(codec);
      if (codec == AudioCodec.eac3 && t.startsWith('ddpa')) atmos = true;
      if (ch.length == 3) channels ??= ch;
      hit = true;
    }
    if (flags[t] case final f? when strictOk) {
      hit = true;
      switch (f) {
        case Flag.proper:
          proper = true;
        case Flag.repack:
          repack = true;
        case Flag.extended:
          extended = true;
        case Flag.imax:
          imax = true;
        case Flag.threeD:
          threeD = true;
        case Flag.multi:
          multiAt.add(at);
        case Flag.dual:
          dual = true;
        case Flag.dubbed:
          dubbed = true;
        case Flag.hardcoded:
          hardcoded = true;
        case Flag.complete:
          complete = true;
        case Flag.completeSeries:
          completeSeries = true;
      }
    }
    if (subtitleWords[t] case final code?) {
      subtitleLanguages.add(code);
      hit = true;
    }
    if (multiSubWords.contains(t)) hit = true;
    if (releaseLanguageWords[t] case final code?
        when t.length > 3 || caseless || original != t) {
      languages.add((code, at));
      _lastLanguageAt = at;
      hit = true;
    }
    if (!hit && t.length > 2 && (t.contains('-') || t.contains('+'))) {
      _compound(original, at);
    }
  }

  /// "HINDI-ENG-5.1", "ES-EN", "DV-HDR", "5.1-Ingles+Subs".
  void _compound(String original, int at) {
    final parts = original.split(compoundSeparator);
    if (parts.length < 2) return;
    final codes = [
      for (final p in parts)
        if (p.length == 2 &&
            p == p.toUpperCase() &&
            isoCodes.contains(p.toLowerCase()))
          p.toLowerCase(),
    ];
    if (codes.length == parts.length) {
      for (final c in codes) {
        languages.add((c, at));
      }
      return;
    }
    for (final p in parts) {
      final lower = p.toLowerCase();
      if (p.isNotEmpty && !subtitleMarkers.contains(lower)) _word(p, lower, at);
    }
  }

  void _addAudio(AudioCodec a) {
    if (!audio.contains(a)) audio.add(a);
  }
}

/// Splits on separators, keeping `-`, `+`, `:` inside tokens and the dot in
/// channel layouts (`DDP5.1`, but `EAC3.5.1` → `EAC3`, `5.1`).
List<String> _tokenize(String s) {
  final out = <String>[];
  var start = -1;
  for (var i = 0; i <= s.length; i++) {
    final c = i < s.length ? s.codeUnitAt(i) : 0x20;
    final sep = separators.contains(c) && !(c == 0x2E && _keepDot(s, i));
    if (sep) {
      if (start >= 0) out.add(s.substring(start, i));
      start = -1;
    } else if (start < 0) {
      start = i;
    }
  }
  return out;
}

bool _keepDot(String s, int i) =>
    i > 0 &&
    i + 1 < s.length &&
    _digitAt(s, i - 1) &&
    !_digitAt(s, i - 2) &&
    _digitAt(s, i + 1) &&
    !_digitAt(s, i + 2) &&
    !(i + 3 < s.length && s.codeUnitAt(i + 2) == 0x2E && _digitAt(s, i + 3));

bool _digitAt(String s, int i) {
  if (i < 0 || i >= s.length) return false;
  final c = s.codeUnitAt(i);
  return c >= 0x30 && c <= 0x39;
}

bool _allDigits(String t) {
  if (t.isEmpty) return false;
  for (var i = 0; i < t.length; i++) {
    if (!_digitAt(t, i)) return false;
  }
  return true;
}

/// Quick check for "S.W.A.T" / "A.I." before running the acronym regex.
bool _hasAcronym(String s) {
  for (var i = 0; i + 3 < s.length; i++) {
    if (s.codeUnitAt(i + 1) == 0x2E &&
        s.codeUnitAt(i + 3) == 0x2E &&
        _upperAt(s, i) &&
        _upperAt(s, i + 2)) {
      return true;
    }
  }
  return false;
}

bool _upperAt(String s, int i) {
  final c = s.codeUnitAt(i);
  return c >= 0x41 && c <= 0x5A;
}

bool _isPunct(String t) =>
    t == '-' || t == '~' || t == ':' || t == '&' || t == '+';

bool _isUpper(String t) =>
    (t == t.toUpperCase() && t != t.toLowerCase()) || t == 'MULTi';

/// Whether the token at [i] is a release tag (ends the title).
/// Ambiguous words (CAM, PROPER, FRENCH ...) only count in upper case.
bool _isTag(List<String> toks, List<String> low, int i) {
  final t = low[i];
  final next = i + 1 < low.length ? low[i + 1] : '';
  if (bigrams.containsKey('$t $next')) return true;
  if (_seasonWords.contains(t) &&
      (_small(next) != null || _numberRange(next) != null)) {
    return true;
  }
  if ((t == 'episode' || t == 'ep') && _small(next, 4) != null) return true;
  if (t == 'complete' && completeKinds.contains(next)) return true;
  if (next == 'season' && _ordinal(t) != null) return true;
  return _isTagWord(toks[i], t);
}

bool _isTagWord(String original, String t) {
  if (vocabulary.contains(t)) {
    return !weakWords.contains(t) || _isUpper(original);
  }
  if (releaseLanguageWords.containsKey(t))
    return _isUpper(original) && t.length > 1;
  if (_episodeMarker(t) ||
      (_digitAt(t, 0) && t.contains('x') && _xRe.hasMatch(t)) ||
      _episodeToken(t) != null ||
      _widthHeight(t) != null ||
      _audioWithChannels(t) != null) {
    return true;
  }
  if (t.length > 2 && (t.contains('-') || t.contains('+'))) {
    final parts = original.split(compoundSeparator);
    return parts.length > 1 &&
        parts.every((p) => p.isNotEmpty) &&
        parts.any((p) => _isTagWord(p, p.toLowerCase()));
  }
  return false;
}

bool _episodeMarker(String t) =>
    t.startsWith('s') &&
    _digitAt(t, 1) &&
    (_seasonToken(t) != null ||
        _sxeRe.hasMatch(t) ||
        _seasonRangeRe.hasMatch(t));

/// `S01E01`, `S01E01E02`, `S01E01-E03`, `S01E01-03`.
bool _sxe(String t, Set<int> seasons, Set<int> episodes) {
  if (t.length < 4 || t.codeUnitAt(0) != 0x73 || !_digitAt(t, 1)) return false;
  final m = _sxeRe.firstMatch(t);
  if (m == null) return false;
  seasons
    ..clear()
    ..add(int.parse(m[1]!));
  var prev = int.parse(m[2]!);
  episodes.add(prev);
  final tail = m[3]!;
  var range = false;
  var number = 0, digits = 0;
  for (var i = 0; i <= tail.length; i++) {
    final c = i < tail.length ? tail.codeUnitAt(i) : 0x2D;
    if (c >= 0x30 && c <= 0x39) {
      number = number * 10 + c - 0x30;
      digits++;
      continue;
    }
    if (digits > 0) {
      range ? _addRange(episodes, prev + 1, number) : episodes.add(number);
      prev = number;
      number = digits = 0;
      range = false;
    }
    if (c == 0x2D) range = true;
  }
  return true;
}

/// `1x02`, `1x01-02`, `1x01-1x02`.
bool _xFormat(String t, Set<int> seasons, Set<int> episodes) {
  if (t.length < 4 || !_digitAt(t, 0) || !t.contains('x')) return false;
  final m = _xRe.firstMatch(t);
  if (m == null) return false;
  seasons
    ..clear()
    ..add(int.parse(m[1]!));
  final first = int.parse(m[2]!);
  episodes.add(first);
  if (m[3] != null) _addRange(episodes, first + 1, int.parse(m[3]!));
  return true;
}

/// `S01` → 1.
int? _seasonToken(String t) =>
    t.length >= 2 && t.length <= 3 && t.codeUnitAt(0) == 0x73
    ? _small(t.substring(1))
    : null;

/// `E05`, `EP05`, `E05v2` → 5.
int? _episodeToken(String t) {
  if (t.length < 2 || t.codeUnitAt(0) != 0x65) return null;
  final m = _episodeRe.firstMatch(t);
  if (m == null) return null;
  // A bare "E5" is too ambiguous; require two digits or the "EP" form.
  return (t.startsWith('ep') || m[1]!.length >= 2) ? int.parse(m[1]!) : null;
}

/// `1st`, `2nd`, `3rd`, `4th` → number.
int? _ordinal(String t) {
  if (t.length < 3) return null;
  final suffix = t.substring(t.length - 2);
  if (suffix != 'st' && suffix != 'nd' && suffix != 'rd' && suffix != 'th')
    return null;
  return _small(t.substring(0, t.length - 2));
}

/// A 1–2 digit number (or up to [maxDigits]).
int? _small(String t, [int maxDigits = 2]) =>
    t.length <= maxDigits && _allDigits(t) ? int.parse(t) : null;

int? _year(String t) {
  if (t.length != 4 ||
      !_allDigits(t) ||
      !(t.startsWith('19') || t.startsWith('20'))) {
    return null;
  }
  final y = int.parse(t);
  return y <= _maxYear ? y : null;
}

/// Anime episode number: `05`, `1071`, `05v2`, never a year.
int? _animeNumber(String t) {
  final v = t.indexOf('v');
  final digits = v > 0 && v == t.length - 2 && _digitAt(t, v + 1)
      ? t.substring(0, v)
      : t;
  if (digits.length > 4 || !_allDigits(digits) || _year(digits) != null)
    return null;
  return int.parse(digits);
}

/// `01-12` / `01~12` (not years).
(int, int)? _numberRange(String t) {
  final dash = t.indexOf('-') > 0 ? t.indexOf('-') : t.indexOf('~');
  if (dash <= 0) return null;
  final a = _animeNumber(t.substring(0, dash));
  final b = _animeNumber(t.substring(dash + 1));
  return a == null || b == null ? null : (a, b);
}

/// `1920x1080` style tokens.
Resolution? _widthHeight(String t) {
  final x = t.indexOf('x');
  if (x < 3 || x > 4 || t.length - x - 1 < 3 || t.length - x - 1 > 4)
    return null;
  final w = t.substring(0, x), h = t.substring(x + 1);
  if (!_allDigits(w) || !_allDigits(h)) return null;
  // Width as 16:9 lines, so cropped 1920x800 still counts as 1080p.
  return resolutionForLines(math.max(int.parse(w) * 9 ~/ 16, int.parse(h)));
}

bool _isChannels(String t) =>
    t.length == 3 &&
    t.codeUnitAt(1) == 0x2E &&
    '125678'.contains(t[0]) &&
    '012'.contains(t[2]);

/// `DDP5.1`, `AAC2.0`, `DD+5.1`, `TrueHD7.1`, `DDP5` → (codec, channels).
(AudioCodec, String)? _audioWithChannels(String t) {
  var d = 0;
  while (d < t.length && !_digitAt(t, d)) {
    d++;
  }
  if (d == 0 || d == t.length) return null;
  final codec = audioCodecs[t.substring(0, d)];
  final rest = t.substring(d);
  if (codec == null ||
      !(_isChannels(rest) || (rest.length == 1 && '25678'.contains(rest)))) {
    return null;
  }
  return (codec, rest);
}

/// Adds `from..to` to [into] when it is a sane range; returns whether it did.
bool _addRange(Set<int> into, int from, int to) {
  if (to < from || to - from > 2000) return false;
  for (var i = from; i <= to; i++) {
    into.add(i);
  }
  return true;
}

/// `…x264-GROUP`, `…x264-GROUP[rarbg]`, `… - GROUP` → (dash index, group).
(int, String)? _trailingDashGroup(String s) {
  var end = s.length;
  // Skip trailing "[rarbg]" / "(x)" distribution tags.
  while (end > 0) {
    final c = s.codeUnitAt(end - 1);
    if (c == 0x20) {
      end--;
    } else if (c == 0x5D || c == 0x29) {
      final open = s.lastIndexOf(c == 0x5D ? '[' : '(', end - 1);
      if (open <= 0) break;
      end = open;
    } else {
      break;
    }
  }
  if (end == 0) return null;
  final dash = s.lastIndexOf('-', end - 1);
  if (dash < 0) return null;
  var start = dash + 1;
  if (start < end && s.codeUnitAt(start) == 0x20) start++;
  if (start >= end) return null;
  for (var i = start; i < end; i++) {
    final c = s.codeUnitAt(i);
    final ok =
        (c >= 0x30 && c <= 0x39) ||
        (c >= 0x41 && c <= 0x5A) ||
        (c >= 0x61 && c <= 0x7A) ||
        (i > start && (c == 0x5F || c == 0x2E || c == 0x40 || c == 0x26));
    if (!ok) return null;
  }
  return (dash, s.substring(start, end));
}

bool _plausibleGroup(String g, {bool leading = false}) {
  if (g.isEmpty || g.length > 30 || (!leading && g.contains(' '))) return false;
  final lower = g.toLowerCase();
  if ('.'.allMatches(g).length > 1 ||
      lower.startsWith('www.') ||
      lower.endsWith('.com') ||
      lower.endsWith('.org') ||
      _allDigits(g) ||
      _animeNumber(lower) != null ||
      notGroups.contains(lower) ||
      vocabulary.contains(lower) ||
      releaseLanguageWords.containsKey(lower) ||
      isCodeList(g)) {
    return false;
  }
  for (final part in g.split(_groupPartRe)) {
    final p = part.toLowerCase();
    if (_isTagWord(part, p) ||
        _year(part) != null ||
        vocabulary.contains(p) ||
        notGroups.contains(p) ||
        releaseLanguageWords.containsKey(p)) {
      return false;
    }
  }
  return true;
}
