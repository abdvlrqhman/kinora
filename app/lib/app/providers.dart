import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../core/db/database.dart';
import '../core/paths.dart';
import '../core/secure_keys.dart';
import '../core/settings.dart';
import '../data/settings_store.dart';

/// App version shown to addons/trackers as the user agent.
const kinoraVersion = '0.1.5';

/// Overridden in main() once resolved.
final pathsProvider = Provider<AppPaths>(
  (_) => throw UnimplementedError('pathsProvider must be overridden'),
);

/// Overridden in main() once opened.
final databaseProvider = Provider<AppDatabase>(
  (_) => throw UnimplementedError('databaseProvider must be overridden'),
);

/// Settings loaded before the first frame (overridden in main()).
final initialSettingsProvider = Provider<AppSettings>(
  (_) => const AppSettings(),
);

/// Shared HTTP client (keep-alive across addons, subtitles, trackers).
final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final secureKeysProvider = Provider<SecureKeys>((_) => SecureKeys());

/// Current settings; `update` persists.
final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

/// Holds and persists [AppSettings].
class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.read(initialSettingsProvider);

  /// Applies [change] and saves it.
  Future<void> update(AppSettings Function(AppSettings) change) async {
    state = change(state);
    await SettingsStore(ref.read(databaseProvider)).save(state);
  }
}
