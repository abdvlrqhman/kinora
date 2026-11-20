import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/settings.dart';
import '../../ui/tokens.dart';
import '../home/home_feed.dart';
import '../home/home_layout.dart';
import 'widgets/settings_ui.dart';

/// Settings › Home: show, hide and order Home's rows. Genres are added
/// from Discovery (Add to Home) and removed here.
class HomeSettingsPage extends ConsumerWidget {
  const HomeSettingsPage({super.key});

  /// What a row needs to show, when it's not obvious.
  static String? detailOf(String id) => switch (id) {
    'for-you' ||
    'because' ||
    'trending-shows' ||
    'trending-movies' => 'With Trakt',
    'new-episodes' => 'Shows you follow, when there are some',
    _ when id.startsWith('pin:') => 'Added from Discovery',
    _ => null,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final choices = ref.watch(homeRowChoicesProvider);
    final titles = {for (final c in choices) c.id: c.title};
    final rows = homeLayout(
      available: [for (final c in choices) c.id],
      order: s.homeOrder,
    );
    final hidden = s.homeHidden.toSet();
    final settings = ref.read(settingsProvider.notifier);
    void save(AppSettings Function(AppSettings) change) =>
        unawaited(settings.update(change));
    void move(int i, int by) {
      final next = [...rows];
      next.insert(i + by, next.removeAt(i));
      save((s) => s.copyWith(homeOrder: next));
    }

    return SettingsPage(
      title: 'Home',
      intro:
          'Show, hide and order the rows of Home. To add a genre, open it in '
          'Discovery and choose Add to Home.',
      children: [
        for (final (i, id) in rows.indexed)
          _HomeRow(
            title: titles[id] ?? id,
            detail: detailOf(id),
            shown: !hidden.contains(id),
            onShown: (v) => save(
              (s) => s.copyWith(
                homeHidden: v
                    ? [...s.homeHidden.where((h) => h != id)]
                    : [...s.homeHidden, id],
              ),
            ),
            onUp: i > 0 ? () => move(i, -1) : null,
            onDown: i < rows.length - 1 ? () => move(i, 1) : null,
            onRemove: id.startsWith('pin:')
                ? () => save(
                    (s) => s.copyWith(
                      homePinned: [...s.homePinned.where((p) => p != id)],
                    ),
                  )
                : null,
          ),
        if (s.homeOrder.isNotEmpty || s.homeHidden.isNotEmpty)
          ActionRow(
            label: 'Reset order and hidden rows',
            icon: Icons.restart_alt_rounded,
            onTap: () => save(
              (s) => s.copyWith(homeOrder: const [], homeHidden: const []),
            ),
          ),
      ],
    );
  }
}

/// A Home row: shown or not, and moved up or down (buttons, or a screen
/// reader's actions).
class _HomeRow extends StatelessWidget implements SettingsRow {
  const _HomeRow({
    required this.title,
    required this.detail,
    required this.shown,
    required this.onShown,
    required this.onUp,
    required this.onDown,
    required this.onRemove,
  });

  final String title;
  final String? detail;
  final bool shown;
  final ValueChanged<bool> onShown;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    Widget button(IconData icon, String tip, VoidCallback? onTap) => IconButton(
      icon: Icon(icon, size: 20),
      tooltip: tip,
      color: KColors.haze,
      disabledColor: KColors.edge,
      onPressed: onTap,
    );
    return Semantics(
      customSemanticsActions: {
        if (onUp case final up?)
          const CustomSemanticsAction(label: 'Move up'): up,
        if (onDown case final down?)
          const CustomSemanticsAction(label: 'Move down'): down,
        if (onRemove case final remove?)
          const CustomSemanticsAction(label: 'Remove from Home'): remove,
      },
      child: Row(
        children: [
          Expanded(
            child: SwitchRow(
              label: title,
              detail: detail,
              value: shown,
              onChanged: onShown,
            ),
          ),
          ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.only(right: KSpace.x2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onRemove != null)
                    button(Icons.close_rounded, 'Remove from Home', onRemove),
                  button(Icons.arrow_upward_rounded, 'Move up', onUp),
                  button(Icons.arrow_downward_rounded, 'Move down', onDown),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
