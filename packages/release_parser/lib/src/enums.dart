/// Vertical resolution of a release.
enum Resolution {
  /// Not stated in the name.
  unknown(0, 'Unknown'),

  /// 480p and below (SD).
  p480(480, '480p'),

  /// 576p (PAL SD).
  p576(576, '576p'),

  /// 720p (HD).
  p720(720, '720p'),

  /// 1080p / 1080i (Full HD).
  p1080(1080, '1080p'),

  /// 1440p (QHD).
  p1440(1440, '1440p'),

  /// 2160p (4K UHD).
  p2160(2160, '4K'),

  /// 4320p (8K).
  p4320(4320, '8K');

  const Resolution(this.lines, this.label);

  /// Number of horizontal lines (0 when [unknown]).
  final int lines;

  /// Short human label, e.g. `1080p` or `4K`.
  final String label;
}

/// Where the video was captured or ripped from.
enum Source {
  /// Not stated in the name.
  unknown('Unknown'),

  /// Camcorder recording in a cinema.
  cam('CAM'),

  /// Telesync: cinema recording with a direct audio feed.
  telesync('TS'),

  /// Telecine: transferred from a film print.
  telecine('TC'),

  /// Screener copy sent to reviewers.
  screener('SCR'),

  /// DVD rip or DVD image.
  dvd('DVD'),

  /// Captured from TV broadcast.
  hdtv('HDTV'),

  /// Re-encode of an unspecified HD source.
  hdrip('HDRip'),

  /// Captured / re-encoded from a streaming service.
  webrip('WEBRip'),

  /// Untouched download from a streaming service.
  webdl('WEB-DL'),

  /// Blu-ray encode (BDRip / BRRip / BluRay).
  bluray('BluRay'),

  /// Untouched Blu-ray streams remuxed into a container.
  remux('REMUX');

  const Source(this.label);

  /// Short human label, e.g. `WEB-DL`.
  final String label;

  /// True for cinema recordings and screeners (CAM, TS, TC, SCR).
  bool get isPreRelease =>
      this == cam || this == telesync || this == telecine || this == screener;
}

/// Video codec.
enum VideoCodec {
  /// Not stated in the name.
  unknown('Unknown'),

  /// H.264 / AVC / x264.
  h264('H.264'),

  /// H.265 / HEVC / x265.
  h265('HEVC'),

  /// AV1.
  av1('AV1'),

  /// VP9.
  vp9('VP9'),

  /// VC-1 (older Blu-ray remuxes).
  vc1('VC-1'),

  /// MPEG-2 (DVD, broadcast).
  mpeg2('MPEG-2'),

  /// Xvid / DivX (MPEG-4 Part 2).
  xvid('XviD');

  const VideoCodec(this.label);

  /// Short human label.
  final String label;
}

/// High dynamic range format.
enum HdrFormat {
  /// HDR10 (also plain "HDR").
  hdr10('HDR10'),

  /// HDR10+ dynamic metadata.
  hdr10Plus('HDR10+'),

  /// Dolby Vision.
  dolbyVision('DV'),

  /// Hybrid Log-Gamma (broadcast HDR).
  hlg('HLG');

  const HdrFormat(this.label);

  /// Short human label.
  final String label;
}

/// Audio codec.
enum AudioCodec {
  /// AAC.
  aac('AAC'),

  /// Dolby Digital (AC-3).
  ac3('DD'),

  /// Dolby Digital Plus (E-AC-3).
  eac3('DD+'),

  /// DTS core (including DTS-ES).
  dts('DTS'),

  /// DTS-HD (Master Audio / High Resolution).
  dtsHd('DTS-HD'),

  /// DTS:X.
  dtsX('DTS:X'),

  /// Dolby TrueHD.
  trueHd('TrueHD'),

  /// FLAC.
  flac('FLAC'),

  /// Opus.
  opus('Opus'),

  /// MP3.
  mp3('MP3'),

  /// Linear PCM.
  pcm('PCM');

  const AudioCodec(this.label);

  /// Short human label.
  final String label;

  /// True for the DTS family (DTS, DTS-HD, DTS:X).
  bool get isDts => this == dts || this == dtsHd || this == dtsX;
}
