import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinora/app/providers.dart';
import 'package:kinora/core/db/database.dart';
import 'package:kinora/core/secure_keys.dart';
import 'package:kinora/services/backup.dart';

import '../features/harness.dart';
import '../features/settings/settings_harness.dart';

void main() {
  test('a sealed code opens with its passphrase, and only with it', () async {
    final code = await BackupCode.seal(
      {
        'keys': {'subdl': 'k'},
      },
      'correct horse',
      iterations: 1000,
    );
    expect(code, startsWith(BackupCode.prefix));
    expect(code, isNot(contains('subdl')));
    // Line breaks from a messaging app don't matter.
    final wrapped = '${code.substring(0, 20)}\n${code.substring(20)}';
    expect(await BackupCode.open(wrapped, 'correct horse'), {
      'keys': {'subdl': 'k'},
    });
    await expectLater(
      BackupCode.open(code, 'wrong horse'),
      throwsA(
        isA<BackupException>().having(
          (e) => e.message,
          'message',
          contains('Wrong passphrase'),
        ),
      ),
    );
    await expectLater(
      BackupCode.open('hello', 'x'),
      throwsA(isA<BackupException>()),
    );
    await expectLater(
      BackupCode.open(code.substring(0, 30), 'correct horse'),
      throwsA(isA<BackupException>()),
    );
  });

  test('sources and keys move to another device', () async {
    Future<(ProviderContainer, AppDatabase, FakeSecureStorage)> device() async {
      final db = testDb();
      final store = FakeSecureStorage();
      final c = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          secureKeysProvider.overrideWithValue(SecureKeys(store)),
        ],
      );
      addTearDown(() async {
        c.dispose();
        await db.close();
      });
      return (c, db, store);
    }

    final (phone, phoneDb, _) = await device();
    for (final (i, url) in [
      'https://torrentio.test/realdebrid=SECRET',
      'https://subs.test',
    ].indexed) {
      await phoneDb
          .into(phoneDb.addons)
          .insert(
            AddonsCompanion.insert(
              transportUrl: url,
              manifestJson: '{"id":"a$i","name":"A$i"}',
              position: Value(i),
              enabled: Value(i == 0),
            ),
          );
    }
    final keys = phone.read(secureKeysProvider);
    await keys.write('tmdb', const ProviderCredentials(apiKey: 'tmdb-key'));
    await keys.write('subdl', const ProviderCredentials(apiKey: 'subdl-key'));
    await phone
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(enabledSubtitleProviders: ['subdl']));

    final data = await phone.read(backupServiceProvider).gather();
    expect(BackupService.count(data), (sources: 2, keys: 2));
    final code = await BackupCode.seal(data, 'passphrase', iterations: 1000);

    // The new device already has one of the sources.
    final (pc, pcDb, _) = await device();
    await pcDb
        .into(pcDb.addons)
        .insert(
          AddonsCompanion.insert(
            transportUrl: 'https://subs.test',
            manifestJson: '{"id":"a1","name":"A1"}',
          ),
        );
    final restored = await pc
        .read(backupServiceProvider)
        .restore(await BackupCode.open(code, 'passphrase'));
    expect(restored, (sources: 1, keys: 2));
    final rows = await pcDb.select(pcDb.addons).get();
    expect(rows.map((r) => r.transportUrl), [
      'https://subs.test',
      'https://torrentio.test/realdebrid=SECRET',
    ]);
    expect(rows.last.enabled, isTrue);
    expect(rows.last.position, 1);
    expect(
      (await pc.read(secureKeysProvider).read('subdl')).apiKey,
      'subdl-key',
    );
    expect((await pc.read(secureKeysProvider).read('tmdb')).apiKey, 'tmdb-key');
    expect(
      pc.read(settingsProvider).enabledSubtitleProviders,
      contains('subdl'),
    );
  });
}
