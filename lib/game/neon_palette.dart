import 'package:flutter/material.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Centralized color palette matching the Gemini Neon Scramble demo:
/// UI colors in sRGB alongside linear HDR emissive factors for Flutter Scene bloom.
abstract final class NeonPalette {
  // UI sRGB colors
  static const Color bgDark = Color(0xFF060914);
  static const Color cardBg = Color(0xE60B1020);
  static const Color cardBorder = Color(0x33FFFFFF);
  static const Color accentOrange = Color(0xFFFF5A1F);
  static const Color accentRedDot = Color(0xFFFF4522);
  static const Color pegmanYellow = Color(0xFFFBBC04);
  static const Color trailMagenta = Color(0xFFFF2A9D);
  static const Color neonCyan = Color(0xFF00E5FF);
  static const Color neonPurple = Color(0xFFA855F7);
  static const Color yamanoteGreen = Color(0xFF5CE65C);
  static const Color googleBlue = Color(0xFF4285F4);
  static const Color googleRed = Color(0xFFEA4335);
  static const Color googleYellow = Color(0xFFFBBC05);
  static const Color googleGreen = Color(0xFF34A853);
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textMuted = Color(0xFF94A3B8);

  // Linear RGBA base colors for PhysicallyBasedMaterial / UnlitMaterial
  static vm.Vector4 get asphaltBase => vm.Vector4(0.025, 0.03, 0.055, 1.0);
  static vm.Vector4 get buildingDark => vm.Vector4(0.03, 0.04, 0.08, 1.0);
  static vm.Vector4 get buildingMid => vm.Vector4(0.045, 0.055, 0.11, 1.0);
  static vm.Vector4 get pegmanBase => vm.Vector4(0.98, 0.68, 0.02, 1.0);
  static vm.Vector4 get crosswalkBase => vm.Vector4(0.85, 0.88, 0.95, 1.0);

  // Linear HDR emissive factors (> 1.0 triggers Flutter Scene bloom)
  static vm.Vector4 get emissiveZero => vm.Vector4(0.0, 0.0, 0.0, 1.0);
  static vm.Vector4 get emissivePegman => vm.Vector4(0.65, 0.42, 0.02, 1.0);
  static vm.Vector4 get emissiveMagenta => vm.Vector4(3.2, 0.18, 1.35, 1.0);
  static vm.Vector4 get emissiveCyan => vm.Vector4(0.15, 2.4, 3.0, 1.0);
  static vm.Vector4 get emissiveOrange => vm.Vector4(3.0, 0.65, 0.12, 1.0);
  static vm.Vector4 get emissivePurple => vm.Vector4(1.6, 0.35, 3.0, 1.0);
  static vm.Vector4 get emissiveYamanote => vm.Vector4(0.45, 2.8, 0.45, 1.0);
  static vm.Vector4 get emissiveRed => vm.Vector4(2.8, 0.18, 0.18, 1.0);
  static vm.Vector4 get emissiveWhiteSoft => vm.Vector4(0.65, 0.72, 0.9, 1.0);

  static List<vm.Vector4> get signEmissives => [
        emissiveCyan,
        emissiveMagenta,
        emissiveOrange,
        emissivePurple,
        emissiveYamanote,
      ];

  static List<vm.Vector4> get googleEmissives => [
        vm.Vector4(0.25, 1.2, 3.0, 1.0), // Blue
        vm.Vector4(3.0, 0.28, 0.22, 1.0), // Red
        vm.Vector4(2.8, 1.9, 0.15, 1.0), // Yellow
        vm.Vector4(0.25, 2.5, 0.65, 1.0), // Green
      ];
}
