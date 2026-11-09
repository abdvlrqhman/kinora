import 'json.dart';

/// A playable source for a video (Stream Object).
///
/// At least one of [infoHash], [url], [ytId] or [externalUrl] is set.
/// `behaviorHints` are flattened into fields.
final class StreamItem {
  /// Creates a stream.
  const StreamItem({
    this.name,
    this.title,
    this.description,
    this.infoHash,
    this.fileIdx,
    this.url,
    this.ytId,
    this.externalUrl,
    this.sources = const [],
    this.bingeGroup,
    this.filename,
    this.videoSize,
    this.videoHash,
    this.notWebReady = false,
    this.proxyRequestHeaders = const {},
    this.proxyResponseHeaders = const {},
  });

  /// Parses a Stream Object; returns null when it has nothing to play.
  static StreamItem? tryParse(Object? value) {
    if (value is! Map<String, Object?>) return null;
    final json = value;
    final infoHash = readString(json, 'infoHash')?.trim().toLowerCase();
    final url = readString(json, 'url');
    final ytId = readString(json, 'ytId');
    final externalUrl = readString(json, 'externalUrl');
    if (infoHash == null &&
        url == null &&
        ytId == null &&
        externalUrl == null) {
      return null;
    }
    final hints = json['behaviorHints'] is Map<String, Object?>
        ? json['behaviorHints']! as JsonMap
        : const <String, Object?>{};
    final proxy = hints['proxyHeaders'] is Map<String, Object?>
        ? hints['proxyHeaders']! as JsonMap
        : const <String, Object?>{};
    return StreamItem(
      name: readString(json, 'name'),
      title: readString(json, 'title'),
      description: readString(json, 'description'),
      infoHash: infoHash,
      fileIdx: readInt(json, 'fileIdx'),
      url: url,
      ytId: ytId,
      externalUrl: externalUrl,
      sources: readStrings(json, 'sources'),
      bingeGroup: readString(hints, 'bingeGroup'),
      filename: readString(hints, 'filename'),
      videoSize: readInt(hints, 'videoSize'),
      videoHash: readString(hints, 'videoHash'),
      notWebReady: readBool(hints, 'notWebReady'),
      proxyRequestHeaders: readStringMap(proxy['request']),
      proxyResponseHeaders: readStringMap(proxy['response']),
    );
  }

  /// Short label, usually addon + quality (`Torrentio\n1080p`).
  final String? name;

  /// Legacy description text (often the release name plus stats).
  final String? title;

  /// Description text (successor of [title]).
  final String? description;

  /// Lowercase hex BitTorrent info hash.
  final String? infoHash;

  /// File index inside the torrent; null means the largest file.
  final int? fileIdx;

  /// Direct http(s) URL (debrid links, web sources).
  final String? url;

  /// YouTube video id.
  final String? ytId;

  /// Web page to open in a browser.
  final String? externalUrl;

  /// Peer sources: `tracker:<url>` and `dht:<hash>` entries.
  final List<String> sources;

  /// `behaviorHints.bingeGroup`.
  final String? bingeGroup;

  /// `behaviorHints.filename`.
  final String? filename;

  /// `behaviorHints.videoSize` in bytes.
  final int? videoSize;

  /// `behaviorHints.videoHash` (OpenSubtitles hash).
  final String? videoHash;

  /// `behaviorHints.notWebReady`.
  final bool notWebReady;

  /// `behaviorHints.proxyHeaders.request`: headers to send with [url].
  final Map<String, String> proxyRequestHeaders;

  /// `behaviorHints.proxyHeaders.response`.
  final Map<String, String> proxyResponseHeaders;

  /// Tracker URLs from [sources] without the `tracker:` prefix.
  List<String> get trackers => [
    for (final s in sources)
      if (s.startsWith('tracker:')) s.substring('tracker:'.length),
  ];

  /// [description] or [title], whichever the addon sent.
  String? get text => description ?? title;

  @override
  bool operator ==(Object other) =>
      other is StreamItem &&
      other.name == name &&
      other.title == title &&
      other.description == description &&
      other.infoHash == infoHash &&
      other.fileIdx == fileIdx &&
      other.url == url &&
      other.ytId == ytId &&
      other.externalUrl == externalUrl &&
      listEquals(other.sources, sources) &&
      other.bingeGroup == bingeGroup &&
      other.filename == filename &&
      other.videoSize == videoSize &&
      other.videoHash == videoHash &&
      other.notWebReady == notWebReady &&
      mapEquals(other.proxyRequestHeaders, proxyRequestHeaders) &&
      mapEquals(other.proxyResponseHeaders, proxyResponseHeaders);

  @override
  int get hashCode => Object.hash(
    name,
    title,
    description,
    infoHash,
    fileIdx,
    url,
    ytId,
    externalUrl,
    Object.hashAll(sources),
    bingeGroup,
    filename,
    videoSize,
    videoHash,
    notWebReady,
    mapHash(proxyRequestHeaders),
    mapHash(proxyResponseHeaders),
  );

  @override
  String toString() {
    final target = infoHash != null
        ? 'infoHash: $infoHash, fileIdx: $fileIdx'
        : 'url: ${url ?? ytId ?? externalUrl}';
    return 'StreamItem(${name?.replaceAll('\n', ' ')}, $target)';
  }
}

/// Removes duplicate streams, keeping the first occurrence.
///
/// Torrents are the same when info hash and file index match; their
/// [StreamItem.sources] are merged so no tracker is lost. Other streams are
/// the same when their URL (or YouTube id / external URL) matches.
List<StreamItem> dedupeStreams(Iterable<StreamItem> streams) {
  final byKey = <String, StreamItem>{};
  for (final s in streams) {
    final key = s.infoHash != null
        ? 'bt:${s.infoHash}:${s.fileIdx ?? ''}'
        : 'url:${s.url ?? s.ytId ?? s.externalUrl}';
    final first = byKey[key];
    if (first == null) {
      byKey[key] = s;
    } else if (s.sources.any((x) => !first.sources.contains(x))) {
      byKey[key] = StreamItem(
        name: first.name,
        title: first.title,
        description: first.description,
        infoHash: first.infoHash,
        fileIdx: first.fileIdx,
        url: first.url,
        ytId: first.ytId,
        externalUrl: first.externalUrl,
        sources: List.unmodifiable({...first.sources, ...s.sources}),
        bingeGroup: first.bingeGroup,
        filename: first.filename,
        videoSize: first.videoSize,
        videoHash: first.videoHash,
        notWebReady: first.notWebReady,
        proxyRequestHeaders: first.proxyRequestHeaders,
        proxyResponseHeaders: first.proxyResponseHeaders,
      );
    }
  }
  return List.unmodifiable(byKey.values);
}

final _keyRejected = RegExp(
  r'invalid\b.{0,30}?\b(api[\s_-]?key|key|token)\b'
  r'|\b(api[\s_-]?key|token)\b.{0,20}?\b(invalid|expired|revoked|rejected)\b',
  caseSensitive: false,
  dotAll: true,
);

/// Whether [stream] is a placeholder a debrid addon returns when the user's
/// API key/token is rejected (e.g. Torrentio's `failed_access` video).
/// Torrents never count, so a release name cannot trigger it.
bool isDebridKeyRejection(StreamItem stream) =>
    stream.infoHash == null &&
    ((stream.url?.contains('failed_access') ?? false) ||
        _keyRejected.hasMatch(
          [stream.name, stream.title, stream.description].nonNulls.join('\n'),
        ));
