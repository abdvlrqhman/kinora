import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:subtitles/subtitles.dart' show Language;

import '../../app/providers.dart';
import '../../core/lang.dart';
import '../../core/settings.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/sheet.dart';
import 'subtitle_style_page.dart';
import 'widgets/settings_ui.dart';

/// English name for a language code ("ar" → "Arabic").
String languageName(String code) =>
    Language.parse(code)?.englishName ?? langName(code);

/// "Arabic, English" (or null when none).
String? languageList(List<String> codes) =>
    codes.isEmpty ? null : codes.map(languageName).join(', ');

void _save(WidgetRef ref, AppSettings Function(AppSettings) change) =>
    unawaited(ref.read(settingsProvider.notifier).update(change));

/// The language choices shared by onboarding and Settings: subtitle
/// languages in order, audio, and when subtitles turn on.
List<Widget> languageSections() => const [
  SectionTitle('Subtitle languages'),
  Note('Kinora looks for subtitles in this order. Drag to reorder.'),
  SubtitleLanguageList(),
  SectionTitle('Audio'),
  AudioChoice(),
  SectionTitle('When subtitles turn on'),
  SubtitleModeChoice(),
];

/// Settings › Languages and subtitles.
class LanguagesPage extends ConsumerWidget {
  const LanguagesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    return SettingsPage(
      title: 'Languages and subtitles',
      children: [
        ...languageSections(),
        const SectionTitle('Subtitles'),
        SwitchRow(
          label: 'Prefer subtitles for the deaf and hard of hearing',
          detail: 'SDH subtitles also describe sounds and music.',
          value: s.preferHearingImpaired,
          onChanged: (v) =>
              _save(ref, (s) => s.copyWith(preferHearingImpaired: v)),
        ),
        NavRow(
          label: 'Subtitle style',
          value: styleSummary(s.subtitleStyle),
          onTap: () => context.go('/settings/languages/style'),
        ),
      ],
    );
  }
}

/// Subtitle languages in preference order: drag to reorder, remove, add.
class SubtitleLanguageList extends ConsumerWidget {
  const SubtitleLanguageList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final langs = ref.watch(
      settingsProvider.select((s) => s.subtitleLanguages),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          proxyDecorator: (child, _, _) =>
              Material(color: KColors.seat, child: child),
          onReorderItem: (from, to) {
            final list = [...langs];
            list.insert(to, list.removeAt(from));
            _save(ref, (s) => s.copyWith(subtitleLanguages: list));
          },
          children: [
            for (final (i, code) in langs.indexed)
              _LanguageRow(
                key: ValueKey(code),
                index: i,
                code: code,
                onRemove: () => _save(
                  ref,
                  (s) =>
                      s.copyWith(subtitleLanguages: [...langs]..remove(code)),
                ),
              ),
          ],
        ),
        ActionRow(
          icon: Icons.add_rounded,
          label: langs.isEmpty ? 'Add a language' : 'Add another language',
          detail: langs.isEmpty ? 'Add the ones you read, best first.' : null,
          onTap: () async {
            final code = await pickLanguage(
              context,
              title: 'Add a subtitle language',
              chosen: langs.toSet(),
            );
            if (code == null || langs.contains(code)) return;
            _save(
              ref,
              (s) =>
                  s.copyWith(subtitleLanguages: [...s.subtitleLanguages, code]),
            );
          },
        ),
      ],
    );
  }
}

class _LanguageRow extends StatelessWidget {
  const _LanguageRow({
    super.key,
    required this.index,
    required this.code,
    required this.onRemove,
  });

  final int index;
  final String code;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final lang = Language.parse(code);
    final name = lang?.englishName ?? langName(code);
    final native = lang?.nativeName;
    return ReorderableDelayedDragStartListener(
      index: index,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Row(
          children: [
            const SizedBox(width: KSpace.margin),
            SizedBox(
              width: 28,
              child: ExcludeSemantics(
                child: Text(
                  '${index + 1}',
                  style: KType.tabular(KType.h2.copyWith(color: KColors.haze)),
                ),
              ),
            ),
            const SizedBox(width: KSpace.x2),
            Expanded(
              child: Semantics(
                label: '$name, choice ${index + 1}',
                excludeSemantics: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: KType.title),
                    if (native != null && native != name)
                      Text(
                        native,
                        style: KType.label.copyWith(color: KColors.haze),
                      ),
                  ],
                ),
              ),
            ),
            _IconAction(
              icon: Icons.close_rounded,
              label: 'Remove $name',
              onTap: onRemove,
            ),
            ReorderableDragStartListener(
              index: index,
              child: const ExcludeSemantics(
                child: SizedBox.square(
                  dimension: 48,
                  child: Icon(Icons.drag_handle_rounded, color: KColors.reel),
                ),
              ),
            ),
            const SizedBox(width: KSpace.x2),
          ],
        ),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    label: label,
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox.square(
        dimension: 48,
        child: Icon(icon, color: KColors.haze, size: 20),
      ),
    ),
  );
}

