import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../game/level_data.dart';
import 'ui_tokens.dart';

/// Full-screen dark-mode Shibuya map shown behind the title card.
///
/// A port of the web demo's `Bg()` "DarkModeGoogleMapsGround" texture
/// (a 4096px canvas spanning the 940 m × 900 m overview bounds) seen from the
/// top-down title camera, plus the animated transit/route light streaks and
/// pulsing start / Google beacon rings of the title scene.
class ShibuyaMapView extends StatelessWidget {
  const ShibuyaMapView({super.key, required this.level, required this.time});

  final ShibuyaLevel level;
  final double time;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _ShibuyaMapPainter(_MapCache.of(level), time),
        size: Size.infinite,
      ),
    );
  }
}

const double _tex = 4096;

/// Static data + recorded picture of the map texture (built once per level).
class _MapCache {
  _MapCache._(this.level) {
    final b = level.overview['bounds'] as Map<String, dynamic>;
    minX = (b['minX'] as num).toDouble();
    maxX = (b['maxX'] as num).toDouble();
    minZ = (b['minZ'] as num).toDouble();
    maxZ = (b['maxZ'] as num).toDouble();
    _buildStreaks();
    picture = _recordTexture();
  }

  static final Map<ShibuyaLevel, _MapCache> _cache = {};
  static _MapCache of(ShibuyaLevel level) =>
      _cache.putIfAbsent(level, () => _MapCache._(level));

  final ShibuyaLevel level;
  late final double minX, maxX, minZ, maxZ;
  late final ui.Picture picture;
  final List<_Streak> streaks = [];

  double get spanX => maxX - minX;
  double get spanZ => maxZ - minZ;
  double d(double x) => (x - minX) / spanX * _tex;
  double f(double z) => (z - minZ) / spanZ * _tex;
  Offset p(XZ q) => Offset(d(q.x), f(q.z));

  List<List<XZ>> get routeLines => [
        [for (final w in level.waypoints) XZ(w.x, w.z)],
      ];

  void _buildStreaks() {
    final rails = level.overview['rails'] as Map<String, dynamic>;
    void add(List<List<XZ>> lines, Color c, double speed, double width,
        int perLine, double minLen) {
      var seed = 0;
      for (final l in lines) {
        final poly = _Poly(l.map(p).toList());
        if (poly.length < minLen) continue;
        for (int i = 0; i < perLine; i++) {
          seed++;
          streaks.add(_Streak(
            poly,
            c,
            speed * (0.85 + 0.3 * ((seed * 37) % 11) / 10),
            width,
            (seed * 0.618 + i / perLine) % 1.0,
          ));
        }
      }
    }

    add(ShibuyaLevel.lines(rails['metro']), const Color(0xFFD8C8FF), 520, 14,
        2, 500);
    add(ShibuyaLevel.lines(rails['inokashira']), const Color(0xFFD6F3FF), 520,
        14, 2, 300);
    add(ShibuyaLevel.lines(rails['ginza']), const Color(0xFFFFEBC2), 520, 14,
        2, 300);
    add(ShibuyaLevel.lines(rails['yamanote']), const Color(0xFFD9FFE3), 560,
        14, 2, 500);
    add(routeLines, const Color(0xFFFFFFFF), 640, 22, 10, 100);
  }

  // ---------------------------------------------------------------------
  // Texture (port of Bg()).
  // ---------------------------------------------------------------------

  ui.Picture _recordTexture() {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    final ov = level.overview;

    void stroke(List<List<XZ>> lines, Color color, double w,
        [List<double>? dash]) {
      if (lines.isEmpty) return;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..color = color
        ..strokeWidth = w
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final path = Path();
      for (final l in lines) {
        if (l.length < 2) continue;
        path.moveTo(d(l[0].x), f(l[0].z));
        for (int i = 1; i < l.length; i++) {
          path.lineTo(d(l[i].x), f(l[i].z));
        }
      }
      c.drawPath(dash == null ? path : _dashPath(path, dash), paint);
    }

    Path poly(List<XZ> pts) {
      final path = Path()..moveTo(d(pts[0].x), f(pts[0].z));
      for (int i = 1; i < pts.length; i++) {
        path.lineTo(d(pts[i].x), f(pts[i].z));
      }
      return path..close();
    }

    // Base + grid.
    c.drawRect(const Rect.fromLTWH(0, 0, _tex, _tex),
        Paint()..color = const Color(0xFF171E29));
    final grid = Paint()
      ..color = const Color.fromRGBO(138, 180, 248, 0.045)
      ..strokeWidth = 2;
    for (int i = 0; i <= 20; i++) {
      final t = i / 20 * _tex;
      c.drawLine(Offset(t, 0), Offset(t, _tex), grid);
      c.drawLine(Offset(0, t), Offset(_tex, t), grid);
    }

    // Parks.
    for (final pk in ov['parks'] as List<dynamic>) {
      final pts = ShibuyaLevel.pts(pk['points']);
      if (pts.length < 3) continue;
      final path = poly(pts);
      c.drawPath(path, Paint()..color = const Color(0xFF1B3B2B));
      c.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4
            ..color = const Color(0xFF2A5E44));
      double cx = 0, cy = 0;
      for (final q in pts) {
        cx += d(q.x);
        cy += f(q.z);
      }
      cx /= pts.length;
      cy /= pts.length;
      for (int e = -2; e <= 2; e++) {
        c.drawCircle(Offset(cx + e * 14, cy + ((e * 19) % 24)), 7,
            Paint()..color = const Color.fromRGBO(52, 168, 83, 0.34));
      }
    }

