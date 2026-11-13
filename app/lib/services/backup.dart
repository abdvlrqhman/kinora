import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/db/database.dart';
import '../core/secure_keys.dart';
import 'sources.dart';
import 'subtitles_service.dart';
import 'tmdb.dart';

/// A backup code couldn't be opened; [message] says why, for the user.
final class BackupException implements Exception {
  const BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// What a restore brought in.
typedef Restored = ({int sources, int keys});

/// Sources and keys sealed with the user's passphrase, as text to carry to
/// another device. The code is useless without the passphrase: AES-256-GCM
/// with a key stretched from it (PBKDF2-SHA256), the salt and the strength
/// travelling with the code.
abstract final class BackupCode {
  static const prefix = 'kinora1.';
  static const minPassphrase = 8;
  static const _version = 1;

  static Future<String> seal(
    Map<String, Object?> data,
    String passphrase, {
    int iterations = 310000,
  }) => Isolate.run(() async {
    final salt = _random(16);
    final key = await _key(passphrase, salt, iterations);
    final box = await AesGcm.with256bits().encrypt(
      gzip.encode(utf8.encode(jsonEncode(data))),
      secretKey: key,
    );
    final head = ByteData(5)
      ..setUint8(0, _version)
      ..setUint32(1, iterations);
    final bytes = [
      ...head.buffer.asUint8List(),
      ...salt,
      ...box.concatenation(),
    ];
    return prefix + base64Url.encode(bytes).replaceAll('=', '');
  });

  static Future<Map<String, Object?>> open(
    String code,
    String passphrase,
  ) async {
    final text = code.replaceAll(RegExp(r'\s'), '');
    if (!text.startsWith(prefix)) {
      throw const BackupException('That isn’t a Kinora backup code.');
    }
    final Uint8List bytes;
    try {
      bytes = base64Url.decode(
        base64Url.normalize(text.substring(prefix.length)),
      );
    } on FormatException {
      throw const BackupException(
        'The code is incomplete. Copy all of it again.',
      );
    }
    if (bytes.length < 5 + 16 + 12 + 16 || bytes[0] != _version) {
      throw const BackupException(
        'The code is incomplete, or from a newer Kinora.',
      );
    }
    return Isolate.run(() async {
      final iterations = ByteData.sublistView(bytes, 1, 5).getUint32(0);
      final salt = bytes.sublist(5, 21);
      final key = await _key(passphrase, salt, iterations);
      final List<int> plain;
      try {
        plain = await AesGcm.with256bits().decrypt(
          SecretBox.fromConcatenation(
            bytes.sublist(21),
            nonceLength: 12,
            macLength: 16,
          ),
          secretKey: key,
        );
      } on SecretBoxAuthenticationError {
        // The right passphrase still opens the first bytes (gzip's header):
        // then the code was cut short in copying, not mistyped.
        final head = await AesCtr.with256bits(macAlgorithm: MacAlgorithm.empty)
            .decrypt(
              SecretBox(
                bytes.sublist(33, 36),
                nonce: [...bytes.sublist(21, 33), 0, 0, 0, 2],
                mac: Mac.empty,
              ),
              secretKey: key,
            );
        throw BackupException(
          head[0] == 0x1f && head[1] == 0x8b && head[2] == 0x08
              ? 'The code is incomplete. Copy all of it again.'
              : 'Wrong passphrase, or the code was changed.',
        );
      }
      return jsonDecode(utf8.decode(gzip.decode(plain)))
          as Map<String, Object?>;
    });
  }

  static Future<SecretKey> _key(String passphrase, List<int> salt, int n) =>
      Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: n,
        bits: 256,
      ).deriveKeyFromPassword(password: passphrase, nonce: salt);

  static List<int> _random(int n) => SecretKeyData.random(length: n).bytes;
}

/// Gathers and restores what a backup holds: the sources (with any keys
/// inside their links), the TMDB and subtitle site keys, and which subtitle
/// sites are on. Not Trakt: each device signs in on its own.
final class BackupService {
  BackupService(this._ref);
  final Ref _ref;

  AppDatabase get _db => _ref.read(databaseProvider);
  SecureKeys get _keys => _ref.read(secureKeysProvider);

  static List<String> get keyIds => [
    tmdbKeyId,
    for (final p in subtitleProviderCatalog)
      if (p.needsKey) p.id,
  ];

  Future<Map<String, Object?>> gather() async {
    final addons = await (_db.select(
      _db.addons,
    )..orderBy([(t) => OrderingTerm.asc(t.position)])).get();
    final keys = <String, Object?>{};
    for (final id in keyIds) {
      final c = await _keys.read(id);
      if (!c.isEmpty) keys[id] = c.toJson();
    }
    return {
      'sources': [
        for (final a in addons)
          {
            'url': a.transportUrl,
            'manifest': a.manifestJson,
            'enabled': a.enabled,
          },
      ],
      'keys': keys,
      'subtitleSites': _ref.read(settingsProvider).enabledSubtitleProviders,
    };
  }

  /// How much [data] holds, for the screen before sealing or restoring.
  static Restored count(Map<String, Object?> data) => (
    sources: (data['sources'] as List? ?? const []).length,
    keys: (data['keys'] as Map? ?? const {}).length,
  );

  /// Adds the sources this device doesn't have (after its own) and sets the
  /// keys from the backup. Returns how many of each came in.
  Future<Restored> restore(Map<String, Object?> data) async {
    final have = {
      for (final a in await _db.select(_db.addons).get()) a.transportUrl,
    };
    var position = have.length;
    var sources = 0;
    await _db.transaction(() async {
      for (final s
          in (data['sources'] as List? ?? const [])
              .whereType<Map<String, Object?>>()) {
        final url = s['url'];
        final manifest = s['manifest'];
        if (url is! String || manifest is! String || !have.add(url)) continue;
        await _db
            .into(_db.addons)
            .insert(
              AddonsCompanion.insert(
                transportUrl: url,
                manifestJson: manifest,
                enabled: Value(s['enabled'] != false),
                position: Value(position++),
              ),
            );
        sources++;
      }
    });
    var keys = 0;
    final saved = (data['keys'] as Map? ?? const {}).cast<String, Object?>();
    for (final id in keyIds) {
      if (saved[id] case final Map<String, Object?> c) {
        await _keys.write(id, ProviderCredentials.fromJson(c));
        keys++;
      }
    }
    final sites = (data['subtitleSites'] as List? ?? const [])
        .whereType<String>();
    await _ref
        .read(settingsProvider.notifier)
        .update(
          (s) => s.copyWith(
            enabledSubtitleProviders: {
              ...s.enabledSubtitleProviders,
              ...sites,
            }.toList(),
          ),
        );
    _ref
      ..invalidate(addonsProvider)
      ..invalidate(subtitleProvidersProvider)
      ..invalidate(tmdbKeyProvider);
    return (sources: sources, keys: keys);
  }
}

final backupServiceProvider = Provider<BackupService>(BackupService.new);
