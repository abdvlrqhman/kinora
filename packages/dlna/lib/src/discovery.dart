import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'device.dart';
import 'errors.dart';
import 'http_util.dart';
import 'ssdp.dart';

/// A port and the description paths to try on it during [DlnaDiscovery.probeSubnet].
final class ProbeTarget {
  /// Creates a probe target. Paths are tried in order until one is a renderer.
  const ProbeTarget(this.port, this.paths);

  /// Samsung Tizen TVs (2016+), including the 5 Series FHD models.
  static const samsungTizen = ProbeTarget(9197, ['/dmr']);

  /// Samsung 2013–2015 TVs: `:7676/smp_N_`, where N changes on every TV
  /// boot (seen 2–131), so the range is swept sequentially (the TV's HTTP
  /// server chokes on parallel requests).
  static final samsungLegacy = ProbeTarget(7676, [
    for (var n = 1; n <= 160; n++) '/smp_${n}_',
  ]);

  /// Samsung 2010–2012 TVs (AllShare, port 52235).
  static const samsungAllShare = ProbeTarget(52235, ['/dmr/SamsungMRDesc.xml']);

  /// Default targets: Samsung first, then common renderer stacks
  /// (libupnp/gmrender on 49152, Sonos on 1400, misc on 8080).
  static final defaults = [
    samsungTizen,
    samsungLegacy,
    samsungAllShare,
    const ProbeTarget(49152, ['/description.xml']),
    const ProbeTarget(1400, ['/xml/device_description.xml']),
    const ProbeTarget(8080, ['/description.xml']),
  ];

  /// TCP port.
  final int port;

  /// Description paths (absolute).
  final List<String> paths;

  @override
  bool operator ==(Object other) =>
      other is ProbeTarget &&
      other.port == port &&
      other.paths.length == paths.length &&
      Iterable<int>.generate(paths.length)
          .every((i) => other.paths[i] == paths[i]);

  @override
  int get hashCode => Object.hash(port, Object.hashAll(paths));

  @override
  String toString() => 'ProbeTarget($port, ${paths.length} paths)';
}

/// Finds DLNA media renderers on the local network.
///
/// On Android hold a `WifiManager.MulticastLock` while [discover] runs. On
/// iOS, multicast needs the `com.apple.developer.networking.multicast`
/// entitlement; without it use [probeSubnet]. Both need the iOS Local
/// Network permission (`NSLocalNetworkUsageDescription`).
final class DlnaDiscovery {
  /// Creates a discovery helper.
  ///
  /// [ssdpAddress]/[ssdpPort] are the M-SEARCH destination and the NOTIFY
  /// listening port (default 239.255.255.250:1900; tests use 127.0.0.1).
  DlnaDiscovery({
    http.Client? httpClient,
    this.descriptionTimeout = const Duration(seconds: 3),
    InternetAddress? ssdpAddress,
    this.ssdpPort = 1900,
    this.listenForNotify = true,
  }) : ssdpAddress = ssdpAddress ?? InternetAddress('239.255.255.250'),
       _ownsClient = httpClient == null,
       _client = httpClient ?? http.Client();

  /// Timeout for fetching one device description.
  final Duration descriptionTimeout;

  /// Where M-SEARCH requests are sent.
  final InternetAddress ssdpAddress;

  /// SSDP port (M-SEARCH destination and NOTIFY listening port).
  final int ssdpPort;

  /// Whether [discover] also listens for NOTIFY announcements on [ssdpPort].
  final bool listenForNotify;

  final http.Client _client;
  final bool _ownsClient;

  /// Fetches and parses the device description at [location].
  ///
  /// Throws [DlnaUnreachableException], [DlnaHttpException] or
  /// [DlnaProtocolException] (not a renderer / malformed).
  Future<DlnaDevice> describe(Uri location) async {
    final response = await sendHttp(
      _client,
      'GET',
      location,
      timeout: descriptionTimeout,
    );
    if (response.statusCode != 200) {
      throw DlnaHttpException(
        'Device description unavailable',
        statusCode: response.statusCode,
        uri: location,
      );
    }
    return DlnaDevice.fromDescription(bodyText(response), location);
  }

  /// Re-fetches a remembered device's description (instant reconnect).
  ///
  /// Throws [DlnaProtocolException] if another device now answers at that
  /// location (e.g. the TV got a new IP); fall back to [discover].
  Future<DlnaDevice> refresh(DlnaDevice known) async {
    final device = await describe(known.location);
    if (device.udn != known.udn) {
      throw DlnaProtocolException(
        'A different device (${device.udn}) answers at this location',
        uri: known.location,
      );
    }
    return device;
  }

