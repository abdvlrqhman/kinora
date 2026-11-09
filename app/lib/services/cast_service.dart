import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dlna/dlna.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:release_parser/release_parser.dart' as rp;
import 'package:subtitles/subtitles.dart';

import '../app/providers.dart';
import '../core/lang.dart';
import '../core/log.dart';
import 'background.dart';
import 'cast_tracker.dart';
import 'engine_service.dart';
import 'play_request.dart';
import 'playback.dart';
import 'resolver.dart';

export 'cast_tracker.dart' show CastPhase;

/// Finds DLNA TVs and plays Kinora's streams on them. The TV pulls the video
/// straight from the phone's stream server (or from the debrid link), with
/// subtitles served as SRT through Samsung's caption extension.
final class CastService extends ChangeNotifier {
  CastService(this._ref);

  final Ref _ref;
  static const _net = MethodChannel('kinora/net');
  final _discovery = DlnaDiscovery();

  List<DlnaDevice> devices = const [];
  bool searching = false;
  DlnaDevice? device;
  CastPhase phase = CastPhase.idle;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  String? message;

  /// The TV's volume after the last change from the phone, while casting.
  int? volume;

  /// The TV missed its last answer (Wi-Fi hiccup): shown as reconnecting.
  bool reconnecting = false;

  DlnaRenderer? _renderer;
  StreamSubscription<RendererStatus>? _watch;
  StreamSubscription<DlnaDevice>? _ssdp;
  StreamSubscription<DlnaDevice>? _probe;
  final _routes = <String>[];
  int _castGen = 0;
  CastTracker? _tracker;

  /// What the current cast plays, to load it again after a TV error.
  _CastArgs? _last;
  int _reloads = 0;

  bool get isCasting =>
      device != null && phase != CastPhase.idle && phase != CastPhase.stopped;

  // -------------------------------------------------------------- target --

  /// The TV chosen before playing ("Living Room TV"): versions are ranked
  /// for it and playback starts on it. Null = this phone.
  DlnaDevice? target;

  /// Chooses where videos play. Re-ranks versions for that screen.
  void selectTarget(DlnaDevice? d) {
    target = d;
    _ref
        .read(castTargetCapsProvider.notifier)
        .set(d == null ? null : (d.isSamsung ? samsungFullHdCaps : null));
    _ref.invalidate(resolveProvider);
    if (d != null) {
      unawaited(
        _ref
            .read(settingsProvider.notifier)
            .update((s) => s.copyWith(lastCastDevice: d.toJson())),
      );
    }
    notifyListeners();
  }

  // ----------------------------------------------------------- discovery --

  /// Looks for TVs: the last one used (instant), SSDP, and a subnet probe
  /// (works without the iOS multicast entitlement).
  Future<void> search() async {
    if (searching) return;
    searching = true;
    message = null;
    devices = const [];
    notifyListeners();
    final found = <String, DlnaDevice>{};
    void add(DlnaDevice d) {
      if (found.containsKey(d.udn)) return;
      found[d.udn] = d;
      devices = found.values.toList()
        ..sort((a, b) => a.friendlyName.compareTo(b.friendlyName));
      notifyListeners();
    }

    final known = _ref.read(settingsProvider).lastCastDevice;
    if (known != null) {
      unawaited(
        _discovery
            .refresh(DlnaDevice.fromJson(known))
            .then(add, onError: (Object _) {}),
      );
    }
    String? ip;
    try {
      ip = await NetworkInfo().getWifiIP();
    } on Object {
      ip = null;
    }
    if (Platform.isAndroid) {
      try {
        await _net.invokeMethod<bool>('acquireMulticast');
      } on Object catch (e) {
        Log.d('cast', 'multicast lock: $e');
      }
    }
    final iface = ip == null ? null : InternetAddress.tryParse(ip);
    final done = <Future<void>>[];
    final ssdp = Completer<void>();
    _ssdp = _discovery
        .discover(timeout: const Duration(seconds: 5), interfaceAddress: iface)
        .listen(
          add,
          onError: (Object e) => Log.d('cast', 'ssdp: $e'),
          onDone: ssdp.complete,
        );
    done.add(ssdp.future);
    if (iface != null && iface.type == InternetAddressType.IPv4) {
      final probe = Completer<void>();
      _probe = _discovery
          .probeSubnet(iface)
          .listen(
            add,
            onError: (Object e) => Log.d('cast', 'probe: $e'),
            onDone: probe.complete,
          );
      done.add(probe.future);
    } else {
      message = 'Connect to Wi-Fi to find your TV.';
    }
    await Future.wait(done)
        .timeout(const Duration(seconds: 12), onTimeout: () => const []);
    await _ssdp?.cancel();
    await _probe?.cancel();
    if (Platform.isAndroid)
      unawaited(
        _net.invokeMethod<bool>('releaseMulticast').catchError((_) => false),
      );
    searching = false;
    if (devices.isEmpty) {
      message ??= Platform.isIOS
          ? 'No TV found. Make sure it’s on and on the same Wi-Fi. If you turned off Local Network for Kinora, turn it on in Settings › Privacy.'
          : 'No TV found. Make sure it’s on and on the same Wi-Fi.';
    }
    notifyListeners();
  }

