import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../ui/tokens.dart';

/// Sub-pages of Settings (filled in by the settings feature).
final List<RouteBase> settingsRoutes = [];

// shortcut: placeholder until the screen is built.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(child: Text('Settings', style: KType.h1)),
  );
}
