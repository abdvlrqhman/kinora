import 'package:media_kit/media_kit.dart';

/// A subtitle the viewer can pick: embedded track or external file.
final class SubtitleOption {
  const SubtitleOption({
    required this.id,
    required this.language,
    required this.label,
    this.track,
    this.uri,
    this.hearingImpaired = false,
    this.forced = false,
    this.detail,
    this.fit,
    this.provider,
    this.load,
  });

  final String id;

  /// Normalized code ("ar"), null when unknown.
  final String? language;
  final String label;

  /// Embedded track.
  final SubtitleTrack? track;

  /// External file or URL.
  final String? uri;
  final bool hearingImpaired;
  final bool forced;

  /// Provider / release name line.
  final String? detail;

  /// 0..1 how well it fits this release (external only).
  final double? fit;

  /// The site it comes from (external only).
  final String? provider;

  /// Downloads/converts an external subtitle when picked; returns a path.
  final Future<String?> Function()? load;

  String get variant =>
      forced ? 'forced' : (hearingImpaired ? 'sdh' : 'normal');
}
