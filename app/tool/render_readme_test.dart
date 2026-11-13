// Renders the README's images into ../docs/ (the repo root):
// - banner.png: the README header;
// - social-preview.png: GitHub › Settings › Social preview (1280 × 640);
// - screens.png: five phone screens, made from the golden renders in
//   test/goldens;
// - desktop.png: Kinora on a computer (the desktop Home render).
// Run from app/: flutter test tool/render_readme_test.dart
// (after `flutter test --update-goldens`, so the screens are current).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinora/ui/tokens.dart';
import 'package:kinora/ui/widgets/brand.dart';
import 'package:kinora/ui/widgets/spacie_logo.dart';

import '../test/goldens/golden_helper.dart';

const _tagline =
    'Stream or download movies and shows, with subtitles in your languages, '
    'on your phone, your computer and your TV.';

/// The mark switched on in a dark room: its lime light is the only color.
class _Banner extends StatelessWidget {
  const _Banner(this.size);
  final Size size;

  @override
  Widget build(BuildContext context) {
    final h = size.height;
    final tall = size.width / h < 2.5;
    return SizedBox.fromSize(
      size: size,
      child: Stack(
        children: [
          const Positioned.fill(child: ColoredBox(color: KColors.blackout)),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.62, 0),
                  radius: tall ? 0.95 : 1.25,
                  colors: [
                    KColors.marquee.withValues(alpha: 0.30),
                    KColors.marquee.withValues(alpha: 0.07),
                    KColors.marquee.withValues(alpha: 0),
                  ],
                  stops: const [0, 0.42, 1],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: size.width * 0.07),
              child: Row(
                children: [
                  CustomPaint(
                    size: Size.square(h * (tall ? 0.46 : 0.62)),
                    painter: const KinoraMark(),
                  ),
                  SizedBox(width: h * 0.06),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Kinora',
                          style: KType.hero.copyWith(
                            fontSize: h * (tall ? 0.22 : 0.3),
                            height: 1,
                            color: KColors.lamp,
                          ),
                        ),
                        SizedBox(height: h * 0.04),
                        Text(
                          _tagline,
                          style: KType.title.copyWith(
                            fontSize: h * (tall ? 0.045 : 0.062),
                            height: 1.35,
                            fontWeight: FontWeight.w500,
                            color: KColors.haze,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: size.width * 0.04,
            bottom: h * 0.08,
            child: Row(
              children: [
                Text(
                  'Powered by',
                  style: KType.label.copyWith(
                    fontSize: h * (tall ? 0.026 : 0.04),
                    color: KColors.haze,
                  ),
                ),
                SizedBox(width: h * 0.02),
                SpacieLogo(size: h * (tall ? 0.05 : 0.075)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

const _shots = [
  ('screens/home.png', 'Pick up where you left off'),
  ('screens/title_series_episodes.png', 'Every episode, with its progress'),
  ('screens/search_results.png', 'Discover across your sources'),
  ('downloads.png', 'Downloads you control'),
  ('screens/cast_picker.png', 'Cast to your TV'),
];

class _Screens extends StatelessWidget {
  const _Screens(this.images);
  final List<ui.Image> images;

  static const phone = 260.0, gap = 36.0, margin = 56.0;
  static const ratio = 2532 / 1170;
  static Size get size => Size(
    margin * 2 + phone * _shots.length + gap * (_shots.length - 1),
    margin * 2 + phone * ratio + 56,
  );

  @override
  Widget build(BuildContext context) => SizedBox.fromSize(
    size: size,
    child: ColoredBox(
      color: KColors.blackout,
      child: Padding(
        padding: const EdgeInsets.all(margin),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < images.length; i++) ...[
              if (i > 0) const SizedBox(width: gap),
              SizedBox(
                width: phone,
                child: Column(
                  children: [
                    ClipRRect(
                      // A phone's screen corners, at this size.
                      borderRadius: BorderRadius.circular(30),
                      child: SizedBox(
                        width: phone,
                        height: phone * ratio,
                        child: RawImage(
                          image: images[i],
                          fit: BoxFit.cover,
                          alignment: Alignment.topCenter,
                          filterQuality: FilterQuality.medium,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _shots[i].$2,
                      textAlign: TextAlign.center,
                      style: KType.title.copyWith(
                        fontWeight: FontWeight.w500,
                        color: KColors.haze,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

Future<void> _render(WidgetTester tester, Widget w, Size size, String path) =>
    tester.runAsync(() async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      final key = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(key: key, child: w),
          ),
        ),
      );
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(path).writeAsBytes(bytes!.buffer.asUint8List());
    });

void main() {
  setUpAll(loadAppFonts);

  testWidgets('render the README images', (tester) async {
    addTearDown(tester.view.reset);
    Directory('../docs').createSync(); // (real I/O never ends in fake time)
    const banner = Size(1600, 480), social = Size(1280, 640);
    await _render(tester, const _Banner(banner), banner, '../docs/banner.png');
    await _render(
      tester,
      const _Banner(social),
      social,
      '../docs/social-preview.png',
    );
    final images = await tester.runAsync(
      () => Future.wait([
        for (final (file, _) in _shots)
          () async {
            final codec = await ui.instantiateImageCodec(
              await File('test/goldens/$file').readAsBytes(),
            );
            return (await codec.getNextFrame()).image;
          }(),
      ]),
    );
    await _render(
      tester,
      _Screens(images!),
      _Screens.size,
      '../docs/screens.png',
    );
    await tester.runAsync(
      () =>
          File('test/goldens/screens/desktop_home.png')
              .copy('../docs/desktop.png'),
    );
  });
}
