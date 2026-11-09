import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../services/sources.dart';
import '../../services/subtitles_service.dart';
import '../../ui/glass.dart';
import '../../ui/tint.dart';
import '../../ui/tokens.dart';
import '../settings/languages.dart';
import '../settings/sources.dart';
import '../settings/subtitle_sites.dart';
import '../settings/widgets/settings_ui.dart';

/// First run: welcome, languages, sources, subtitle sites, done. Every
/// step after the welcome can be skipped; choices save as they're made.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const _last = 4;
  int _step = 0;

  void _go(int step) => setState(() => _step = step.clamp(0, _last));

  Future<void> _finish() => ref
      .read(settingsProvider.notifier)
      .update((s) => s.copyWith(onboarded: true));

  @override
  Widget build(BuildContext context) {
    final reduce = reduceMotion(context);
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _go(_step - 1);
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_step > 0)
                _TopBar(
                  step: _step,
                  last: _last,
                  onBack: () => _go(_step - 1),
                  onSkip: _step < _last ? () => _go(_last) : null,
                ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: reduce ? Duration.zero : KMotion.base,
                  switchInCurve: KMotion.curve,
                  switchOutCurve: KMotion.curve,
                  child: KeyedSubtree(
                    key: ValueKey(_step),
                    child: switch (_step) {
                      0 => const _Welcome(),
                      1 => _Step(
                        title: 'Your languages',
                        intro:
                            'Choose the languages you read and hear. You can '
                            'change them any time in Settings.',
                        children: languageSections(),
                      ),
                      2 => const _Step(
                        title: 'Add your sources',
                        intro:
                            'Kinora has no movies or shows of its own. You '
                            'add Stremio-compatible addons by their link, '
                            'and they bring catalogs, streams and '
                            'subtitles.',
                        children: [
                          AddAddonField(),
                          SectionTitle('Start with these'),
                          SuggestedAddons(),
                          SectionTitle('Your sources'),
                          AddonList(),
                        ],
                      ),
                      3 => const _Step(
                        title: 'Subtitle sites',
                        intro: 'Optional. $subtitleSitesIntro',
                        children: [SubtitleSiteList()],
                      ),
                      _ => const _Done(),
                    },
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  KSpace.margin,
                  KSpace.x3,
                  KSpace.margin,
                  KSpace.x3,
                ),
                child: GlassGroup(
                  child: GlassButton(
                    key: const ValueKey('onboarding-next'),
                    label: _step == _last ? 'Start watching' : 'Continue',
                    prominent: true,
                    onPressed: () =>
                        _step == _last ? unawaited(_finish()) : _go(_step + 1),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.step,
    required this.last,
    required this.onBack,
    required this.onSkip,
  });

  final int step;
  final int last;
  final VoidCallback onBack;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(KSpace.x3, KSpace.x2, KSpace.x2, 0),
    child: Row(
      children: [
        GlassGroup(
          child: GlassIconButton(
            icon: Icons.chevron_left_rounded,
            label: 'Back',
            onPressed: onBack,
          ),
        ),
        const SizedBox(width: KSpace.x4),
        Expanded(
          child: Semantics(
            label: 'Step $step of $last',
            excludeSemantics: true,
            child: Row(
              children: [
                for (var i = 1; i <= last; i++) ...[
                  if (i > 1) const SizedBox(width: KSpace.x1),
                  Expanded(
                    child: Container(
                      height: 3,
                      decoration: BoxDecoration(
                        color: i <= step
                            ? KinoraTint.of(context)
                            : KColors.lamp.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: KSpace.x2),
        SizedBox(
          width: 72,
          child: onSkip == null
              ? null
              : Semantics(
                  button: true,
                  label: 'Skip setup',
                  excludeSemantics: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onSkip,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: Center(
                        child: Text(
                          'Skip',
                          style: KType.title.copyWith(color: KColors.haze),
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    ),
  );
}

class _Step extends StatelessWidget {
  const _Step({
    required this.title,
    required this.intro,
    required this.children,
  });

  final String title;
  final String intro;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.only(top: KSpace.x4, bottom: KSpace.x4),
    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: KSpace.margin),
        child: Semantics(header: true, child: Text(title, style: KType.h1)),
      ),
      Note(intro, top: KSpace.x2),
      ...children,
    ],
  );
}

/// Scrolls when large text needs it; otherwise sits at the bottom.
class _BottomAligned extends StatelessWidget {
  const _BottomAligned({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) => SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: KSpace.margin),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: c.maxHeight),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    ),
  );
}

class _Welcome extends StatelessWidget {
  const _Welcome();

  @override
  Widget build(BuildContext context) => _BottomAligned(
    children: [
      Semantics(
        header: true,
        child: Text(
          'Welcome',
          style: KType.hero.copyWith(fontSize: 72, height: 68 / 72),
        ),
      ),
      const SizedBox(height: KSpace.x3),
      Text(
        'Kinora streams or downloads movies and shows from the sources you '
        'add, and picks the best version for you.',
        style: KType.body.copyWith(fontSize: 17, color: KColors.haze),
      ),
      const SizedBox(height: KSpace.x4),
    ],
  );
}

class _Done extends ConsumerWidget {
  const _Done();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final addons = ref.watch(addonsProvider).value ?? const [];
    final sites = [
      for (final p in subtitleProviderCatalog)
        if (s.enabledSubtitleProviders.contains(p.id)) p.name,
    ];
    final langs = languageList(s.subtitleLanguages);
    Widget fact(IconData icon, String text, {Color color = KColors.lamp}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: KSpace.x3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: KSpace.x3),
              Expanded(
                child: Text(text, style: KType.body.copyWith(color: color)),
              ),
            ],
          ),
        );
    return _BottomAligned(
      children: [
        Semantics(header: true, child: Text('You’re set', style: KType.hero)),
        const SizedBox(height: KSpace.x4),
        fact(
          Icons.translate_rounded,
          langs == null ? 'No subtitle languages yet' : 'Subtitles in $langs',
        ),
        if (addons.isEmpty)
          fact(
            Icons.hub_outlined,
            'No sources yet. Add one in Settings to see movies and shows.',
            color: KColors.marquee,
          )
        else
          fact(
            Icons.hub_outlined,
            addons.length == 1
                ? '1 source: ${addons.first.name}'
                : '${addons.length} sources',
          ),
        fact(
          Icons.subtitles_outlined,
          sites.isEmpty
              ? 'No subtitle sites on'
              : 'Subtitles also from ${sites.join(', ')}',
        ),
        Text(
          'Change any of this in Settings.',
          style: KType.body.copyWith(color: KColors.haze),
        ),
        const SizedBox(height: KSpace.x4),
      ],
    );
  }
}
