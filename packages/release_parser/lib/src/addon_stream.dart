import 'enums.dart';
import 'languages.dart';
import 'parsed_release.dart';
import 'parser.dart';

// Metadata markers used by Torrentio, Knightcrawler, Comet, MediaFusion,
// StremThru, Jackettio, Peerflix and Orion stream texts.
final _metaLineRe = RegExp(
  '(?:👤|👥|💾|📦|⚙|🔎|🔍|🔗|☁|📺|🎞|🎨|🎵|🔊|📹|⭐|🏷|👂|💿|🎥|🎧|💬|🎙|🌐|ℹ|⬇|⚡|🧲)'
  r'|^(?:seeders|seeds|size|source|languages?)\s*:',
  caseSensitive: false,
);
final _videoFileRe = RegExp(
  r'\.(?:mkv|mp4|avi|m4v|mov|wmv|webm|ts|m2ts)$',
  caseSensitive: false,
);
final _sizeRe = RegExp(
  r'(💾|📦|size\s*:?)\s*([\d]+(?:[.,]\d+)?)\s*([KMGT]i?B|B)(?![a-z])',
  caseSensitive: false,
);
final _statsRe = RegExp(
  r'(?:💾|📦|size\s*:?)\s*[\d.,]+\s*[KMGT]?i?B(?![a-z])|(?:👤|👥|🌱|seeders\s*:?|seeds\s*:?)\s*\d+',
  caseSensitive: false,
);
final _seedersRe = RegExp(
  r'(?:👤|👥|🌱)\s*(\d+)|(?:seeders|seeds)\s*:?\s*(\d+)',
  caseSensitive: false,
);
// Value runs until the next emoji / symbol or end of line.
const _value =
    r'\s*([A-Za-z0-9][^\n\u2000-\u2BFF\u{1F000}-\u{1FFFF}|]*(?:\|[^\n\u2000-\u2BFF\u{1F000}-\u{1FFFF}]+)?)';
final _gearRe = RegExp('\u2699\uFE0F?$_value', unicode: true);
final _indexerRe = RegExp('(?:🔎|🔍|🔗|\u2601\uFE0F?)$_value', unicode: true);
final _globeRe = RegExp('🌐$_value', unicode: true);
final _sourceRe = RegExp(
  '(?:^|\\n)source\\s*:$_value',
  caseSensitive: false,
  unicode: true,
);
final _flagRe = RegExp(r'[\u{1F1E6}-\u{1F1FF}]{2}', unicode: true);
final _langLineRe = RegExp(
  r'^\s*(?:languages?\s*:|🌐|👂|🎙\uFE0F?|💬)\s*(.+)$',
  caseSensitive: false,
  unicode: true,
);
final _tokenSepRe = RegExp(r'[\s/,+|•]+');
final _docMarkRe = RegExp(r'^(?:📄|📁)\s*');
final _debridTagRe = RegExp(r'^\s*\[[^\]]*\]\s*');
final _cachedRe = RegExp(
  r'\[[A-Z]{2,4}\+\]|⚡|\binstant\b',
  caseSensitive: false,
);
final _uncachedRe = RegExp(
  r'\[[A-Z]{2,4} download\]|⬇|⏳|not cached|uncached',
  caseSensitive: false,
);

