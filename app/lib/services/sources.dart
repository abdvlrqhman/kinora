import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stremio/stremio.dart';

import '../app/providers.dart';
import '../core/db/database.dart';
import '../core/log.dart';

/// An addon the user installed.
final class InstalledAddon {
  const InstalledAddon({
    required this.id,
    required this.addon,
    required this.enabled,
    required this.position,
  });

  final int id;
  final Addon addon;
  final bool enabled;
  final int position;

  String get name => addon.manifest.name;
  Set<String> get resources => {
    for (final r in addon.manifest.resources) r.name,
  };
}

final addonClientProvider = Provider<AddonClient>(
  (ref) => AddonClient(
    httpClient: ref.watch(httpClientProvider),
    userAgent: 'Kinora/$kinoraVersion',
    cache: ResponseCache(),
  ),
);

final aggregatorProvider = Provider<AddonAggregator>(
  (ref) => AddonAggregator(ref.watch(addonClientProvider)),
);

/// Installed addons in the user's order.
final addonsProvider =
    AsyncNotifierProvider<AddonsNotifier, List<InstalledAddon>>(
      AddonsNotifier.new,
    );

/// Enabled addons only.
final enabledAddonsProvider = FutureProvider<List<Addon>>((ref) async {
  final all = await ref.watch(addonsProvider.future);
  return [
    for (final a in all)
      if (a.enabled) a.addon,
  ];
});

class AddonsNotifier extends AsyncNotifier<List<InstalledAddon>> {
  AppDatabase get _db => ref.read(databaseProvider);

  @override
  Future<List<InstalledAddon>> build() async {
    final rows = await (_db.select(
      _db.addons,
    )..orderBy([(t) => OrderingTerm.asc(t.position)])).get();
    return [
      for (final r in rows)
        if (_parse(r) case final a?) a,
    ];
  }

  InstalledAddon? _parse(AddonRow r) {
    try {
      return InstalledAddon(
        id: r.id,
        addon: Addon(
          transportUrl: Uri.parse(r.transportUrl),
          manifest: AddonManifest.fromJson(jsonDecode(r.manifestJson)),
        ),
        enabled: r.enabled,
        position: r.position,
      );
    } on Object catch (e) {
      Log.w('addons', 'skipping unreadable addon ${r.transportUrl}: $e');
      return null;
    }
  }

  /// Fetches the manifest at [input] and installs it. Throws
  /// [StremioException] with a user-facing message on failure.
  Future<InstalledAddon> install(String input) async {
    final url = parseAddonUrl(input.trim());
    final addon = await ref.read(addonClientProvider).fetchManifest(url);
    final current = await future;
    final key = addon.transportUrl.toString();
    final existing = current.where(
      (a) => a.addon.transportUrl.toString() == key,
    );
    final manifestJson = jsonEncode(
      addon.manifest.raw ?? const <String, Object?>{},
    );
    if (existing.isNotEmpty) {
      await (_db.update(_db.addons)
            ..where((t) => t.id.equals(existing.first.id)))
          .write(AddonsCompanion(manifestJson: Value(manifestJson)));
    } else {
      await _db
          .into(_db.addons)
          .insert(
            AddonsCompanion.insert(
              transportUrl: key,
              manifestJson: manifestJson,
              position: Value(current.length),
            ),
          );
    }
    Log.i(
      'addons',
      'installed ${addon.manifest.name} ${addon.manifest.version}',
    );
    ref.invalidateSelf();
    final updated = await future;
    return updated.firstWhere((a) => a.addon.transportUrl.toString() == key);
  }

  Future<void> remove(int id) async {
    await (_db.delete(_db.addons)..where((t) => t.id.equals(id))).go();
    ref.invalidateSelf();
  }

  Future<void> setEnabled(int id, {required bool enabled}) async {
    await (_db.update(_db.addons)..where((t) => t.id.equals(id))).write(
      AddonsCompanion(enabled: Value(enabled)),
    );
    ref.invalidateSelf();
  }

