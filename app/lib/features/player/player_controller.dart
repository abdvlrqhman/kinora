import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:stremio/stremio.dart';

import '../../app/providers.dart';
import '../../core/lang.dart';
import '../../core/log.dart';
import '../../core/settings.dart';
import '../../data/repositories.dart';
import '../../services/engine_service.dart';
import '../../services/library.dart';
import '../../services/play_request.dart';
import '../../services/playback.dart';
import '../../services/cast_service.dart';
import '../../services/downloads.dart';
import '../../services/resolver.dart';
import '../../services/sources.dart';
import '../../ui/widgets/media.dart' show runtimeMinutes;
import '../../services/subtitle_option.dart';
import '../../services/subtitles_service.dart';

enum PlayerPhase { preparing, playing, failed }

/// Drives one playback session (and the episodes after it).
class PlayerController extends ChangeNotifier {
  PlayerController(this._ref, PlayRequest request) : _request = request {
    debugLast = this;
    player = Player(
      configuration: const PlayerConfiguration(
        title: 'Kinora',
        bufferSize: 64 * 1024 * 1024,
        logLevel: MPVLogLevel.warn,
      ),
    );
    video = VideoController(player);
    _subs = [
      player.stream.error.listen((e) => Log.w('player', e)),
      player.stream.tracks.listen((_) => _onTracks()),
      player.stream.completed.listen((done) {
        if (done) unawaited(_onCompleted());
      }),
      player.stream.playing.listen((_) => notifyListeners()),
      player.stream.position.listen(_onPosition),
    ];
  }

  /// The most recent controller, for integration tests.
  @visibleForTesting
  static PlayerController? debugLast;

  /// The app's container (outlives the screen, so cleanup after the
  /// screen closes still works).
  final ProviderContainer _ref;
  late final Player player;
  late final VideoController video;
  late final List<StreamSubscription<Object?>> _subs;

  PlayRequest _request;
  PlayRequest get request => _request;

  PlayerPhase phase = PlayerPhase.preparing;
  String status = 'Finding the best version';
  String? error;
  PlaybackSource? source;
  MetaDetail? meta;

  /// Embedded + external subtitles, grouped by language in the UI.
  List<SubtitleOption> subtitles = const [];
  String? activeSubtitleId;
  Duration subtitleDelay = Duration.zero;
  bool nightMode = false;
  double rate = 1;

  /// Chapter markers (title, start) read from the file.
  List<({String title, Duration start})> chapters = const [];

  /// Whether Up Next may start the next episode by itself.
  bool get autoplayNext => _settings.autoplayNext;

  /// Up Next is offered near the end of an episode.
  bool upNextDismissed = false;
  PlayRequest? nextEpisode;
  PlayRequest? previousEpisode;

  Timer? _saveTimer;
  Timer? _statusTimer;
  bool _tracksApplied = false;
  bool _disposed = false;
  bool _prefetchedNext = false;
  bool _watchedHandled = false;

  /// A watched download to delete when the viewer leaves it (setting).
  String? _watchedLocalFile;
  double? _bandwidth;
  int _generation = 0;
  Completer<void>? _cancelPrepare;

  AppSettings get _settings => _ref.read(settingsProvider);

  // ------------------------------------------------------------ lifecycle --

  Future<void> start() => _load(_request);

