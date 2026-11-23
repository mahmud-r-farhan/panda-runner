import 'package:flutter/material.dart';
import 'package:vector_math/vector_math.dart' as vm;

enum MapLocationId { shibuya, bambooForest, cyberCircuit }

/// Represents a distinct playable map environment with custom skybox,
/// lighting palette, street labels, and thematic accents.
class MapLocation {
  const MapLocation({
    required this.id,
    required this.name,
    required this.nameJa,
    required this.subtitle,
    required this.emoji,
    required this.accentColor,
    required this.secondaryColor,
    required this.zenithRgb,
    required this.horizonRgb,
    required this.groundRgb,
    required this.startStreetJa,
    required this.startStreetEn,
    required this.destinationJa,
    required this.destinationEn,
    required this.description,
  });

  final MapLocationId id;
  final String name;
  final String nameJa;
  final String subtitle;
  final String emoji;
  final Color accentColor;
  final Color secondaryColor;
  final List<double> zenithRgb;
  final List<double> horizonRgb;
  final List<double> groundRgb;
  final String startStreetJa;
  final String startStreetEn;
  final String destinationJa;
  final String destinationEn;
  final String description;

  vm.Vector3 get skyZenith => vm.Vector3(zenithRgb[0], zenithRgb[1], zenithRgb[2]);
  vm.Vector3 get skyHorizon => vm.Vector3(horizonRgb[0], horizonRgb[1], horizonRgb[2]);
  vm.Vector3 get skyGround => vm.Vector3(groundRgb[0], groundRgb[1], groundRgb[2]);

  /// Tokyo Shibuya Scramble (The original cyberpunk neon metropolis).
  static const shibuya = MapLocation(
    id: MapLocationId.shibuya,
    name: 'Shibuya Neon Scramble',
    nameJa: '渋谷スクランブル',
    subtitle: 'Shibuya Crossing → Google Tokyo',
    emoji: '🏮',
    accentColor: Color(0xFFFF4F00),
    secondaryColor: Color(0xFF38BDF8),
    zenithRgb: [0.0085, 0.0220, 0.0680],
    horizonRgb: [0.0520, 0.1220, 0.2960],
    groundRgb: [0.0055, 0.0095, 0.0220],
    startStreetJa: '渋谷スクランブル',
    startStreetEn: 'Scramble',
    destinationJa: '渋谷ストリーム · Google Tokyo',
    destinationEn: 'Google Tokyo',
    description: 'Neon metropolis · 3-lane scramble · Yamanote Line viaduct',
  );

  /// Kyoto Bamboo Forest & Torii Gates (Serene bamboo forest & golden lanterns).
  static const bambooForest = MapLocation(
    id: MapLocationId.bambooForest,
    name: 'Kyoto Bamboo Temple',
    nameJa: '嵐山竹林街道',
    subtitle: 'Bamboo Grove → Golden Sanctuary',
    emoji: '🎋',
    accentColor: Color(0xFF10B981),
    secondaryColor: Color(0xFFF59E0B),
    zenithRgb: [0.006, 0.048, 0.028],
    horizonRgb: [0.032, 0.185, 0.095],
    groundRgb: [0.012, 0.062, 0.028],
    startStreetJa: '嵐山竹林',
    startStreetEn: 'Bamboo Grove',
    destinationJa: '金閣寺高台 · Golden Sanctuary',
    destinationEn: 'Golden Sanctuary',
    description: 'Emerald bamboo paths · Glowing torii arches · Sacred river bridge',
  );

  /// Akihabara Electric Cyberway (Ultra-violet highway & laser grids).
  static const cyberCircuit = MapLocation(
    id: MapLocationId.cyberCircuit,
    name: 'Akihabara Cyberway',
    nameJa: '秋葉原電脳街',
    subtitle: 'Electric City → Core Network Tower',
    emoji: '⚡',
    accentColor: Color(0xFFD946EF),
    secondaryColor: Color(0xFF06B6D4),
    zenithRgb: [0.038, 0.009, 0.072],
    horizonRgb: [0.175, 0.045, 0.295],
    groundRgb: [0.022, 0.006, 0.035],
    startStreetJa: '電脳大通り',
    startStreetEn: 'Cyberway',
    destinationJa: '電波タワー · Core Tower',
    destinationEn: 'Core Tower',
    description: 'Ultra-violet speedway · Hologram billboards · High-voltage grid',
  );

  static const List<MapLocation> all = [shibuya, bambooForest, cyberCircuit];

  static MapLocation byId(MapLocationId id) =>
      all.firstWhere((loc) => loc.id == id, orElse: () => shibuya);
}
