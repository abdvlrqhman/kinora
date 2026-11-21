import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinora/app/providers.dart';
import 'package:kinora/core/db/database.dart';
import 'package:kinora/core/paths.dart';
import 'package:kinora/services/subtitle_option.dart';
import 'package:kinora/services/subtitles_service.dart';
import 'package:path/path.dart' as p;
import 'package:subtitles/subtitles.dart';

import '../features/harness.dart' show testDb;

/// Start times (no text) of real subtitles, shared with the subtitles
/// package's own timing tests.
final _real = (jsonDecode(
  File('../packages/subtitles/test/fixtures/timing/real_starts.json')
      .readAsStringSync(),
) as Map<String, Object?>).map((k, v) => MapEntry(k, (v! as List).cast<int>()));

String _srt(List<int> starts, {int shiftMs = 0}) => SubtitleDocument(
  cues: [
    for (final (i, ms) in starts.indexed)
      Cue(
        start: Duration(milliseconds: ms + shiftMs),
        end: Duration(milliseconds: ms + shiftMs + 1500),
        text: 'Line $i',
      ),
  ],
  sourceFormat: SubtitleFormat.srt,
).toSrt();

SubtitleOption _opt(
  String id, {
  double? fit,
  String? provider = 'podnapisi',
  bool forced = false,
  String? label,
}) => SubtitleOption(
  id: id,
  language: 'en',
  label: label ?? id,
  fit: fit,
  provider: provider,
  forced: forced,
  load: () async => null,
);

void main() {
  group('syncReferences', () {
    final arabic = _opt('ar', fit: 0.35);
    final all = [
      arabic,
      _opt('en-hash', fit: 0.92),
      _opt('en-release', fit: 0.76),
      _opt('en-group', fit: 0.66),
      _opt('en-os', fit: 0.95, provider: 'opensubtitles'),
      _opt('en-forced', fit: 0.9, forced: true),
      _opt('ar-copy', fit: 0.4, label: 'ar'),
    ];

    test('unasked: only ones made for this release, from open sites', () {
      expect(syncReferences(all, arabic, auto: true).map((s) => s.id), [
        'en-hash',
        'en-release',
      ]);
    });

    test('unasked: never when the subtitle is made for this release', () {
      expect(syncReferences(all, all[1], auto: true), isEmpty);
      expect(syncReferences(all, all[2], auto: true), isEmpty);
    });

    test('asked: any other text subtitle, best fit first', () {
      expect(syncReferences(all, arabic, auto: false).map((s) => s.id), [
        'en-os',
        'en-hash',
        'en-release',
        'en-group',
      ]);
      expect(
        syncReferences(all, arabic, auto: false, skip: {'en-os'}).first.id,
        'en-hash',
      );
    });
  });

  group('lining up', () {
    late Directory tmp;
    late ProviderContainer container;
    late PlayerSubtitles subs;
    late AppPaths paths;
    late AppDatabase db;
    const hour = Duration(minutes: 70);

    String file(String name, String text) =>
        (File(p.join(tmp.path, name))..writeAsStringSync(text)).path;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('kinora-sync');
      db = testDb();
      paths = AppPaths(support: tmp, downloadsRoot: tmp, cache: tmp);
      container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          pathsProvider.overrideWithValue(paths),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await db.close();
        tmp.deleteSync(recursive: true);
      });
      subs = container.read(playerSubtitlesProvider);
    });

    test(
      'a translation 16 s late is moved back, in a corrected copy',
      () async {
        final he = file('he.srt', _srt(_real['drama-e1-he']!, shiftMs: 16000));
        final en = file('en.srt', _srt(_real['drama-e1-en']!));
        final s = (await subs.lineUp(
          he,
          en,
          duration: hour,
          referenceName: 'English',
        ))!;
        expect(s.offset.inMilliseconds, closeTo(-16000, 1000));
        expect(s.reference, 'English');
        expect(nearlyInSync(s), isFalse);
        expect(syncSummary(s), startsWith('Subtitles moved 1'));
        expect(syncSummary(s), endsWith('s earlier'));

        final before = File(he).readAsStringSync();
        final fixed = await subs.corrected(he, s);
        expect(fixed, isNot(he));
        expect(p.dirname(fixed), container.read(pathsProvider).subtitles.path);
        // The original is left as it was; the copy now lines up.
        expect(File(he).readAsStringSync(), before);
        final again = (await subs.lineUp(
          fixed,
          en,
          duration: hour,
          referenceName: 'English',
        ))!;
        expect(nearlyInSync(again), isTrue);
      },
    );

    test('another episode is never lined up', () async {
      final e2 = file('e2.srt', _srt(_real['drama-e2-en']!));
      final e1 = file('e1.srt', _srt(_real['drama-e1-en']!));
      expect(
        await subs.lineUp(e2, e1, duration: hour, referenceName: 'x'),
        isNull,
      );
    });

    test('nothing that would run past the end of the video', () async {
      final late = file(
        'late.srt',
        _srt(_real['drama-e1-en']!, shiftMs: -60000),
      );
      final en = file('en.srt', _srt(_real['drama-e1-en']!));
      // The video ends 40 s before the reference's last line (a wrong
      // reference): this one fits, moved a minute later it wouldn't.
      final end = Duration(
        milliseconds: _real['drama-e1-en']!.last + 1500 - 40000,
      );
      expect(
        await subs.lineUp(late, en, duration: end, referenceName: 'x'),
        isNull,
      );
    });

    test(
      'a line-up and an Undo are remembered per video and subtitle',
      () async {
        expect(await subs.storedSync('tt1:1:1', 'ext:a'), isNull);
        const sync = (
          offset: Duration(milliseconds: -2400),
          scale: 1.0,
          reference: 'English',
        );
        await subs.saveSync('tt1:1:1', 'ext:a', sync);
        // Opening the video again (a fresh start, the same database).
        final again = ProviderContainer(
          overrides: [
            databaseProvider.overrideWithValue(db),
            pathsProvider.overrideWithValue(paths),
          ],
        );
        addTearDown(again.dispose);
        final reopened = again.read(playerSubtitlesProvider);
        expect((await reopened.storedSync('tt1:1:1', 'ext:a'))!.sync, sync);
        // Another subtitle, or another episode, starts undecided.
        expect(await reopened.storedSync('tt1:1:1', 'ext:b'), isNull);
        expect(await reopened.storedSync('tt1:1:2', 'ext:a'), isNull);

        await reopened.saveSync('tt1:1:1', 'ext:a', null);
        final undone = await subs.storedSync('tt1:1:1', 'ext:a');
        expect(undone, isNotNull, reason: 'an Undo is a decision too');
        expect(undone!.sync, isNull);
      },
    );
  });
}
