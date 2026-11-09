import 'dart:async';

import 'package:http/http.dart' as http;

import 'device.dart';
import 'didl.dart';
import 'errors.dart';
import 'protocol_info.dart';
import 'soap.dart';
import 'time.dart';

/// AVTransport `TransportState`.
enum TransportState {
  /// `PLAYING`.
  playing('PLAYING'),

  /// `PAUSED_PLAYBACK`.
  pausedPlayback('PAUSED_PLAYBACK'),

  /// `STOPPED`.
  stopped('STOPPED'),

  /// `TRANSITIONING` (loading/buffering).
  transitioning('TRANSITIONING'),

  /// `NO_MEDIA_PRESENT`.
  noMediaPresent('NO_MEDIA_PRESENT'),

  /// Anything else (vendor or recording states).
  unknown('');

  const TransportState(this.upnpValue);

  /// The UPnP string value.
  final String upnpValue;

  /// Maps a UPnP value; unrecognised values map to [unknown].
  static TransportState parse(String? value) => values.firstWhere(
    (s) => s.upnpValue == value?.trim(),
    orElse: () => unknown,
  );
}

/// Result of AVTransport `GetPositionInfo`.
final class PositionInfo {
  /// Creates a position snapshot.
  const PositionInfo({this.trackDuration, this.relTime, this.trackUri});

  /// Track length; null when the renderer doesn't know (or `NOT_IMPLEMENTED`).
  final Duration? trackDuration;

  /// Current position in the track; null when unknown.
  final Duration? relTime;

  /// The URI being played; null when empty.
  final Uri? trackUri;

  @override
  bool operator ==(Object other) =>
      other is PositionInfo &&
      other.trackDuration == trackDuration &&
      other.relTime == relTime &&
      other.trackUri == trackUri;

  @override
  int get hashCode => Object.hash(trackDuration, relTime, trackUri);

  @override
  String toString() => 'PositionInfo($relTime / $trackDuration, $trackUri)';
}

/// One poll result of [DlnaRenderer.watch].
sealed class RendererStatus {
  const RendererStatus();
}

/// The renderer answered: its transport state and position.
final class RendererActive extends RendererStatus {
  /// Creates a status.
  const RendererActive(this.state, this.position);

  /// Transport state.
  final TransportState state;

  /// Position snapshot.
  final PositionInfo position;

  @override
  bool operator ==(Object other) =>
      other is RendererActive &&
      other.state == state &&
      other.position == position;

  @override
  int get hashCode => Object.hash(state, position);

  @override
  String toString() => 'RendererActive(${state.name}, $position)';
}

/// The renderer stopped answering (TV switched off, left the Wi-Fi, …).
final class RendererUnreachable extends RendererStatus {
  /// Creates a status.
  const RendererUnreachable(this.error);

  /// The last network error.
  final DlnaUnreachableException error;

  @override
  bool operator ==(Object other) => other is RendererUnreachable;

  @override
  int get hashCode => (RendererUnreachable).hashCode;

  @override
  String toString() => 'RendererUnreachable(${error.message})';
}

