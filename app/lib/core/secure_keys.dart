import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Credentials for one provider (subtitle sites, debrid). Never logged.
final class ProviderCredentials {
  const ProviderCredentials({
    this.apiKey = '',
    this.username = '',
    this.password = '',
  });

  factory ProviderCredentials.fromJson(Map<String, Object?> j) =>
      ProviderCredentials(
        apiKey: j['apiKey'] as String? ?? '',
        username: j['username'] as String? ?? '',
        password: j['password'] as String? ?? '',
      );

  final String apiKey;
  final String username;
  final String password;

  bool get isEmpty => apiKey.isEmpty && username.isEmpty && password.isEmpty;

  Map<String, Object?> toJson() => {
    'apiKey': apiKey,
    'username': username,
    'password': password,
  };

  @override
  String toString() => 'ProviderCredentials(${isEmpty ? 'empty' : 'set'})';
}

/// Keychain (iOS) / Keystore-backed (Android) storage for provider keys.
/// Nothing is stored by default; the user enters each key in Settings.
final class SecureKeys {
  SecureKeys([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _prefix = 'provider.';

  Future<ProviderCredentials> read(String providerId) async {
    final raw = await _storage.read(key: '$_prefix$providerId');
    if (raw == null) return const ProviderCredentials();
    return ProviderCredentials.fromJson(
      jsonDecode(raw) as Map<String, Object?>,
    );
  }

  Future<void> write(String providerId, ProviderCredentials c) => c.isEmpty
      ? _storage.delete(key: '$_prefix$providerId')
      : _storage.write(
          key: '$_prefix$providerId',
          value: jsonEncode(c.toJson()),
        );

  Future<void> delete(String providerId) =>
      _storage.delete(key: '$_prefix$providerId');

  /// Other secrets Kinora keeps for the user (a Trakt sign-in).
  Future<String?> readSecret(String key) => _storage.read(key: 'secret.$key');

  Future<void> writeSecret(String key, String? value) => value == null
      ? _storage.delete(key: 'secret.$key')
      : _storage.write(key: 'secret.$key', value: value);
}
