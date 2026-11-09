import 'package:flutter/material.dart';

import '../../ui/tokens.dart';

// shortcut: placeholder until the screen is built.
class TitleScreen extends StatelessWidget {
  const TitleScreen({super.key, required this.type, required this.id});

  final String type;
  final String id;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(child: Text(id, style: KType.h1)),
  );
}