  Future<void> _load(PlayRequest req) async {
    final gen = ++_generation;
    _cancelPrepare?.complete();
    _cancelPrepare = Completer<void>();
    if (req.localFile == null) {
      final local = await completedDownloadFile(
        _ref.read(databaseProvider),
        req.videoId,
      );
      if (local != null) req = req.copyWith(localFile: local);
    }
    if (gen != _generation || _disposed) return;
    _request = req;
    phase = PlayerPhase.preparing;
    status = req.localFile != null ? 'Opening' : 'Finding the best version';
    error = null;
    _tracksApplied = false;
    _pending = null;
    upNextDismissed = false;
    _prefetchedNext = false;
    _watchedHandled = false;
    subtitles = const [];
    activeSubtitleId = null;
    notifyListeners();
    unawaited(_loadMeta());
    await _configureMpv();
    try {
      final runtime = _runtimeMinutes();
      final src = await _ref
          .read(playbackServiceProvider)
          .prepare(
            req,
            runtimeMinutes: runtime,
            cancel: _cancelPrepare!.future,
            onStatus: (s) {
              if (gen != _generation) return;
              status = switch (s) {
                Resolving() => 'Finding the best version',
                FindingPeers(:final peers, :final seeds) =>
                  peers == 0
                      ? 'Looking for people sharing it'
                      : 'Connecting to $peers people ($seeds with the full file)',
                TryingNext() => 'Trying another version',
              };
              notifyListeners();
            },
          );
      if (gen != _generation || _disposed) {
        await _dropSource(src, keepIfComplete: false);
        return;
      }
      source = src;
      final start = req.startAt ?? await _savedPosition(req.videoId);
      status = 'Buffering';
      notifyListeners();
      await player.open(
        Media(src.uri.toString(), httpHeaders: src.headers, start: start),
      );
      if (gen != _generation || _disposed) return;
      phase = PlayerPhase.playing;
      _startTimers();
      notifyListeners();
      unawaited(_loadExternalSubtitles(gen));
    } on PlaybackException catch (e) {
      if (gen != _generation) return;
      phase = PlayerPhase.failed;
      error = e.message;
      notifyListeners();
    } on Object catch (e, st) {
      Log.e('player', 'prepare failed', e, st);
      if (gen != _generation) return;
      phase = PlayerPhase.failed;
      error = 'Playback couldn’t start. Choose another version or try again.';
      notifyListeners();
    }
  }

  Future<void> _configureMpv() async {
    final p = player.platform;
    if (p is! NativePlayer) return;
    final s = _settings;
    Future<void> set(String k, String v) async {
      try {
        await p.setProperty(k, v);
      } on Object catch (e) {
        Log.d('player', 'mpv $k: $e');
      }
    }

    await set('cache', 'yes');
    await set('cache-secs', '120');
    await set('demuxer-max-bytes', '${150 << 20}');
    await set('demuxer-max-back-bytes', '${48 << 20}');
    await set('demuxer-readahead-secs', '60');
    await set('network-timeout', '120');
    await set(
      'stream-lavf-o',
      'reconnect=1,reconnect_on_network_error=1,reconnect_delay_max=10',
    );
    await set('volume-max', '200');
    final audio = [
      for (final l in s.audioLanguages)
        if (l != 'original') ...mpvLangCodes(l),
    ];
    if (audio.isNotEmpty) await set('alang', audio.join(','));
    await set('sid', 'no'); // subtitles are chosen by Kinora, not mpv
  }

  int? _runtimeMinutes() => runtimeMinutes(meta?.runtime);

  Future<void> _loadMeta() async {
    if (_request.videoId.startsWith('magnet:') ||
        _request.videoId.startsWith('http'))
      return;
    try {
      meta = await _ref.read(
        metaProvider((type: _request.type, id: _request.mediaId)).future,
      );
      _computeNeighbours();
      notifyListeners();
    } on Object catch (e) {
      Log.d('player', 'meta unavailable: $e');
    }
  }

  /// Saved subtitles of a download (offline) plus provider results.
  Future<void> _loadExternalSubtitles(int gen) async {
    final req = _request;
    final saved = await savedDownloadSubtitles(
      _ref.read(databaseProvider),
      req.videoId,
    );
    if (gen != _generation || _disposed) return;
    if (saved.isNotEmpty) {
      addExternalSubtitles([
        for (final s in saved)
          SubtitleOption(
            id: 'saved:${s['path']}',
            language: normalizeLang(s['lang']),
            label: s['label'] ?? langName(s['lang']),
            uri: s['path'],
            detail: 'Saved with the download',
            fit: 0.95,
          ),
      ]);
    }
    if (req.videoId.startsWith('magnet:') || req.videoId.startsWith('http'))
      return;
    try {
      final options = await _ref
          .read(playerSubtitlesProvider)
          .optionsFor(
            VideoRef(
              type: req.type,
              mediaId: req.mediaId,
              videoId: req.videoId,
              season: req.season,
              episode: req.episode,
            ),
            releaseName: source?.release?.releaseName ?? source?.fileName,
          );
      if (gen != _generation || _disposed) return;
      addExternalSubtitles(options);
    } on Object catch (e) {
      Log.w('player', 'subtitles unavailable: $e');
    }
  }

