import 'dart:async';

import 'package:flutter/material.dart';

import '../ui/tokens.dart';
import '../ui/widgets/brand.dart';
import '../ui/widgets/spacie_logo.dart';

/// The first thing you see at launch: the mark switches on, "Kinora", and
/// "Powered by Spacie". The app builds and loads underneath the whole time
/// and takes over after about two seconds (a tap skips ahead).
class IntroOverlay extends StatefulWidget {
  const IntroOverlay({super.key, required this.child});

  final Widget child;

  /// Lets a test show it again (it shows once per launch).
  @visibleForTesting
  static void debugReset() => _IntroOverlayState._shown = false;

  @override
  State<IntroOverlay> createState() => _IntroOverlayState();
}

class _IntroOverlayState extends State<IntroOverlay>
    with SingleTickerProviderStateMixin {
  /// Once per launch, not every time the widget tree is rebuilt.
  static bool _shown = false;

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
  );
  bool _done = _shown;

  @override
  void initState() {
    super.initState();
    if (_done) return;
    _shown = true;
    // A status listener, not forward()'s future: restarting the animation
    // (skip, reduced motion) cancels that future, which then never ends.
    _c.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _done = true);
      }
    });
    unawaited(_c.forward());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion: everything at once, a short hold, then a quick fade.
    if (!_done &&
        _c.value < 0.5 &&
        (MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
      _c.duration = const Duration(milliseconds: 1100);
      unawaited(_c.forward(from: 0.5));
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _skip() {
    if (_c.value < 0.8) unawaited(_c.forward(from: 0.8));
  }

  /// [t] mapped onto [begin]..[end], eased.
  double _span(double t, double begin, double end, [Curve c = Curves.linear]) =>
      c.transform(((t - begin) / (end - begin)).clamp(0, 1));

  @override
  Widget build(BuildContext context) {
    // The app keeps its place in the tree when the intro goes (dropping the
    // Stack would rebuild it from scratch).
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (!_done)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _skip,
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                final t = _c.value;
                final words = _span(t, 0.30, 0.48, Curves.easeOutCubic);
                final credit = _span(t, 0.40, 0.58, Curves.easeOutCubic);
                return Opacity(
                  opacity: 1 - _span(t, 0.80, 1, Curves.easeInCubic),
                  child: Material(
                    // Above the app's navigator: give the text a Material.
                    color: KColors.seat,
                    child: Semantics(
                      label: 'Kinora. Powered by Spacie.',
                      excludeSemantics: true,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CustomPaint(
                              size: const Size.square(132),
                              painter: KinoraMark(
                                lamp: _span(t, 0, 0.15),
                                light: _span(
                                  t,
                                  0.12,
                                  0.40,
                                  Curves.easeOutCubic,
                                ),
                              ),
                            ),
                            const SizedBox(height: KSpace.x2),
                            Opacity(
                              opacity: words,
                              child: Transform.translate(
                                offset: Offset(0, 8 * (1 - words)),
                                child: Text(
                                  'Kinora',
                                  style: KType.hero.copyWith(
                                    color: KColors.lamp,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: KSpace.x4),
                            Opacity(
                              opacity: credit,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Powered by',
                                    style: KType.label.copyWith(
                                      color: KColors.haze,
                                    ),
                                  ),
                                  const SizedBox(width: KSpace.x2),
                                  const SpacieLogo(size: 30),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
