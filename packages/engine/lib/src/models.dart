import 'dart:typed_data';

/// Thrown when the native engine rejects a call.
final class EngineException implements Exception {
  /// Creates an exception with a human-readable [message].
  const EngineException(this.message);

  /// What went wrong, as reported by the engine.
  final String message;

  @override
  String toString() => 'EngineException: $message';
}

/// Session-wide settings. `null` keeps the engine default.
final class EngineConfig {
  /// Creates a config.
  const EngineConfig({
    this.statePath,
    this.resumeDir,
    this.listenPort = 0,
    this.userAgent,
    this.dht,
    this.lsd,
    this.upnp,
    this.natpmp,
    this.utp,
    this.connectionsLimit,
    this.downloadRateLimit,
    this.uploadRateLimit,
    this.outgoingInterfaces,
    this.anonymousMode,
    this.testMode = false,
  });

  /// File that keeps the DHT routing table between launches (fast peer
  /// discovery on the next start).
  final String? statePath;

  /// Directory for per-torrent fast-resume files.
  final String? resumeDir;

  /// BitTorrent listen port; 0 picks a free one.
  final int listenPort;

  /// HTTP user agent for trackers.
  final String? userAgent;

  /// Peer discovery and transport toggles (all on by default).
  final bool? dht, lsd, upnp, natpmp, utp;

  /// Global connection cap.
  final int? connectionsLimit;

  /// Bytes per second; 0 = unlimited.
  final int? downloadRateLimit, uploadRateLimit;

  /// Restrict outgoing connections to these interfaces (e.g. a VPN), "" = any.
  final String? outgoingInterfaces;

  /// Hides client identity from peers and trackers.
  final bool? anonymousMode;

  /// Loopback only, no DHT/LSD/UPnP, several connections per IP (tests).
  final bool testMode;

  /// The bencodable form the native side reads.
  Map<String, Object?> toMap() => {
    'state_path': statePath,
    'resume_dir': resumeDir,
    'listen_port': listenPort,
    'user_agent': userAgent,
    'dht': dht,
    'lsd': lsd,
    'upnp': upnp,
    'natpmp': natpmp,
    'utp': utp,
    'connections_limit': connectionsLimit,
    'download_rate_limit': downloadRateLimit,
    'upload_rate_limit': uploadRateLimit,
    'outgoing_interfaces': outgoingInterfaces,
    'anonymous_mode': anonymousMode,
    'test_mode': testMode,
  };
}

/// What to add to the session. Use one of the named constructors.
final class AddTorrent {
  const AddTorrent._({
    required this.savePath,
    this.magnet,
    this.torrentBytes,
    this.resumePath,
    this.name,
    this.trackers = const [],
    this.filePriorities,
    this.peers = const [],
    this.paused = false,
    this.seedMode = false,
    this.sequential = false,
    this.maxConnections,
    this.downloadLimit,
    this.uploadLimit,
  });

  /// Adds a magnet link. [resumePath] wins when that file exists.
  const AddTorrent.magnet(
    String uri, {
    required String savePath,
    String? resumePath,
    String? name,
    List<String> trackers = const [],
    List<int>? filePriorities,
    List<String> peers = const [],
    bool paused = false,
    bool sequential = false,
    int? maxConnections,
  }) : this._(
         magnet: uri,
         savePath: savePath,
         resumePath: resumePath,
         name: name,
         trackers: trackers,
         filePriorities: filePriorities,
         peers: peers,
         paused: paused,
         sequential: sequential,
         maxConnections: maxConnections,
       );

  /// Adds a `.torrent` file's bytes.
  const AddTorrent.torrentFile(
    Uint8List bytes, {
    required String savePath,
    String? resumePath,
    List<String> trackers = const [],
    List<int>? filePriorities,
    List<String> peers = const [],
    bool paused = false,
    bool seedMode = false,
  }) : this._(
         torrentBytes: bytes,
         savePath: savePath,
         resumePath: resumePath,
         trackers: trackers,
         filePriorities: filePriorities,
         peers: peers,
         paused: paused,
         seedMode: seedMode,
       );

  final String savePath;
  final String? magnet;
  final Uint8List? torrentBytes;
  final String? resumePath;
  final String? name;
  final List<String> trackers;
  final List<int>? filePriorities;

  /// Peers to connect to right away, as `ip:port` (`[v6]:port`).
  final List<String> peers;
  final bool paused;
  final bool seedMode;
  final bool sequential;
  final int? maxConnections;
  final int? downloadLimit;
  final int? uploadLimit;

  /// The bencodable form the native side reads.
  Map<String, Object?> toMap() => {
    'save_path': savePath,
    'magnet': magnet,
    'torrent': torrentBytes,
    'resume_path': resumePath,
    'name': name,
    'trackers': trackers,
    'file_priorities': filePriorities,
    'peers': peers,
    'paused': paused,
    'seed_mode': seedMode,
    'sequential': sequential,
    'max_connections': maxConnections,
    'download_limit': downloadLimit,
    'upload_limit': uploadLimit,
  };
}