  Future<void> _loadChapters() async {
    final p = player.platform;
    if (p is! NativePlayer) return;
    try {
      final count =
          int.tryParse(await p.getProperty('chapter-list/count')) ?? 0;
      final out = <({String title, Duration start})>[];
      for (var i = 0; i < count && i < 200; i++) {
        final title = await p.getProperty('chapter-list/$i/title');
        final time =
            double.tryParse(await p.getProperty('chapter-list/$i/time')) ?? 0;
        out.add((
          title: title,
          start: Duration(milliseconds: (time * 1000).round()),
        ));
      }
      chapters = out;
      notifyListeners();
    } on Object catch (e) {
      Log.d('player', 'chapters: $e');
    }
  }

  static final _skippable = RegExp(
    r'\b(intro|opening|op|recap|previously|cold open)\b',
    caseSensitive: false,
  );
  static final _credits = RegExp(
    r'\b(credits|ending|ed|outro|end titles)\b',
    caseSensitive: false,
  );

  /// The intro/recap chapter playing now and where it ends, if any.
  ({String label, Duration end})? get skippable {
    if (!_settings.skipIntros || chapters.length < 2) return null;
    final pos = player.state.position;
    for (var i = 0; i < chapters.length - 1; i++) {
      final ch = chapters[i];
      final end = chapters[i + 1].start;
      if (pos >= ch.start &&
          pos < end - const Duration(seconds: 2) &&
          _skippable.hasMatch(ch.title)) {
        final recap = RegExp(
          'recap|previously',
          caseSensitive: false,
        ).hasMatch(ch.title);
        return (label: recap ? 'Skip recap' : 'Skip intro', end: end);
      }
    }
    return null;
  }

  Future<void> skip() async {
    final s = skippable;
    if (s != null) await player.seek(s.end);
  }

  // ------------------------------------------------------------- episodes --

  /// Episodes in watching order (specials last).
  List<Episode> get episodes {
    final list = [
      ...?meta?.videos.where((v) => v.season != null && v.episode != null),
    ];
    list.sort((a, b) {
      final sa = a.season == 0 ? 1 << 20 : a.season!,
          sb = b.season == 0 ? 1 << 20 : b.season!;
      return sa != sb ? sa.compareTo(sb) : a.episode!.compareTo(b.episode!);
    });
    return list;
  }

  PlayRequest requestFor(Episode e) => _request
      .copyWith(
        videoId: e.id,
        season: e.season,
        episode: e.episode,
        episodeTitle: e.title,
        still: e.thumbnail,
        clearCandidate: true,
        clearLocal: true,
      )
      .withStart(null);

  void _computeNeighbours() {
    if (!_request.isEpisode) return;
    final list = episodes;
    final i = list.indexWhere((e) => e.id == _request.videoId);
    nextEpisode = i >= 0 && i + 1 < list.length
        ? requestFor(list[i + 1])
        : null;
    previousEpisode = i > 0 ? requestFor(list[i - 1]) : null;
  }

  /// Switches to another episode or version without leaving the player.
  Future<void> switchTo(PlayRequest next) async {
    await _saveProgress();
    _releasePrefetch();
    await _releaseSource();
    await player.stop();
    await _load(next);
    _computeNeighbours();
  }

  Future<void> playNext() async {
    final n = nextEpisode;
    if (n != null) await switchTo(n);
  }

  Future<void> playPrevious() async {
    final p = previousEpisode;
    if (p != null) await switchTo(p);
  }

