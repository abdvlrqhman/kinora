import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/trakt.dart';
import '../../ui/glass.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/sheet.dart';
import 'widgets/settings_ui.dart';

/// "Synced 3 min ago".
String syncedAgo(DateTime at, DateTime now) {
  final d = now.difference(at);
  if (d.inMinutes < 1) return 'Synced just now';
  if (d.inMinutes < 60) return 'Synced ${d.inMinutes} min ago';
  if (d.inHours < 24) return 'Synced ${d.inHours} h ago';
  return 'Synced ${d.inDays} d ago';
}

/// Settings › Trakt: sign in to keep what you watch in step everywhere.
class TraktPage extends ConsumerWidget {
  const TraktPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trakt = ref.watch(traktSyncProvider);
    return ListenableBuilder(
      listenable: trakt,
      builder: (context, _) => SettingsPage(
        title: 'Trakt',
        children: [
          const Note(
            'Keeps what you’ve watched, where you stopped and My List the '
            'same on your other devices, and in apps like Stremio and Kodi. '
            'Optional: Kinora works the same without it.',
          ),
          if (!trakt.available)
            const Note('This version of Kinora was built without Trakt.')
          else if (!trakt.signedIn) ...[
            Padding(
              padding: const EdgeInsets.all(KSpace.margin),
              child: GlassButton(
                label: 'Sign in with Trakt',
                icon: Icons.login_rounded,
                prominent: true,
                onPressed: () => unawaited(showTraktSignIn(context)),
              ),
            ),
            const Note(
              'You’ll get a code to enter at trakt.tv. Kinora never sees '
              'your password.',
            ),
          ] else ...[
            const SectionTitle('Signed in'),
            Note(
              [
                'As ${trakt.user}.',
                if (trakt.syncing)
                  'Syncing…'
                else if (trakt.lastSync case final at?)
                  '${syncedAgo(at, DateTime.now())}.',
              ].join(' '),
            ),
            ActionRow(
              icon: Icons.sync_rounded,
              label: 'Sync now',
              onTap: trakt.syncing ? null : () => unawaited(trakt.syncNow()),
            ),
            ActionRow(
              icon: Icons.logout_rounded,
              label: 'Sign out',
              detail: 'What you watched stays on this phone.',
              color: KColors.cut,
              onTap: () async {
                final ok = await confirmAction(
                  context,
                  title: 'Sign out of Trakt?',
                  message:
                      'Kinora stops syncing. What you watched stays on this '
                      'phone and on Trakt.',
                  action: 'Sign out',
                );
                if (ok) await trakt.signOut();
              },
            ),
          ],
          if (trakt.note case final note?)
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
      ),
    );
  }
}

/// The code to approve at trakt.tv, waiting until it's approved.
Future<void> showTraktSignIn(BuildContext context) =>
    showGlassSheet<void>(context, builder: (_) => const _SignInSheet());

class _SignInSheet extends ConsumerStatefulWidget {
  const _SignInSheet();

  @override
  ConsumerState<_SignInSheet> createState() => _SignInSheetState();
}

class _SignInSheetState extends ConsumerState<_SignInSheet> {
  TraktCode? _code;
  String? _problem;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _code = null;
      _problem = null;
    });
    final trakt = ref.read(traktSyncProvider);
    final TraktCode code;
    try {
      code = await trakt.startSignIn();
    } on Object {
      if (mounted) {
        setState(
          () => _problem =
              'Couldn’t reach Trakt. Check your connection, then try again.',
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() => _code = code);
    final result = await trakt.finishSignIn(code, cancelled: () => _closed);
    if (_closed || !mounted) return;
    switch (result) {
      case TraktSignIn.approved:
        Navigator.pop(context);
        showNote(context, 'Signed in as ${trakt.user}. Syncing…');
      case TraktSignIn.denied:
        setState(() => _problem = 'The code was declined on trakt.tv.');
      case TraktSignIn.expired:
        setState(() => _problem = 'The code ran out. Get a new one.');
      case TraktSignIn.failed:
        setState(
          () => _problem = 'Trakt didn’t sign you in. Try again in a moment.',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final code = _code;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KSpace.margin,
        KSpace.x2,
        KSpace.margin,
        KSpace.margin,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text('Sign in with Trakt', style: KType.h2),
          ),
          const SizedBox(height: KSpace.x2),
          if (_problem case final problem?) ...[
            Semantics(
              liveRegion: true,
              child: Text(
                problem,
                style: KType.body.copyWith(color: KColors.cut),
              ),
            ),
            const SizedBox(height: KSpace.x4),
            GlassButton(
              label: 'Get a new code',
              icon: Icons.refresh_rounded,
              prominent: true,
              onPressed: () => unawaited(_start()),
            ),
          ] else if (code == null)
            const Padding(
              padding: EdgeInsets.all(KSpace.margin),
              child: Center(child: CircularProgressIndicator.adaptive()),
            )
          else ...[
            Text(
              'On any device, go to ${Uri.parse(code.url).host}'
              '${Uri.parse(code.url).path} and enter this code:',
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
                    launchUrl(
                      Uri.parse(code.url),
                      mode: LaunchMode.externalApplication,
                    ),
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
                Text(
                  'Waiting for you to approve it…',
                  style: KType.label.copyWith(color: KColors.haze),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
