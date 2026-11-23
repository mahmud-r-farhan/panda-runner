import 'package:flutter/material.dart';

import 'game/neon_palette.dart';
import 'ui/game_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NeonScrambleApp());
}

class NeonScrambleApp extends StatelessWidget {
  const NeonScrambleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PANDA RUNNER — 3D Neon Parkour Runner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: NeonPalette.bgDark,
        colorScheme: const ColorScheme.dark(
          primary: NeonPalette.accentOrange,
          secondary: NeonPalette.neonCyan,
          surface: NeonPalette.cardBg,
        ),
      ),
      home: const NeonScrambleGameScreen(),
    );
  }
}
