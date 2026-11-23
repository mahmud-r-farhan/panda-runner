import 'package:flutter/material.dart';

import 'game/neon_palette.dart';
import 'ui/game_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PandaRunnerApp());
}

class PandaRunnerApp extends StatelessWidget {
  const PandaRunnerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Panda Runner — 3D Neon Parkour',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: NeonPalette.bgDark,
        colorScheme: const ColorScheme.dark(
          primary: NeonPalette.accentOrange,
          secondary: NeonPalette.neonCyan,
          surface: NeonPalette.cardBg,
        ),
      ),
      home: const PandaRunnerGameScreen(),
    );
  }
}
