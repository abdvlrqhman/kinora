import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:collection/collection.dart';

import 'errors.dart';
import 'language.dart';
import 'models.dart';
import 'parsers.dart';
import 'release.dart';

/// A subtitle file taken out of a download (or the download itself).
final class SubtitleFile {
  const SubtitleFile(this.fileName, this.bytes);

  final String fileName;
  final Uint8List bytes;

  @override
  bool operator ==(Object other) =>
      other is SubtitleFile &&
      other.fileName == fileName &&
      const ListEquality<int>().equals(other.bytes, bytes);

  @override
  int get hashCode => Object.hash(fileName, bytes.length);

  @override
  String toString() => 'SubtitleFile($fileName, ${bytes.length} B)';
}

/// `zip`, `rar`, `7z`, `gzip` or null (not an archive), from magic bytes.
String? archiveKind(List<int> b) {
  bool magic(List<int> m) =>
      b.length >= m.length &&
      Iterable<int>.generate(m.length).every((i) => b[i] == m[i]);
  if (magic(const [0x50, 0x4B, 0x03, 0x04]) ||
      magic(const [0x50, 0x4B, 0x05, 0x06])) {
    return 'zip';
  }
  if (magic(const [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07])) return 'rar';
  if (magic(const [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C])) return '7z';
  if (magic(const [0x1F, 0x8B])) return 'gzip';
  return null;
}

const _subtitleExts = {'srt', 'ass', 'ssa', 'vtt', 'sub'};
const _formatRank = {
  'srt': 5,
  'ass': 4,
  'ssa': 4,
  'vtt': 3,
  'sub': 1,
  'txt': 0,
};

/// Returns the subtitle file to use from [download].
///
/// Non-archives are returned as-is. ZIPs (also nested one level, and gzip)
/// are opened and the best entry picked: the wanted [season]/[episode]
/// (entries for other episodes are skipped), the [language], [forced] and
/// [hearingImpaired] variants, then SRT > ASS > VTT > SUB. `.nfo`, VobSub
/// `.sub`+`.idx` pairs and `.txt` notes are ignored (`.txt` files whose content
/// is MPL2/MicroDVD/SRT are kept, ranked last). Throws [SubtitleArchiveException]
/// for RAR/7z or when nothing usable is inside.
SubtitleFile extractSubtitle(
  SubtitleDownload download, {
  int? season,
  int? episode,
  Language? language,
  bool forced = false,
  bool hearingImpaired = false,
  ReleaseNameParser parser = parseReleaseName,
}) {
  final kind = archiveKind(download.bytes);
  if (kind == null) return SubtitleFile(download.fileName, download.bytes);
  final entries = _entries(download.bytes, kind, depth: 0);
  final names = {for (final e in entries) e.fileName.toLowerCase()};
  SubtitleFile? best;
  var bestScore = -1 << 30;
  for (final e in entries) {
    final lower = e.fileName.toLowerCase();
    final ext = lower.split('.').last;
    if (e.bytes.isEmpty) continue;
    // .txt is usually notes, but MPL2/MicroDVD files use it too.
    if (ext == 'txt' && !_looksLikeSubtitle(e.bytes)) continue;
    if (!_subtitleExts.contains(ext) && ext != 'txt') continue;
    if (ext == 'sub' &&
        names.contains('${lower.substring(0, lower.length - 3)}idx')) {
      continue; // VobSub images
    }
    final base = e.fileName.split('/').last;
    final info = parser(base);
    var score = _formatRank[ext]!;
    if (episode != null && info.episodes.isNotEmpty) {
      if (!info.episodes.contains(episode)) continue;
      score += 100;
    }
    if (season != null && info.season != null && info.season != season) {
      continue;
    }
    final lang = languageFromFileName(base);
    if (language != null && lang != null) score += lang == language ? 20 : -20;
    final isForced = RegExp(r'\bforced\b', caseSensitive: false).hasMatch(base);
    score += isForced == forced ? 3 : -10;
    final isHi = RegExp(
      r'\b(sdh|hi|cc|hearing)\b',
      caseSensitive: false,
    ).hasMatch(base.replaceAll(RegExp(r'[._]'), ' '));
    score += isHi == hearingImpaired ? 2 : -2;
    if (score > bestScore) {
      bestScore = score;
      best = e;
    }
  }
  if (best == null) {
    throw SubtitleArchiveException(
      'no subtitle${episode == null ? '' : ' for episode $episode'} '
      'in ${download.fileName}',
    );
  }
  return best;
}

bool _looksLikeSubtitle(Uint8List bytes) =>
    detectFormat(
      latin1.decode(bytes.sublist(0, bytes.length.clamp(0, 4096))),
    ) !=
    null;

List<SubtitleFile> _entries(
  Uint8List bytes,
  String kind, {
  required int depth,
}) {
  if (kind == 'rar' || kind == '7z') {
    throw SubtitleArchiveException(
      '${kind.toUpperCase()} archives are not supported',
      unsupportedFormat: kind,
    );
  }
  try {
    if (kind == 'gzip') {
      final inner = Uint8List.fromList(const GZipDecoder().decodeBytes(bytes));
      final innerKind = archiveKind(inner);
      if (innerKind != null && depth < 1) {
        return _entries(inner, innerKind, depth: depth + 1);
      }
      return [SubtitleFile('subtitle.srt', inner)];
    }
    final out = <SubtitleFile>[];
    for (final f in ZipDecoder().decodeBytes(bytes)) {
      if (!f.isFile) continue;
      final data = f.readBytes();
      if (data == null) continue;
      final innerKind = archiveKind(data);
      if (innerKind != null && depth < 1) {
        out.addAll(_entries(data, innerKind, depth: depth + 1));
      } else {
        out.add(SubtitleFile(f.name, data));
      }
    }
    return out;
  } on SubtitleArchiveException {
    rethrow;
  } on Exception catch (e) {
    throw SubtitleArchiveException('corrupt $kind archive: ${e.runtimeType}');
  }
}

const _notLanguageTokens = {'hi', 'sdh', 'cc', 'it', 'me', 'no', 'ma', 'am'};

/// Language named in a subtitle file name (`Show.S01E01.ar.srt`,
/// `movie_eng.srt`, `Movie.Arabic.srt`, `[English] ...`), looking at the last
/// three tokens; null if none. Short tokens must be lower or upper case and
/// name a major language, so title words like "Sun" or "Man" don't count.
Language? languageFromFileName(String fileName) {
  final base = fileName.split('/').last.replaceFirst(RegExp(r'\.[^.]+$'), '');
  final bracket = RegExp(r'\[([A-Za-z ]{4,})\]').firstMatch(base);
  if (bracket != null) {
    final l = Language.parse(bracket.group(1));
    if (l != null) return l;
  }
  final tokens = base
      .split(RegExp(r'[\s._\-\[\]()]+'))
      .where((t) => t.isNotEmpty)
      .toList();
  for (final t in tokens.reversed.take(3)) {
    final lower = t.toLowerCase();
    if (_notLanguageTokens.contains(lower) || RegExp(r'\d').hasMatch(t)) {
      continue;
    }
    if (t.length <= 3) {
      if (t != lower && t != t.toUpperCase()) continue;
      final l = Language.parse(lower);
      if (l != null && (l.baseCode.length == 2 || l.code.contains('-'))) {
        return l;
      }
      continue;
    }
    final l = Language.parse(lower);
    if (l != null) return l;
  }
  return null;
}
