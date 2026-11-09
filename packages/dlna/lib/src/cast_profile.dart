import 'protocol_info.dart';

/// File container of a video.
enum CastContainer {
  /// Matroska.
  mkv('MKV', ['video/x-matroska', 'video/x-mkv']),

  /// MPEG-4 Part 14.
  mp4('MP4', ['video/mp4']),

  /// MPEG transport stream (.ts/.m2ts).
  ts('MPEG-TS', ['video/mp2t', 'video/mpeg', 'video/vnd.dlna.mpeg-tts']),

  /// AVI.
  avi('AVI', ['video/x-msvideo', 'video/avi', 'video/x-avi', 'video/divx']),

  /// QuickTime.
  mov('MOV', ['video/quicktime']),

  /// WebM.
  webm('WebM', ['video/webm']);

  const CastContainer(this.label, this.mimeTypes);

  /// Display name used in reasons.
  final String label;

  /// MIME types renderers use for this container, preferred first.
  final List<String> mimeTypes;

  /// The MIME type to announce to a renderer: the first of [mimeTypes] its
  /// [sink] protocols accept, else the preferred one.
  String mimeTypeFor(Iterable<ProtocolInfo> sink) {
    final accepted = {for (final p in sink) p.mimeType};
    return mimeTypes.firstWhere(
      accepted.contains,
      orElse: () => mimeTypes.first,
    );
  }
}

/// Video codec.
enum VideoCodec {
  /// H.264 / AVC (x264).
  h264('H.264'),

  /// H.265 / HEVC (x265).
  hevc('HEVC'),

  /// AV1.
  av1('AV1'),

  /// VP9.
  vp9('VP9'),

  /// MPEG-4 Part 2 (XviD/DivX).
  mpeg4('MPEG-4 (XviD/DivX)'),

  /// MPEG-2.
  mpeg2('MPEG-2');

  const VideoCodec(this.label);

  /// Display name used in reasons.
  final String label;
}

/// Audio codec.
enum AudioCodec {
  /// AAC / HE-AAC.
  aac('AAC'),

  /// Dolby Digital.
  ac3('Dolby Digital (AC3)'),

  /// Dolby Digital Plus (incl. Atmos in DD+).
  eac3('Dolby Digital Plus (E-AC3)'),

  /// MP3.
  mp3('MP3'),

  /// DTS, DTS-HD, DTS:X.
  dts('DTS'),

  /// Dolby TrueHD (incl. Atmos in TrueHD).
  truehd('Dolby TrueHD'),

  /// FLAC.
  flac('FLAC'),

  /// Opus.
  opus('Opus'),

  /// Vorbis.
  vorbis('Vorbis'),

  /// Linear PCM.
  pcm('PCM');

  const AudioCodec(this.label);

  /// Display name used in reasons.
  final String label;
}

/// High dynamic range format.
enum HdrFormat {
  /// HDR10.
  hdr10('HDR10'),

  /// HDR10+ (always carries an HDR10 base).
  hdr10Plus('HDR10+'),

  /// Hybrid Log-Gamma.
  hlg('HLG'),

  /// Dolby Vision (any profile).
  dolbyVision('Dolby Vision');

  const HdrFormat(this.label);

  /// Display name used in reasons.
  final String label;
}

/// Subtitle format.
enum SubtitleFormat {
  /// SubRip.
  srt('SRT'),

  /// Advanced SubStation Alpha.
  ass('ASS'),

  /// SubStation Alpha.
  ssa('SSA'),

  /// SAMI.
  smi('SAMI'),

  /// WebVTT.
  vtt('WebVTT'),

  /// Blu-ray image subtitles.
  pgs('PGS'),

  /// DVD image subtitles.
  vobsub('VobSub');

  const SubtitleFormat(this.label);

  /// Display name used in reasons.
  final String label;
}

/// How a renderer supports one video codec.
final class VideoCodecSupport {
  /// Creates a support entry.
  const VideoCodecSupport({this.maxBitDepth = 8, this.containers});

  /// Highest decodable bit depth (8 or 10).
  final int maxBitDepth;

  /// Containers the codec is accepted in; null means any supported container.
  final Set<CastContainer>? containers;

  @override
  bool operator ==(Object other) =>
      other is VideoCodecSupport &&
      other.maxBitDepth == maxBitDepth &&
      _setEquals(other.containers, containers);

  @override
  int get hashCode => Object.hash(
    maxBitDepth,
    containers == null ? null : Object.hashAllUnordered(containers!),
  );

  @override
  String toString() =>
      'VideoCodecSupport($maxBitDepth-bit${containers == null ? '' : ', ${containers!.map((c) => c.name).join('/')}'})';
}

