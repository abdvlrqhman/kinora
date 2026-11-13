import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:subtitles/subtitles.dart';

import '../../app/desktop.dart';
import '../../app/providers.dart';
import '../../core/secure_keys.dart';
import '../../services/subtitles_service.dart';
import '../../ui/glass.dart';
import '../../ui/tokens.dart';
import 'widgets/settings_ui.dart';

/// Settings › Subtitle sites.
class SubtitleSitesPage extends StatelessWidget {
  const SubtitleSitesPage({super.key});

  @override
  Widget build(BuildContext context) => SettingsPage(
    title: 'Subtitle sites',
    intro: subtitleSitesIntro,
    children: const [SubtitleSiteList(showTest: true)],
  );
}

String get subtitleSitesIntro =>
    'Turn on the sites you use and add your own key. Kinora ships no keys, '
    'and yours stay on $thisDevice.';

/// Every site in [subtitleProviderCatalog], each with its switch.
class SubtitleSiteList extends StatelessWidget {
  const SubtitleSiteList({super.key, this.showTest = false});

  final bool showTest;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final info in subtitleProviderCatalog)
        SubtitleSiteTile(info: info, showTest: showTest),
    ],
  );
}

/// What a subtitle site said, in words.
String subtitleErrorText(SubtitleException? e, String site) => switch (e) {
  SubtitleAuthException() =>
    '$site didn’t accept your key. Check it, then save it again.',
  SubtitleRateLimitException() =>
    '$site is limiting requests right now. Try again in a minute.',
  SubtitleQuotaException() =>
    'Your daily limit on $site is used up. Try again after it renews.',
  SubtitleNetworkException(isTimeout: true) =>
    '$site took too long to answer. Try again.',
  SubtitleNetworkException() => 'Couldn’t reach $site. Check your connection.',
  SubtitleHttpException(:final statusCode) =>
    '$site answered with error $statusCode. Try again later.',
  SubtitleResponseException() ||
  SubtitleFormatException() ||
  SubtitleArchiveException() =>
    '$site sent something Kinora can’t read. Try again later.',
  SubtitleCancelledException() => 'The test was cancelled.',
  null => '$site didn’t answer. Try again.',
};

/// The known titles a test searches for.
const _testMovie = SubtitleQuery(
  type: MediaType.movie,
  imdbId: 'tt0111161',
  tmdbId: 278,
  title: 'The Shawshank Redemption',
  year: 1994,
);
const _testAnime = SubtitleQuery(
  type: MediaType.episode,
  tmdbId: 30991,
  title: 'Cowboy Bebop',
  season: 1,
  episode: 1,
);

/// Runs one search on [provider] for a known title. Returns (ok, words).
Future<(bool, String)> testSubtitleSite(
  SubtitleProvider provider,
  ProviderInfo info,
) async {
  final anime = info.id == 'jimaku';
  final base = anime ? _testAnime : _testMovie;
  final query = SubtitleQuery(
    type: base.type,
    imdbId: base.imdbId,
    tmdbId: base.tmdbId,
    title: base.title,
    year: base.year,
    season: base.season,
    episode: base.episode,
    languages: [Language.of(anime ? 'ja' : 'en')],
  );
  final update = await SubtitleSearch(
    providers: [provider],
    providerTimeout: const Duration(seconds: 15),
  ).searchAll(query);
  final status = update.providers[provider.id];
  if (status?.state == ProviderState.done) {
    final n = status!.count;
    return (
      true,
      n == 0
          ? 'Connected. It found no subtitles for ${base.title}, but your '
                'key works.'
          : 'Working. Found $n subtitle${n == 1 ? '' : 's'} for '
                '${base.title}.',
    );
  }
  return (false, subtitleErrorText(status?.error, info.name));
}

/// One site: a switch, and a key form when it needs one. The switch only
/// turns on once a key is saved. Turning it off forgets the key.
class SubtitleSiteTile extends ConsumerStatefulWidget {
  const SubtitleSiteTile({
    super.key,
    required this.info,
    this.showTest = false,
  });

  final ProviderInfo info;
  final bool showTest;

  @override
  ConsumerState<SubtitleSiteTile> createState() => _SubtitleSiteTileState();
}

class _SubtitleSiteTileState extends ConsumerState<SubtitleSiteTile> {
  final _key = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _editing = false;
  bool _testing = false;
  String? _error;
  (bool, String)? _result;

  ProviderInfo get info => widget.info;

