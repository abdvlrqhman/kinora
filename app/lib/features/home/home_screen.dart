import 'package:flutter/material.dart';

import '../../ui/tokens.dart';

// shortcut: placeholder until the screen is built.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(child: Text('Home', style: KType.h1)),
  );
}