/// What a media file contains (from the release parser or file probing).
/// Null/empty fields are unknown and are not checked.
final class MediaTraits {
  /// Creates traits.
  const MediaTraits({
    this.container,
    this.videoCodec,
    this.videoBitDepth,
    this.width,
    this.height,
    this.hdr = const {},
    this.audioCodec,
    this.subtitleFormat,
  });

  /// File container.
  final CastContainer? container;

  /// Video codec.
  final VideoCodec? videoCodec;

  /// Video bit depth (8 or 10).
  final int? videoBitDepth;

  /// Frame width in pixels.
  final int? width;

  /// Frame height in pixels (1080 for "1080p").
  final int? height;

  /// HDR layers present (e.g. {dolbyVision, hdr10} for a "DV HDR10" hybrid).
  final Set<HdrFormat> hdr;

  /// Codec of the audio track that will play (the default one).
  final AudioCodec? audioCodec;

  /// Format of the subtitle that will be shown, if any.
  final SubtitleFormat? subtitleFormat;

  @override
  bool operator ==(Object other) =>
      other is MediaTraits &&
      other.container == container &&
      other.videoCodec == videoCodec &&
      other.videoBitDepth == videoBitDepth &&
      other.width == width &&
      other.height == height &&
      _setEquals(other.hdr, hdr) &&
      other.audioCodec == audioCodec &&
      other.subtitleFormat == subtitleFormat;

  @override
  int get hashCode => Object.hash(
    container,
    videoCodec,
    videoBitDepth,
    width,
    height,
    Object.hashAllUnordered(hdr),
    audioCodec,
    subtitleFormat,
  );

  @override
  String toString() =>
      'MediaTraits(${container?.name}, ${videoCodec?.name} ${videoBitDepth ?? '?'}-bit, '
      '${width ?? '?'}x${height ?? '?'}, hdr: ${hdr.map((h) => h.name).join('+')}, '
      '${audioCodec?.name}, sub: ${subtitleFormat?.name})';
}

/// Result of [CastProfile.canPlay].
final class CastCheck {
  /// Creates a result.
  const CastCheck({this.problems = const [], this.warnings = const []});

  /// Why the media can't play (empty when it can), e.g. "DTS audio isn't
  /// supported by this TV".
  final List<String> problems;

  /// Non-blocking issues, e.g. subtitles that won't show.
  final List<String> warnings;

  /// True when nothing blocks playback.
  bool get isPlayable => problems.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is CastCheck &&
      _listEquals(other.problems, problems) &&
      _listEquals(other.warnings, warnings);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(problems), Object.hashAll(warnings));

  @override
  String toString() => isPlayable
      ? 'CastCheck(playable${warnings.isEmpty ? '' : ', warnings: $warnings'})'
      : 'CastCheck(not playable: $problems)';
}

/// What a renderer can decode.
final class CastProfile {
  /// Creates a profile.
  const CastProfile({
    required this.name,
    required this.containers,
    required this.videoCodecs,
    required this.maxWidth,
    required this.maxHeight,
    required this.audioCodecs,
    this.hdrFormats = const {},
    this.subtitleFormats = const {},
  });

