import 'dart:async';

import 'package:dlna/dlna.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/fake_samsung_dmr.dart';

void main() {
  late FakeSamsungDmr tv;
  late DlnaRenderer renderer;

  setUp(() async {
    tv = await FakeSamsungDmr.start();
    final device = DlnaDevice.fromDescription(samsungDescription, tv.location);
    renderer = DlnaRenderer(device, timeout: const Duration(seconds: 2));
  });

  tearDown(() async {
    renderer.close();
    await tv.close();
  });

  final media = Uri.parse('http://192.168.1.20:8090/s/abc/0.mkv?x=1&y=2');
  final srt = Uri.parse('http://192.168.1.20:8090/sub/1.srt');

  test(
    'load sends SetAVTransportURI with Samsung captions, then Play',
    () async {
      await renderer.load(
        media,
        title: 'Episode & more',
        mimeType: 'video/x-matroska',
        sizeBytes: 1000,
        duration: const Duration(minutes: 45),
        subtitleSrt: srt,
      );
      expect(tv.actions, ['SetAVTransportURI', 'Play']);
      final set = tv.calls.first;
      expect(set.path, '/upnp/control/AVTransport1');
      expect(
        set.soapAction,
        '"urn:schemas-upnp-org:service:AVTransport:1#SetAVTransportURI"',
      );
      expect(set.args['InstanceID'], '0');
      expect(set.args['CurrentURI'], '$media');
      final item = XmlDocument.parse(set.args['CurrentURIMetaData']!)
          .rootElement
          .childElements
          .single;
      expect(item.getElement('dc:title')!.innerText, 'Episode & more');
      expect(item.getElement('res')!.innerText, '$media');
      expect(item.getElement('res')!.getAttribute('duration'), '0:45:00.000');
      expect(
        item.getElement('sec:CaptionInfoEx')!.getAttribute('sec:type'),
        'srt',
      );
      expect(item.getElement('sec:CaptionInfoEx')!.innerText, '$srt');
      expect(tv.calls.last.args, {'InstanceID': '0', 'Speed': '1'});
      expect(tv.state, 'PLAYING');
    },
  );

  test('load retries with minimal DIDL when metadata is rejected', () async {
    tv.faults['SetAVTransportURI'] = [DlnaSoapFault.illegalMimeType];
    await renderer.load(
      media,
      title: 'T',
      mimeType: 'video/x-matroska',
      subtitleSrt: srt,
      autoplay: false,
    );
    expect(tv.actions, ['SetAVTransportURI', 'SetAVTransportURI']);
    final minimal = tv.calls.last.args['CurrentURIMetaData']!;
    expect(minimal, contains('protocolInfo="http-get:*:video/x-matroska:*"'));
    expect(minimal, isNot(contains('CaptionInfo')));
  });

  test('load stops a busy transport and sets the URI again', () async {
    tv.faults['SetAVTransportURI'] = [DlnaSoapFault.transportLocked];
    await renderer.load(media, title: 'T', mimeType: 'video/mp4');
    expect(tv.actions, [
      'SetAVTransportURI',
      'Stop',
      'SetAVTransportURI',
      'Play',
    ]);
  });

  test('load surfaces the fault when even minimal DIDL is rejected', () async {
    tv.faults['SetAVTransportURI'] = [714, 714];
    await expectLater(
      renderer.load(media, title: 'T', mimeType: 'video/x-matroska'),
      throwsA(
        isA<DlnaSoapFault>().having((f) => f.errorCode, 'errorCode', 714),
      ),
    );
    expect(tv.actions, isNot(contains('Play')));
  });

  test('play retries while TRANSITIONING (701)', () async {
    tv.faults['Play'] = [701];
    await renderer.play();
    expect(tv.actions, ['Play', 'Play']);
  });

  test('pause, stop', () async {
    await renderer.pause();
    expect(tv.state, 'PAUSED_PLAYBACK');
    await renderer.stop();
    expect(tv.state, 'STOPPED');
  });

  test('seek uses REL_TIME, falls back to ABS_TIME', () async {
    await renderer.seek(
      const Duration(hours: 1, minutes: 2, seconds: 3, milliseconds: 900),
    );
    expect(tv.calls.single.args, {
      'InstanceID': '0',
      'Unit': 'REL_TIME',
      'Target': '1:02:03',
    });

    tv.calls.clear();
    tv.faults['Seek'] = [DlnaSoapFault.seekModeNotSupported];
    await renderer.seek(const Duration(seconds: 30));
    expect(
      [for (final c in tv.calls) c.args['Unit']],
      ['REL_TIME', 'ABS_TIME'],
    );
  });

  test('seek throws the REL_TIME fault when both modes fail', () async {
    tv.faults['Seek'] = [711, 710];
    await expectLater(
      renderer.seek(const Duration(seconds: 30)),
      throwsA(
        isA<DlnaSoapFault>().having((f) => f.errorCode, 'errorCode', 711),
      ),
    );
  });

  test('position, transport state', () async {
    expect(await renderer.transportState(), TransportState.noMediaPresent);
    expect(
      await renderer.position(),
      const PositionInfo(trackDuration: Duration.zero, relTime: Duration.zero),
    );
    await renderer.load(media, title: 'T', mimeType: 'video/mp4');
    tv
      ..relTime = '0:10:05'
      ..trackDuration = '0:44:59.500';
    expect(await renderer.transportState(), TransportState.playing);
    expect(
      await renderer.position(),
      PositionInfo(
        trackDuration: const Duration(
          minutes: 44,
          seconds: 59,
          milliseconds: 500,
        ),
        relTime: const Duration(minutes: 10, seconds: 5),
        trackUri: media,
      ),
    );
  });

  test('volume and mute (RenderingControl, Channel Master)', () async {
    expect(await renderer.volume(), 12);
    await renderer.setVolume(30);
    expect(tv.volume, 30);
    expect(tv.calls.last.path, '/upnp/control/RenderingControl1');
    expect(
      tv.calls.last.soapAction,
      '"urn:schemas-upnp-org:service:RenderingControl:1#SetVolume"',
    );
    expect(tv.calls.last.args, {
      'InstanceID': '0',
      'Channel': 'Master',
      'DesiredVolume': '30',
    });
    expect(() => renderer.setVolume(101), throwsRangeError);
    expect(await renderer.isMuted(), isFalse);
    await renderer.setMuted(true);
    expect(await renderer.isMuted(), isTrue);
  });

  test('sinkProtocols', () async {
    final sink = await renderer.sinkProtocols();
    expect(sink.map((p) => p.mimeType), contains('video/x-mkv'));
    expect(tv.calls.single.path, '/upnp/control/ConnectionManager1');
  });

  test('unknown action fault is typed', () async {
    tv.faults['Pause'] = [DlnaSoapFault.invalidInstanceId];
    await expectLater(
      renderer.pause(),
      throwsA(
        isA<DlnaSoapFault>()
            .having((f) => f.action, 'action', 'Pause')
            .having((f) => f.errorDescription, 'description', 'Fake error 718'),
      ),
    );
  });

  test('timeout becomes DlnaUnreachableException', () async {
    final slow = DlnaRenderer(
      renderer.device,
      timeout: const Duration(milliseconds: 100),
    );
    tv.delay = const Duration(milliseconds: 500);
    await expectLater(
      slow.play(),
      throwsA(
        isA<DlnaUnreachableException>().having(
          (e) => e.isTimeout,
          'isTimeout',
          isTrue,
        ),
      ),
    );
    slow.close();
  });

  test('watch polls, reports unreachable, and stops on cancel', () async {
    await renderer.load(media, title: 'T', mimeType: 'video/mp4');
    final statuses = <RendererStatus>[];
    final unreachable = Completer<void>();
    final sub = renderer
        .watch(interval: const Duration(milliseconds: 20), unreachableAfter: 2)
        .listen((s) {
          statuses.add(s);
          if (s is RendererActive && statuses.length == 2)
            unawaited(tv.close());
          if (s is RendererUnreachable && !unreachable.isCompleted)
            unreachable.complete();
        });
    await unreachable.future.timeout(const Duration(seconds: 5));
    await sub.cancel();
    expect(
      statuses.first,
      isA<RendererActive>().having(
        (s) => s.state,
        'state',
        TransportState.playing,
      ),
    );
    expect(statuses.whereType<RendererActive>().first.position.trackUri, media);
    expect(statuses.last, isA<RendererUnreachable>());
    final count = statuses.length;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(statuses.length, count, reason: 'no polling after cancel');
  });

  test('watch stops issuing requests after cancel', () async {
    final sub = renderer
        .watch(interval: const Duration(milliseconds: 10))
        .listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await sub.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final count = tv.calls.length;
    expect(count, greaterThan(2));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(tv.calls.length, count);
  });
}
