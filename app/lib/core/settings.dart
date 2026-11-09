import 'dart:convert';

/// When subtitles turn on by themselves.
enum SubtitleMode {
  /// On when the audio isn't in your first language.
  auto,

  /// Always on in your first available language.
  always,

  /// Only forced subtitles (signs, foreign dialogue).
  forcedOnly,

  /// Never by default.
  off,
}

/// How subtitles look.
final class SubtitleStyle {
  const SubtitleStyle({
    this.scale = 1.0,
    this.color = 0xFFF5EEE4,
    this.backgroundOpacity = 0.0,
    this.outline = true,
    this.bold = false,
    this.bottomMargin = 0.06,
  });

  factory SubtitleStyle.fromJson(Map<String, Object?> j) => SubtitleStyle(
    scale: (j['scale'] as num? ?? 1).toDouble(),
    color: (j['color'] as num? ?? 0xFFF5EEE4).toInt(),
    backgroundOpacity: (j['bg'] as num? ?? 0).toDouble(),
    outline: j['outline'] as bool? ?? true,
    bold: j['bold'] as bool? ?? false,
    bottomMargin: (j['bottom'] as num? ?? 0.06).toDouble(),
  );

  /// 0.6 – 2.0 relative to the default size.
  final double scale;
  final int color;

  /// 0 = no box, 1 = solid black box behind the text.
  final double backgroundOpacity;
  final bool outline;
  final bool bold;

  /// Distance from the bottom as a fraction of the video height.
  final double bottomMargin;

  Map<String, Object?> toJson() => {
    'scale': scale,
    'color': color,
    'bg': backgroundOpacity,
    'outline': outline,
    'bold': bold,
    'bottom': bottomMargin,
  };

  SubtitleStyle copyWith({
    double? scale,
    int? color,
    double? backgroundOpacity,
    bool? outline,
    bool? bold,
    double? bottomMargin,
  }) => SubtitleStyle(
    scale: scale ?? this.scale,
    color: color ?? this.color,
    backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
    outline: outline ?? this.outline,
    bold: bold ?? this.bold,
    bottomMargin: bottomMargin ?? this.bottomMargin,
  );