  /// Samsung Full HD Tizen TVs, 2018–2024 (5 Series: UE43N5300, UE43T5300 …).
  ///
  /// Encoded from the N5300 (2018) e-manual "Supported video codecs" and
  /// Samsung's developer "2020 TV Video Specifications" (FHD profile):
  /// * containers AVI/MKV/MP4/MOV/TS/WebM; HEVC only in MKV, MP4 and TS;
  /// * H.264 BP/MP/HP ≤ 1920×1080 60 fps, Level 4.1 (8-bit only: no Hi10P);
  /// * HEVC Main and Main10 ≤ 1920×1080 (Level 4.1);
  /// * MPEG-4 SP/ASP and MPEG-2 listed; no VP9 or AV1 on FHD models;
  /// * Dolby Digital, Dolby Digital Plus (≤ 5.1), AAC/HE-AAC, MP3, Opus,
  ///   Vorbis, LPCM. No DTS ("DivX and DTS codecs are not supported by the
  ///   Samsung TV models released in 2018"; "not supported on 2020 TVs"),
  ///   no TrueHD; FLAC isn't listed for video files;
  /// * subtitles SRT, SAMI, SSA/ASS (external and embedded); no image
  ///   subtitles (PGS/VobSub).
  ///
  /// Still to verify on the real TV (PLAN.md Phase 4): HEVC Main10 over
  /// DLNA (PLAN assumed 8-bit only), XviD in AVI (DivX was dropped in
  /// 2018), Opus/Vorbis inside MKV, sustained bitrate of 1080p remuxes
  /// (developer spec lists 20 Mbps for FHD H.264), and HDR: T5300 accepts
  /// HDR10/HLG input but tone mapping on the FHD panel is unverified, so HDR
  /// is treated as unsupported.
  static const samsungFullHdTizen = CastProfile(
    name: 'Samsung Full HD (Tizen 2018+)',
    containers: {
      CastContainer.mkv,
      CastContainer.mp4,
      CastContainer.ts,
      CastContainer.avi,
      CastContainer.mov,
      CastContainer.webm,
    },
    videoCodecs: {
      VideoCodec.h264: VideoCodecSupport(),
      VideoCodec.hevc: VideoCodecSupport(
        maxBitDepth: 10,
        containers: {CastContainer.mkv, CastContainer.mp4, CastContainer.ts},
      ),
      VideoCodec.mpeg4: VideoCodecSupport(),
      VideoCodec.mpeg2: VideoCodecSupport(),
    },
    maxWidth: 1920,
    maxHeight: 1080,
    audioCodecs: {
      AudioCodec.aac,
      AudioCodec.ac3,
      AudioCodec.eac3,
      AudioCodec.mp3,
      AudioCodec.opus,
      AudioCodec.vorbis,
      AudioCodec.pcm,
    },
    subtitleFormats: {
      SubtitleFormat.srt,
      SubtitleFormat.smi,
      SubtitleFormat.ssa,
      SubtitleFormat.ass,
    },
  );

  /// Conservative profile for an unknown DLNA renderer: the DLNA mandatory
  /// formats (MP4/MPEG-TS, H.264 8-bit ≤ 1080p, MPEG-2, AAC/AC3/MP3) and no
  /// subtitles (DLNA has no standard subtitle mechanism).
  static const genericDlna = CastProfile(
    name: 'Generic DLNA',
    containers: {CastContainer.mp4, CastContainer.ts},
    videoCodecs: {
      VideoCodec.h264: VideoCodecSupport(),
      VideoCodec.mpeg2: VideoCodecSupport(),
    },
    maxWidth: 1920,
    maxHeight: 1080,
    audioCodecs: {AudioCodec.aac, AudioCodec.ac3, AudioCodec.mp3},
  );

  /// Refines [base] with what a renderer advertises in ConnectionManager
  /// `GetProtocolInfo` (see `DlnaRenderer.sinkProtocols`).
  ///
  /// Containers become exactly the advertised video MIME types (renderers
  /// reject URIs whose MIME type they don't list), unless the renderer
  /// lists a `*` wildcard or no video types at all. Codecs named by DLNA
  /// profiles (`DLNA.ORG_PN=AVC_…_AAC`, `HEVC_…`, `…_AC3` …) are added to
  /// [base]'s. Resolution, HDR and subtitles stay as in [base].
  factory CastProfile.fromSinkProtocols(
    Iterable<ProtocolInfo> sink, {
    CastProfile base = genericDlna,
  }) {
    final mimes = {for (final p in sink) p.mimeType};
    final advertised = {
      for (final c in CastContainer.values)
        if (c.mimeTypes.any(mimes.contains)) c,
    };
    final video = {...base.videoCodecs};
    final audio = {...base.audioCodecs};
    for (final p in sink) {
      final tokens = (p.dlnaProfile ?? '').toUpperCase().split('_').toSet();
      if (tokens.contains('AVC'))
        video.putIfAbsent(VideoCodec.h264, VideoCodecSupport.new);
      if (tokens.contains('HEVC'))
        video.putIfAbsent(VideoCodec.hevc, VideoCodecSupport.new);
      if (tokens.contains('MPEG4'))
        video.putIfAbsent(VideoCodec.mpeg4, VideoCodecSupport.new);
      if (tokens.containsAll(['MPEG', 'TS']) ||
          tokens.containsAll(['MPEG', 'PS'])) {
        video.putIfAbsent(VideoCodec.mpeg2, VideoCodecSupport.new);
      }
      if (tokens.contains('AAC') || tokens.contains('HEAAC'))
        audio.add(AudioCodec.aac);
      if (tokens.contains('AC3')) audio.add(AudioCodec.ac3);
      if (tokens.contains('EAC3') || tokens.contains('DDPLUS'))
        audio.add(AudioCodec.eac3);
      if (tokens.contains('MP3') || tokens.contains('MP3X'))
        audio.add(AudioCodec.mp3);
      if (tokens.contains('LPCM')) audio.add(AudioCodec.pcm);
    }
    return CastProfile(
      name: '${base.name} (renderer protocols)',
      containers: mimes.contains('*') || advertised.isEmpty
          ? base.containers
          : Set.unmodifiable(advertised),
      videoCodecs: Map.unmodifiable(video),
      maxWidth: base.maxWidth,
      maxHeight: base.maxHeight,
      audioCodecs: Set.unmodifiable(audio),
      hdrFormats: base.hdrFormats,
      subtitleFormats: base.subtitleFormats,
    );
  }

