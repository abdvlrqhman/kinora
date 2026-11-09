import 'dart:convert';

import '../core/db/database.dart';
import '../core/settings.dart';

/// Reads/writes [AppSettings] as one JSON row.
final class SettingsStore {
  SettingsStore(this._db);
  final AppDatabase _db;
  static const _key = 'settings';

  Future<AppSettings> load() async {
    final row = await (_db.select(
      _db.keyValues,
    )..where((t) => t.key.equals(_key))).getSingleOrNull();
    if (row == null) return const AppSettings();
    try {
      return AppSettings.fromJson(
        jsonDecode(row.value) as Map<String, Object?>,
      );
    } on FormatException {
      return const AppSettings();
    }
  }

  Future<void> save(AppSettings s) => _db
      .into(_db.keyValues)
      .insertOnConflictUpdate(
        KeyValue(key: _key, value: jsonEncode(s.toJson())),
      );
}
