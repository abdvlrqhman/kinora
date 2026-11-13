import 'package:flutter/material.dart';

import '../trakt/trakt_ui.dart';
import 'widgets/settings_ui.dart';

/// Settings › Trakt: the same panel as Home's Trakt button.
class TraktPage extends StatelessWidget {
  const TraktPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const SettingsPage(title: 'Trakt', children: [TraktAccountPanel()]);
}