    // River.
    final river = ShibuyaLevel.pts((ov['river'] as Map)['points']);
    if (river.length >= 2) {
      stroke([river], const Color(0xFF1A3A63), 52);
      stroke([river], const Color(0xFF26538A), 28);
    }

    // Station platforms.
    for (final st in ov['stations'] as List<dynamic>) {
      final pts = ShibuyaLevel.pts(st['points']);
      if (pts.length < 3) continue;
      final path = poly(pts);
      c.drawPath(path, Paint()..color = const Color(0xFF222D3D));
      c.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = const Color(0xFF364963));
    }

    // Buildings.
    final bFill = Paint()..color = const Color(0xFF1E2736);
    final bStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFF2A374C);
    for (final b in ov['buildings'] as List<dynamic>) {
      final pts = ShibuyaLevel.pts(b);
      if (pts.length < 3) continue;
      final path = poly(pts);
      c.drawPath(path, bFill);
      c.drawPath(path, bStroke);
    }
    for (final b in level.buildings) {
      if (b['isGoogleHero'] != true) continue;
      final pts = ShibuyaLevel.pts(b['footprint']);
      if (pts.length < 3) continue;
      final path = poly(pts);
      c.drawPath(path, Paint()..color = const Color(0xFF223E6E));
      c.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 6
            ..color = const Color(0xFF60A5FA));
    }

    // Roads.
    final roads = ov['roads'] as Map<String, dynamic>;
    final ped = ShibuyaLevel.lines(roads['pedestrian']);
    final local = ShibuyaLevel.lines(roads['local']);
    final secondary = ShibuyaLevel.lines(roads['secondary']);
    final arterial = ShibuyaLevel.lines(roads['arterial']);
    final expressway = ShibuyaLevel.lines(roads['expressway']);
    stroke(ped, const Color(0xFF202A3A), 7);
    stroke(local, const Color(0xFF1D2634), 18);
    stroke(local, const Color(0xFF283447), 12);
    stroke(secondary, const Color(0xFF263348), 30);
    stroke(secondary, const Color(0xFF384862), 21);
    stroke(arterial, const Color(0xFF2B364A), 42);
    stroke(arterial, const Color(0xFF445572), 31);

    // Scramble plaza + crosswalk stripes.
    final scramble = ShibuyaLevel.pts(level.streets['scramblePolygon']);
    if (scramble.length >= 3) {
      c.drawPath(poly(scramble), Paint()..color = const Color(0xFF3E4E68));
    }
    final cws = (ov['crosswalks'] as List<dynamic>?) ??
        (level.streets['crosswalks'] as List<dynamic>);
    for (final cw in cws) {
      final s0 = cw['start'] as List<dynamic>, s1 = cw['end'] as List<dynamic>;
      final i0 = d((s0[0] as num).toDouble()), a0 = f((s0[1] as num).toDouble());
      final i1 = d((s1[0] as num).toDouble()), a1 = f((s1[1] as num).toDouble());
      final px = i1 - i0, my = a1 - a0, h = math.sqrt(px * px + my * my);
      if (h < 6) continue;
      final g = px / h, nx = -(my / h), ny = g;
      final y = ((cw['width'] as num?)?.toDouble() ?? 9) / spanX * _tex * 0.48;
      final x = ((cw['stripeCount'] as num?)?.toDouble() ?? 12).clamp(8, 18).toInt();
      final paint = Paint()
        ..color = const Color.fromRGBO(226, 236, 248, 0.85)
        ..strokeWidth = math.max(3, h / x * 0.45);
      for (int e = 0; e < x; e++) {
        final t = (e + 0.5) / x;
        final cx = i0 + px * t, cy = a0 + my * t;
        c.drawLine(Offset(cx - nx * y, cy - ny * y),
            Offset(cx + nx * y, cy + ny * y), paint);
      }
    }

    stroke(expressway, const Color(0xFF4A3B1E), 52);
    stroke(expressway, const Color(0xFF8E6E2B), 34);
    stroke(expressway, const Color(0xFFC59F47), 4, [24, 20]);

    final rails = ov['rails'] as Map<String, dynamic>;
    final yamanote = ShibuyaLevel.lines(rails['yamanote']);
    stroke(ShibuyaLevel.lines(rails['metro']), const Color(0xFF8B5CF6), 8,
        [16, 12]);
    stroke(ShibuyaLevel.lines(rails['inokashira']), const Color(0xFF38BDF8), 9,
        [20, 12]);
    stroke(ShibuyaLevel.lines(rails['ginza']), const Color(0xFFF59E0B), 10,
        [22, 12]);
    stroke(yamanote, const Color(0xFF173D24), 18);
    stroke(yamanote, const Color(0xFF34A853), 11, [26, 12]);

    stroke(arterial, const Color.fromRGBO(56, 189, 248, 0.20), 22);
    stroke(secondary, const Color.fromRGBO(56, 189, 248, 0.14), 12);
    final route = routeLines;
    stroke(route, const Color.fromRGBO(56, 189, 248, 0.34), 56);
    stroke(route, const Color.fromRGBO(255, 255, 255, 0.88), 28);
    stroke(route, const Color(0xFF4285F4), 20);
    stroke(route, const Color(0xFF93C5FD), 6);

    final beacon = _finalBeacon;
    final bt = Offset(d(beacon.x), f(beacon.z));
    c.drawCircle(bt, 42, Paint()..color = const Color.fromRGBO(66, 133, 244, 0.25));
    c.drawCircle(bt, 22, Paint()..color = const Color(0xFFEA4335));
    c.drawCircle(
        bt,
        22,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..color = Colors.white);

    _Labels(this, c, expressway, yamanote, bt).paint();
    return rec.endRecording();
  }

  XZ get _finalBeacon {
    final fb = level.route['finalBeacon'] as Map<String, dynamic>?;
    final pos = fb?['pos'] as List<dynamic>?;
    if (pos == null) return const XZ(242.89, 257.3);
    return XZ((pos[0] as num).toDouble(), (pos[2] as num).toDouble());
  }
}