  /// Searches with SSDP for [timeout] and emits each renderer once (by UDN).
  ///
  /// Sends M-SEARCH for MediaRenderer:1 and `ssdp:all` three times, listens
  /// for NOTIFY alive announcements, and fetches descriptions concurrently.
  /// Bind to the Wi-Fi address with [interfaceAddress] so the search leaves
  /// on the right interface. A device announcing `ssdp:byebye` is not
  /// emitted unless it comes back. The stream closes after [timeout] plus
  /// any in-flight description fetches; cancel it to stop early.
  ///
  /// Emits a [DlnaUnreachableException] error (and closes) if the network
  /// refuses multicast, e.g. on iOS without the multicast entitlement.
  Stream<DlnaDevice> discover({
    Duration timeout = const Duration(seconds: 4),
    InternetAddress? interfaceAddress,
  }) {
    late final StreamController<DlnaDevice> controller;
    final sockets = <RawDatagramSocket>[];
    final timers = <Timer>[];
    final fetches = <Future<void>>[];
    final locations = <Uri, String?>{}; // location -> uuid
    final emitted = <String>{};
    final departed = <String>{};
    var stopped = false;
    var cancelled = false;

    void stop() {
      if (stopped) return;
      stopped = true;
      for (final t in timers) {
        t.cancel();
      }
      for (final s in sockets) {
        s.close();
      }
    }

    Future<void> finish() async {
      stop();
      await Future.wait(fetches);
      if (!controller.isClosed) await controller.close();
    }

    void fail(Object error) {
      if (stopped) return;
      controller.addError(error);
      unawaited(finish());
    }

    void handle(SsdpMessage message) {
      final uuid = message.uuid;
      if (message.isByeBye) {
        if (uuid == null) return;
        departed.add(uuid);
        emitted.remove(uuid);
        locations.removeWhere((_, u) => u == uuid);
        return;
      }
      final location = message.location;
      if (!message.isRenderer || location == null || !location.hasAuthority) {
        return;
      }
      if (uuid != null) departed.remove(uuid);
      if (locations.containsKey(location)) return;
      locations[location] = uuid;
      fetches.add(
        describe(location).then(
          (device) {
            if (cancelled || departed.contains(device.udn)) return;
            if (emitted.add(device.udn)) controller.add(device);
          },
          // Unreachable/not a renderer: allow a later retry of this location.
          onError: (Object _) => locations.remove(location),
        ),
      );
    }

    void listen(RawDatagramSocket socket) {
      sockets.add(socket);
      socket.listen((event) {
        if (event != RawSocketEvent.read || stopped) return;
        for (var d = socket.receive(); d != null; d = socket.receive()) {
          final message = SsdpMessage.parse(d.data);
          if (message != null) handle(message);
        }
      }, onError: (Object _) {});
    }

    Future<void> start() async {
      final RawDatagramSocket search;
      try {
        search = await RawDatagramSocket.bind(
          interfaceAddress ?? InternetAddress.anyIPv4,
          0,
        );
      } on SocketException catch (e) {
        return fail(
          DlnaUnreachableException('Cannot open SSDP socket', cause: e),
        );
      }
      if (stopped) return search.close();
      listen(search);
      if (ssdpAddress.isMulticast) {
        search.multicastHops = 4;
        if (interfaceAddress != null) {
          try {
            search.setRawOption(
              RawSocketOption(
                RawSocketOption.levelIPv4,
                RawSocketOption.IPv4MulticastInterface,
                interfaceAddress.rawAddress,
              ),
            );
          } on SocketException {
            // Best effort: the bound address usually selects the interface.
          }
        }
      }
      final host = '${ssdpAddress.address}:$ssdpPort';
      void send() {
        if (stopped) return;
        try {
          for (final st in const [mediaRendererSt, 'ssdp:all']) {
            search.send(
              buildMSearch(host: host, st: st),
              ssdpAddress,
              ssdpPort,
            );
          }
        } on SocketException catch (e) {
          fail(DlnaUnreachableException('SSDP send failed', cause: e));
        }
      }

      send();
      for (final ms in const [700, 1600]) {
        if (ms < timeout.inMilliseconds) {
          timers.add(Timer(Duration(milliseconds: ms), send));
        }
      }
      if (listenForNotify) {
        final notify = await _bindNotify(interfaceAddress);
        if (notify == null) return;
        if (stopped) return notify.close();
        listen(notify);
      }
    }

    controller = StreamController<DlnaDevice>(
      onListen: () {
        timers.add(Timer(timeout, finish));
        unawaited(start());
      },
      onCancel: () {
        cancelled = true;
        stop();
      },
    );
    return controller.stream;
  }

