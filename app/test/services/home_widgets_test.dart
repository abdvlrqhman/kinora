import 'package:flutter_test/flutter_test.dart';
import 'package:kinora/core/db/database.dart';
import 'package:kinora/services/home_widgets.dart';

WatchProgressData row(
  String id, {
  int? season,
  int? episode,
  int position = 0,
  int duration = 0,
  String type = 'series',
}) => WatchProgressData(
  videoId: season == null ? id : '$id:$season:$episode',
  mediaId: id,
  type: type,
  name: 'Show $id',
  season: season,
  episode: episode,
  positionMs: position,
  durationMs: duration,
  completed: false,
  dismissed: false,
  poster: 'https://img.test/$id.jpg',
  updatedAt: DateTime(2026, 11, 20),
);

void main() {
  test('the widget shows three titles, with where you are in each', () {
    final items = widgetItems([
      row('tt1', season: 1, episode: 3, position: 600000, duration: 2400000),
      row('tt2', season: 2, episode: 1),
      row('tt3', type: 'movie', position: 3600000, duration: 7800000),
      row('tt4', season: 1, episode: 1),
    ]);
    expect(items, hasLength(3));
    expect(items[0].sub, 'S1 E3, 30m left');
    expect(items[0].progress, closeTo(0.25, 0.001));
    expect(items[0].open, '/title/series/tt1');
    expect(items[1].sub, 'Up next: S2 E1');
    expect(items[1].progress, 0);
    expect(items[2].sub, '1h 10m left');
    expect(items[2].open, '/title/movie/tt3');
  });

  test('a widget tap opens its title, the card opens Home', () {
    expect(
      widgetPath(Uri.parse('kinora://title/series/tt1')),
      '/title/series/tt1',
    );
    expect(widgetPath(Uri.parse('kinora://home')), '/');
    expect(widgetPath(Uri.parse('https://example.com/x')), isNull);
    expect(widgetPath(null), isNull);
  });
}