/// Lifecycle state of a torrent.
enum TorrentState {
  /// Verifying data already on disk.
  checking,

  /// Fetching the file list from peers (magnet links).
  metadata,

  /// Downloading wanted pieces.
  downloading,

  /// All wanted pieces done (not every file may be wanted).
  finished,

  /// Complete and uploading.
  seeding,

  /// Anything the engine didn't name.
  unknown;

  static TorrentState _parse(String? s) => switch (s) {
    'checking' => checking,
    'metadata' => metadata,
    'downloading' => downloading,
    'finished' => finished,
    'seeding' => seeding,
    _ => unknown,
  };
}

/// A snapshot of one torrent.
final class TorrentStatus {
  /// Creates a status snapshot.
  const TorrentStatus({
    required this.infoHash,
    required this.name,
    required this.state,
    required this.paused,
    required this.hasMetadata,
    required this.progress,
    required this.totalWanted,
    required this.totalWantedDone,
    required this.downloadRate,
    required this.uploadRate,
    required this.numPeers,
    required this.numSeeds,
    required this.listPeers,
    required this.listSeeds,
    required this.numComplete,
    required this.numIncomplete,
    required this.savePath,
    this.error,
  });

  /// Parses one element of the engine's status array.
  factory TorrentStatus.fromJson(Map<String, Object?> j) => TorrentStatus(
    infoHash: j['ih']! as String,
    name: j['name'] as String? ?? '',
    state: TorrentState._parse(j['state'] as String?),
    paused: j['paused'] == true,
    hasMetadata: j['has_metadata'] == true,
    progress: (j['progress'] as num? ?? 0).toDouble(),
    totalWanted: (j['total_wanted'] as num? ?? 0).toInt(),
    totalWantedDone: (j['total_wanted_done'] as num? ?? 0).toInt(),
    downloadRate: (j['download_rate'] as num? ?? 0).toInt(),
    uploadRate: (j['upload_rate'] as num? ?? 0).toInt(),
    numPeers: (j['num_peers'] as num? ?? 0).toInt(),
    numSeeds: (j['num_seeds'] as num? ?? 0).toInt(),
    listPeers: (j['list_peers'] as num? ?? 0).toInt(),
    listSeeds: (j['list_seeds'] as num? ?? 0).toInt(),
    numComplete: (j['num_complete'] as num? ?? -1).toInt(),
    numIncomplete: (j['num_incomplete'] as num? ?? -1).toInt(),
    savePath: j['save_path'] as String? ?? '',
    error: j['error'] as String?,
  );

  final String infoHash;
  final String name;
  final TorrentState state;
  final bool paused;
  final bool hasMetadata;

  /// 0..1 over wanted bytes.
  final double progress;
  final int totalWanted;
  final int totalWantedDone;

  /// Payload bytes per second.
  final int downloadRate;
  final int uploadRate;

  /// Connected peers / seeds.
  final int numPeers;
  final int numSeeds;

  /// Known peers / seeds (not necessarily connected).
  final int listPeers;
  final int listSeeds;

  /// Swarm size reported by trackers (-1 unknown).
  final int numComplete;
  final int numIncomplete;
  final String savePath;
  final String? error;

  /// Time left at the current rate, or null when stalled/complete.
  Duration? get eta {
    final left = totalWanted - totalWantedDone;
    if (left <= 0 || downloadRate <= 0) return null;
    return Duration(seconds: (left / downloadRate).ceil());
  }

  /// True once every wanted byte is on disk.
  bool get isComplete =>
      state == TorrentState.finished || state == TorrentState.seeding;

  @override
  String toString() =>
      'TorrentStatus($infoHash ${state.name} ${(progress * 100).toStringAsFixed(1)}% '
      'peers=$numPeers seeds=$numSeeds rate=$downloadRate)';
}

/// One file inside a torrent.
final class TorrentFile {
  /// Creates a file entry.
  const TorrentFile({
    required this.index,
    required this.path,
    required this.size,
    required this.offset,
    required this.isPad,
  });

  /// Parses one element of the engine's file array.
  factory TorrentFile.fromJson(Map<String, Object?> j) => TorrentFile(
    index: (j['index']! as num).toInt(),
    path: j['path']! as String,
    size: (j['size']! as num).toInt(),
    offset: (j['offset']! as num).toInt(),
    isPad: j['pad'] == true,
  );

  static const _videoExtensions = {
    'mkv', 'mp4', 'm4v', 'avi', 'mov', 'webm', 'ts', 'm2ts', 'mts', 'wmv', //
    'flv', 'mpg', 'mpeg',
  };

  final int index;

  /// Path inside the torrent, `/`-separated.
  final String path;
  final int size;

  /// Byte offset inside the torrent's concatenated data.
  final int offset;