/// Map label placement (simplified port of Bg()'s collision-aware labeler).
class _Labels {
  _Labels(this.m, this.c, List<List<XZ>> expressway, List<List<XZ>> yamanote,
      this.beacon) {
    for (final l in expressway) {
      for (int i = 0; i < l.length - 1; i++) {
        _expSegs.add([l[i].x, l[i].z, l[i + 1].x, l[i + 1].z]);
      }
    }
    for (final l in yamanote) {
      for (int i = 0; i < l.length - 1; i++) {
        _yamSegs.add([l[i].x, l[i].z, l[i + 1].x, l[i + 1].z]);
      }
    }
  }

  final _MapCache m;
  final Canvas c;
  final Offset beacon;
  final List<List<double>> _expSegs = [];
  final List<List<double>> _yamSegs = [];
  final List<List<Offset>> _placed = [];
  final List<List<Offset>> _routeBoxes = [];

  double get dX => _tex / m.spanX;
  double get dZ => _tex / m.spanZ;
  double k(double px) => m.minX + px / _tex * m.spanX;
  double a(double py) => m.minZ + py / _tex * m.spanZ;

  /// Northern edge (max z) of the expressway at world x.
  double expZ(double x) {
    double best = double.negativeInfinity;
    for (final r in _expSegs) {
      final lo = math.min(r[0], r[2]), hi = math.max(r[0], r[2]);
      if (x >= lo - 2 && x <= hi + 2 && (r[2] - r[0]).abs() > .001) {
        final t = ((x - r[0]) / (r[2] - r[0])).clamp(0.0, 1.0);
        final z = r[1] + (r[3] - r[1]) * t;
        if (z > best) best = z;
      }
    }
    return best.isFinite ? best : 259 - x * .4;
  }

  double expDist(double x, double z) {
    double best = double.infinity;
    for (final r in _expSegs) {
      final ax = r[2] - r[0], az = r[3] - r[1], l2 = ax * ax + az * az;
      final t = l2 > 1e-6
          ? (((x - r[0]) * ax + (z - r[1]) * az) / l2).clamp(0.0, 1.0)
          : 0.0;
      final px = r[0] + t * ax, pz = r[1] + t * az;
      final dd = (x - px) * (x - px) + (z - pz) * (z - pz);
      if (dd < best) best = dd;
    }
    return math.sqrt(best);
  }

  /// Western x of the Yamanote line at world z.
  double yamX(double z) {
    double best = double.infinity;
    for (final r in _yamSegs) {
      final lo = math.min(r[1], r[3]), hi = math.max(r[1], r[3]);
      if (z >= lo - 2 && z <= hi + 2 && (r[3] - r[1]).abs() > .001) {
        final t = ((z - r[1]) / (r[3] - r[1])).clamp(0.0, 1.0);
        final x = r[0] + (r[2] - r[0]) * t;
        if (x < best) best = x;
      }
    }
    return best.isFinite ? best : 154;
  }

