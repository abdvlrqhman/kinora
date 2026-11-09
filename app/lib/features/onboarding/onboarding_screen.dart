import 'package:flutter/material.dart';

import '../../ui/tokens.dart';

// shortcut: placeholder until the screen is built.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(child: Text('Welcome', style: KType.h1)),
  );
}