  /// Adds a TV by its address when discovery can't see it.
  Future<void> addByAddress(String address) async {
    final host = address.trim();
    for (final target in [
      ProbeTarget.samsungTizen,
      ProbeTarget.samsungAllShare,
    ]) {
      for (final path in target.paths) {
        try {
          final d = await _discovery.describe(
            Uri.parse('http://$host:${target.port}$path'),
          );
          devices = [...devices.where((x) => x.udn != d.udn), d];
          notifyListeners();
          return;
        } on Object {
          continue;
        }
      }
    }
    message = 'No TV answered at $host.';
    notifyListeners();
  }

  // -------------------------------------------------------------- checks --

  /// Whether the TV can decode the version that's playing.
  CastCheck check(DlnaDevice d, PlaybackSource source) {
    final name = source.release?.releaseName ?? source.fileName ?? '';
    final r = rp.parseRelease(name);
    final ext = p
        .extension(source.fileName ?? name)
        .replaceFirst('.', '')
        .toLowerCase();
    final traits = MediaTraits(
      container: switch (ext) {
        'mkv' => CastContainer.mkv,
        'mp4' || 'm4v' => CastContainer.mp4,
        'ts' || 'm2ts' => CastContainer.ts,
        'avi' => CastContainer.avi,
        'mov' => CastContainer.mov,
        'webm' => CastContainer.webm,
        _ => null,
      },
      videoCodec: switch (r.videoCodec) {
        rp.VideoCodec.h264 => VideoCodec.h264,
        rp.VideoCodec.h265 => VideoCodec.hevc,
        rp.VideoCodec.av1 => VideoCodec.av1,
        rp.VideoCodec.vp9 => VideoCodec.vp9,
        rp.VideoCodec.xvid => VideoCodec.mpeg4,
        rp.VideoCodec.mpeg2 => VideoCodec.mpeg2,
        _ => null,
      },
      videoBitDepth: r.isTenBit ? 10 : (r.bitDepth ?? 8),
      height: r.resolution == rp.Resolution.unknown ? null : r.resolution.lines,
      hdr: {
        for (final h in r.hdr)
          switch (h) {
            rp.HdrFormat.hdr10 => HdrFormat.hdr10,
            rp.HdrFormat.hdr10Plus => HdrFormat.hdr10Plus,
            rp.HdrFormat.dolbyVision => HdrFormat.dolbyVision,
            rp.HdrFormat.hlg => HdrFormat.hlg,
          },
      },
      audioCodec: switch (r.audioCodecs.firstOrNull) {
        rp.AudioCodec.aac => AudioCodec.aac,
        rp.AudioCodec.ac3 => AudioCodec.ac3,
        rp.AudioCodec.eac3 => AudioCodec.eac3,
        rp.AudioCodec.dts ||
        rp.AudioCodec.dtsHd ||
        rp.AudioCodec.dtsX => AudioCodec.dts,
        rp.AudioCodec.trueHd => AudioCodec.truehd,
        rp.AudioCodec.flac => AudioCodec.flac,
        rp.AudioCodec.opus => AudioCodec.opus,
        rp.AudioCodec.mp3 => AudioCodec.mp3,
        _ => null,
      },
    );
    final profile = d.isSamsung
        ? CastProfile.samsungFullHdTizen
        : CastProfile.genericDlna;
    return profile.canPlay(traits);
  }

