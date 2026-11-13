import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/desktop.dart';
import '../../services/trakt.dart';
import '../../ui/glass.dart';
import '../../ui/tint.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/media.dart';
import '../../ui/widgets/sheet.dart';
import '../settings/widgets/settings_ui.dart';

/// "Synced 3 min ago".
String syncedAgo(DateTime at, DateTime now) {
  final d = now.difference(at);
  if (d.inMinutes < 1) return 'Synced just now';
  if (d.inMinutes < 60) return 'Synced ${d.inMinutes} min ago';
  if (d.inHours < 24) return 'Synced ${d.inHours} h ago';
  return 'Synced ${d.inDays} d ago';
}

/// "Brought in 120 watched, 3 to resume and 12 for My List", or null.
String? broughtIn(({int watched, int resume, int listed})? b) {
  if (b == null) return null;
  final parts = [
    if (b.watched > 0) '${b.watched} watched',
    if (b.resume > 0) '${b.resume} to resume',
    if (b.listed > 0) '${b.listed} for My List',
  ];
  if (parts.isEmpty) return null;
  final list = parts.length == 1
      ? parts.first
      : '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
  return 'Brought in $list.';
}

/// Trakt in one place: sign in with a code, then who you are, when it last
/// synced and what it brought in. On Home's sheet, in onboarding and in
/// Settings.
class TraktAccountPanel extends ConsumerStatefulWidget {
  const TraktAccountPanel({super.key, this.intro = true});

  /// The line explaining Trakt (off where the page says it already).
  final bool intro;

  @override
  ConsumerState<TraktAccountPanel> createState() => _TraktAccountPanelState();
}

class _TraktAccountPanelState extends ConsumerState<TraktAccountPanel> {
  TraktCode? _code;
  bool _waitingForCode = false;
  String? _problem;
  bool _gone = false;

  @override
  void dispose() {
    _gone = true;
    super.dispose();
  }

  Future<void> _signIn() async {
    final trakt = ref.read(traktSyncProvider);
    setState(() {
      _waitingForCode = true;
      _problem = null;
    });
    final TraktCode code;
    try {
      code = await trakt.startSignIn();
    } on Object {
      if (mounted) {
        setState(() {
          _waitingForCode = false;
          _problem =
              'Couldn’t reach Trakt. Check your connection, then try again.';
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _waitingForCode = false;
      _code = code;
    });
    final result = await trakt.finishSignIn(
      code,
      cancelled: () => _gone || _code != code,
    );
    if (_gone || !mounted || _code != code) return;
    setState(() {
      _code = null;
      _problem = switch (result) {
        TraktSignIn.approved => null,
        TraktSignIn.denied => 'The code was declined on trakt.tv.',
        TraktSignIn.expired => 'The code ran out. Get a new one.',
        TraktSignIn.failed =>
          'Trakt didn’t sign you in. Try again in a moment.',
      };
    });
    // The first sync: both ways. The panel shows it, then what came in.
    if (result == TraktSignIn.approved) unawaited(trakt.syncNow());
  }

  @override
  Widget build(BuildContext context) {
    final trakt = ref.watch(traktSyncProvider);
    return ListenableBuilder(
      listenable: trakt,
      builder: (context, _) {
        final code = _code;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!trakt.available)
              const Note('This version of Kinora was built without Trakt.')
            else if (trakt.signedIn)
              _SignedIn(trakt: trakt)
            else if (code != null)
              _Code(code: code, onCancel: () => setState(() => _code = null))
            else ...[
              if (widget.intro)
                const Note(
                  'Bring in what you’ve watched, where you stopped and your '
                  'watchlist, and keep them the same on your other devices and '
                  'in apps like Stremio and Kodi.',
                ),
              if (_problem case final problem?)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    KSpace.margin,
                    KSpace.x2,
                    KSpace.margin,
                    0,
                  ),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      problem,
                      style: KType.body.copyWith(color: KColors.cut),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(KSpace.margin),
                child: GlassButton(
                  label: _waitingForCode
                      ? 'Getting a code…'
                      : _problem == null
                      ? 'Sign in with Trakt'
                      : 'Get a new code',
                  icon: Icons.login_rounded,
                  prominent: true,
                  onPressed: _waitingForCode
                      ? null
                      : () => unawaited(_signIn()),
                ),
              ),
              const Note(
                'You’ll get a code to enter at trakt.tv. Kinora never sees '
                'your password, and works the same without Trakt.',
              ),
            ],
            if (trakt.note case final note? when trakt.signedIn || code == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  KSpace.margin,
                  KSpace.x3,
                  KSpace.margin,
                  0,
                ),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    note,
                    style: KType.label.copyWith(color: KColors.caution),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The code to type at trakt.tv, and the wait for it.
class _Code extends StatelessWidget {
  const _Code({required this.code, required this.onCancel});

  final TraktCode code;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final url = Uri.parse(code.url);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KSpace.margin),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'On any device, go to ${url.host}${url.path} and enter this code:',
            style: KType.body.copyWith(color: KColors.haze),
          ),
          const SizedBox(height: KSpace.x4),
          Semantics(
            label: 'Code ${code.userCode.split('').join(' ')}',
            excludeSemantics: true,
            child: SelectableText(
              code.userCode,
              textAlign: TextAlign.center,
              style: KType.hero.copyWith(letterSpacing: 6),
            ),
          ),
          const SizedBox(height: KSpace.x4),
          Wrap(
            spacing: KSpace.x2,
            runSpacing: KSpace.x2,
            alignment: WrapAlignment.center,
            children: [
              GlassButton(
                label: 'Open trakt.tv',
                icon: Icons.open_in_new_rounded,
                prominent: true,
                onPressed: () => unawaited(
                  launchUrl(url, mode: LaunchMode.externalApplication),
                ),
              ),
              GlassButton(
                label: 'Copy code',
                icon: Icons.copy_rounded,
                onPressed: () {
                  unawaited(
                    Clipboard.setData(ClipboardData(text: code.userCode)),
                  );
                  showNote(context, 'Code copied.');
                },
              ),
            ],
          ),
          const SizedBox(height: KSpace.x4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: KSpace.x2),
              Flexible(
                child: Text(
                  'Waiting for you to approve it…',
                  style: KType.label.copyWith(color: KColors.haze),
                ),
              ),
            ],
          ),
          Center(
            child: TextButton(onPressed: onCancel, child: const Text('Cancel')),
          ),
        ],
      ),
    );
  }
}

