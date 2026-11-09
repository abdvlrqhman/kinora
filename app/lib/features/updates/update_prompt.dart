import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../services/updates.dart';
import '../../ui/glass.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/sheet.dart';
import '../settings/widgets/settings_ui.dart';

/// Checks for a newer Kinora once a launch, a few seconds in (after the
/// intro), unless the user turned it off. Sits invisibly in the shell.
class UpdateCheck extends ConsumerStatefulWidget {
  const UpdateCheck({super.key});

  @override
  ConsumerState<UpdateCheck> createState() => _UpdateCheckState();
}

class _UpdateCheckState extends ConsumerState<UpdateCheck> {
  static bool _checked = false;

  @override
  void initState() {
    super.initState();
    // Not under `flutter test`: no network, and no timer left behind.
    if (_checked || Platform.environment.containsKey('FLUTTER_TEST')) return;
    _checked = true;
    unawaited(_check());
  }

  Future<void> _check() async {
    await Future<void>.delayed(const Duration(seconds: 4));
    if (!mounted || !ref.read(settingsProvider).updateChecks) return;
    final release = await newerRelease(
      ref.read(httpClientProvider),
      kinoraVersion,
    );
    if (release != null && mounted) await showUpdate(context, release);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// "Settings › About › Check for updates": now, and says when there's none.
Future<void> checkForUpdatesNow(BuildContext context, WidgetRef ref) async {
  final release = await newerRelease(
    ref.read(httpClientProvider),
    kinoraVersion,
  );
  if (!context.mounted) return;
  if (release == null) {
    showNote(context, 'You have the latest Kinora ($kinoraVersion).');
  } else {
    await showUpdate(context, release);
  }
}

/// The update sheet: what's new (scrollable), Update now, Later, and Don't
/// ask again (turns the launch check off; Settings › About turns it on).
Future<void> showUpdate(BuildContext context, KinoraRelease release) =>
    showGlassSheet<void>(
      context,
      builder: (sheet) => _UpdateSheet(release: release),
    );

class _UpdateSheet extends ConsumerStatefulWidget {
  const _UpdateSheet({required this.release});
  final KinoraRelease release;

  @override
  ConsumerState<_UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends ConsumerState<_UpdateSheet> {
  /// Download progress (Android), null when not downloading.
  double? _progress;
  String? _error;

  Future<void> _update() async {
    final r = widget.release;
    if (Platform.isIOS) {
      await installIos(r);
      if (mounted) Navigator.pop(context);
      return;
    }
    setState(() {
      _progress = 0;
      _error = null;
    });
    final ok = await installAndroid(
      ref.read(httpClientProvider),
      r,
      ref.read(pathsProvider).cache,
      onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      },
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      setState(() {
        _progress = null;
        _error =
            'The update couldn’t be downloaded. Try again, or get it '
            'from the release page.';
      });
    }
  }

  Future<void> _never() async {
    await ref
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(updateChecks: false));
    if (!mounted) return;
    Navigator.pop(context);
    showNote(context, 'Turn it back on in Settings › About.');
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.release;
    final busy = _progress != null;
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
            child: Text('Kinora ${r.version} is out', style: KType.h1),
          ),
          Text(
            'You have $kinoraVersion.',
            style: KType.body.copyWith(color: KColors.haze),
          ),
          const SizedBox(height: KSpace.x4),
          // What's new, scrollable: the sheet keeps its buttons in view.
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.4,
              ),
              child: Changelog(notes: r.notes),
            ),
          ),
          const SizedBox(height: KSpace.x4),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: KSpace.x3),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: KType.body.copyWith(color: KColors.cut),
                ),
              ),
            ),
          if (busy) ...[
            Semantics(
              liveRegion: true,
              label: 'Downloading ${(_progress! * 100).round()}%',
              child: LinearProgressIndicator(
                value: _progress == 0 ? null : _progress,
                color: KColors.marquee,
                backgroundColor: KColors.lamp.withValues(alpha: 0.18),
              ),
            ),
            const SizedBox(height: KSpace.x3),
          ],
          GlassGroup(
            child: Wrap(
              spacing: KSpace.x2,
              runSpacing: KSpace.x2,
              children: [
                GlassButton(
                  label: busy ? 'Downloading…' : 'Update now',
                  icon: Icons.system_update_rounded,
                  prominent: true,
                  onPressed: busy ? null : () => unawaited(_update()),
                ),
                GlassButton(
                  label: 'Later',
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: KSpace.x2),
          ActionRow(
            icon: Icons.notifications_off_outlined,
            label: 'Don’t ask again',
            onTap: busy ? null : () => unawaited(_never()),
          ),
        ],
      ),
    );
  }
}

/// The release notes as titles and lines, scrollable. Markdown marks are
/// dropped; there's no need for a renderer.
class Changelog extends StatelessWidget {
  const Changelog({super.key, required this.notes});
  final String notes;

  /// Titles and items, with lines wrapped by the commit message joined
  /// back into sentences.
  static List<(bool title, String text)> parse(String notes) {
    String clean(String s) => s.replaceAll('**', '').replaceAll('`', '').trim();
    final out = <(bool, String)>[];
    var open = false; // the last item can take continuation lines
    for (final raw in notes.split('\n')) {
      final l = raw.trim();
      if (l.isEmpty) {
        open = false;
      } else if (l.startsWith('#')) {
        out.add((true, clean(l.replaceFirst(RegExp(r'^#+\s*'), ''))));
        open = false;
      } else if (RegExp(r'^[-*]\s+').hasMatch(l)) {
        out.add((
          false,
          '•  ${clean(l.replaceFirst(RegExp(r'^[-*]\s+'), ''))}',
        ));
        open = true;
      } else if (open && out.isNotEmpty && !out.last.$1) {
        out[out.length - 1] = (false, '${out.last.$2} ${clean(l)}');
      } else {
        out.add((false, clean(l)));
        open = true;
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final items = parse(notes);
    if (items.isEmpty) {
      return Text(
        'Fixes and improvements.',
        style: KType.body.copyWith(color: KColors.haze),
      );
    }
    return Scrollbar(
      child: ListView(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        children: [
          for (final (title, text) in items)
            Padding(
              padding: title
                  ? const EdgeInsets.only(top: KSpace.x3, bottom: KSpace.x1)
                  : const EdgeInsets.only(bottom: KSpace.x1),
              child: Text(
                text,
                style: title
                    ? KType.title
                    : KType.body.copyWith(color: KColors.haze),
              ),
            ),
        ],
      ),
    );
  }
}
