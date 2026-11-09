import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stremio/stremio.dart';

import '../../app/providers.dart';
import '../../core/db/database.dart';
import '../../services/sources.dart';

/// Recent searches in the `SearchHistory` table.
final class SearchHistoryStore {
  SearchHistoryStore(this._db);
  final AppDatabase _db;

  // shortcut: old rows are hidden by the limit, never pruned; prune if the
  // table ever matters for size.
  Stream<List<String>> watch({int limit = 8}) =>
      (_db.select(_db.searchHistory)
            ..orderBy([(t) => OrderingTerm.desc(t.at)])
            ..limit(limit))
          .map((r) => r.query)
          .watch();

  Future<void> add(String query) => _db
      .into(_db.searchHistory)
      .insertOnConflictUpdate(
        SearchHistoryCompanion.insert(query: query, at: Value(DateTime.now())),
      );

  Future<void> remove(String query) =>
      (_db.delete(_db.searchHistory)..where((t) => t.query.equals(query))).go();
}

final searchHistoryProvider = Provider(
  (ref) => SearchHistoryStore(ref.watch(databaseProvider)),
);

/// Newest first.
final recentSearchesProvider = StreamProvider.autoDispose<List<String>>(
  (ref) => ref.watch(searchHistoryProvider).watch(),
);

/// Results of one type ("Movies", 12 items).
final class SearchGroup {
  const SearchGroup(this.label, this.items);

  final String label;
  final List<MetaPreview> items;
}

const _groupLabels = {'movie': 'Movies', 'series': 'Shows', 'anime': 'Anime'};

/// Results grouped by type; the group holding the best match comes first
/// (sources return results best match first).
List<SearchGroup> groupResults(List<MetaPreview> items) {
  final byType = <String, List<MetaPreview>>{};
  for (final m in items) {
    (byType[m.type] ??= []).add(m);
  }
  return [
    for (final MapEntry(key: t, value: list) in byType.entries)
      SearchGroup(_groupLabels[t] ?? _capitalized(typeLabel(t)), list),
  ];
}

String _capitalized(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

final searchGroupsProvider = Provider.autoDispose
    .family<AsyncValue<List<SearchGroup>>, String>(
      (ref, query) => ref.watch(searchProvider(query)).whenData(groupResults),
    );

/// A pasted magnet or http(s) link to play directly.
final class PlayLink {
  const PlayLink(this.url, this.name);

  final String url;

  /// The magnet's `dn`, or the URL's file name.
  final String name;
}

/// Recognizes `magnet:` URIs and http(s) URLs; null for search text.
PlayLink? parsePlayLink(String input) {
  final text = input.trim();
  if (text.contains(RegExp(r'\s'))) return null;
  if (text.toLowerCase().startsWith('magnet:?')) {
    String? name;
    for (final part in text.substring(8).split('&')) {
      if (!part.startsWith('dn=')) continue;
      final raw = part.substring(3);
      try {
        name = Uri.decodeQueryComponent(raw);
      } on FormatException {
        name = raw;
      }
    }
    return PlayLink(
      text,
      (name?.trim().isNotEmpty ?? false) ? name!.trim() : 'Magnet link',
    );
  }
  final uri = Uri.tryParse(text);
  if (uri == null ||
      !(uri.isScheme('http') || uri.isScheme('https')) ||
      uri.host.isEmpty) {
    return null;
  }
  String? file;
  try {
    file = uri.pathSegments.where((s) => s.isNotEmpty).lastOrNull;
  } on FormatException {
    // Undecodable path: fall back to the host.
  }
  return PlayLink(text, file ?? uri.host);
}