  /// True in the last stretch of an episode, when Up Next shows.
  bool get inCredits {
    final d = player.state.duration;
    if (d == Duration.zero || nextEpisode == null) return false;
    final pos = player.state.position;
    final credits = chapters
        .where((c) => _credits.hasMatch(c.title))
        .lastOrNull;
    if (credits != null && credits.start > d * 0.7 && pos >= credits.start)
      return true;
    final window = Duration(
      seconds: (d.inSeconds * 0.04).clamp(25, 90).toInt(),
    );
    return d - pos <= window;
  }

  void _onPosition(Duration pos) {
    final d = player.state.duration;
    if (d == Duration.zero) return;
    if (!_prefetchedNext &&
        pos.inSeconds > d.inSeconds * 0.8 &&
        nextEpisode != null) {
      _prefetchedNext = true;
      unawaited(_prefetch(nextEpisode!));
      if (_settings.autoDownloadNext) {
        unawaited(_ref.read(downloadActionsProvider).download(nextEpisode!));
      }
    }
    if (!_watchedHandled &&
        pos.inMilliseconds >
            d.inMilliseconds * ProgressRepository.watchedFraction) {
      _watchedHandled = true;
      _watchedLocalFile = _request.localFile;
    }
  }

  /// Resolves the next episode and fetches its torrent metadata so Next
  /// starts in seconds.
  Future<void> _prefetch(PlayRequest next) async {
    try {
      final result = await _ref.read(
        resolveProvider(
          VideoRef(
            type: next.type,
            mediaId: next.mediaId,
            videoId: next.videoId,
            season: next.season,
            episode: next.episode,
            runtimeMinutes: _runtimeMinutes(),
          ),
        ).future,
      );
      final best = result.best?.stream;
      if (best?.infoHash == null || _disposed) return;
      final service = _ref.read(engineServiceProvider);
      final ih = service.add(
        infoHash: best!.infoHash!,
        name: best.filename,
        trackers: best.trackers.map((t) => t.toString()).toList(),
      );
      // Metadata and peers only: nothing downloads until Next is pressed.
      _releasePrefetch();
      _prefetched = (ih: ih, owner: 'prefetch:${next.videoId}');
      service.claim(ih, _prefetched!.owner, -1);
    } on Object catch (e) {
      Log.d('player', 'prefetch next failed: $e');
    }
  }

  ({String ih, String owner})? _prefetched;

  void _releasePrefetch() {
    final p = _prefetched;
    _prefetched = null;
    if (p == null) return;
    final service = _ref.read(engineServiceProvider);
    if (!service.release(p.ih, p.owner)) {
      Timer(
        const Duration(seconds: 30),
        () => service.removeIfUnclaimed(p.ih, deleteFiles: true),
      );
    }
  }

  Future<void> _onCompleted() async {
    await _saveProgress();
    if (nextEpisode != null && _settings.autoplayNext && !upNextDismissed) {
      await playNext();
    }
  }

  // --------------------------------------------------------------- tracks --

  Future<void> _onTracks() async {
    final tracks = player.state.tracks;
    final embedded = [
      for (final t in tracks.subtitle)
        if (t.id != 'auto' && t.id != 'no' && !t.uri && !t.data)
          SubtitleOption(
            id: 'emb:${t.id}',
            language: normalizeLang(t.language),
            label: _trackTitle(t.title, t.language),
            track: t,
            forced: (t.title ?? '').toLowerCase().contains('forced'),
            hearingImpaired: RegExp(
              r'\b(sdh|hi|cc)\b',
              caseSensitive: false,
            ).hasMatch(t.title ?? ''),
            detail: 'In the video file',
          ),
    ];
    final external = subtitles.where((s) => s.track == null);
    subtitles = [...embedded, ...external];
    notifyListeners();
    bool real(String id) => id != 'auto' && id != 'no';
    final hasTracks =
        tracks.audio.any((a) => real(a.id)) ||
        tracks.video.any((v) => real(v.id));
    if (_tracksApplied || !hasTracks) return;
    _tracksApplied = true;
    unawaited(_loadChapters());
    await _applyRemembered();
  }

