import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/backup.dart';
import '../../ui/glass.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/sheet.dart';
import 'widgets/settings_ui.dart';

/// Settings › Backup: carry sources and keys to another device as a code
/// locked with a passphrase.
class BackupPage extends StatelessWidget {
  const BackupPage({super.key});

  @override
  Widget build(BuildContext context) => const SettingsPage(
    title: 'Backup',
    children: [
      Note(
        'Move your sources and keys to another phone or computer. They '
        'travel as a code locked with a passphrase you choose. Kinora keeps '
        'no copy anywhere.',
      ),
      SectionTitle('Back up'),
      _MakeBackup(),
      SectionTitle('Restore'),
      RestoreBackupPanel(),
    ],
  );
}

/// Opens Restore in a sheet (onboarding's "Moving from another device?").
Future<void> showRestoreSheet(BuildContext context) => showGlassSheet<void>(
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
          child: Semantics(
            header: true,
            child: Text('Restore a backup', style: KType.h2),
          ),
        ),
        const Note(
          'On your other device, open Settings › Backup › Back up, then '
          'paste the code here.',
        ),
        const RestoreBackupPanel(),
        const SizedBox(height: KSpace.margin),
      ],
    ),
  ),
);

class _MakeBackup extends ConsumerStatefulWidget {
  const _MakeBackup();

  @override
  ConsumerState<_MakeBackup> createState() => _MakeBackupState();
}

class _MakeBackupState extends ConsumerState<_MakeBackup> {
  final _pass = TextEditingController();
  final _again = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _code;
  Restored? _held;

  @override
  void dispose() {
    _pass.dispose();
    _again.dispose();
    super.dispose();
  }

  Future<void> _make() async {
    final pass = _pass.text;
    final error = switch (pass) {
      _ when pass.length < BackupCode.minPassphrase =>
        'Use at least ${BackupCode.minPassphrase} characters.',
      _ when pass != _again.text => 'The two passphrases don’t match.',
      _ => null,
    };
    setState(() => _error = error);
    if (error != null) return;
    setState(() => _busy = true);
    try {
      final data = await ref.read(backupServiceProvider).gather();
      final code = await BackupCode.seal(data, pass);
      await Clipboard.setData(ClipboardData(text: code));
      if (!mounted) return;
      setState(() {
        _code = code;
        _held = BackupService.count(data);
      });
      showNote(context, 'Backup code copied.');
    } on Object {
      if (mounted) {
        setState(() => _error = 'Kinora couldn’t make the code. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final code = _code;
    if (code != null) {
      final held = _held!;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Note(
            'Copied: ${_plural(held.sources, 'source')} and '
            '${_plural(held.keys, 'key')}. Paste the code on your other '
            'device in Settings › Backup › Restore, with the same '
            'passphrase. Without the passphrase it can’t be opened.',
          ),
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
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GlassButton(
                      label: 'Copy again',
                      prominent: true,
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: code));
                        if (context.mounted) {
                          showNote(context, 'Backup code copied.');
                        }
                      },
                    ),
                    const SizedBox(width: KSpace.x2),
                    GlassButton(
                      label: 'Done',
                      onPressed: () => setState(() {
                        _code = null;
                        _pass.clear();
                        _again.clear();
                      }),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassField(
          controller: _pass,
          label: 'Choose a passphrase',
          obscure: true,
          fieldKey: const ValueKey('backup-pass'),
        ),
        GlassField(
          controller: _again,
          label: 'Type it again',
          obscure: true,
          onSubmitted: (_) => unawaited(_make()),
          fieldKey: const ValueKey('backup-again'),
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
              child: GlassButton(
                label: _busy ? 'Locking…' : 'Copy backup code',
                prominent: true,
                onPressed: _busy ? null : () => unawaited(_make()),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Paste a backup code and its passphrase: the sources this device doesn't
/// have are added, and the keys are set.
class RestoreBackupPanel extends ConsumerStatefulWidget {
  const RestoreBackupPanel({super.key});

  @override
  ConsumerState<RestoreBackupPanel> createState() => _RestoreState();
}

class _RestoreState extends ConsumerState<RestoreBackupPanel> {
  final _code = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _done;

  @override
  void dispose() {
    _code.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    if (_code.text.trim().isEmpty) {
      setState(() => _error = 'Paste the backup code first.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _done = null;
    });
    String? error;
    String? done;
    try {
      final data = await BackupCode.open(_code.text, _pass.text);
      final r = await ref.read(backupServiceProvider).restore(data);
      done = r.sources == 0 && r.keys == 0
          ? 'Nothing new: this device already has everything in the backup.'
          : 'Restored ${_plural(r.sources, 'source')} and '
                '${_plural(r.keys, 'key')}.';
    } on BackupException catch (e) {
      error = e.message;
    } on Object {
      error = 'Kinora couldn’t restore the backup. Try again.';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
      _done = done;
      if (done != null) {
        _code.clear();
        _pass.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      GlassField(
        controller: _code,
        label: 'Backup code',
        hint: '${BackupCode.prefix}…',
        paste: true,
        // A code with a few sources runs past any usual field limit.
        maxLength: null,
        fieldKey: const ValueKey('restore-code'),
      ),
      GlassField(
        controller: _pass,
        label: 'Passphrase',
        obscure: true,
        onSubmitted: (_) => unawaited(_restore()),
        fieldKey: const ValueKey('restore-pass'),
      ),
      if (_error != null)
        Semantics(liveRegion: true, child: Note(_error!, color: KColors.cut)),
      if (_done != null) Semantics(liveRegion: true, child: Note(_done!)),
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
            child: GlassButton(
              label: _busy ? 'Unlocking…' : 'Restore',
              prominent: true,
              onPressed: _busy ? null : () => unawaited(_restore()),
            ),
          ),
        ),
      ),
    ],
  );
}

String _plural(int n, String word) => '$n $word${n == 1 ? '' : 's'}';
