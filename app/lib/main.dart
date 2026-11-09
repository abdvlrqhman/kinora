import 'package:flutter/material.dart';

import 'shell.dart';

void main() => runApp(const KinoraApp());

class KinoraApp extends StatelessWidget {
  const KinoraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kinora',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF7C9CFF),
        scaffoldBackgroundColor: const Color(0xFF07080C),
      ),
      home: const RootShell(),
    );
  }
}