  @override
  bool operator ==(Object other) =>
      other is SubtitleStyle &&
      jsonEncode(toJson()) == jsonEncode(other.toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

/// Everything the user can change. Stored as one JSON document.
/// The keyless OpenSubtitles source (on unless the user turns it off).
const freeOpenSubtitlesId = 'opensubtitles-free';

final class AppSettings {
  const AppSettings({
    this.onboarded = false,
    this.subtitleLanguages = const [],
    this.audioLanguages = const ['original'],
    this.subtitleMode = SubtitleMode.auto,
    this.preferHearingImpaired = false,
    this.subtitleStyle = const SubtitleStyle(),
    this.maxResolution = 1080,
    this.dataSaver = false,
    this.autoplayNext = true,
    this.skipIntros = true,
    this.wifiOnlyDownloads = true,
    this.autoDownloadNext = false,
    this.keepCompletedStreams = true,
    this.deleteWatchedDownloads = false,
    this.seedWhileWatching = true,
    this.seedAfterDownload = false,
    this.uploadLimitKBps = 0,
    this.downloadLimitKBps = 0,
    this.keepStreamsHours = 0,
    this.updateChecks = true,
    this.vpnInterface = '',
    this.enabledSubtitleProviders = const [freeOpenSubtitlesId],
    this.lastCastDevice,
  });

  factory AppSettings.fromJson(Map<String, Object?> j) => AppSettings(
    onboarded: j['onboarded'] as bool? ?? false,
    subtitleLanguages: _strings(j['subtitleLanguages']),
    audioLanguages: _strings(j['audioLanguages'], fallback: const ['original']),
    subtitleMode:
        SubtitleMode.values.asNameMap()[j['subtitleMode']] ?? SubtitleMode.auto,
    preferHearingImpaired: j['preferHearingImpaired'] as bool? ?? false,
    subtitleStyle: j['subtitleStyle'] is Map<String, Object?>
        ? SubtitleStyle.fromJson(j['subtitleStyle']! as Map<String, Object?>)
        : const SubtitleStyle(),
    maxResolution: (j['maxResolution'] as num? ?? 1080).toInt(),
    dataSaver: j['dataSaver'] as bool? ?? false,
    autoplayNext: j['autoplayNext'] as bool? ?? true,
    skipIntros: j['skipIntros'] as bool? ?? true,
    wifiOnlyDownloads: j['wifiOnlyDownloads'] as bool? ?? true,
    autoDownloadNext: j['autoDownloadNext'] as bool? ?? false,
    keepCompletedStreams: j['keepCompletedStreams'] as bool? ?? true,
    deleteWatchedDownloads: j['deleteWatchedDownloads'] as bool? ?? false,
    seedWhileWatching: j['seedWhileWatching'] as bool? ?? true,
    seedAfterDownload: j['seedAfterDownload'] as bool? ?? false,
    uploadLimitKBps: (j['uploadLimitKBps'] as num? ?? 0).toInt(),
    downloadLimitKBps: (j['downloadLimitKBps'] as num? ?? 0).toInt(),
    keepStreamsHours: (j['keepStreamsHours'] as num? ?? 0).toInt(),
    updateChecks: j['updateChecks'] as bool? ?? true,
    vpnInterface: j['vpnInterface'] as String? ?? '',
    // Settings saved before the keyless OpenSubtitles existed get it on once.
    enabledSubtitleProviders: [
      ..._strings(j['enabledSubtitleProviders']),
      if (j['freeOpenSubtitlesOffered'] != true) freeOpenSubtitlesId,
    ],
    lastCastDevice: j['lastCastDevice'] as Map<String, Object?>?,
  );

  static List<String> _strings(Object? v, {List<String> fallback = const []}) =>
      v is List ? List.unmodifiable(v.whereType<String>()) : fallback;

  final bool onboarded;

  /// Subtitle languages in order of preference (e.g. `ar`, `en`).
  final List<String> subtitleLanguages;

  /// Audio languages in order; `original` means the film's own language.
  final List<String> audioLanguages;
  final SubtitleMode subtitleMode;
  final bool preferHearingImpaired;
  final SubtitleStyle subtitleStyle;

  /// Highest resolution to pick automatically (p).
  final int maxResolution;

  /// Prefer smaller files.
  final bool dataSaver;
  final bool autoplayNext;
  final bool skipIntros;
  final bool wifiOnlyDownloads;
  final bool autoDownloadNext;

  /// Streams that reach 100% move into Downloads instead of being deleted.
  final bool keepCompletedStreams;
  final bool deleteWatchedDownloads;

  /// Keep sharing while a stream plays (helps the swarm, costs upload).
  final bool seedWhileWatching;
  final bool seedAfterDownload;

  /// 0 = no limit.
  final int uploadLimitKBps;
  final int downloadLimitKBps;

  /// How long streamed data stays on the device after you stop watching.
  final int keepStreamsHours;

  /// Tell about new Kinora versions (from GitHub releases) at launch.
  final bool updateChecks;

  /// Only connect through this network interface (VPN), '' = any.
  final String vpnInterface;

  /// Subtitle provider ids the user turned on (none by default).
  final List<String> enabledSubtitleProviders;
  final Map<String, Object?>? lastCastDevice;

  /// The user's first subtitle language, if any.
  String? get primaryLanguage =>
      subtitleLanguages.isEmpty ? null : subtitleLanguages.first;

  Map<String, Object?> toJson() => {
    'onboarded': onboarded,
    'subtitleLanguages': subtitleLanguages,
    'audioLanguages': audioLanguages,
    'subtitleMode': subtitleMode.name,
    'preferHearingImpaired': preferHearingImpaired,
    'subtitleStyle': subtitleStyle.toJson(),
    'maxResolution': maxResolution,
    'dataSaver': dataSaver,
    'autoplayNext': autoplayNext,
    'skipIntros': skipIntros,
    'wifiOnlyDownloads': wifiOnlyDownloads,
    'autoDownloadNext': autoDownloadNext,
    'keepCompletedStreams': keepCompletedStreams,
    'deleteWatchedDownloads': deleteWatchedDownloads,
    'seedWhileWatching': seedWhileWatching,
    'seedAfterDownload': seedAfterDownload,
    'uploadLimitKBps': uploadLimitKBps,
    'downloadLimitKBps': downloadLimitKBps,
    'keepStreamsHours': keepStreamsHours,
    'updateChecks': updateChecks,
    'vpnInterface': vpnInterface,
    'enabledSubtitleProviders': enabledSubtitleProviders,
    'freeOpenSubtitlesOffered': true,
    'lastCastDevice': lastCastDevice,
  };

  AppSettings copyWith({
    bool? onboarded,
    List<String>? subtitleLanguages,
    List<String>? audioLanguages,
    SubtitleMode? subtitleMode,
    bool? preferHearingImpaired,
    SubtitleStyle? subtitleStyle,
    int? maxResolution,
    bool? dataSaver,
    bool? autoplayNext,
    bool? skipIntros,
    bool? wifiOnlyDownloads,
    bool? autoDownloadNext,
    bool? keepCompletedStreams,
    bool? deleteWatchedDownloads,
    bool? seedWhileWatching,
    bool? seedAfterDownload,
    int? uploadLimitKBps,
    int? downloadLimitKBps,
    int? keepStreamsHours,
    bool? updateChecks,
    String? vpnInterface,
    List<String>? enabledSubtitleProviders,
    Map<String, Object?>? lastCastDevice,
  }) => AppSettings(
    onboarded: onboarded ?? this.onboarded,
    subtitleLanguages: subtitleLanguages ?? this.subtitleLanguages,
    audioLanguages: audioLanguages ?? this.audioLanguages,
    subtitleMode: subtitleMode ?? this.subtitleMode,
    preferHearingImpaired: preferHearingImpaired ?? this.preferHearingImpaired,
    subtitleStyle: subtitleStyle ?? this.subtitleStyle,
    maxResolution: maxResolution ?? this.maxResolution,
    dataSaver: dataSaver ?? this.dataSaver,
    autoplayNext: autoplayNext ?? this.autoplayNext,
    skipIntros: skipIntros ?? this.skipIntros,
    wifiOnlyDownloads: wifiOnlyDownloads ?? this.wifiOnlyDownloads,
    autoDownloadNext: autoDownloadNext ?? this.autoDownloadNext,
    keepCompletedStreams: keepCompletedStreams ?? this.keepCompletedStreams,
    deleteWatchedDownloads:
        deleteWatchedDownloads ?? this.deleteWatchedDownloads,
    seedWhileWatching: seedWhileWatching ?? this.seedWhileWatching,
    seedAfterDownload: seedAfterDownload ?? this.seedAfterDownload,
    uploadLimitKBps: uploadLimitKBps ?? this.uploadLimitKBps,
    downloadLimitKBps: downloadLimitKBps ?? this.downloadLimitKBps,
    keepStreamsHours: keepStreamsHours ?? this.keepStreamsHours,
    updateChecks: updateChecks ?? this.updateChecks,
    vpnInterface: vpnInterface ?? this.vpnInterface,
    enabledSubtitleProviders:
        enabledSubtitleProviders ?? this.enabledSubtitleProviders,
    lastCastDevice: lastCastDevice ?? this.lastCastDevice,
  );
}