  // ------------------------------------------------------------- casting --

  /// Starts playing [source] on [d] at [startAt], with [subtitlePath]
  /// (any format; converted to SRT) when given. True once the TV has the
  /// video; it then reports playing when it really starts.
  Future<bool> cast({
    required DlnaDevice d,
    required PlaybackSource source,
    required PlayRequest request,
    required Duration startAt,
    Duration? length,
    String? subtitlePath,
    String? subtitleLanguage,
  }) {
    _reloads = 0;
    _last = (
      d: d,
      source: source,
      request: request,
      length: length,
      subtitlePath: subtitlePath,
      subtitleLanguage: subtitleLanguage,
    );
    return _start(startAt);
  }

  Future<bool> _start(Duration startAt) async {
    final a = _last!;
    final d = a.d;
    final gen = ++_castGen;
    final previous = _teardown(CastPhase.idle);
    device = d;
    phase = CastPhase.connecting;
    message = null;
    volume = null;
    position = startAt;
    notifyListeners();
    if (previous != null) await _stopQuietly(previous);
    if (gen != _castGen) return false;
    _ref
        .read(castTargetCapsProvider.notifier)
        .set(d.isSamsung ? samsungFullHdCaps : null);
    try {
      final lan = await NetworkInfo().getWifiIP();
      if (lan == null && a.source.kind != PlaybackKind.direct) {
        throw const _CastFailure(
          'Connect the phone to the same Wi-Fi as the TV.',
        );
      }
      final engine = _ref.read(engineServiceProvider).engine;
      Uri media;
      String? routeToken;
      switch (a.source.kind) {
        case PlaybackKind.torrent:
          media = a.source.uri.replace(host: lan);
          routeToken = a.source.streamToken;
        case PlaybackKind.local:
          final served = engine.serveFile(a.source.uri.toFilePath());
          _routes.add(served.token);
          media = served.uri(host: lan!);
          routeToken = served.token;
        case PlaybackKind.direct:
          media = a.source.uri;
      }
      Uri? caption;
      if (a.subtitlePath case final path? when lan != null) {
        caption = await _serveSrt(path, a.subtitleLanguage, lan);
      }
      final mime = _mime(a.source.fileName ?? media.path);
      if (routeToken != null) {
        engine.setRouteHeaders(
          routeToken,
          dlnaStreamHeaders(mimeType: mime, captionSrt: caption),
        );
      }
      final renderer = DlnaRenderer(
        d,
        httpClient: _ref.read(httpClientProvider),
      );
      _renderer = renderer;
      await renderer.load(
        media,
        title: a.request.isEpisode
            ? '${a.request.title} S${a.request.season} E${a.request.episode}'
            : a.request.title,
        mimeType: mime,
        sizeBytes: a.source.sizeBytes,
        duration: a.length,
        subtitleSrt: caption,
        posterUrl: a.request.poster == null
            ? null
            : Uri.tryParse(a.request.poster!),
        autoplay: false,
      );
      // Stopped meanwhile ("Watch on this phone"): don't start the TV.
      if (gen != _castGen) return false;
      await renderer.play();
      if (gen != _castGen) return false;
      // Connecting until the TV says it plays; then it seeks to [startAt].
      _tracker = CastTracker(DateTime.now(), startAt: startAt);
      // The TV pulls from this phone (except debrid links): stay alive while
      // the screen is off or Kinora is in the background.
      if (a.source.kind != PlaybackKind.direct) {
        unawaited(
          BackgroundKeeper.instance.hold(
            'cast',
            title: 'Playing on ${d.friendlyName}',
            text: a.request.title,
          ),
        );
      }
      _watch = renderer
          .watch(interval: const Duration(seconds: 1))
          .listen(_onStatus, onError: (Object e) => Log.d('cast', 'poll: $e'));
      await _ref
          .read(settingsProvider.notifier)
          .update((s) => s.copyWith(lastCastDevice: d.toJson()));
      return true;
    } on _CastFailure catch (e) {
      if (gen == _castGen) _fail(e.message);
    } on DlnaUnreachableException catch (e) {
      Log.w('cast', 'cast unreachable: $e');
      if (gen == _castGen) {
        _fail(
          'Couldn’t reach ${d.friendlyName}. Check it’s on and on this Wi-Fi.',
        );
      }
    } on DlnaException catch (e) {
      Log.w('cast', 'cast failed: $e');
      if (gen == _castGen) {
        _fail(
          '${d.friendlyName} didn’t accept the video. Try another version, or restart the TV.',
        );
      }
    } on Object catch (e, st) {
      Log.e('cast', 'cast failed', e, st);
      if (gen == _castGen) {
        _fail('Casting failed. Check that the TV is on and on this Wi-Fi.');
      }
    }
    return false;
  }