  String _trackTitle(String? title, String? lang) {
    final name = langName(lang);
    final t = title?.trim();
    if (t == null || t.isEmpty || t.toLowerCase() == name.toLowerCase())
      return name;
    return '$name, $t';
  }

  /// Applies the episode's (or show's) remembered choice, else preferences.
  Future<void> _applyRemembered() async {
    final memory = _ref.read(trackMemoryProvider);
    final choice = await memory.resolve(
      mediaId: _request.mediaId,
      videoId: _request.videoId,
    );
    final s = _settings;
    final audios = player.state.tracks.audio
        .where((a) => a.id != 'auto' && a.id != 'no')
        .toList();

    AudioTrack? audio;
    if (choice?.audioTrackId != null) {
      audio = audios
          .where(
            (a) =>
                a.id == choice!.audioTrackId &&
                sameLang(a.language, choice.audioLanguage),
          )
          .firstOrNull;
    }
    audio ??= choice?.audioLanguage == null
        ? null
        : audios
              .where((a) => sameLang(a.language, choice!.audioLanguage))
              .firstOrNull;
    if (audio == null) {
      for (final l in s.audioLanguages) {
        if (l == 'original') break;
        audio = audios.where((a) => sameLang(a.language, l)).firstOrNull;
        if (audio != null) break;
      }
    }
    if (audio != null) await player.setAudioTrack(audio);

    final audioLang = normalizeLang(
      (audio ?? player.state.track.audio).language,
    );
    SubtitleOption? sub;
    if (choice != null && choice.subtitlesOff) {
      sub = null;
    } else if (choice?.subtitleLanguage != null) {
      sub = _bestSubtitle(
        choice!.subtitleLanguage!,
        variant: choice.subtitleVariant,
        id: choice.subtitleId,
      );
      // The exact remembered file may still be on its way (external
      // subtitles arrive after playback starts): wait for it even when a
      // fallback in the same language shows meanwhile.
      if (sub == null ||
          (choice.subtitleId != null && sub.id != choice.subtitleId)) {
        _pending = (
          lang: choice.subtitleLanguage!,
          variant: choice.subtitleVariant,
          id: choice.subtitleId,
        );
      }
    } else {
      sub = _subtitleFromPreferences(s, audioLang);
      final want = s.primaryLanguage;
      if (sub == null &&
          want != null &&
          s.subtitleMode != SubtitleMode.off &&
          !(s.subtitleMode == SubtitleMode.auto && sameLang(audioLang, want))) {
        _pending = (
          lang: want,
          variant: s.preferHearingImpaired ? 'sdh' : 'normal',
          id: null,
        );
      }
    }
    await _activate(sub, remember: false);
    if (choice != null && choice.subtitleOffsetMs != 0) {
      await setSubtitleDelay(
        Duration(milliseconds: choice.subtitleOffsetMs),
        remember: false,
      );
    }
  }

  SubtitleOption? _subtitleFromPreferences(AppSettings s, String? audioLang) {
    final primary = s.primaryLanguage;
    switch (s.subtitleMode) {
      case SubtitleMode.off:
        return null;
      case SubtitleMode.forcedOnly:
        return primary == null
            ? null
            : _bestSubtitle(primary, variant: 'forced', strictVariant: true);
      case SubtitleMode.auto:
        if (primary == null) return null;
        if (sameLang(audioLang, primary)) {
          return _bestSubtitle(primary, variant: 'forced', strictVariant: true);
        }
      case SubtitleMode.always:
    }
    for (final l in s.subtitleLanguages) {
      final pick = _bestSubtitle(
        l,
        variant: s.preferHearingImpaired ? 'sdh' : 'normal',
      );
      if (pick != null) return pick;
    }
    return null;
  }