  @override
  void dispose() {
    _key.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _setEnabled(bool on) => ref
      .read(settingsProvider.notifier)
      .update(
        (s) => s.copyWith(
          enabledSubtitleProviders: [
            ...s.enabledSubtitleProviders.where((id) => id != info.id),
            if (on) info.id,
          ],
        ),
      );

  Future<void> _toggle(bool on) async {
    if (on && info.needsKey) {
      setState(() {
        _editing = true;
        _error = null;
      });
      return;
    }
    if (!on) {
      setState(() {
        _editing = false;
        _result = null;
      });
      await ref.read(secureKeysProvider).delete(info.id);
    }
    await _setEnabled(on);
  }

  Future<void> _save() async {
    final key = _key.text.trim();
    final user = _user.text.trim();
    final pass = _pass.text;
    final error = key.isEmpty
        ? 'Enter your ${info.keyLabel} to turn on ${info.name}.'
        : info.supportsLogin && (user.isEmpty != pass.isEmpty)
        ? 'Enter both your username and password, or leave both empty.'
        : null;
    setState(() => _error = error);
    if (error != null) return;
    await ref
        .read(secureKeysProvider)
        .write(
          info.id,
          ProviderCredentials(apiKey: key, username: user, password: pass),
        );
    await _setEnabled(true);
    _key.clear();
    _user.clear();
    _pass.clear();
    if (mounted) setState(() => _editing = false);
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _result = null;
    });
    (bool, String) result;
    try {
      final providers = await ref.read(subtitleProvidersProvider.future);
      final p = providers.where((p) => p.id == info.id).firstOrNull;
      result = p == null
          ? (false, 'Save your key first, then test.')
          : await testSubtitleSite(p, info);
    } on Object {
      result = (false, '${info.name} couldn’t be tested. Try again.');
    }
    if (mounted) {
      setState(() {
        _testing = false;
        _result = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(
      settingsProvider.select(
        (s) => s.enabledSubtitleProviders.contains(info.id),
      ),
    );
    final detail = enabled && info.needsKey
        ? '${info.description} Your key is saved on $thisDevice.'
        : info.description;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchRow(
          label: info.name,
          detail: detail,
          value: enabled || _editing,
          onChanged: (v) => unawaited(_toggle(v)),
        ),
        AnimatedSize(
          duration: reduceMotion(context) ? Duration.zero : KMotion.base,
          curve: KMotion.curve,
          alignment: Alignment.topCenter,
          child: _editing ? _form() : const SizedBox(width: double.infinity),
        ),
        if (widget.showTest && enabled && !_editing) _testRow(),
      ],
    );
  }

  Widget _form() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (info.keyHelp != null)
        Note('Get your ${info.keyLabel} at ${info.keyHelp}.'),
      GlassField(
        controller: _key,
        label: info.keyLabel,
        obscure: true,
        paste: true,
        fieldKey: ValueKey('key-${info.id}'),
      ),
      if (info.supportsLogin) ...[
        GlassField(
          controller: _user,
          label: 'Username (optional)',
          fieldKey: ValueKey('user-${info.id}'),
        ),
        GlassField(
          controller: _pass,
          label: 'Password (optional)',
          obscure: true,
          fieldKey: ValueKey('pass-${info.id}'),
        ),
        const Note('Signing in raises your daily download limit.'),
      ],
      if (_error != null)
        Semantics(liveRegion: true, child: Note(_error!, color: KColors.cut)),
      Padding(
        padding: const EdgeInsets.fromLTRB(
          KSpace.margin,
          KSpace.x1,
          KSpace.margin,
          KSpace.x3,
        ),
        child: GlassGroup(
          child: Wrap(
            spacing: KSpace.x2,
            runSpacing: KSpace.x2,
            children: [
              GlassButton(
                label: 'Save and turn on',
                prominent: true,
                semanticLabel: 'Save key and turn on ${info.name}',
                onPressed: () => unawaited(_save()),
              ),
              GlassButton(
                label: 'Cancel',
                onPressed: () => setState(() {
                  _editing = false;
                  _error = null;
                }),
              ),
            ],
          ),
        ),
      ),
    ],
  );

  Widget _testRow() => Padding(
    padding: const EdgeInsets.fromLTRB(
      KSpace.margin,
      0,
      KSpace.margin,
      KSpace.x3,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GlassGroup(
          child: GlassButton(
            label: _testing ? 'Testing' : 'Test',
            icon: Icons.play_circle_outline_rounded,
            semanticLabel: 'Test ${info.name}',
            onPressed: _testing ? null : () => unawaited(_test()),
          ),
        ),
        if (_result case (final ok, final text)) ...[
          const SizedBox(height: KSpace.x2),
          Semantics(
            liveRegion: true,
            child: Text(
              text,
              style: KType.label.copyWith(color: ok ? KColors.go : KColors.cut),
            ),
          ),
        ],
      ],
    ),
  );
}