  /// Alignment padding (BEP 47); never shown or streamed.
  final bool isPad;

  /// The last path segment.
  String get name => path.split(RegExp(r'[/\\]')).last;

  /// Lowercase extension without the dot ('' if none).
  String get extension {
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  /// Whether this looks like a playable video (not a sample).
  bool get isVideo =>
      !isPad &&
      _videoExtensions.contains(extension) &&
      !RegExp(r'(^|[\W_])sample([\W_]|$)', caseSensitive: false).hasMatch(name);
}

/// Something that happened inside the engine.
sealed class EngineEvent {
  const EngineEvent();

  /// Parses one element of the engine's event array.
  static EngineEvent fromJson(Map<String, Object?> j) {
    final ih = j['ih'] as String? ?? '';
    final message = j['message'] as String? ?? '';
    return switch (j['type']) {
      'metadata' => MetadataReceived(ih),
      'finished' => TorrentFinished(ih),
      'checked' => TorrentChecked(ih),
      'removed' => TorrentRemoved(ih),
      'error' => TorrentFailed(ih, message),
      'file_error' => TorrentFileError(ih, message),
      'listen' => ListenSucceeded((j['port'] as num? ?? 0).toInt()),
      'moved' => StorageMoved(ih, j['path'] as String? ?? ''),
      'move_failed' => StorageMoveFailed(ih, message),
      _ => EngineLog(message),
    };
  }
}

/// The file list of a magnet link arrived.
final class MetadataReceived extends EngineEvent {
  const MetadataReceived(this.infoHash);
  final String infoHash;
}

/// Every wanted piece is on disk.
final class TorrentFinished extends EngineEvent {
  const TorrentFinished(this.infoHash);
  final String infoHash;
}

/// Existing data was verified.
final class TorrentChecked extends EngineEvent {
  const TorrentChecked(this.infoHash);
  final String infoHash;
}

/// The torrent left the session.
final class TorrentRemoved extends EngineEvent {
  const TorrentRemoved(this.infoHash);
  final String infoHash;
}

/// The torrent stopped because of an error.
final class TorrentFailed extends EngineEvent {
  const TorrentFailed(this.infoHash, this.message);
  final String infoHash;
  final String message;
}

/// A disk error (full disk, permissions…).
final class TorrentFileError extends EngineEvent {
  const TorrentFileError(this.infoHash, this.message);
  final String infoHash;
  final String message;
}

/// Data moved to a new folder.
final class StorageMoved extends EngineEvent {
  const StorageMoved(this.infoHash, this.path);
  final String infoHash;
  final String path;
}

/// Moving data failed (disk full, permissions).
final class StorageMoveFailed extends EngineEvent {
  const StorageMoveFailed(this.infoHash, this.message);
  final String infoHash;
  final String message;
}

/// The BitTorrent port is open.
final class ListenSucceeded extends EngineEvent {
  const ListenSucceeded(this.port);
  final int port;
}

/// Diagnostic message.
final class EngineLog extends EngineEvent {
  const EngineLog(this.message);
  final String message;
}

/// An open stream of one torrent file over the local HTTP server.
final class StreamHandle {
  /// Creates a handle.
  const StreamHandle({
    required this.token,
    required this.path,
    required this.size,
    required this.port,
  });

  /// Secret route id; also the key for stats and closing.
  final String token;

  /// URL path on the server, ending with the file name.
  final String path;
  final int size;

  /// Server port at open time.
  final int port;

  /// URL for a player on this device ([host] = LAN IP for a TV).
  Uri uri({String host = '127.0.0.1'}) => Uri.parse('http://$host:$port$path');
}

/// Live numbers for an open stream.
final class StreamStats {
  /// Creates stream stats.
  const StreamStats({
    required this.size,
    required this.haveBytes,
    required this.bufferedAhead,
    required this.position,
    required this.connections,
  });

  /// Parses the engine's stream stats.
  factory StreamStats.fromJson(Map<String, Object?> j) => StreamStats(
    size: (j['size']! as num).toInt(),
    haveBytes: (j['have_bytes']! as num).toInt(),
    bufferedAhead: (j['buffered_ahead']! as num).toInt(),
    position: (j['position']! as num).toInt(),
    connections: (j['connections']! as num).toInt(),
  );

  final int size;

  /// Bytes of this file on disk.
  final int haveBytes;

  /// Contiguous bytes ready after the current read position.
  final int bufferedAhead;

  /// Last read position of the player.
  final int position;

  /// Open player connections.
  final int connections;
}

/// A local file exposed over the server (downloads, subtitles for a TV).
final class ServedFile {
  /// Creates a served-file handle.
  const ServedFile({
    required this.token,
    required this.path,
    required this.port,
  });

  final String token;
  final String path;
  final int port;

  /// URL for a client on this device or the LAN.
  Uri uri({String host = '127.0.0.1'}) => Uri.parse('http://$host:$port$path');
}
