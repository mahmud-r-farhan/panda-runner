import 'package:flutter/material.dart';
import 'package:vector_math/vector_math.dart' as vm;

enum MapLocationId { shibuya, bambooForest, cyberCircuit }

/// A sky mood / colour grade for the shared Shibuya route.
///
/// The level geometry (scramble crossing, Yamanote viaduct, Shibuya Stream)
/// is identical for every entry; switching a location re-grades the sky,
/// environment map and accent palette, which changes the look of the whole
/// run without a separate level download.
class MapLocation {
  const MapLocation({
    required this.id,
    required this.name,
    required this.nameJa,
    required this.shortName,
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

  /// Compact label used by the title-card selector pills.
  final String shortName;
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

  /// Tokyo Shibuya Scramble (the original cyberpunk neon grade).
  static const shibuya = MapLocation(
    id: MapLocationId.shibuya,
    name: 'Neon Night',
    nameJa: '渋谷ナイト',
    shortName: 'Neon',
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
    description: 'Cyan + orange night grade · 3-lane scramble · Yamanote viaduct',
  );

  /// Emerald dawn grade (serene jade light over the same Shibuya route).
  static const bambooForest = MapLocation(
    id: MapLocationId.bambooForest,
    name: 'Jade Dawn',
    nameJa: '翡翠の夜明け',
    shortName: 'Jade',
    subtitle: 'Shibuya Crossing → Google Tokyo',
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
    description: 'Emerald dawn grade · jade sky · golden lantern accents',
  );

  /// Ultraviolet grade (magenta voltage over the same Shibuya route).
  static const cyberCircuit = MapLocation(
    id: MapLocationId.cyberCircuit,
    name: 'Ultraviolet',
    nameJa: '紫電の街',
    shortName: 'Ultra',
    subtitle: 'Shibuya Crossing → Google Tokyo',
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
    description: 'Ultraviolet grade · magenta sky · high-voltage neon cyan',
  );

  static const List<MapLocation> all = [shibuya, bambooForest, cyberCircuit];

  static MapLocation byId(MapLocationId id) =>
      all.firstWhere((loc) => loc.id == id, orElse: () => shibuya);
}