/// Who's signed in, the last sync and what it brought, Sync now, Sign out.
class _SignedIn extends StatelessWidget {
  const _SignedIn({required this.trakt});

  final TraktSync trakt;

  @override
  Widget build(BuildContext context) {
    final user = trakt.user ?? '';
    final status = trakt.syncing
        ? (trakt.lastSync == null
              ? 'Bringing in what you’ve watched…'
              : 'Syncing…')
        : trakt.lastSync == null
        ? 'Not synced yet'
        : syncedAgo(trakt.lastSync!, DateTime.now());
    final brought = trakt.syncing ? null : broughtIn(trakt.brought);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            KSpace.margin,
            KSpace.x2,
            KSpace.margin,
            KSpace.x2,
          ),
          child: Row(
            children: [
              TraktAvatar(user: user, syncing: trakt.syncing, size: 48),
              const SizedBox(width: KSpace.x3),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Signed in as $user', style: KType.title),
                      Text(
                        [status, ?brought].join('. '),
                        style: KType.label.copyWith(color: KColors.haze),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        ActionRow(
          icon: Icons.sync_rounded,
          label: 'Sync now',
          onTap: trakt.syncing ? null : () => unawaited(trakt.syncNow()),
        ),
        ActionRow(
          icon: Icons.logout_rounded,
          label: 'Sign out',
          detail: 'What you watched stays on $thisDevice and on Trakt.',
          color: KColors.cut,
          onTap: () async {
            final ok = await confirmAction(
              context,
              title: 'Sign out of Trakt?',
              message:
                  'Kinora stops syncing. What you watched stays on $thisDevice '
                  'and on Trakt.',
              action: 'Sign out',
            );
            if (ok) await trakt.signOut();
          },
        ),
      ],
    );
  }
}

/// The signed-in user's initial in the accent, ringed while syncing.
class TraktAvatar extends StatelessWidget {
  const TraktAvatar({
    super.key,
    required this.user,
    required this.syncing,
    this.size = 44,
  });

  final String user;
  final bool syncing;
  final double size;

  @override
  Widget build(BuildContext context) {
    final accent = KinoraTint.of(context);
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: 0.22),
              border: Border.all(color: accent.withValues(alpha: 0.6)),
            ),
            child: SizedBox.square(
              dimension: size - 6,
              child: Center(
                child: Text(
                  user.isEmpty ? '·' : user.characters.first.toUpperCase(),
                  style: KType.title.copyWith(
                    color: KColors.lamp,
                    fontSize: size * 0.4,
                  ),
                ),
              ),
            ),
          ),
          if (syncing)
            SizedBox.square(
              dimension: size,
              child: CircularProgressIndicator(strokeWidth: 2, color: accent),
            ),
        ],
      ),
    );
  }
}

/// Trakt on its own sheet (from Home).
Future<void> showTraktSheet(BuildContext context) => showGlassSheet<void>(
  context,
  builder: (_) => SingleChildScrollView(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            KSpace.margin,
            KSpace.x2,
            KSpace.margin,
            KSpace.x1,
          ),
          child: Semantics(header: true, child: Text('Trakt', style: KType.h2)),
        ),
        const TraktAccountPanel(),
        const SizedBox(height: KSpace.margin),
      ],
    ),
  ),
);

/// Home's Trakt button, beside Cast: sign in, or your initial when signed
/// in (ringed while syncing). Opens the Trakt sheet.
class TraktButton extends ConsumerWidget {
  const TraktButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trakt = ref.watch(traktSyncProvider);
    return ListenableBuilder(
      listenable: trakt,
      builder: (context, _) {
        if (!trakt.available) return const SizedBox.shrink();
        void open() => unawaited(showTraktSheet(context));
        if (!trakt.signedIn) {
          return GlassIconButton(
            icon: Icons.person_add_alt_rounded,
            label: 'Sign in with Trakt',
            onPressed: open,
          );
        }
        return Pressable(
          label: 'Trakt, signed in as ${trakt.user}',
          hint: trakt.syncing ? 'Syncing' : null,
          onTap: open,
          child: Glass(
            radius: 999,
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: TraktAvatar(
                user: trakt.user ?? '',
                syncing: trakt.syncing,
                size: 44,
              ),
            ),
          ),
        );
      },
    );
  }
}