/// Parses one Stremio stream object from a torrent/debrid addon.
///
/// The release name is `filename` (`behaviorHints.filename`) when given,
/// else the first line naming a video file (`Show.S01E02.mkv` inside a
/// pack), else Comet/StremThru's `📄` line, else the first plain line of
/// [title] / [description]. Tags missing from that name (resolution in
/// `name: "Torrentio\n4k DV | HDR"`, MediaFusion's `📺 BluRay 🎞️ hevc`
/// line, the torrent title above a file line ...) are filled in from the
/// remaining text. Size, seeders, provider, flag languages and the debrid
/// cache marker come from the emoji / `Size:` / `Seeders:` lines.
ParsedRelease parseAddonStream({
  String? name,
  String? title,
  String? description,
  String? filename,
}) {
  final text = [title, description].whereType<String>().join('\n');
  String? fileLine, docLine, plainLine;
  final rest = <String>[];
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('📄') || line.startsWith('📁')) {
      final value = line.replaceFirst(_docMarkRe, '');
      if (line.startsWith('📄')) docLine ??= value;
      rest.add(value);
    } else if (_metaLineRe.hasMatch(line)) {
      rest.add(line.replaceAll(_statsRe, ' '));
    } else {
      if (_videoFileRe.hasMatch(line)) fileLine ??= line.split('/').last;
      plainLine ??= line;
      rest.add(line);
    }
  }
  final hint = filename?.trim();
  final releaseName = (hint != null && hint.isNotEmpty)
      ? hint.split('/').last
      : fileLine ?? docLine ?? plainLine ?? '';

  final primary = parseRelease(releaseName);
  // The addon name goes last and loses its "[RD+]" tag so it can't be
  // mistaken for an anime group or a title.
  final others = [
    ...rest.where(
      (l) =>
          releaseName.isEmpty || (l != releaseName && !l.endsWith(releaseName)),
    ),
    ?name?.replaceFirst(_debridTagRe, ''),
  ].join(' ').replaceAll('\n', ' ');
  final secondary = parseRelease(others);

  final all = '${name ?? ''}\n$text';
  final languages = {...primary.languages, ...secondary.languages};
  final subtitleLanguages = {
    ...primary.subtitleLanguages,
    ...secondary.subtitleLanguages,
  };
  for (final line in all.split('\n')) {
    // StremThru lists subtitle flags after 💬.
    final into = line.contains('💬') ? subtitleLanguages : languages;
    for (final m in _flagRe.allMatches(line)) {
      final country = String.fromCharCodes(
        m[0]!.runes.map((r) => r - 0x1F1E6 + 0x41),
      );
      final lang = countryLanguages[country];
      if (lang != null) into.add(lang);
    }
    final list = _langLineRe.firstMatch(line);
    if (list != null) into.addAll(_languageCodes(list[1]!));
  }

  final gear = _clean(_gearRe.firstMatch(text)?[1]);
  final indexer = _clean(_indexerRe.firstMatch(text)?[1]);
  final globe = _clean(_globeRe.firstMatch(text)?[1]);
  // StremThru shows the group after ⚙️ and the indexer after 🔍; everyone
  // else puts the provider after ⚙️. Peerflix puts it after 🌐, which
  // MediaFusion uses for languages.
  final provider =
      indexer ??
      gear ??
      _clean(_sourceRe.firstMatch(text)?[1]) ??
      (globe != null && _languageCodes(globe).isEmpty ? globe : null);
  final group = primary.group ?? (indexer != null ? gear : null);

  final bool? cached = _cachedRe.hasMatch(all)
      ? true
      : _uncachedRe.hasMatch(all)
      ? false
      : null;

  final p = primary, s = secondary;
  return ParsedRelease(
    raw: releaseName,
    // A bare "05.mkv" inside a pack has no usable title of its own.
    title:
        (p.title.isNotEmpty && int.tryParse(p.title) == null) ||
            plainLine == null
        ? p.title
        : parseRelease(plainLine).title,
    year: p.year ?? s.year,
    seasons: p.hasEpisodeInfo ? p.seasons : s.seasons,
    episodes: p.hasEpisodeInfo ? p.episodes : s.episodes,
    absoluteEpisode: p.hasEpisodeInfo ? p.absoluteEpisode : s.absoluteEpisode,
    isSeasonPack: p.hasEpisodeInfo ? p.isSeasonPack : s.isSeasonPack,
    isCompleteSeries: p.hasEpisodeInfo
        ? p.isCompleteSeries
        : s.isCompleteSeries,
    resolution: p.resolution != Resolution.unknown
        ? p.resolution
        : s.resolution,
    source: p.source != Source.unknown ? p.source : s.source,
    videoCodec: p.videoCodec != VideoCodec.unknown
        ? p.videoCodec
        : s.videoCodec,
    bitDepth: p.bitDepth ?? s.bitDepth,
    hdr: p.hdr.isNotEmpty ? p.hdr : s.hdr,
    audioCodecs: p.audioCodecs.isNotEmpty ? p.audioCodecs : s.audioCodecs,
    atmos: p.atmos || s.atmos,
    channels: p.channels ?? s.channels,
    languages: languages,
    subtitleLanguages: subtitleLanguages,
    multiAudio: p.multiAudio || s.multiAudio,
    dualAudio: p.dualAudio || s.dualAudio,
    dubbed: p.dubbed || s.dubbed,
    hardcodedSubs: p.hardcodedSubs || s.hardcodedSubs,
    group: group,
    proper: p.proper || s.proper,
    repack: p.repack || s.repack,
    extended: p.extended || s.extended,
    imax: p.imax || s.imax,
    threeD: p.threeD || s.threeD,
    container: p.container,
    sizeBytes: _size(text),
    seeders: _seeders(text),
    provider: provider,
    debridCached: cached,
  );
}

/// ISO codes or language words in a list like `English + Hindi`, `EN FR`.
Set<String> _languageCodes(String list) => {
  for (final t in list.split(_tokenSepRe))
    if (isoCodes.contains(t.toLowerCase()))
      t.toLowerCase()
    else if (releaseLanguageWords[t.toLowerCase()] case final code?)
      code,
};

String? _clean(String? v) {
  if (v == null) return null;
  final t = v.trim();
  if (t.isEmpty) return null;
  // Comet / MediaFusion prefix the scraper: "Comet|TorrentGalaxy".
  final last = t.split('|').last.trim();
  return last.isEmpty ? null : last;
}

int? _size(String text) {
  RegExpMatch? best;
  for (final m in _sizeRe.allMatches(text)) {
    // 💾 is the file size; 📦 / Size: may be the whole pack.
    if (m[1] == '💾') {
      best = m;
      break;
    }
    best ??= m;
  }
  if (best == null) return null;
  final value = double.tryParse(best[2]!.replaceAll(',', '.'));
  if (value == null) return null;
  final unit = best[3]!.toUpperCase()[0];
  final exp = switch (unit) {
    'K' => 1,
    'M' => 2,
    'G' => 3,
    'T' => 4,
    _ => 0,
  };
  var bytes = value;
  for (var i = 0; i < exp; i++) {
    bytes *= 1024;
  }
  return bytes.round();
}

int? _seeders(String text) {
  final m = _seedersRe.firstMatch(text);
  return m == null ? null : int.parse(m[1] ?? m[2]!);
}
