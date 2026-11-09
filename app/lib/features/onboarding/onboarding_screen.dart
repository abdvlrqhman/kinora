import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../services/cast_service.dart';
import '../../services/sources.dart';
import '../../services/subtitles_service.dart';
import '../../ui/glass.dart';
import '../../ui/tint.dart';
import '../../ui/tokens.dart';
import '../cast/cast_picker.dart';
import '../settings/languages.dart';
import '../settings/sources.dart';
import '../settings/subtitle_sites.dart';
import '../settings/widgets/settings_ui.dart';

/// First run: welcome, languages, sources, instant playback (debrid),
/// subtitle sites, your TV, done. Every step after the welcome can be
/// skipped; choices save as they're made.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const _last = 6;
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
        body: Stack(
          children: [
            if (_step == 0) const Positioned.fill(child: _Beam()),
            SafeArea(
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
                            title: 'Instant playback',
                            intro:
                                'Optional. A debrid service (Real-Debrid, '
                                'AllDebrid, Premiumize and others) keeps popular '
                                'versions ready, so they start at once, marked '
                                'Instant. Set up your stream source with your '
                                'debrid key on the source’s own site, then add the '
                                'link it gives you here.',
                            children: [AddAddonField()],
                          ),
                          4 => const _Step(
                            title: 'Subtitle sites',
                            intro: 'Optional. $subtitleSitesIntro',
                            children: [SubtitleSiteList()],
                          ),
                          5 => const _Step(
                            title: 'Your TV',
                            intro:
                                'Optional. Choose a TV on this Wi-Fi: Kinora picks '
                                'versions it can play and starts them there. You '
                                'can change it from Home any time.',
                            children: [_TvPicker()],
                          ),
                          _ => _Done(onAddSource: () => _go(2)),
                        },
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      KSpace.margin,
                      KSpace.margin,
                      KSpace.margin,
                      KSpace.x3,
                    ),
                    child: GlassGroup(
                      child: GlassButton(
                        key: const ValueKey('onboarding-next'),
                        label: switch (_step) {
                          0 => 'Set up Kinora',
                          _last => 'Start watching',
                          _ => 'Continue',
                        },
                        prominent: true,
                        onPressed: () => _step == _last
                            ? unawaited(_finish())
                            : _go(_step + 1),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
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
    padding: const EdgeInsets.fromLTRB(KSpace.margin, KSpace.x2, KSpace.x2, 0),
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
  Widget build(BuildContext context) => Stack(
    children: [
      ListView(
        padding: const EdgeInsets.only(top: KSpace.x4, bottom: KSpace.section),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: KSpace.margin),
            child: Semantics(header: true, child: Text(title, style: KType.h1)),
          ),
          Note(intro, top: KSpace.x2),
          ...children,
        ],
      ),
      // The list fades out above the button instead of ending against it.
      const Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        height: 32,
        child: LegibilityScrim(stops: [0, 1]),
      ),
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

/// The first frame: the Kinora wordmark lit by a projector beam.
class _Welcome extends StatelessWidget {
  const _Welcome();

  @override
  Widget build(BuildContext context) => _BottomAligned(
    children: [
      ExcludeSemantics(
        child: Text(
          'Kinora',
          style: KType.hero.copyWith(
            fontSize: 72,
            height: 68 / 72,
            letterSpacing: -0.5,
          ),
        ),
      ),
      const SizedBox(height: KSpace.x3),
      Semantics(
        header: true,
        label: 'Kinora. Your own cinema',
        excludeSemantics: true,
        child: Text('Your own cinema', style: KType.h1),
      ),
      const SizedBox(height: KSpace.x3),
      Text(
        'Add the sources you use. Kinora finds the best version of every '
        'film and episode, with subtitles in your language.',
        style: KType.body.copyWith(fontSize: 17, color: KColors.haze),
      ),
      const SizedBox(height: KSpace.x4),
    ],
  );
}

/// A projector beam from the top of the screen: Marquee light fading out,
/// drifting slowly into place once (still with reduced motion).
class _Beam extends StatelessWidget {
  const _Beam();

  @override
  Widget build(BuildContext context) {
    final reduce = reduceMotion(context);
    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: reduce ? 1 : 0, end: 1),
        duration: reduce ? Duration.zero : const Duration(seconds: 6),
        curve: Curves.easeOutSine,
        builder: (context, t, _) => DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(-0.45 * (1 - t), -1.1 + 0.1 * t),
              // Of the shorter side: 1.2x the width on a phone.
              radius: 1.2,
              colors: [
                KColors.marquee.withValues(alpha: 0.22),
                KColors.marquee.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pick a TV now (optional); the same list as Cast to a TV on Home.
class _TvPicker extends ConsumerWidget {
  const _TvPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) => CastTargetBuilder(
    builder: (context, tv) {
      final cast = ref.read(castServiceProvider);
      return CastDeviceList(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        selected: tv?.udn,
        onPick: cast.selectTarget,
        leading: [
          CastDeviceRow(
            name: 'This phone',
            label: 'Play on this phone',
            selected: tv == null,
            onTap: () => cast.selectTarget(null),
          ),
        ],
      );
    },
  );
}

class _Done extends ConsumerWidget {
  const _Done({required this.onAddSource});

  final VoidCallback onAddSource;

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
            color: KColors.caution,
          )
        else ...[
          fact(
            Icons.hub_outlined,
            addons.length == 1
                ? '1 source: ${addons.first.name}'
                : '${addons.length} sources',
          ),
          if (!addons.any((a) => a.resources.contains('stream'))) ...[
            fact(
              Icons.play_disabled_rounded,
              'Nothing will play yet: add a source that provides streams.',
              color: KColors.caution,
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: KSpace.x3),
              child: GlassButton(
                label: 'Add a source',
                icon: Icons.add_rounded,
                onPressed: onAddSource,
              ),
            ),
          ],
        ],
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
