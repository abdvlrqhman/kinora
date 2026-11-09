// Kinora's glass, alone: the same settings as app/lib/ui/glass.dart over a
// busy scene, so the simulator shows whether real liquid glass draws.
import 'package:flutter/material.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

const violet = Color(0xFFB48CFF);
const lamp = Color(0xFFF5EEE4);

void main() => runApp(const ProbeApp());

class ProbeApp extends StatelessWidget {
  const ProbeApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(),
    home: const Scaffold(backgroundColor: Colors.black, body: _Scene()),
  );
}

Widget _glass({required Widget child, double? radius, EdgeInsets? padding}) =>
    LiquidGlass.auto(
      shape: LiquidRoundedSuperellipse(borderRadius: radius ?? 999),
      settings: LiquidGlassSettings.ios27RegularDark(),
      appearance: LiquidGlassAppearance.ios27RegularDark(
        tint: violet.withValues(alpha: 0.16),
      ),
      child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
    );

class _Scene extends StatelessWidget {
  const _Scene();

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      // Something to refract: color, stripes and text.
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF3B1E6E), Color(0xFFB0476B), Color(0xFFFFB35C)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),
      for (var i = 0; i < 12; i++)
        Positioned(
          left: 0,
          right: 0,
          top: 40.0 + i * 64,
          child: Container(
            height: 18,
            color: Colors.white.withValues(alpha: 0.12),
          ),
        ),
      const Center(
        child: Text(
          'Kinora',
          style: TextStyle(
            fontSize: 120,
            fontWeight: FontWeight.w900,
            color: lamp,
          ),
        ),
      ),
      LiquidGlassLayer(
        settings: LiquidGlassSettings.ios27RegularDark(),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final icon in [
                  Icons.replay_10_rounded,
                  Icons.play_arrow_rounded,
                  Icons.forward_10_rounded,
                ])
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: _glass(
                      child: SizedBox.square(
                        dimension: icon == Icons.play_arrow_rounded ? 64 : 48,
                        child: Icon(icon, color: lamp, size: 28),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 40),
            _glass(
              radius: 28,
              padding: const EdgeInsets.all(24),
              child: const SizedBox(
                width: 260,
                child: Text(
                  'Audio and subtitles',
                  style: TextStyle(fontSize: 22, color: lamp),
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