  /// Display name.
  final String name;

  /// Accepted containers.
  final Set<CastContainer> containers;

  /// Decodable video codecs.
  final Map<VideoCodec, VideoCodecSupport> videoCodecs;

  /// Maximum frame width.
  final int maxWidth;

  /// Maximum frame height.
  final int maxHeight;

  /// HDR formats shown correctly (empty: SDR only).
  final Set<HdrFormat> hdrFormats;

  /// Decodable audio codecs.
  final Set<AudioCodec> audioCodecs;

  /// Subtitle formats the renderer can display.
  final Set<SubtitleFormat> subtitleFormats;

  /// Whether [media] can be cast to this renderer, with reasons.
  CastCheck canPlay(MediaTraits media) {
    const tv = "isn't supported by this TV";
    final problems = <String>[];
    final warnings = <String>[];
    final container = media.container;
    if (container != null && !containers.contains(container)) {
      problems.add("${container.label} files aren't supported by this TV");
    }
    final codec = media.videoCodec;
    final support = codec == null ? null : videoCodecs[codec];
    if (codec != null && support == null) {
      problems.add('${codec.label} video $tv');
    } else if (codec != null && support != null) {
      final depth = media.videoBitDepth;
      if (depth != null && depth > support.maxBitDepth) {
        problems.add('$depth-bit ${codec.label} video $tv');
      }
      final allowed = support.containers;
      if (container != null &&
          containers.contains(container) &&
          allowed != null &&
          !allowed.contains(container)) {
        problems.add('${codec.label} video in ${container.label} files $tv');
      }
    }
    final height = media.height ?? 0;
    final width = media.width ?? 0;
    if (height > maxHeight || width > maxWidth) {
      final size = height > 0 ? '${height}p' : '$width pixels wide';
      problems.add('$size video is above this TV\'s ${maxHeight}p maximum');
    }
    if (media.hdr.isNotEmpty) {
      final layers = {
        ...media.hdr,
        if (media.hdr.contains(HdrFormat.hdr10Plus)) HdrFormat.hdr10,
      };
      if (!layers.any(hdrFormats.contains)) {
        final names = media.hdr.map((h) => h.label).join(' + ');
        problems.add('$names $tv (colours would look wrong)');
      }
    }
    final audio = media.audioCodec;
    if (audio != null && !audioCodecs.contains(audio)) {
      problems.add('${audio.label} audio $tv');
    }
    final subtitle = media.subtitleFormat;
    if (subtitle != null && !subtitleFormats.contains(subtitle)) {
      warnings.add("${subtitle.label} subtitles can't be shown on this TV");
    }
    return CastCheck(problems: problems, warnings: warnings);
  }

  @override
  bool operator ==(Object other) =>
      other is CastProfile &&
      other.name == name &&
      _setEquals(other.containers, containers) &&
      other.videoCodecs.length == videoCodecs.length &&
      videoCodecs.entries.every((e) => other.videoCodecs[e.key] == e.value) &&
      other.maxWidth == maxWidth &&
      other.maxHeight == maxHeight &&
      _setEquals(other.hdrFormats, hdrFormats) &&
      _setEquals(other.audioCodecs, audioCodecs) &&
      _setEquals(other.subtitleFormats, subtitleFormats);

  @override
  int get hashCode => Object.hash(
    name,
    Object.hashAllUnordered(containers),
    Object.hashAllUnordered(
      videoCodecs.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    maxWidth,
    maxHeight,
    Object.hashAllUnordered(hdrFormats),
    Object.hashAllUnordered(audioCodecs),
    Object.hashAllUnordered(subtitleFormats),
  );

  @override
  String toString() =>
      'CastProfile($name: ${containers.map((c) => c.name).join('/')}, '
      '${videoCodecs.keys.map((c) => c.name).join('/')} ≤${maxWidth}x$maxHeight, '
      '${audioCodecs.map((c) => c.name).join('/')})';
}

bool _setEquals<T>(Set<T>? a, Set<T>? b) =>
    identical(a, b) ||
    (a != null && b != null && a.length == b.length && a.containsAll(b));

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
