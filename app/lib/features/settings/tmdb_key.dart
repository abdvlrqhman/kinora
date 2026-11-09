import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/secure_keys.dart';
import '../../services/tmdb.dart';
import '../../ui/glass.dart';
import '../../ui/tokens.dart';
import 'widgets/settings_ui.dart';

/// Settings › Sources › Cast photos and trailers: the user's own TMDB key, checked
/// before it's saved. None by default.
class TmdbKeySection extends ConsumerStatefulWidget {
  const TmdbKeySection({super.key});

  @override
  ConsumerState<TmdbKeySection> createState() => _TmdbKeySectionState();
}

class _TmdbKeySectionState extends ConsumerState<TmdbKeySection> {
  final _key = TextEditingController();
  bool _checking = false;
  String? _error;

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final key = _key.text.trim();
    if (key.isEmpty) {
      setState(() => _error = 'Paste your TMDB key first.');
      return;
    }
    setState(() {
      _checking = true;
      _error = null;
    });
    String? error;
    try {
      await TmdbClient(key, ref.read(httpClientProvider)).verify();
    } on TmdbKeyRejected {
      error = 'TMDB didn’t accept this key. Check it, then try again.';
    } on Object {
      error = 'Couldn’t reach TMDB. Check your connection, then try again.';
    }
    if (error == null) {
      try {
        await ref
            .read(secureKeysProvider)
            .write(tmdbKeyId, ProviderCredentials(apiKey: key));
        ref.invalidate(tmdbKeyProvider);
        _key.clear();
      } on Object {
        error = 'Kinora couldn’t save the key on this phone. Try again.';
      }
    }
    if (!mounted) return;
    setState(() {
      _checking = false;
      _error = error;
    });
    if (error == null) showNote(context, 'TMDB is on.');
  }

  Future<void> _remove() async {
    await ref.read(secureKeysProvider).delete(tmdbKeyId);
    ref.invalidate(tmdbKeyProvider);
    if (mounted) showNote(context, 'TMDB key removed.');
  }

  @override
  Widget build(BuildContext context) {
    final on = ref.watch(tmdbKeyProvider).value != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('Cast photos and trailers'),
        Note(
          on
              ? 'TMDB adds cast photos, trailers, More like this, age '
                    'ratings and missing artwork. Your key is saved on this '
                    'phone.'
              : 'Add your free TMDB key for cast photos, trailers, More like '
                    'this, age ratings and missing artwork. Get one at '
                    'themoviedb.org › Settings › API (the API key or the '
                    'read token both work).',
        ),
        if (!on)
          GlassField(
            controller: _key,
            label: 'Your TMDB key',
            obscure: true,
            paste: true,
            onSubmitted: (_) => unawaited(_save()),
            fieldKey: const ValueKey('tmdb-key'),
          ),
        if (_error != null)
          Semantics(liveRegion: true, child: Note(_error!, color: KColors.cut)),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            KSpace.margin,
            KSpace.x1,
            KSpace.margin,
            KSpace.x3,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: GlassGroup(
              child: on
                  ? GlassButton(
                      label: 'Remove key',
                      onPressed: () => unawaited(_remove()),
                    )
                  : GlassButton(
                      label: _checking ? 'Checking…' : 'Save key',
                      prominent: true,
                      onPressed: _checking ? null : () => unawaited(_save()),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}