  Future<RawDatagramSocket?> _bindNotify(
    InternetAddress? interfaceAddress,
  ) async {
    RawDatagramSocket socket;
    try {
      socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        ssdpPort,
        reusePort: true,
      );
    } on Object {
      try {
        socket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          ssdpPort,
        );
      } on SocketException {
        return null; // Port taken: NOTIFY listening is best effort.
      }
    }
    if (ssdpAddress.isMulticast) {
      try {
        final interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4,
        );
        final interface = interfaceAddress == null
            ? null
            : interfaces
                  .where((i) => i.addresses.contains(interfaceAddress))
                  .firstOrNull;
        socket.joinMulticast(ssdpAddress, interface);
      } on SocketException {
        socket.close();
        return null;
      }
    }
    return socket;
  }

  /// Fallback discovery without multicast: probes every host of
  /// [local]'s IPv4 subnet for known renderer description URLs.
  ///
  /// Runs up to [concurrency] TCP connects at a time (each limited to
  /// [connectTimeout]); [targets] are probed in order across all hosts, so
  /// Samsung Tizen TVs show up first. Hosts that don't answer a connect at
  /// all are skipped for the remaining targets, so a /24 finishes in a few
  /// seconds. Emits each renderer once; cancel to stop.
  Stream<DlnaDevice> probeSubnet(
    InternetAddress local, {
    int prefix = 24,
    List<ProbeTarget>? targets,
    int concurrency = 32,
    Duration connectTimeout = const Duration(milliseconds: 400),
  }) {
    if (local.type != InternetAddressType.IPv4) {
      throw ArgumentError.value(local, 'local', 'must be an IPv4 address');
    }
    RangeError.checkValueInInterval(prefix, 20, 30, 'prefix');
    RangeError.checkValueInInterval(concurrency, 1, 256, 'concurrency');
    final hosts = subnetHosts(local, prefix);
    late final StreamController<DlnaDevice> controller;
    var cancelled = false;

    Future<void> run() async {
      final dead = <InternetAddress>{};
      final done = <InternetAddress>{};
      final emitted = <String>{};
      final tasks = [
        for (final target in targets ?? ProbeTarget.defaults)
          for (final host in hosts) (host, target),
      ].iterator;

      Future<void> worker() async {
        while (!cancelled && tasks.moveNext()) {
          final (host, target) = tasks.current;
          if (dead.contains(host) || done.contains(host)) continue;
          final open = await _connect(host, target.port, connectTimeout);
          if (open == null) dead.add(host);
          if (open != true) continue;
          for (final path in target.paths) {
            if (cancelled) return;
            try {
              final device = await describe(
                Uri(
                  scheme: 'http',
                  host: host.address,
                  port: target.port,
                  path: path,
                ),
              );
              done.add(host);
              if (emitted.add(device.udn) && !cancelled) controller.add(device);
              break;
            } on DlnaUnreachableException {
              break; // The device's HTTP server gave up; don't hammer it.
            } on DlnaException {
              continue; // 404 or not a renderer: next path.
            }
          }
        }
      }

      await Future.wait([for (var i = 0; i < concurrency; i++) worker()]);
      if (!controller.isClosed) await controller.close();
    }

    controller = StreamController<DlnaDevice>(
      onListen: () => unawaited(run()),
      onCancel: () => cancelled = true,
    );
    return controller.stream;
  }

  /// Closes the HTTP client if this instance created it.
  void close() {
    if (_ownsClient) _client.close();
  }
}

/// True if the port accepted, false if refused (host is up), null if the
/// host did not answer (absent, firewalled or timed out).
Future<bool?> _connect(InternetAddress host, int port, Duration timeout) async {
  try {
    final socket = await Socket.connect(host, port, timeout: timeout);
    socket.destroy();
    return true;
  } on SocketException catch (e) {
    // ECONNREFUSED on Linux/Android, Darwin/iOS and Windows.
    return const {111, 61, 10061}.contains(e.osError?.errorCode) ? false : null;
  }
}

/// Every usable host address of [local]'s IPv4 /[prefix] network, excluding
/// the network, broadcast and [local] addresses.
List<InternetAddress> subnetHosts(InternetAddress local, int prefix) {
  final b = local.rawAddress;
  final ip = b[0] << 24 | b[1] << 16 | b[2] << 8 | b[3];
  final mask = (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF;
  final network = ip & mask;
  final broadcast = network | (~mask & 0xFFFFFFFF);
  return [
    for (var a = network + 1; a < broadcast; a++)
      if (a != ip)
        InternetAddress.fromRawAddress(
          Uint8List.fromList([
            a >> 24 & 255,
            a >> 16 & 255,
            a >> 8 & 255,
            a & 255,
          ]),
        ),
  ];
}
