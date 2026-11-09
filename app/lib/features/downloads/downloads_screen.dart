import 'package:flutter/material.dart';

import '../../ui/tokens.dart';

// shortcut: placeholder until the screen is built.
class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(child: Text('Downloads', style: KType.h1)),
  );
}