  static List<Offset> rect(double x0, double y0, double x1, double y1) =>
      [Offset(x0, y0), Offset(x1, y0), Offset(x1, y1), Offset(x0, y1)];

  void reserve(double x0, double y0, double x1, double y1) =>
      _placed.add(rect(x0, y0, x1, y1));

  late final double pe = m.d(-416.5), me = m.d(516.5);
  late final double fTop = m.f(-148.4), he = m.f(376.4);

  bool nearViewEdge(List<Offset> q) {
    final r = _bounds(q);
    if (!(r.right > pe && r.left < me) || !(r.bottom > fTop && r.top < he)) {
      return false;
    }
    return r.left < pe + 32 ||
        r.right > me - 32 ||
        r.top < fTop + 32 ||
        r.bottom > he - 32;
  }

  bool collides(List<Offset> q, double gap, bool avoidRoute) {
    if (nearViewEdge(q)) return true;
    for (final o in _placed) {
      if (_satOverlap(q, o, gap)) return true;
    }
    if (avoidRoute) {
      for (final o in _routeBoxes) {
        if (_satOverlap(q, o, 4)) return true;
      }
    }
    return false;
  }

  void paint() {
    final route = m.level.waypoints;
    final start = route.isNotEmpty ? route.first : null;
    final se = m.d(start?.x ?? -48), ce = m.f(start?.z ?? -5.2);
    reserve(se - 92, ce - 92, se + 92, ce + 92);
    reserve(beacon.dx - 108, beacon.dy - 108, beacon.dx + 108, beacon.dy + 108);
    reserve(m.d(-22), m.f(-22), m.d(36), m.f(22));
    reserve(m.d(-144), m.f(251), m.d(244), m.f(368));
    reserve(m.d(-412), m.f(336), m.d(-238), m.f(376));
    final districtAvoid = rect(m.d(-302), m.f(-148), m.d(-124), m.f(-112));
    for (int e = 0; e < route.length - 1; e++) {
      final t = route[e], n = route[e + 1];
      final rx = n.x - t.x, rz = n.z - t.z;
      final steps = math.max(1, (math.sqrt(rx * rx + rz * rz) / 14).ceil());
      for (int i = 0; i <= steps; i++) {
        final u = i / steps;
        final o = m.d(t.x + rx * u), s = m.f(t.z + rz * u);
        _routeBoxes.add(rect(o - 28, s - 28, o + 28, s + 28));
      }
    }

    final ring = <Offset>[Offset.zero];
    for (final r in [56, 108, 160, 215, 275, 340, 368, 410, 480]) {
      for (int t = 0; t < 16; t++) {
        final ang = t / 16 * math.pi * 2;
        ring.add(Offset((math.cos(ang) * r).roundToDouble(),
            (math.sin(ang) * r).roundToDouble()));
      }
    }
    final grid = <List<double>>[];
    for (double e = -340; e <= 220; e += 28) {
      for (double t = -280; t <= 340; t += 36) {
        grid.add([t, e, t * t + e * e]);
      }
    }
    grid.sort((x, y) => x[2].compareTo(y[2]));

    final labels = List<Map<String, dynamic>>.from(
        (m.level.overview['labels'] as List<dynamic>).cast());
    labels.sort((x, y) =>
        ((x['priority'] as num?) ?? 99).compareTo((y['priority'] as num?) ?? 99));

    for (final t in labels) {
      final text = (t['label'] ?? t['shortLabel']) as String?;
      if (text == null || text.isEmpty) continue;
      final kind = t['kind'] as String? ?? '';
      final r = m.d((t['x'] as num).toDouble());
      final i = m.f((t['z'] as num).toDouble());
      final isDistrict = kind == 'district';
      final isPill =
          kind == 'landmark' || kind == 'google_hq' || kind == 'station';
      final isTransit = kind == 'transit';
      final isExpy = kind == 'expressway';
      final angle = (t['angleRad'] as num?)?.toDouble() ?? 0;
      final rotated = !isPill && !isDistrict && kind != 'park' && angle.abs() > .02;
      var rot = rotated
          ? math.atan2(math.sin(angle) * dZ, math.cos(angle) * dX)
          : 0.0;
      while (rot > math.pi * .5) {
        rot -= math.pi;
      }
      while (rot < -math.pi * .5) {
        rot += math.pi;
      }
      final h = isPill
          ? 34.0
          : isDistrict
              ? 27.0
              : isExpy
                  ? 25.0
                  : isTransit
                      ? 26.0
                      : 25.0;
      final weight = isPill ? FontWeight.w800 : FontWeight.w700;
      final tw = _measure(text, h, weight).ceilToDouble();
      final color = _hex(t['color'] as String? ?? '#8AB4F8');
      final shield = (t['shield'] as String?)?.trim().toUpperCase();
      final hasShield = shield != null && shield.isNotEmpty;

      if (isPill) {
        final w = tw + 54, hh = h + 24;
        final landmarkish = kind == 'google_hq' || kind == 'landmark';
        Offset? at;
        for (final strict in [true, false]) {
          for (final o in ring) {
            final cx = r + o.dx, cy = i + o.dy;
            final q = rect(cx - w * .5, cy - hh * .5, cx + w * .5, cy + hh * .5);
            if (collides(q, 8, true)) continue;
            if (strict && landmarkish) {
              final n = k(cx - w * .45), mid = k(cx), e = k(cx + w * .45);
              final az = a(cy);
              if (expDist(n, az) < 16 || expDist(mid, az) < 16 ||
                  expDist(e, az) < 16 ||
                  (kind == 'google_hq' && (n < yamX(az) + 32 || e > 396))) {
                continue;
              }
            }
            at = Offset(cx, cy);
            break;
          }
          if (at != null) break;
        }
        if (at == null) continue;
        final left = at.dx - w * .5, top = at.dy - hh * .5;
        reserve(left, top, left + w, top + hh);
        final rr = RRect.fromRectAndRadius(
            Rect.fromLTWH(left, top, w, hh), Radius.circular(hh * .5));
        c.drawRRect(rr, Paint()..color = const Color.fromRGBO(11, 18, 32, 0.92));
        c.drawRRect(
            rr,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 4
              ..color = color);
        c.drawCircle(Offset(left + 23, at.dy), 8.2, Paint()..color = color);
        _text(text, Offset(left + 40, at.dy + 1), h, weight,
            const Color(0xFFF8FAFC), align: TextAlign.left);
      } else if (isDistrict) {
        final w = tw + 18, hh = h + 12;
        final ox = w * .5 / dX, oz = hh * .5 / dZ;
        final southOfExpy = (t['z'] as num).toDouble() >
            expZ((t['x'] as num).toDouble()) + 4;
        Offset? at;
        for (final strict in [true, false]) {
          for (final g in grid) {
            final cx = r + g[0], cy = i + g[1];
            final mx = k(cx), mz = a(cy);
            if (southOfExpy) {
              final top = mz - oz, x0 = mx - ox, x1 = mx + ox;
              final yx = yamX(mz);
              if (x1 > (strict ? yx - 5.5 : 168)) continue;
              if (top < expZ(x0) + 6.2 ||
                  top < expZ(mx) + 6.2 ||
                  top < expZ(x1) + 6.2) {
                continue;
              }
            }
            final q = rect(cx - w * .5, cy - hh * .5, cx + w * .5, cy + hh * .5);
            if (strict && _satOverlap(q, districtAvoid, 4)) continue;
            if (collides(q, 6, true)) continue;
            at = Offset(cx, cy);
            break;
          }
          if (at != null) break;
        }
        if (at == null) continue;
        reserve(at.dx - w * .5, at.dy - hh * .5, at.dx + w * .5, at.dy + hh * .5);
        _outlined(text, at, h, weight, const Color.fromRGBO(164, 184, 210, 0.78));
      } else if (rotated) {
        final plainTransit = isTransit && !hasShield;
        final shieldBox = hasShield ? (shield == 'LOOP' ? 36.0 : 38.0) : 0.0;
        final shieldW = hasShield ? (shield == 'LOOP' ? 56.0 : 48.0) : 0.0;
        final shieldGap = hasShield ? 10.0 : 0.0;
        final w = (hasShield ? shieldW + shieldGap : plainTransit ? 24 : 0) +
            tw +
            14;
        final hh = math.max(h + 10, hasShield ? shieldBox + 4 : h + 10);
        final l = w * .5, dd = hh * .5;
        final fx = math.cos(rot), fy = math.sin(rot), nx = -fy, ny = fx;
        final along = isExpy
            ? [0, -140, -260, -380, -450, -500, -560, 140, 260, -640]
            : [0, 48, -48, 96, -96, 148, -148, 200, -200, 260, -260];
        final across = isExpy
            ? [0, -20, 20, -38, 38]
            : plainTransit
                ? [-26, 26, -42, 42, 0, -60, 60]
                : [0, 34, -34, 54, -54, 72, -72];
        Offset? at;
        List<Offset>? box;
        for (final avoidRoute in [true, false]) {
          for (final tt in across) {
            for (final n in along) {
              final cx = r + fx * n + nx * tt, cy = i + fy * n + ny * tt;
              final q = _obb(cx, cy, fx, fy, nx, ny, l, dd);
              if (!collides(q, avoidRoute ? 6 : 5, avoidRoute)) {
                at = Offset(cx, cy);
                box = q;
                break;
              }
            }
            if (at != null) break;
          }
          if (at != null) break;
        }
        if (at == null || box == null) continue;
        _placed.add(box);
        final txtColor = isExpy
            ? const Color(0xFFFCD34D)
            : isTransit
                ? color
                : kind == 'water'
                    ? const Color(0xFF7DD3FC)
                    : kind == 'park'
                        ? const Color(0xFF6EE7B7)
                        : const Color(0xFFDCE6F4);
        c.save();
        c.translate(at.dx, at.dy);
        c.rotate(rot);
        final m0 = -w * .5 + 7;
        if (hasShield) {
          _shield(shield, Offset(m0 + shieldW * .5, 0), shieldBox);
          _outlined(text, Offset(m0 + shieldW + shieldGap, 0), h, weight,
              txtColor,
              align: TextAlign.left);
        } else if (plainTransit) {
          c.drawCircle(Offset(m0 + 8, 0), 7.5, Paint()..color = color);
          c.drawCircle(
              Offset(m0 + 8, 0),
              7.5,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 3
                ..color = const Color(0xFF0B1220));
          _outlined(text, Offset(m0 + 22, 0), h, weight, txtColor,
              align: TextAlign.left);
        } else {
          _outlined(text, Offset.zero, h, weight, txtColor);
        }
        c.restore();
      } else {
        final w = tw + 18, hh = h + 12;
        Offset? at;
        for (final o in ring) {
          final cx = r + o.dx, cy = i + o.dy;
          if (!collides(
              rect(cx - w * .5, cy - hh * .5, cx + w * .5, cy + hh * .5), 6, true)) {
            at = Offset(cx, cy);
            break;
          }
        }
        if (at == null) continue;
        reserve(at.dx - w * .5, at.dy - hh * .5, at.dx + w * .5, at.dy + hh * .5);
        final col = isExpy
            ? const Color(0xFFFCD34D)
            : kind == 'park'
                ? const Color(0xFF6EE7B7)
                : kind == 'water'
                    ? const Color(0xFF7DD3FC)
                    : const Color(0xFFCBD5E1);
        _outlined(text, at, h, weight, col);
      }
    }
  }

