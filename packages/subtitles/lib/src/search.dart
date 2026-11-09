import 'dart:async';

import 'package:collection/collection.dart';

import 'ads.dart';
import 'archive.dart';
import 'cache.dart';
import 'cancel.dart';
import 'charset.dart';
import 'document.dart';
import 'errors.dart';
import 'language.dart';
import 'matcher.dart';
import 'models.dart';
import 'parsers.dart';
import 'release.dart';
import 'timing.dart';

/// Where one provider is in a search.
enum ProviderState { pending, done, failed, timedOut, cancelled }

/// One provider's outcome in a [SubtitleSearchUpdate].
final class ProviderStatus {
  const ProviderStatus(
    this.providerId,
    this.state, {
    this.count = 0,
    this.error,
  });

  final String providerId;
  final ProviderState state;

  /// Results it returned (before dedupe and episode checks).
  final int count;
  final SubtitleException? error;

  @override
  bool operator ==(Object other) =>
      other is ProviderStatus &&
      other.providerId == providerId &&
      other.state == state &&
      other.count == count &&
      other.error == error;

  @override
  int get hashCode => Object.hash(providerId, state, count, error);

  @override
  String toString() =>
      'ProviderStatus($providerId ${state.name} $count'
      '${error == null ? '' : ' $error'})';
}

/// Snapshot of a running search; a new one is emitted per provider answer.
final class SubtitleSearchUpdate {
  const SubtitleSearchUpdate({
    required this.byLanguage,
    required this.providers,
    this.rejected = 0,
  });

  /// Languages (preferred first) -> subtitles, best fit first.
  final Map<Language, List<RankedSubtitle>> byLanguage;

  /// Provider id -> status.
  final Map<String, ProviderStatus> providers;

  /// Results dropped for being another episode/movie.
  final int rejected;

  /// Every provider has answered, failed or timed out.
  bool get isComplete =>
      providers.values.every((p) => p.state != ProviderState.pending);

  /// Languages with how many subtitles each has (for the picker).
  Map<Language, int> get counts => {
    for (final e in byLanguage.entries) e.key: e.value.length,
  };

  /// Best subtitle per language.
  Map<Language, RankedSubtitle> get best => {
    for (final e in byLanguage.entries)
      if (e.value.isNotEmpty) e.key: e.value.first,
  };

  @override
  bool operator ==(Object other) =>
      other is SubtitleSearchUpdate &&
      other.rejected == rejected &&
      const DeepCollectionEquality().equals(other.byLanguage, byLanguage) &&
      const MapEquality<String, ProviderStatus>().equals(
        other.providers,
        providers,
      );

  @override
  int get hashCode => Object.hash(
    rejected,
    const DeepCollectionEquality().hash(byLanguage),
    const MapEquality<String, ProviderStatus>().hash(providers),
  );

  @override
  String toString() =>
      'SubtitleSearchUpdate(${counts.entries.map((e) => '${e.key.code}:${e.value}').join(' ')}'
      ', ${providers.values.where((p) => p.state == ProviderState.pending).length} pending)';
}

/// A downloaded, decoded and parsed subtitle.
final class LoadedSubtitle {
  const LoadedSubtitle({
    required this.result,
    required this.document,
    required this.encoding,
    required this.fileName,
    this.timing,
  });

  final SubtitleResult result;
  final SubtitleDocument document;

  /// Charset the file was decoded from (`utf-8`, `windows-1256` ...).
  final String encoding;

  /// File used (inside the archive, when it was one).
  final String fileName;

  /// Length check against the video, when the query had a duration.
  final TimingReport? timing;

  @override
  bool operator ==(Object other) =>
      other is LoadedSubtitle &&
      other.result == result &&
      other.document == document &&
      other.encoding == encoding &&
      other.fileName == fileName &&
      other.timing == timing;

  @override
  int get hashCode => Object.hash(result, document, encoding, fileName, timing);

  @override
  String toString() =>
      'LoadedSubtitle(${result.key} $fileName $encoding '
      '${document.cues.length} cues)';
}

/// Queries the enabled providers in parallel and merges their answers.
///
/// Each provider gets [providerTimeout]; results stream in as they arrive,
/// are deduped (same provider id, or the same normalized release + language
/// + HI from another provider, keeping the better fit), checked for the
/// right episode/movie, ranked with [matcher] and grouped by language.
final class SubtitleSearch {
  SubtitleSearch({
    required Iterable<SubtitleProvider> providers,
    this.matcher = const SubtitleMatcher(),
    this.providerTimeout = const Duration(seconds: 20),
    this.cache,
  }) : providers = List.unmodifiable(providers);

  final List<SubtitleProvider> providers;
  final SubtitleMatcher matcher;
  final Duration providerTimeout;

  /// Optional download cache used by [load].
  final SubtitleCache? cache;

