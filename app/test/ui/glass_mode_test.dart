import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinora/core/db/database.dart';
import 'package:kinora/ui/glass_mode.dart';

import '../features/harness.dart';

void main() {
  // On screen, as a normal launch is (the probe waits for that).
  TestWidgetsFlutterBinding.ensureInitialized().handleAppLifecycleStateChanged(
    AppLifecycleState.resumed,
  );

  test('liquid glass turns off after a launch that drew nothing', () async {
    final db = testDb();
    addTearDown(db.close);

    await decideGlass(db, shaderFilters: false);
    expect(realGlass, isFalse);

    // Supported: on, until this launch proves it draws.
    await decideGlass(db, shaderFilters: true);
    expect(realGlass, isTrue);

    // That launch never confirmed a frame (froze or was killed).
    await decideGlass(db, shaderFilters: true);
    expect(realGlass, isFalse);
    expect(glassFailed, isTrue);
    await decideGlass(db, shaderFilters: true);
    expect(realGlass, isFalse, reason: 'stays off');

    // Diagnostics › Try liquid glass again.
    await retryGlass(db);
    await decideGlass(db, shaderFilters: true);
    expect(realGlass, isTrue);
  });

  test('a failing check never keeps Kinora from opening', () async {
    // Every read and write throws (like a full or broken disk).
    final db = AppDatabase.forExecutor(
      NativeDatabase.memory(setup: (_) => throw StateError('disk full')),
    );
    addTearDown(db.close);
    await decideGlass(db, shaderFilters: true);
    expect(realGlass, isFalse);
    expect(glassReason, contains('Frosted'));
  });
}