  /// Best option in [lang]: exact id, then variant, embedded before
  /// external at equal fit, then highest fit.
  SubtitleOption? _bestSubtitle(
    String lang, {
    String? variant,
    String? id,
    bool strictVariant = false,
  }) {
    final inLang = subtitles.where((o) => sameLang(o.language, lang)).toList();
    if (inLang.isEmpty) return null;
    if (id != null) {
      final exact = inLang.where((o) => o.id == id).firstOrNull;
      if (exact != null) return exact;
    }
    final wanted = variant ?? 'normal';
    final sameVariant = inLang.where((o) => o.variant == wanted).toList();
    if (strictVariant && sameVariant.isEmpty) return null;
    final pool = sameVariant.isNotEmpty
        ? sameVariant
        : inLang.where((o) => !o.forced).toList();
    if (pool.isEmpty) return null;
    pool.sort((a, b) {
      final fa = a.track != null ? 0.9 : (a.fit ?? 0.5),
          fb = b.track != null ? 0.9 : (b.fit ?? 0.5);
      return fb.compareTo(fa);
    });
    return pool.first;
  }

  /// A wanted subtitle language that wasn't available yet (external
  /// subtitles arrive after the video starts).
  ({String lang, String? variant, String? id})? _pending;

  /// Adds external subtitles (from providers) to the list, and turns on the
  /// remembered/preferred language if it just became available.
  void addExternalSubtitles(List<SubtitleOption> options) {
    final ids = {for (final s in subtitles) s.id};
    subtitles = [...subtitles, ...options.where((o) => ids.add(o.id))];
    notifyListeners();
    final want = _pending;
    if (want == null) return;
    final exact = want.id == null
        ? null
        : subtitles.where((o) => o.id == want.id).firstOrNull;
    if (exact != null) {
      _pending = null;
      unawaited(_activate(exact, remember: false));
    } else if (activeSubtitleId == null) {
      final pick = _bestSubtitle(want.lang, variant: want.variant, id: want.id);
      if (pick != null && want.id == null) _pending = null;
      if (pick != null) unawaited(_activate(pick, remember: false));
    }
  }

  final _loaded = <String, String>{};

  /// A text subtitle file for the TV: the active external one, or the best
  /// external one in the active embedded track's language (TVs can't read
  /// subtitles inside the video stream we serve).
  Future<({String path, String? language})?> subtitleForTv() async {
    final active = subtitles.where((s) => s.id == activeSubtitleId).firstOrNull;
    if (active == null) return null;
    final option = active.track == null
        ? active
        : subtitles
              .where(
                (s) => s.track == null && sameLang(s.language, active.language),
              )
              .fold<SubtitleOption?>(
                null,
                (best, s) =>
                    best == null || (s.fit ?? 0) > (best.fit ?? 0) ? s : best,
              );
    if (option == null) return null;
    final path = option.uri ?? _loaded[option.id] ?? await option.load?.call();
    if (path == null) return null;
    _loaded[option.id] = path;
    return (path: path, language: option.language);
  }

  /// A short message for the viewer (shown briefly by the screen).
  String? notice;

  Future<void> selectSubtitle(SubtitleOption? option) {
    _pending = null;
    return _activate(option, remember: true);
  }

  Future<void> _activate(
    SubtitleOption? option, {
    required bool remember,
  }) async {
    activeSubtitleId = option?.id;
    notifyListeners();
    if (option == null) {
      await player.setSubtitleTrack(SubtitleTrack.no());
    } else if (option.track != null) {
      await player.setSubtitleTrack(option.track!);
    } else {
      final path =
          option.uri ?? _loaded[option.id] ?? await option.load?.call();
      if (path == null) {
        activeSubtitleId = null;
        notice = 'That subtitle couldn’t be loaded. Pick another one.';
        notifyListeners();
        return;
      }
      _loaded[option.id] = path;
      await player.setSubtitleTrack(
        SubtitleTrack.uri(path, title: option.label, language: option.language),
      );
    }
    if (remember) await _remember();
  }

  Future<void> selectAudio(AudioTrack track) async {
    await player.setAudioTrack(track);
    notifyListeners();
    await _remember();
  }