  /// Streams snapshots: one immediately (all pending), then one per provider
  /// answer; the last has [SubtitleSearchUpdate.isComplete]. [video] is the
  /// release being played (default: parsed `query.releaseNames.first`).
  /// Cancelling [cancel] or the subscription cancels provider requests.
  Stream<SubtitleSearchUpdate> search(
    SubtitleQuery query, {
    ReleaseInfo? video,
    CancelToken? cancel,
  }) {
    final token = CancelToken(parent: cancel);
    // Group in the query's language order unless prefs say otherwise.
    final m = matcher.prefs.languages.isNotEmpty
        ? matcher
        : SubtitleMatcher(
            parser: matcher.parser,
            prefs: SubtitlePrefs(
              languages: query.languages,
              preferHearingImpaired: matcher.prefs.preferHearingImpaired,
              forcedOnly: matcher.prefs.forcedOnly,
            ),
          );
    final target =
        video ??
        (query.releaseNames.isEmpty
            ? const ReleaseInfo()
            : m.parser(query.releaseNames.first));
    final status = <String, ProviderStatus>{
      for (final p in providers)
        p.id: ProviderStatus(p.id, ProviderState.pending),
    };
    final kept = <String, RankedSubtitle>{}; // result.key -> ranked
    final byRelease = <String, String>{}; // release key -> result.key
    var rejected = 0;
    late final StreamController<SubtitleSearchUpdate> out;

    void emit() {
      if (out.isClosed) return;
      out.add(
        SubtitleSearchUpdate(
          byLanguage: Map.unmodifiable(m.groupByLanguage(kept.values)),
          providers: Map.unmodifiable(status),
          rejected: rejected,
        ),
      );
    }

    void accept(List<SubtitleResult> results) {
      for (final r in results) {
        if (kept.containsKey(r.key)) continue;
        if (query.languages.isNotEmpty &&
            !query.languages.contains(r.language)) {
          continue;
        }
        final ranked = m.rate(
          r,
          target,
          query: query,
          videoHash: query.fileHash,
        );
        if (ranked == null) {
          rejected++;
          continue;
        }
        final rk = _releaseKey(r);
        final existingKey = rk == null ? null : byRelease[rk];
        final existing = existingKey == null ? null : kept[existingKey];
        if (existing != null && existing.result.providerId != r.providerId) {
          if (!_better(ranked, existing)) continue;
          kept.remove(existingKey);
        }
        kept[r.key] = ranked;
        if (rk != null) byRelease[rk] = r.key;
      }
    }

    Future<void> run(SubtitleProvider p) async {
      final providerToken = CancelToken(parent: token);
      try {
        final results = await p
            .search(query, cancel: providerToken)
            .timeout(
              providerTimeout,
              onTimeout: () {
                providerToken.cancel();
                throw SubtitleNetworkException(
                  'no answer within ${providerTimeout.inSeconds}s',
                  providerId: p.id,
                  isTimeout: true,
                );
              },
            );
        accept(results);
        status[p.id] = ProviderStatus(
          p.id,
          ProviderState.done,
          count: results.length,
        );
      } on SubtitleCancelledException catch (e) {
        status[p.id] = ProviderStatus(p.id, ProviderState.cancelled, error: e);
      } on SubtitleNetworkException catch (e) {
        status[p.id] = ProviderStatus(
          p.id,
          e.isTimeout ? ProviderState.timedOut : ProviderState.failed,
          error: e,
        );
      } on SubtitleException catch (e) {
        status[p.id] = ProviderStatus(p.id, ProviderState.failed, error: e);
      } on Object catch (e) {
        // A provider bug (e.g. an unexpected JSON shape) must not kill the search.
        status[p.id] = ProviderStatus(
          p.id,
          ProviderState.failed,
          error: SubtitleResponseException('$e', providerId: p.id),
        );
      }
      emit();
    }

    out = StreamController<SubtitleSearchUpdate>(
      onListen: () {
        emit();
        Future.wait(providers.map(run)).whenComplete(out.close);
      },
      onCancel: token.cancel,
    );
    return out.stream;
  }

  /// Runs [search] to completion and returns the final snapshot.
  Future<SubtitleSearchUpdate> searchAll(
    SubtitleQuery query, {
    ReleaseInfo? video,
    CancelToken? cancel,
  }) => search(query, video: video, cancel: cancel).last;

  /// Downloads (or reads from [cache]) [result], extracts the right file
  /// from archives, decodes its charset and parses it.
  Future<LoadedSubtitle> load(
    SubtitleResult result, {
    SubtitleQuery? query,
    CancelToken? cancel,
  }) async {
    final provider = providers.firstWhereOrNull(
      (p) => p.id == result.providerId,
    );
    if (provider == null) {
      throw ArgumentError.value(result.providerId, 'providerId', 'not enabled');
    }
    var raw = await cache?.getRaw(result);
    if (raw == null) {
      raw = await provider.download(result, cancel: cancel);
      await cache?.putRaw(result, raw);
    }
    final episodic = query?.isEpisode ?? false;
    final file = extractSubtitle(
      raw,
      season: episodic ? query?.season : null,
      episode: episodic ? query?.episode : null,
      language: result.language,
      forced: result.forced,
      hearingImpaired: result.hearingImpaired,
      parser: matcher.parser,
    );
    final decoded = decodeSubtitleBytes(file.bytes, language: result.language);
    final doc = removeAds(
      parseSubtitle(decoded.text, fps: result.fps ?? query?.fps),
    );
    final seconds = query?.durationSec;
    return LoadedSubtitle(
      result: result,
      document: doc,
      encoding: decoded.encoding,
      fileName: file.fileName,
      timing: seconds == null
          ? null
          : checkTiming(doc.cues, Duration(seconds: seconds)),
    );
  }

  late final Set<String> _aggregators = {
    for (final p in providers)
      if (p.capabilities.contains(ProviderCapability.aggregator)) p.id,
  };

  bool _better(RankedSubtitle a, RankedSubtitle b) {
    if (a.fit != b.fit) return a.fit > b.fit;
    // Same fit: prefer the original source over an aggregator's copy.
    return !_aggregators.contains(a.result.providerId) &&
        _aggregators.contains(b.result.providerId);
  }

  static String? _releaseKey(SubtitleResult r) {
    final name = r.releaseNames.firstOrNull ?? r.fileName;
    if (name == null) return null;
    final norm = name
        .toLowerCase()
        .replaceFirst(RegExp(r'\.(srt|ass|ssa|vtt|sub|zip)$'), '')
        .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
        .trim();
    if (norm.isEmpty) return null;
    return '$norm|${r.language.code}|${r.hearingImpaired}';
  }
}
