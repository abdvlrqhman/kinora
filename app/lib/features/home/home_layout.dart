import 'package:stremio/stremio.dart';

import '../search/discovery.dart';

/// Home's own rows, in their default order. Source catalogs follow
/// (`cat:<source>|<type>|<catalog>`), then rows pinned from Discovery
/// (`pin:<source>|<type>|<catalog>|<genre>`).
const homeBuiltIns = [
  'continue',
  'new-episodes',
  'top10',
  'my-list',
  'for-you',
  'because',
  'trending-shows',
  'trending-movies',
];

String catalogRowId(String source, String type, String catalog) =>
    'cat:$source|$type|$catalog';

String pinnedRowId(BrowseKey k) =>
    'pin:${k.addon}|${k.type}|${k.catalog}|${k.genre ?? ''}';

/// The catalog and genre of a pinned row's id (null for other ids).
BrowseKey? pinnedKey(String id) {
  if (!id.startsWith('pin:')) return null;
  final p = id.substring(4).split('|');
  if (p.length != 4) return null;
  return (
    addon: p[0],
    type: p[1],
    catalog: p[2],
    genre: p[3].isEmpty ? null : p[3],
  );
}

/// Home's rows in order: the viewer's [order] of the [available] ones;
/// rows missing from it go after the row they follow by default (a new
/// kind of row) or, a new source's or pin's, at the end. Then without the
/// [hidden] ones.
List<String> homeLayout({
  required List<String> available,
  List<String> order = const [],
  Set<String> hidden = const {},
}) {
  final there = available.toSet();
  final out = [
    for (final id in order)
      if (there.contains(id)) id,
  ];
  final placed = out.toSet();
  for (var i = 0; i < available.length; i++) {
    final id = available[i];
    if (placed.contains(id)) continue;
    var at = id.startsWith('cat:') || id.startsWith('pin:') ? out.length : 0;
    for (var j = i - 1; at == 0 && j >= 0; j--) {
      final k = out.indexOf(available[j]);
      if (k >= 0) {
        at = k + 1;
        break;
      }
    }
    out.insert(at, id);
    placed.add(id);
  }
  return [
    for (final id in out)
      if (!hidden.contains(id)) id,
  ];
}

/// A row Home can show: its id, its title, and the catalog behind it
/// (catalog rows, the ranked top ten and pins).
typedef HomeRowChoice = ({String id, String title, String? catalog});

/// Every row Home can show, in default order: Home's own, then the
/// sources' catalogs (the first, ranked, is "Trending now"), then pins.
List<HomeRowChoice> homeRowChoices({
  required List<({String source, ManifestCatalog catalog})> catalogs,
  List<({String source, ManifestCatalog catalog})> browsable = const [],
  List<String> pinned = const [],
  required String Function(ManifestCatalog) titleOf,
}) {
  String id(({String source, ManifestCatalog catalog}) c) =>
      catalogRowId(c.source, c.catalog.type, c.catalog.id);
  ({String source, ManifestCatalog catalog})? pinOf(BrowseKey k) => browsable
      .where(
        (c) =>
            c.source == k.addon &&
            c.catalog.type == k.type &&
            c.catalog.id == k.catalog,
      )
      .firstOrNull;
  final first = catalogs.firstOrNull;
  return [
    (id: 'continue', title: 'Keep watching', catalog: null),
    (id: 'new-episodes', title: 'New episodes', catalog: null),
    if (first != null)
      (
        id: 'top10',
        title: 'Trending now: ${titleOf(first.catalog)}',
        catalog: id(first),
      ),
    (id: 'my-list', title: 'My list', catalog: null),
    (id: 'for-you', title: 'For you', catalog: null),
    (id: 'because', title: 'Because you watched…', catalog: null),
    (id: 'trending-shows', title: 'Trending shows', catalog: null),
    (id: 'trending-movies', title: 'Trending movies', catalog: null),
    for (final c in catalogs.skip(1))
      (id: id(c), title: titleOf(c.catalog), catalog: id(c)),
    for (final p in pinned)
      if (pinnedKey(p) case final k?)
        if (pinOf(k) case final c?)
          (
            id: p,
            title: [titleOf(c.catalog), ?k.genre].join(': '),
            catalog: id(c),
          ),
  ];
}
