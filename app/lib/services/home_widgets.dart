import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import '../app/providers.dart';
import '../core/db/database.dart';
import '../core/format.dart';
import '../core/log.dart';
import '../features/home/home_feed.dart';

/// What the home screen widget shows for one title (Continue watching).
typedef WidgetItem = ({
  String title,
  String sub,
  double progress,
  String open,
  String? poster,
});

/// The first three of Keep watching, as the widget shows them.
List<WidgetItem> widgetItems(List<WatchProgressData> rows) => [
  for (final r in rows.take(3))
    () {
      final fresh = r.positionMs <= 0 || r.durationMs <= 0;
      final episode = r.season != null && r.episode != null
          ? Fmt.episode(r.season!, r.episode!)
          : null;
      final left = Fmt.duration(
        Duration(milliseconds: math.max(0, r.durationMs - r.positionMs)),
      );
      return (
        title: r.name,
        sub: fresh
            ? (episode == null ? 'Start watching' : 'Up next: $episode')
            : [?episode, '$left left'].join(', '),
        progress: fresh ? 0.0 : (r.positionMs / r.durationMs).clamp(0.0, 1.0),
        open: '/title/${r.type}/${r.mediaId}',
        poster: r.poster,
      );
    }(),
];

/// The app path a widget tap asks for (`kinora://title/series/tt1` →
/// `/title/series/tt1`; the card itself → Home).
String? widgetPath(Uri? uri) {
  if (uri == null || uri.scheme != 'kinora') return null;
  if (uri.host == 'title') return '/title${uri.path}';
  return '/';
}

/// The home screen widget (Android and iPhone): kept
/// in step with Keep watching, and its taps open the title.
final class HomeWidgets {
  HomeWidgets(this._ref);
  final Ref _ref;

  static const group = 'group.io.github.abdvlrqhman.kinora';
  static const _android = 'io.github.abdvlrqhman.kinora.KinoraWidgetProvider';
  static const _ios = 'KinoraWidget';

  static bool get supported => Platform.isAndroid || Platform.isIOS;

  var _started = false;
  Timer? _soon;
  String? _shown;
  StreamSubscription<Uri?>? _taps;
  ProviderSubscription<AsyncValue<List<WatchProgressData>>>? _rows;

  Future<void> start(void Function(String path) open) async {
    if (!supported || _started) return;
    _started = true;
    try {
      final signed = Platform.isIOS ? await _signedGroup() ?? group : group;
      Log.i('widget', 'app group $signed');
      await HomeWidget.setAppGroupId(signed);
      void tapped(Uri? uri) {
        if (widgetPath(uri) case final path?) open(path);
      }

      tapped(await HomeWidget.initiallyLaunchedFromHomeWidget());
      _taps = HomeWidget.widgetClicked.listen(tapped);
    } on Object catch (e) {
      Log.w('widget', 'start: $e');
    }
    _rows = _ref.listen(continueItemsProvider, (_, next) {
      if (next.value case final rows?) {
        _soon?.cancel();
        _soon = Timer(const Duration(seconds: 2), () => unawaited(_show(rows)));
      }
    }, fireImmediately: true);
  }

  /// The group SideStore signed this copy with (its own name for ours).
  static Future<String?> _signedGroup() async {
    try {
      return await const MethodChannel('kinora/files')
          .invokeMethod<String>('appGroup');
    } on Object {
      return null;
    }
  }

  void dispose() {
    _soon?.cancel();
    unawaited(_taps?.cancel());
    _rows?.close();
  }

  Future<void> _show(List<WatchProgressData> rows) async {
    final items = widgetItems(rows);
    final key = jsonEncode([
      for (final i in items) [i.title, i.sub, i.progress, i.open, i.poster],
    ]);
    if (key == _shown) return; // nothing changed
    try {
      final http = _ref.read(httpClientProvider);
      final out = <Map<String, Object?>>[];
      for (final (n, i) in items.indexed) {
        String? poster;
        if (i.poster case final url?) {
          try {
            final res = await http
                .get(Uri.parse(url))
                .timeout(const Duration(seconds: 15));
            if (res.statusCode == 200) {
              poster = await HomeWidget.saveFile(
                'poster$n',
                res.bodyBytes,
                extension: 'jpg',
              );
            }
          } on Object catch (e) {
            // No poster: the row shows without one.
            Log.w('widget', 'poster: $e');
          }
        }
        out.add({
          'title': i.title,
          'sub': i.sub,
          'progress': i.progress,
          'open': i.open,
          'poster': ?poster,
        });
      }
      await HomeWidget.saveWidgetData<String>('items', jsonEncode(out));
      await HomeWidget.updateWidget(
        qualifiedAndroidName: _android,
        iOSName: _ios,
      );
      _shown = key;
      Log.i('widget', 'showing ${out.length}');
    } on Object catch (e) {
      Log.w('widget', 'update: $e');
    }
  }
}

final homeWidgetsProvider = Provider<HomeWidgets>((ref) {
  final w = HomeWidgets(ref);
  ref.onDispose(w.dispose);
  return w;
});