/// Controls one DLNA media renderer through AVTransport, RenderingControl
/// and ConnectionManager (InstanceID 0, channel Master).
///
/// Every call has [timeout]; network failures throw
/// [DlnaUnreachableException], UPnP errors throw [DlnaSoapFault].
final class DlnaRenderer {
  /// Creates a controller for [device]. Pass [httpClient] to share or mock a
  /// client; otherwise one is created and closed by [close].
  DlnaRenderer(
    this.device, {
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 5),
  }) : _ownsClient = httpClient == null,
       _client = httpClient ?? http.Client() {
    _soap = SoapClient(_client, timeout: timeout);
  }

  /// The controlled device.
  final DlnaDevice device;

  /// Timeout of each SOAP action.
  final Duration timeout;

  final http.Client _client;
  final bool _ownsClient;
  late final SoapClient _soap;

  /// Loads [media] (SetAVTransportURI with DIDL-Lite metadata) and, when
  /// [autoplay], starts playback.
  ///
  /// [subtitleSrt] is announced with Samsung's `sec:CaptionInfoEx` /
  /// `sec:CaptionInfo`; also send `CaptionInfo.sec` from the stream server
  /// (see [dlnaStreamHeaders]). If the renderer rejects the metadata it is
  /// retried once with minimal DIDL-Lite. A busy transport (701/705) is
  /// stopped and the URI set again.
  Future<void> load(
    Uri media, {
    required String title,
    required String mimeType,
    int? sizeBytes,
    Duration? duration,
    Uri? subtitleSrt,
    Uri? posterUrl,
    bool autoplay = true,
  }) async {
    String didl({required bool minimal}) => buildVideoDidl(
      media: media,
      title: title,
      mimeType: mimeType,
      sizeBytes: sizeBytes,
      duration: duration,
      subtitleSrt: subtitleSrt,
      posterUrl: posterUrl,
      minimal: minimal,
    );
    try {
      await _setUri(media, didl(minimal: false));
    } on DlnaSoapFault {
      await _setUri(media, didl(minimal: true));
    }
    if (autoplay) await play();
  }

  Future<void> _setUri(Uri media, String metadata) async {
    Future<void> set() => _avt('SetAVTransportURI', {
      'CurrentURI': '$media',
      'CurrentURIMetaData': metadata,
    });
    try {
      await set();
    } on DlnaSoapFault catch (f) {
      if (f.errorCode != DlnaSoapFault.transitionNotAvailable &&
          f.errorCode != DlnaSoapFault.transportLocked) {
        rethrow;
      }
      try {
        await stop();
      } on DlnaSoapFault {
        // Already stopped: set the URI again anyway.
      }
      await set();
    }
  }

  /// Starts or resumes playback. Retries briefly while the renderer is
  /// still `TRANSITIONING` after a load (UPnP error 701).
  Future<void> play() async {
    for (var attempt = 1; ; attempt++) {
      try {
        await _avt('Play', {'Speed': '1'});
        return;
      } on DlnaSoapFault catch (f) {
        if (f.errorCode != DlnaSoapFault.transitionNotAvailable ||
            attempt == 3) {
          rethrow;
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
  }

  /// Pauses playback.
  Future<void> pause() => _avt('Pause', const {});

  /// Stops playback.
  Future<void> stop() => _avt('Stop', const {});

  /// Seeks to [position] with unit `REL_TIME`, falling back to `ABS_TIME`
  /// for renderers that only support the latter. Throws the `REL_TIME`
  /// fault if both are rejected.
  Future<void> seek(Duration position) async {
    final target = formatDlnaTime(position);
    try {
      await _avt('Seek', {'Unit': 'REL_TIME', 'Target': target});
    } on DlnaSoapFault {
      try {
        await _avt('Seek', {'Unit': 'ABS_TIME', 'Target': target});
        return;
      } on DlnaSoapFault {
        // Report the REL_TIME fault: it's the standard mode.
      }
      rethrow;
    }
  }

  /// Current position (AVTransport `GetPositionInfo`).
  Future<PositionInfo> position() async {
    final out = await _avt('GetPositionInfo', const {});
    final uri = out['TrackURI']?.trim() ?? '';
    return PositionInfo(
      trackDuration: parseDlnaTime(out['TrackDuration']),
      relTime: parseDlnaTime(out['RelTime']),
      trackUri: uri.isEmpty ? null : Uri.tryParse(uri),
    );
  }

  /// Current transport state (AVTransport `GetTransportInfo`).
  Future<TransportState> transportState() async => TransportState.parse(
    (await _avt('GetTransportInfo', const {}))['CurrentTransportState'],
  );

  /// Volume 0–100 (RenderingControl `GetVolume`).
  Future<int> volume() async {
    final out = await _rc('GetVolume', const {});
    final value = int.tryParse(out['CurrentVolume']?.trim() ?? '');
    if (value == null) {
      throw DlnaProtocolException(
        'Bad CurrentVolume ${out['CurrentVolume']}',
        uri: device.renderingControlUrl,
      );
    }
    return value;
  }

  /// Sets the volume (0–100).
  Future<void> setVolume(int volume) {
    RangeError.checkValueInInterval(volume, 0, 100, 'volume');
    return _rc('SetVolume', {'DesiredVolume': '$volume'});
  }

  /// Whether the renderer is muted (RenderingControl `GetMute`).
  Future<bool> isMuted() async {
    final value = (await _rc('GetMute', const {}))['CurrentMute']?.trim();
    return value == '1' || value?.toLowerCase() == 'true';
  }

  /// Mutes or unmutes.
  Future<void> setMuted(bool muted) =>
      _rc('SetMute', {'DesiredMute': muted ? '1' : '0'});

  /// What the renderer accepts (ConnectionManager `GetProtocolInfo` Sink).
  Future<List<ProtocolInfo>> sinkProtocols() async {
    final url = _require(device.connectionManagerUrl, 'ConnectionManager');
    final out = await _soap.call(
      url,
      UpnpService.connectionManager,
      'GetProtocolInfo',
      const {},
    );
    return ProtocolInfo.parseList(out['Sink'] ?? '');
  }

  /// Polls transport state + position every [interval] until the
  /// subscription is cancelled.
  ///
  /// Emits [RendererUnreachable] once [unreachableAfter] consecutive polls
  /// failed with network errors (and on every failed poll after that);
  /// polling continues so the stream recovers when the TV comes back. UPnP
  /// faults are delivered as stream errors. Use `.distinct()` to drop
  /// repeats.
  Stream<RendererStatus> watch({
    Duration interval = const Duration(seconds: 1),
    int unreachableAfter = 2,
  }) {
    // Never closed: the stream ends by cancellation, which stops polling.
    // ignore: close_sinks
    late final StreamController<RendererStatus> controller;
    Timer? timer;
    var failures = 0;
    var cancelled = false;

    Future<void> poll() async {
      try {
        final state = await transportState();
        final position = await this.position();
        failures = 0;
        if (!cancelled) controller.add(RendererActive(state, position));
      } on DlnaUnreachableException catch (e) {
        if (++failures >= unreachableAfter && !cancelled) {
          controller.add(RendererUnreachable(e));
        }
      } on Object catch (e, stack) {
        failures = 0;
        if (!cancelled) controller.addError(e, stack);
      }
      if (!cancelled) timer = Timer(interval, poll);
    }

    controller = StreamController<RendererStatus>(
      onListen: poll,
      onCancel: () {
        cancelled = true;
        timer?.cancel();
      },
    );
    return controller.stream;
  }

  /// Closes the HTTP client if this renderer created it.
  void close() {
    if (_ownsClient) _client.close();
  }

  Future<Map<String, String>> _avt(String action, Map<String, String> args) =>
      _soap.call(
        device.avTransportControlUrl,
        UpnpService.avTransport,
        action,
        {'InstanceID': '0', ...args},
      );

  Future<Map<String, String>> _rc(String action, Map<String, String> args) =>
      _soap.call(
        _require(device.renderingControlUrl, 'RenderingControl'),
        UpnpService.renderingControl,
        action,
        {'InstanceID': '0', 'Channel': 'Master', ...args},
      );

  Uri _require(Uri? url, String service) =>
      url ??
      (throw DlnaProtocolException(
        '${device.friendlyName} has no $service service',
        uri: device.location,
      ));
}