  Future<void> setSubtitleDelay(Duration delay, {bool remember = true}) async {
    subtitleDelay = delay;
    notifyListeners();
    final p = player.platform;
    if (p is NativePlayer) {
      await p.setProperty(
        'sub-delay',
        (delay.inMilliseconds / 1000).toStringAsFixed(3),
      );
    }
    if (remember) await _remember();
  }

  Future<void> _remember() async {
    final active = subtitles.where((s) => s.id == activeSubtitleId).firstOrNull;
    final pending = active == null ? _pending : null;
    final audio = player.state.track.audio;
    await _ref
        .read(trackMemoryProvider)
        .remember(
          mediaId: _request.mediaId,
          videoId: _request.videoId,
          choice: TrackChoice(
            audioLanguage: normalizeLang(audio.language),
            audioTrackId: audio.id == 'auto' ? null : audio.id,
            subtitleLanguage: active?.language ?? pending?.lang,
            subtitleVariant: active?.variant ?? pending?.variant ?? 'off',
            subtitleId: active?.id ?? pending?.id,
            subtitleOffsetMs: subtitleDelay.inMilliseconds,
          ),
        );
  }

  // ------------------------------------------------------------ controls --

  Future<void> setRate(double value) async {
    rate = value;
    await player.setRate(value);
    notifyListeners();
  }

  Future<void> toggleNightMode() async {
    nightMode = !nightMode;
    final p = player.platform;
    if (p is NativePlayer) {
      await p.setProperty(
        'af',
        nightMode ? 'lavfi=[dynaudnorm=f=250:g=15:p=0.9]' : '',
      );
    }
    notifyListeners();
  }

  Future<void> seekRelative(Duration delta) async {
    final d = player.state.duration;
    var target = player.state.position + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (d > Duration.zero && target > d)
      target = d - const Duration(seconds: 1);
    await player.seek(target);
  }

  Future<void> retry() => _load(_request.copyWith(clearCandidate: true));

  // -------------------------------------------------------------- engine --

  /// Buffer numbers for torrent streams (null otherwise).
  ({int bufferedAhead, int have, int size, int peers, int rate})? engineStats;