/// Original audio, or a dubbed language when a version has it.
class AudioChoice extends ConsumerWidget {
  const AudioChoice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audio = ref.watch(settingsProvider.select((s) => s.audioLanguages));
    final dub = audio.isEmpty || audio.first == 'original' ? null : audio.first;
    Future<void> pickDub() async {
      final code = await pickLanguage(
        context,
        title: 'Dubbed audio in',
        chosen: {?dub},
      );
      if (code != null) {
        _save(ref, (s) => s.copyWith(audioLanguages: [code, 'original']));
      }
    }

    return Column(
      children: [
        ChoiceRow(
          label: 'Original language',
          detail: 'Hear each film as it was made.',
          selected: dub == null,
          onTap: () =>
              _save(ref, (s) => s.copyWith(audioLanguages: ['original'])),
        ),
        ChoiceRow(
          label: dub == null ? 'Dubbed' : 'Dubbed in ${languageName(dub)}',
          detail: dub == null
              ? 'Choose a language for dubbed audio.'
              : 'When a version has it; otherwise the original plays. '
                    'Choose to change it.',
          selected: dub != null,
          onTap: pickDub,
        ),
      ],
    );
  }
}

/// Plain name and one-line explanation of each subtitle mode.
(String, String) subtitleModeText(SubtitleMode m) => switch (m) {
  SubtitleMode.auto => (
    'Automatic',
    'On when the audio isn’t in your first language.',
  ),
  SubtitleMode.always => (
    'Always',
    'On in your first language, even when you understand the audio.',
  ),
  SubtitleMode.forcedOnly => (
    'Forced only',
    'Only signs and lines spoken in another language.',
  ),
  SubtitleMode.off => ('Off', 'You turn them on from the player.'),
};

/// Auto / always / forced only / off.
class SubtitleModeChoice extends ConsumerWidget {
  const SubtitleModeChoice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(settingsProvider.select((s) => s.subtitleMode));
    return Column(
      children: [
        for (final m in SubtitleMode.values)
          ChoiceRow(
            label: subtitleModeText(m).$1,
            detail: subtitleModeText(m).$2,
            selected: m == mode,
            onTap: () => _save(ref, (s) => s.copyWith(subtitleMode: m)),
          ),
      ],
    );
  }
}

/// Searchable list of every language; returns the picked code.
Future<String?> pickLanguage(
  BuildContext context, {
  required String title,
  Set<String> chosen = const {},
}) => showGlassSheet<String>(
  context,
  builder: (_) => _LanguagePicker(title: title, chosen: chosen),
);

class _LanguagePicker extends StatefulWidget {
  const _LanguagePicker({required this.title, required this.chosen});

  final String title;
  final Set<String> chosen;

  @override
  State<_LanguagePicker> createState() => _LanguagePickerState();
}

class _LanguagePickerState extends State<_LanguagePicker> {
  final _query = TextEditingController();
  List<Language> _shown = Language.all;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _filter(String text) {
    final q = text.trim().toLowerCase();
    setState(
      () => _shown = q.isEmpty
          ? Language.all
          : [
              for (final l in Language.all)
                if (l.englishName.toLowerCase().contains(q) ||
                    l.nativeName.toLowerCase().contains(q) ||
                    l.code.toLowerCase() == q)
                  l,
            ],
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(
          KSpace.margin,
          KSpace.x3,
          KSpace.margin,
          0,
        ),
        child: Semantics(
          header: true,
          child: Text(widget.title, style: KType.h2),
        ),
      ),
      GlassField(
        controller: _query,
        label: 'Search languages',
        hint: 'Arabic, Español, 日本語',
        onChanged: _filter,
        fieldKey: const ValueKey('language-search'),
      ),
      Flexible(
        child: _shown.isEmpty
            ? const Note('No language matches. Try its English name.')
            : ListView.builder(
                padding: const EdgeInsets.only(bottom: KSpace.x4),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                itemCount: _shown.length,
                itemBuilder: (context, i) {
                  final l = _shown[i];
                  final picked = widget.chosen.contains(l.code);
                  return ChoiceRow(
                    label: l.englishName,
                    detail: l.nativeName == l.englishName ? null : l.nativeName,
                    selected: picked,
                    onTap: () => Navigator.pop(context, l.code),
                  );
                },
              ),
      ),
    ],
  );
}