  static List<Offset> _obb(double cx, double cy, double fx, double fy,
      double nx, double ny, double l, double d) {
    return [
      Offset(cx - fx * l - nx * d, cy - fy * l - ny * d),
      Offset(cx + fx * l - nx * d, cy + fy * l - ny * d),
      Offset(cx + fx * l + nx * d, cy + fy * l + ny * d),
      Offset(cx - fx * l + nx * d, cy - fy * l + ny * d),
    ];
  }

  TextPainter _tp(String text, double size, FontWeight w, Paint? fg,
      Color? color) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: Ui.fontUi,
          fontFamilyFallback: Ui.fontFallback,
          fontSize: size,
          fontWeight: w,
          color: fg == null ? color : null,
          foreground: fg,
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  double _measure(String text, double size, FontWeight w) =>
      _tp(text, size, w, null, Colors.white).width;

  void _text(String text, Offset at, double size, FontWeight w, Color color,
      {TextAlign align = TextAlign.center}) {
    final tp = _tp(text, size, w, null, color);
    final dx = align == TextAlign.left ? 0.0 : -tp.width / 2;
    tp.paint(c, at + Offset(dx, -tp.height / 2));
  }

  /// `ve()`: dark 9px outline then fill.
  void _outlined(String text, Offset at, double size, FontWeight w, Color color,
      {TextAlign align = TextAlign.center}) {
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeJoin = StrokeJoin.round
      ..color = const Color.fromRGBO(11, 18, 32, 0.94);
    final tpo = _tp(text, size, w, outline, null);
    final dx = align == TextAlign.left ? 0.0 : -tpo.width / 2;
    tpo.paint(c, at + Offset(dx, -tpo.height / 2));
    _text(text, at, size, w, color, align: align);
  }

