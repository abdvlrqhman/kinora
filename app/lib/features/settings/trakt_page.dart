import 'package:flutter/material.dart';

import '../../ui/tokens.dart';
import '../trakt/trakt_ui.dart';
import 'widgets/settings_ui.dart';

/// Settings › Trakt: the same panel as Home's Trakt button.
class TraktPage extends StatelessWidget {
  const TraktPage({super.key});

  @override
  Widget build(BuildContext context) => const SettingsPage(
    title: 'Trakt',
    children: [
      TraktAccountPanel(),
      // Trakt's API Use Policy asks every app to carry this line.
      Note(
        'Kinora uses Trakt but is not endorsed or certified by Trakt.',
        top: KSpace.x3,
        color: KColors.muted,
      ),
    ],
  );
}
