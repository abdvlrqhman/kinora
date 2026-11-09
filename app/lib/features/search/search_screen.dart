import 'package:flutter/material.dart';

import '../../ui/tokens.dart';

// shortcut: placeholder until the screen is built.
class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(child: Text('Search', style: KType.h1)),
  );
}