  /// Route shields (`Dg()` + the expressway "3" variant).
  void _shield(String s, Offset at, double size) {
    c.save();
    c.translate(at.dx, at.dy);
    final white = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white;
    void label(String t, double fs, Color col, [double dy = 1]) {
      final tp = _tp(t, fs, FontWeight.w900, null, col);
      tp.paint(c, Offset(-tp.width / 2, dy - tp.height / 2));
    }

    if (s == '3') {
      final e = size * .46;
      final rr = RRect.fromRectAndRadius(
          Rect.fromLTRB(-e, -e, e, e), Radius.circular(size * .18));
      c.drawRRect(rr, Paint()..color = const Color(0xFFD97706));
      c.drawRRect(rr, white..strokeWidth = math.max(2.5, size * .085));
      label('3', (size * .5).roundToDouble(), Colors.white);
    } else if (s == '305') {
      final t = size * .62, n = size * .5;
      final path = Path()
        ..moveTo(-t * .56, -n)
        ..lineTo(t * .56, -n)
        ..lineTo(t, 0)
        ..lineTo(t * .56, n)
        ..lineTo(-t * .56, n)
        ..lineTo(-t, 0)
        ..close();
      c.drawPath(path, Paint()..color = const Color(0xFFF59E0B));
      c.drawPath(path, white..strokeWidth = math.max(2.5, size * .08));
      label('305', (size * .44).roundToDouble(), const Color(0xFF0B1220));
    } else if (s == '246') {
      final t = size * .54;
      final path = Path()
        ..moveTo(-t * .88, -t * .58)
        ..quadraticBezierTo(0, -t * .96, t * .88, -t * .58)
        ..quadraticBezierTo(t * 1.02, t * .25, 0, t * .96)
        ..quadraticBezierTo(-t * 1.02, t * .25, -t * .88, -t * .58)
        ..close();
      c.drawPath(path, Paint()..color = const Color(0xFF003C82));
      c.drawPath(path, white..strokeWidth = math.max(2.5, size * .085));
      label('246', (size * .4).roundToDouble(), Colors.white, -size * .04);
    } else if (s == 'LOOP') {
      final t = size * .72, n = size * .44;
      final rr = RRect.fromRectAndRadius(
          Rect.fromLTRB(-t, -n, t, n), Radius.circular(n));
      c.drawRRect(rr, Paint()..color = const Color(0xFF16A34A));
      c.drawRRect(rr, white..strokeWidth = math.max(2.5, size * .075));
      label('LOOP', (size * .36).roundToDouble(), Colors.white);
    } else {
      final t = size * .46;
      final rr = RRect.fromRectAndRadius(
          Rect.fromLTRB(-t, -t, t, t), Radius.circular(size * .14));
      c.drawRRect(rr, Paint()..color = const Color(0xFF047857));
      c.drawRRect(rr, white..strokeWidth = math.max(2.5, size * .08));
      label(s, (size * .46).roundToDouble(), Colors.white);
    }
    c.restore();
  }
}