  void _fail(String text) {
    _teardown(CastPhase.stopped);
    message = text;
    notifyListeners();
  }

  /// Converts the subtitle to UTF-8 SRT (with RTL fixes the TV needs) and
  /// serves it on the LAN.
  Future<Uri?> _serveSrt(String path, String? language, String lan) async {
    try {
      final bytes = await File(path).readAsBytes();
      final text = decodeSubtitleBytes(
        bytes,
        language: language == null ? null : Language.of(language),
      ).text;
      var doc = parseSubtitle(text);
      if (language != null &&
          const {'ar', 'he', 'fa', 'ur'}.contains(normalizeLang(language))) {
        doc = doc.mapText(fixRtl);
      }
      final out = File(
        p.join(
          _ref.read(pathsProvider).subtitles.path,
          'cast-${DateTime.now().millisecondsSinceEpoch}.srt',
        ),
      );
      await out.writeAsString(doc.toSrt(), encoding: utf8);
      final served = _ref
          .read(engineServiceProvider)
          .engine
          .serveFile(out.path, mime: 'text/srt');
      _routes.add(served.token);
      return served.uri(host: lan);
    } on Object catch (e) {
      Log.w('cast', 'subtitle for TV failed: $e');
      return null;
    }
  }

  void _onStatus(RendererStatus s) {
    final t = _tracker;
    if (t == null) return;
    final now = DateTime.now();
    final wasStarted = t.started;
    final end = switch (s) {
      RendererActive(:final state, :final position, :final error) => t.answer(
        state,
        position,
        now,
        error: error,
      ),
      RendererUnreachable() => t.silence(now),
    };
    phase = t.phase;
    position = t.position;
    duration = t.duration;
    reconnecting = t.reconnecting;
    if (end != null) return _ended(end);
    // TVs ignore a seek until they really play.
    final to = t.seekTarget;
    if (!wasStarted && t.started && to != null) unawaited(seek(to));
    notifyListeners();
  }