  /// Moves the addon at [from] to [to] (list indices).
  Future<void> reorder(int from, int to) async {
    final list = [...await future];
    final item = list.removeAt(from);
    list.insert(to.clamp(0, list.length), item);
    await _db.transaction(() async {
      for (var i = 0; i < list.length; i++) {
        await (_db.update(_db.addons)..where((t) => t.id.equals(list[i].id)))
            .write(AddonsCompanion(position: Value(i)));
      }
    });
    ref.invalidateSelf();
  }
}

/// One home-screen row from an addon catalog.
final class CatalogRow {
  const CatalogRow({
    required this.title,
    required this.type,
    required this.items,
    required this.addon,
    required this.catalog,
  });

  final String title;
  final String type;
  final List<MetaPreview> items;
  final Addon addon;
  final ManifestCatalog catalog;
}

String typeLabel(String type) => switch (type) {
  'movie' => 'movies',
  'series' => 'shows',
  'anime' => 'anime',
  'channel' => 'channels',
  'tv' => 'TV',
  _ => type,
};

/// Rows for Home: every catalog that needs no input, first page each.
final homeCatalogsProvider = FutureProvider<List<CatalogRow>>((ref) async {
  final addons = await ref.watch(enabledAddonsProvider.future);
  final client = ref.watch(addonClientProvider);
  final jobs = <Future<CatalogRow?>>[];
  var failures = 0;
  for (final addon in addons) {
    for (final c in addon.manifest.catalogs) {
      if (c.requiredExtras.isNotEmpty) continue;
      jobs.add(() async {
        try {
          final items = await client
              .catalog(addon, c.type, c.id)
              .timeout(const Duration(seconds: 15));
          if (items.isEmpty) return null;
          final name = (c.name?.trim().isNotEmpty ?? false)
              ? c.name!.trim()
              : c.id;
          final lower = name.toLowerCase();
          final title =
              lower.contains(typeLabel(c.type)) || lower.contains(c.type)
              ? name
              : '$name ${typeLabel(c.type)}';
          return CatalogRow(
            title: title,
            type: c.type,
            items: items,
            addon: addon,
            catalog: c,
          );
        } on Object catch (e) {
          Log.w('catalog', '${addon.manifest.name}/${c.id}: $e');
          failures++;
          return null;
        }
      }());
    }
  }
  final rows = await Future.wait(jobs);
  final ok = [for (final r in rows) ?r];
  if (ok.isEmpty && jobs.isNotEmpty && failures == jobs.length) {
    throw StateError(
      'Your sources didn’t answer. Check your connection and try again.',
    );
  }
  return ok.take(20).toList();
});

/// Full metadata for a title from the first addon that knows it.
final metaProvider =
    FutureProvider.family<MetaDetail, ({String type, String id})>((
      ref,
      key,
    ) async {
      final addons = await ref.watch(enabledAddonsProvider.future);
      final client = ref.watch(addonClientProvider);
      Object? lastError;
      for (final a in addons.where(
        (a) => a.supports('meta', key.type, key.id),
      )) {
        try {
          return await client.meta(a, key.type, key.id);
        } on StremioException catch (e) {
          lastError = e;
        }
      }
      throw lastError ?? StateError('No source has details for this title.');
    });

/// Search across every addon catalog that supports it. Not cached past its
/// screen, and when every source failed it says so (offline) instead of
/// pretending nothing matched.
final searchProvider = FutureProvider.autoDispose
    .family<List<MetaPreview>, String>((ref, query) async {
      final q = query.trim();
      if (q.length < 2) return const [];
      final addons = await ref.watch(enabledAddonsProvider.future);
      final agg = ref.watch(aggregatorProvider);
      final types = {for (final a in addons) ...a.manifest.types}
        ..retainAll({'movie', 'series', 'anime'});
      final perType = await Future.wait([
        for (final t in types) agg.search(addons, t, q).results.toList(),
      ]);
      final answers = [for (final list in perType) ...list];
      if (answers.isNotEmpty && answers.every((r) => r.error != null)) {
        throw StateError(
          'Your sources didn’t answer. Check your connection and try again.',
        );
      }
      final seen = <String>{};
      return [
        for (final r in answers)
          for (final m in r.items)
            if (seen.add('${m.type}:${m.id}')) m,
      ];
    });