Rect _bounds(List<Offset> q) {
  double x0 = double.infinity, y0 = double.infinity;
  double x1 = -double.infinity, y1 = -double.infinity;
  for (final p in q) {
    x0 = math.min(x0, p.dx);
    y0 = math.min(y0, p.dy);
    x1 = math.max(x1, p.dx);
    y1 = math.max(y1, p.dy);
  }
  return Rect.fromLTRB(x0, y0, x1, y1);
}

/// Separating-axis overlap test for convex quads, treating shapes closer
/// than [gap] as overlapping.
bool _satOverlap(List<Offset> a, List<Offset> b, double gap) {
  final ra = _bounds(a), rb = _bounds(b);
  if (ra.right + gap <= rb.left ||
      ra.left - gap >= rb.right ||
      ra.bottom + gap <= rb.top ||
      ra.top - gap >= rb.bottom) {
    return false;
  }
  for (final poly in [a, b]) {
    for (int i = 0; i < poly.length; i++) {
      final p0 = poly[i], p1 = poly[(i + 1) % poly.length];
      final ax = -(p1.dy - p0.dy), ay = p1.dx - p0.dx;
      final len = math.sqrt(ax * ax + ay * ay);
      if (len < 1e-9) continue;
      final nx = ax / len, ny = ay / len;
      double amin = double.infinity, amax = -double.infinity;
      for (final p in a) {
        final v = p.dx * nx + p.dy * ny;
        amin = math.min(amin, v);
        amax = math.max(amax, v);
      }
      double bmin = double.infinity, bmax = -double.infinity;
      for (final p in b) {
        final v = p.dx * nx + p.dy * ny;
        bmin = math.min(bmin, v);
        bmax = math.max(bmax, v);
      }
      if (amax + gap <= bmin || bmax + gap <= amin) return false;
    }
  }
  return true;
}

Color _hex(String s) {
  var h = s.replaceFirst('#', '');
  if (h.length == 6) h = 'FF$h';
  return Color(int.parse(h, radix: 16));
}

Path _dashPath(Path src, List<double> pattern) {
  final out = Path();
  for (final metric in src.computeMetrics()) {
    double dist = 0;
    int idx = 0;
    bool draw = true;
    while (dist < metric.length) {
      final len = pattern[idx % pattern.length];
      if (draw) {
        out.addPath(metric.extractPath(dist, math.min(dist + len, metric.length)),
            Offset.zero);
      }
      dist += len;
      idx++;
      draw = !draw;
    }
  }
  return out;
}

/// Polyline in texture px with cumulative arc length.
class _Poly {
  _Poly(this.pts) {
    cum = [0];
    for (int i = 1; i < pts.length; i++) {
      cum.add(cum.last + (pts[i] - pts[i - 1]).distance);
    }
  }

  final List<Offset> pts;
  late final List<double> cum;
  double get length => cum.last;

  Offset at(double s) {
    if (s <= 0) return pts.first;
    if (s >= length) return pts.last;
    int lo = 0, hi = cum.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (cum[mid] <= s) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final t = (s - cum[lo]) / math.max(1e-6, cum[hi] - cum[lo]);
    return Offset.lerp(pts[lo], pts[hi], t)!;
  }
}

