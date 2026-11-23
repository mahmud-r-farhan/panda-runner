import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// 2D point in route/map space: `x` = meters east, `z` = meters south
/// (the web demo's right-handed three.js frame, origin at Shibuya Scramble).
class XZ {
  const XZ(this.x, this.z);
  final double x;
  final double z;
}

/// A sampled route waypoint (8 m spacing) with unit tangent.
class RouteWaypoint {
  const RouteWaypoint({
    required this.s,
    required this.x,
    required this.y,
    required this.z,
    required this.tx,
    required this.tz,
    required this.width,
    required this.surface,
  });

  final double s;
  final double x;
  final double y;
  final double z;
  final double tx;
  final double tz;
  final double width;
  final String surface;
}

/// Shibuya level data exported from the web demo's bundled OpenStreetMap
/// extract (route spline, buildings, roads, rails, props). Loaded once from
/// `assets/data/shibuya_level.json`.
class ShibuyaLevel {
  ShibuyaLevel._(this.raw);

  final Map<String, dynamic> raw;

  static Future<ShibuyaLevel> load() async {
    final text = await rootBundle.loadString('assets/data/shibuya_level.json');
    return ShibuyaLevel._(jsonDecode(text) as Map<String, dynamic>);
  }

  Map<String, dynamic> get route => raw['route'] as Map<String, dynamic>;
  Map<String, dynamic> get overview => raw['overview'] as Map<String, dynamic>;
  Map<String, dynamic> get minimap => raw['minimap'] as Map<String, dynamic>;
  Map<String, dynamic> get meta => raw['meta'] as Map<String, dynamic>;
  Map<String, dynamic> get streets => raw['streets'] as Map<String, dynamic>;
  List<dynamic> get buildings => raw['buildings'] as List<dynamic>;

  double get routeLength => (route['length'] as num).toDouble();

  late final List<RouteWaypoint> waypoints = [
    for (final w in route['waypoints'] as List<dynamic>)
      RouteWaypoint(
        s: _d(w['s']),
        x: _d(w['x']),
        y: _d(w['y']),
        z: _d(w['z']),
        tx: _d(w['tx']),
        tz: _d(w['tz']),
        width: _d(w['width']),
        surface: (w['surface'] ?? 'street') as String,
      ),
  ];

  static double _d(dynamic v) => (v as num?)?.toDouble() ?? 0.0;

  /// Converts `[[x, z], ...]` JSON into points.
  static List<XZ> pts(dynamic list) => [
        for (final p in list as List<dynamic>)
          XZ((p[0] as num).toDouble(), (p[1] as num).toDouble()),
      ];

  /// Converts a list of polylines `[[[x, z], ...], ...]`.
  static List<List<XZ>> lines(dynamic list) => [
        if (list != null)
          for (final l in list as List<dynamic>)
            pts(l is Map ? l['points'] : l),
      ];
}
