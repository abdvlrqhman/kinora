import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/db/database.dart';
import 'trakt.dart';

/// How the viewer feels about a whole show or movie (never one episode).
enum Taste {
  notForMe('Not for me', 3),
  like('I like it', 7),
  love('Love it', 10);

  const Taste(this.label, this.trakt);
  final String label;

  /// On Trakt's 1–10 scale.
  final int trakt;

  /// A Trakt rating: 1–5 is not for me ("Meh" included), 9–10 is love.
  static Taste fromTrakt(int rating) => rating <= 5
      ? notForMe
      : rating <= 8
      ? like
      : love;
}

/// Ratings, kept on the device (`rating:<id>` → `{"t": type, "r": 1–10}`).
final class Ratings {
  Ratings(this._db, {this.onRated});

  final AppDatabase _db;

  /// The viewer rated (or unrated, null) a title here: Trakt hears of it.
  final void Function(String mediaId, String type, int? rating)? onRated;

  static const _prefix = 'rating:';

  /// Every rated title: id → (type, 1–10).
  Stream<Map<String, ({String type, int rating})>> watchAll() => (_db.select(
    _db.keyValues,
  )..where((t) => t.key.like('$_prefix%'))).watch().map(_parse);

  Future<Map<String, ({String type, int rating})>> all() async => _parse(
    await (_db.select(
      _db.keyValues,
    )..where((t) => t.key.like('$_prefix%'))).get(),
  );

  static Map<String, ({String type, int rating})> _parse(List<KeyValue> rows) {
    final out = <String, ({String type, int rating})>{};
    for (final r in rows) {
      try {
        final j = jsonDecode(r.value) as Map<String, Object?>;
        out[r.key.substring(_prefix.length)] = (
          type: j['t']! as String,
          rating: (j['r']! as num).toInt(),
        );
      } on Object {
        // A damaged entry counts as unrated.
      }
    }
    return out;
  }

  /// The viewer rated [mediaId] ([taste] null removes the rating).
  Future<void> rate(String mediaId, String type, Taste? taste) async {
    await _write(mediaId, type, taste?.trakt);
    onRated?.call(mediaId, type, taste?.trakt);
  }

  /// Ratings from Trakt. [merge] (the first sync) keeps ratings only made
  /// here; later syncs mirror Trakt, except [keep] (not sent yet). Never
  /// sent back.
  Future<void> fromTrakt(
    Map<String, ({String type, int rating})> theirs, {
    required bool merge,
    Set<String> keep = const {},
  }) => _db.transaction(() async {
    if (!merge) {
      for (final id in (await all()).keys) {
        if (id.startsWith('tt') &&
            !theirs.containsKey(id) &&
            !keep.contains(id)) {
          await _write(id, '', null);
        }
      }
    }
    for (final MapEntry(key: id, value: (:type, :rating)) in theirs.entries) {
      await _write(id, type, rating);
    }
  });

  Future<void> _write(String mediaId, String type, int? rating) =>
      rating == null
      ? (_db.delete(
          _db.keyValues,
        )..where((t) => t.key.equals('$_prefix$mediaId'))).go()
      : _db
            .into(_db.keyValues)
            .insertOnConflictUpdate(
              KeyValuesCompanion.insert(
                key: '$_prefix$mediaId',
                value: jsonEncode({'t': type, 'r': rating}),
              ),
            );
}

final ratingsProvider = Provider(
  (ref) => Ratings(
    ref.watch(databaseProvider),
    onRated: (id, type, rating) =>
        ref.read(traktSyncProvider).rated(id, type, rating),
  ),
);

/// Every rated title as a [Taste].
final tastesProvider = StreamProvider<Map<String, Taste>>(
  (ref) => ref
      .watch(ratingsProvider)
      .watchAll()
      .map(
        (m) => {
          for (final e in m.entries) e.key: Taste.fromTrakt(e.value.rating),
        },
      ),
);

/// How the viewer rated one title (null: not rated).
final tasteProvider = Provider.family<Taste?, String>(
  (ref, mediaId) => ref.watch(tastesProvider).value?[mediaId],
);