class _Streak {
  _Streak(this.poly, this.color, this.speed, this.width, this.phase);
  final _Poly poly;
  final Color color;
  final double speed; // texture px / s
  final double width;
  final double phase;
}

/// Camera framing of the title scene: top-down, north-up. At 1280×720 the
/// world origin sits at (571, 202) px with 1.373 px per meter.
class _ShibuyaMapPainter extends CustomPainter {
  _ShibuyaMapPainter(this.cache, this.time);

  final _MapCache cache;
  final double time;

  static const double basePxPerMeter = 1.373;
  static const double centerX = 50.0, centerZ = 115.0;

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width / 1280, size.height / 720);
    final k = basePxPerMeter * s;
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF131A25));
    canvas.save();
    canvas.translate(size.width / 2 - centerX * k, size.height / 2 - centerZ * k);
    canvas.scale(k);
    // Into texture pixel space.
    canvas.translate(cache.minX, cache.minZ);
    canvas.scale(cache.spanX / _tex, cache.spanZ / _tex);
    // The web demo shows the texture lit by its cool night scene lighting;
    // this per-channel grade reproduces that (fit against the reference).
    canvas.saveLayer(
      const Rect.fromLTWH(0, 0, _tex, _tex),
      Paint()
        ..colorFilter = const ColorFilter.matrix(<double>[
          1.15, 0, 0, 0, -7, //
          0, 1.2, 0, 0, -6, //
          0.15, 0, 1.15, 0, -4, //
          0, 0, 0, 1, 0,
        ]),
    );
    canvas.drawPicture(cache.picture);
    canvas.restore();
    _paintStreaks(canvas);
    _paintRings(canvas);
    canvas.restore();
  }

  void _paintStreaks(Canvas canvas) {
    for (final st in cache.streaks) {
      final len = st.poly.length;
      final period = len + 900;
      final head = ((time * st.speed + st.phase * period) % period) - 200;
      const tail = 190.0;
      const segs = 10;
      for (int i = 0; i < segs; i++) {
        final s0 = head - tail * (i + 1) / segs, s1 = head - tail * i / segs;
        if (s1 < 0 || s0 > len) continue;
        final a = 1 - i / segs;
        final p0 = st.poly.at(s0.clamp(0, len)), p1 = st.poly.at(s1.clamp(0, len));
        canvas.drawLine(
          p0,
          p1,
          Paint()
            ..color = st.color.withValues(alpha: 0.35 * a)
            ..strokeWidth = st.width * 2.4
            ..strokeCap = StrokeCap.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
        );
        canvas.drawLine(
          p0,
          p1,
          Paint()
            ..color = st.color.withValues(alpha: 0.95 * a)
            ..strokeWidth = st.width * (0.5 + 0.5 * a)
            ..strokeCap = StrokeCap.round,
        );
      }
    }
  }

  void _paintRings(Canvas canvas) {
    final wp = cache.level.waypoints;
    final start = wp.isNotEmpty
        ? Offset(cache.d(wp.first.x), cache.f(wp.first.z))
        : Offset(cache.d(-48), cache.f(-5.2));
    final fb = cache._finalBeacon;
    final beacon = Offset(cache.d(fb.x), cache.f(fb.z));
    final pulse = 0.5 + 0.5 * math.sin(time * 2.4);

    Paint ring(Color c, double w) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..color = c;

    // Scramble start: wide champagne halo, cool inner ring, orange target.
    canvas.drawCircle(start, 127,
        ring(Color.fromRGBO(226, 210, 170, 0.62 + 0.1 * pulse), 16));
    canvas.drawCircle(start, 58, ring(const Color.fromRGBO(120, 178, 235, 0.45), 7));
    canvas.drawCircle(start, 36, ring(const Color.fromRGBO(240, 160, 50, 0.9), 5));
    canvas.drawCircle(
        start,
        30,
        Paint()
          ..color = const Color.fromRGBO(255, 236, 214, 0.55)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
    canvas.drawCircle(start, 15, Paint()..color = const Color(0xFFFFF1E2));
    canvas.drawCircle(start, 7, Paint()..color = const Color(0xFFFF9A4D));

    // Google beacon: blue halo + rose inner ring around the red pin.
    canvas.drawCircle(beacon, 120,
        ring(Color.fromRGBO(110, 165, 245, 0.72 + 0.12 * pulse), 13));
    canvas.drawCircle(beacon, 70, ring(const Color.fromRGBO(222, 168, 205, 0.6), 9));
    canvas.drawCircle(
        beacon,
        26,
        Paint()
          ..color = const Color.fromRGBO(255, 190, 170, 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
  }

  @override
  bool shouldRepaint(_ShibuyaMapPainter old) =>
      old.time != time || old.cache != cache;
}