  /// The TV ended the cast: the phone takes over where it was, except
  /// after a TV player error, which loads the video again (twice at most).
  void _ended(CastEnd end) {
    final name = device?.friendlyName ?? 'The TV';
    Log.i('cast', 'ended: ${end.name} at $position');
    if (end == CastEnd.tvError && _reloads < 2 && _last != null) {
      _reloads++;
      unawaited(_start(position));
      return;
    }
    _teardown(CastPhase.stopped);
    message = switch (end) {
      CastEnd.finished => null,
      CastEnd.stoppedOnTv => '$name stopped the video. It continues here.',
      CastEnd.tvError =>
        '$name couldn’t keep playing this video. It continues here; cast again to try once more.',
      CastEnd.neverStarted =>
        '$name couldn’t start this video. Try again, or choose another version.',
      CastEnd.lost =>
        '$name stopped answering. It continues here; cast again when the TV is back.',
    };
    notifyListeners();
  }

  Future<void> togglePlay() async {
    final r = _renderer;
    if (r == null) return;
    try {
      if (phase == CastPhase.playing) {
        await r.pause();
        phase = CastPhase.paused;
      } else {
        await r.play();
        phase = CastPhase.playing;
      }
      notifyListeners();
    } on DlnaException catch (e) {
      Log.w('cast', 'toggle: $e');
    }
  }

  Future<void> seek(Duration to) async {
    try {
      await _renderer?.seek(to < Duration.zero ? Duration.zero : to);
      position = to;
      notifyListeners();
    } on DlnaException catch (e) {
      Log.w('cast', 'seek: $e');
    }
  }

  Future<void> changeVolume(int delta) async {
    final r = _renderer;
    if (r == null) return;
    try {
      final v = (await r.volume() + delta).clamp(0, 100);
      await r.setVolume(v);
      volume = v;
      notifyListeners();
    } on DlnaException catch (e) {
      Log.w('cast', 'volume: $e');
    }
  }

  /// Stops on the TV; returns where it was so the phone can continue.
  /// Everything here ends at once (the phone can play right away); the
  /// TV's Stop is awaited last.
  Future<Duration> stop() async {
    _castGen++; // a cast still connecting must not start the TV
    _last = null;
    final at = position;
    final r = _teardown(CastPhase.idle);
    notifyListeners();
    if (r != null) await _stopQuietly(r);
    return at;
  }

  /// Ends the cast on this side: polling, the keep-alive and the served
  /// files. Returns the renderer, for the caller to stop the TV.
  DlnaRenderer? _teardown(CastPhase to) {
    unawaited(BackgroundKeeper.instance.drop('cast'));
    unawaited(_watch?.cancel());
    _watch = null;
    _tracker = null;
    final r = _renderer;
    _renderer = null;
    final engine = _ref.read(engineServiceProvider);
    if (engine.isRunning) {
      for (final t in _routes) {
        engine.engine.closeRoute(t);
      }
    }
    _routes.clear();
    device = null;
    phase = to;
    reconnecting = false;
    final t = target;
    _ref
        .read(castTargetCapsProvider.notifier)
        .set(t == null ? null : (t.isSamsung ? samsungFullHdCaps : null));
    return r;
  }

  static Future<void> _stopQuietly(DlnaRenderer r) async {
    try {
      await r.stop();
    } on Object {
      // The TV may already be off.
    }
  }

  static String _mime(String name) => switch (p.extension(name).toLowerCase()) {
    '.mp4' || '.m4v' => 'video/mp4',
    '.ts' || '.m2ts' => 'video/mp2t',
    '.avi' => 'video/x-msvideo',
    '.mov' => 'video/quicktime',
    '.webm' => 'video/webm',
    _ => 'video/x-matroska',
  };

  @override
  void dispose() {
    unawaited(_watch?.cancel());
    unawaited(_ssdp?.cancel());
    unawaited(_probe?.cancel());
    super.dispose();
  }
}

typedef _CastArgs = ({
  DlnaDevice d,
  PlaybackSource source,
  PlayRequest request,
  Duration? length,
  String? subtitlePath,
  String? subtitleLanguage,
});

final class _CastFailure implements Exception {
  const _CastFailure(this.message);
  final String message;
}

final castServiceProvider = Provider<CastService>((ref) {
  final s = CastService(ref);
  ref.onDispose(s.dispose);
  return s;
});