  void _startTimers() {
    _saveTimer?.cancel();
    _saveTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => unawaited(_saveProgress()),
    );
    _statusTimer?.cancel();
    final src = source;
    if (src?.kind != PlaybackKind.torrent) {
      engineStats = null;
      return;
    }
    _statusTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final engine = _ref.read(engineServiceProvider).engine;
      final stats = engine.streamStats(src!.streamToken!);
      final st = engine.status(src.infoHash!);
      if (stats == null) return;
      final rate = st?.downloadRate ?? 0;
      if (rate > 0 && stats.haveBytes < stats.size) {
        _bandwidth = _bandwidth == null
            ? rate.toDouble()
            : _bandwidth! * 0.85 + rate * 0.15;
        _ref.read(bandwidthEstimateProvider.notifier).set(_bandwidth);
      }
      engineStats = (
        bufferedAhead: stats.bufferedAhead,
        have: stats.haveBytes,
        size: stats.size,
        peers: st?.numPeers ?? 0,
        rate: st?.downloadRate ?? 0,
      );
      notifyListeners();
    });
  }

  Future<Duration?> _savedPosition(String videoId) async {
    final row = await _ref.read(progressRepositoryProvider).get(videoId);
    if (row == null || row.completed) return null;
    final pos = Duration(milliseconds: row.positionMs);
    return pos > const Duration(seconds: 20)
        ? pos - const Duration(seconds: 3)
        : null;
  }

  Future<void> _saveProgress() async {
    final cast = _ref.read(castServiceProvider);
    final casting = cast.isCasting && cast.duration > Duration.zero;
    final d = casting ? cast.duration : player.state.duration;
    final pos = casting ? cast.position : player.state.position;
    if (d == Duration.zero || pos < const Duration(seconds: 5)) return;
    if (_request.videoId.startsWith('magnet:') ||
        _request.videoId.startsWith('http'))
      return;
    await _ref
        .read(progressRepositoryProvider)
        .save(
          videoId: _request.videoId,
          mediaId: _request.mediaId,
          type: _request.type,
          name: _request.title,
          episodeTitle: _request.episodeTitle,
          season: _request.season,
          episode: _request.episode,
          position: pos,
          duration: d,
          poster: _request.poster,
          still: _request.still ?? _request.background,
        );
  }

  /// Ends a torrent stream: complete files are kept for Downloads (when the
  /// setting allows), unfinished data is deleted or kept per settings.
  Future<void> _releaseSource() async {
    final watched = _watchedLocalFile;
    _watchedLocalFile = null;
    if (watched != null && _settings.deleteWatchedDownloads) {
      final db = _ref.read(databaseProvider);
      final rows = await (db.select(
        db.downloads,
      )..where((t) => t.filePath.equals(watched))).get();
      for (final row in rows) {
        await _ref.read(downloadActionsProvider).remove(row.id);
      }
    }
    final src = source;
    source = null;
    _statusTimer?.cancel();
    if (src != null) await _dropSource(src, keepIfComplete: true);
  }

  /// Ends a source: closes its stream and releases its claim. A complete
  /// file is kept as a download (setting); otherwise the torrent goes after
  /// 30 s unless someone else claims it (the next episode of a pack).
  Future<void> _dropSource(
    PlaybackSource src, {
    required bool keepIfComplete,
  }) async {
    if (src.kind != PlaybackKind.torrent) return;
    final service = _ref.read(engineServiceProvider);
    final ih = src.infoHash!;
    try {
      service.engine.closeStream(src.streamToken!);
    } on Object {
      // Already gone.
    }
    final complete = () {
      final fp = service.engine.fileProgress(ih);
      final i = src.fileIndex;
      return fp != null &&
          i != null &&
          i < fp.length &&
          src.sizeBytes != null &&
          fp[i] >= src.sizeBytes!;
    }();
    if (keepIfComplete && complete && _settings.keepCompletedStreams) {
      // Runs in the background: moving a big file must not hold up Next.
      unawaited(
        _ref.read(completedStreamHandlerProvider)(src, _request).whenComplete(
          () {
            if (src.owner != null) service.release(ih, src.owner!);
          },
        ),
      );
      return;
    }
    if (src.owner != null) service.release(ih, src.owner!);
    final keep = _settings.keepStreamsHours > 0;
    Timer(const Duration(seconds: 30), () async {
      if (service.isClaimed(ih)) return;
      // A download of the same torrent may have started meanwhile.
      final db = _ref.read(databaseProvider);
      final owned = await (db.select(
        db.downloads,
      )..where((t) => t.infoHash.equals(ih))).get();
      if (owned.isNotEmpty || service.isClaimed(ih)) return;
      if (keep) {
        try {
          service.engine.pause(ih);
        } on Object {
          // Gone already.
        }
      } else {
        service.removeIfUnclaimed(ih, deleteFiles: true);
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelPrepare?.complete();
    _saveTimer?.cancel();
    _statusTimer?.cancel();
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    unawaited(() async {
      await _saveProgress();
      _releasePrefetch();
      await _releaseSource();
      await player.dispose();
    }());
    super.dispose();
  }
}

extension on PlayRequest {
  PlayRequest withStart(Duration? start) => PlayRequest(
    type: type,
    mediaId: mediaId,
    videoId: videoId,
    title: title,
    episodeTitle: episodeTitle,
    season: season,
    episode: episode,
    poster: poster,
    background: background,
    logo: logo,
    still: still,
    startAt: start,
    candidateId: candidateId,
    localFile: localFile,
  );
}

/// Called when a stream finished downloading completely. The downloads
/// service overrides this to move it into Downloads.
final completedStreamHandlerProvider =
    Provider<Future<void> Function(PlaybackSource, PlayRequest)>(
      (ref) => (source, request) async {},
    );
