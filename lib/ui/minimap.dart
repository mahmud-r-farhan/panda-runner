import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/game_state.dart';
import '../game/level_data.dart';
import 'street_pill.dart';
import 'ui_tokens.dart';

/// `.hud-pill-minimap`: street header + live 244×136 dark-mode OSM minimap
/// (port of the web demo's minimap `L()` draw routine).
class MinimapPill extends StatelessWidget {
  const MinimapPill({super.key, required this.state, required this.level});

  final GameState state;
  final ShibuyaLevel level;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 1180;
    final cw = compact ? 204.0 : 244.0, ch = compact ? 118.0 : 136.0;
    return GlassDock(
      radius: 16,
      width: compact ? 224 : 264,
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            constraints: const BoxConstraints(minHeight: 19),
            padding: const EdgeInsets.symmetric(horizontal: 2),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    _header(state.street),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Ui.ui(compact ? 11 : 12,
                        weight: FontWeight.w600, height: 1.25),
                  ),
                ),
                if ((state.street?.shield ?? '').isNotEmpty) ...[
                  SizedBox(width: compact ? 4 : 5),
                  MlitShield(state.street!.shield!),
                ],
              ],
            ),
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: cw,
              height: ch,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: FittedBox(
                      fit: BoxFit.fill,
                      child: SizedBox(
                        width: 244,
                        height: 136,
                        child: _MinimapCanvas(state: state, level: level),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 4,
                    bottom: 4,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xF50B0F19),
                        border: Border.all(color: const Color(0x3D94A3B8)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '© OpenStreetMap',
                        style: Ui.ui(11,
                            weight: FontWeight.w500,
                            color: Ui.textStrongSub,
                            height: 1.15),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `${shortJa} · ${miniEn}` plus ` [shield]` like the web demo's header.
String _header(StreetSegment? s) {
  if (s == null) return '渋谷スクランブル · Scramble';
  return s.headerLabel;
}

class _MinimapCanvas extends StatefulWidget {
  const _MinimapCanvas({required this.state, required this.level});
  final GameState state;
  final ShibuyaLevel level;

  @override
  State<_MinimapCanvas> createState() => _MinimapCanvasState();
}

class _MinimapCanvasState extends State<_MinimapCanvas> {
  // Smoothed camera centre (`be`, `xe`).
  double? _cx, _cz;
  AppPhase? _lastPhase;
  double _skyDropStart = 0;

  @override
  Widget build(BuildContext context) {
    final st = widget.state;
    final data = _MinimapData.of(widget.level);
    if (st.phase != _lastPhase) {
      if (st.phase == AppPhase.skyDrop) _skyDropStart = st.elapsed;
      _lastPhase = st.phase;
    }
    final finale = st.phase == AppPhase.finale;
    final skyDrop = st.phase == AppPhase.skyDrop;
    final sweepT = skyDrop ? ((st.elapsed - _skyDropStart) / 1.4).clamp(0.0, 1.0) : 1.0;
    final eased = 1 - math.pow(1 - sweepT, 3).toDouble();

    final beacon = data.finalBeacon;
    final heroNearBeacon = math.sqrt(math.pow(st.heroX - beacon.x, 2) +
            math.pow(st.heroZ - beacon.z, 2)) <=
        65;
    final heroShown = !finale || heroNearBeacon;
    final hx = heroShown ? st.heroX : (finale ? beacon.x : data.start.x);
    final hz = heroShown ? st.heroZ : (finale ? beacon.z : data.start.z);
    final heading = heroShown
        ? st.heroHeading
        : (finale ? data.finalBeaconYaw : data.startHeading);
    final zoom = finale ? .185 : (skyDrop ? .28 + .05 * eased : .33);
    double tx, tz;
    if (finale) {
      tx = 138;
      tz = 68;
    } else {
      tx = (hx * .62 + 31.16).clamp(-28.0, 225.0);
      tz = (hz + math.cos(heading) * 34).clamp(-145.0, 218.0);
    }
    if (_cx == null ||
        math.sqrt(math.pow(tx - _cx!, 2) + math.pow(tz - _cz!, 2)) > 70) {
      _cx = tx;
      _cz = tz;
    } else {
      _cx = _cx! + (tx - _cx!) * .16;
      _cz = _cz! + (tz - _cz!) * .16;
    }
    return CustomPaint(
      size: const Size(244, 136),
      painter: _MinimapPainter(
        data: data,
        cx: _cx!,
        cz: _cz!,
        zoom: zoom,
        finale: finale,
        routeS: finale ? data.length : st.routeS,
        heroX: hx,
        heroZ: hz,
        heading: heading,
        skyDropSweep: skyDrop ? sweepT : null,
      ),
    );
  }
}

class _MinimapLabel {
  _MinimapLabel(this.id, this.text, this.kind, this.x, this.z, this.color);
  final String id, text, kind;
  final double x, z;
  final Color color;
}

class _MinimapData {
  _MinimapData._(ShibuyaLevel level) {
    final b = level.minimap['bounds'] as Map<String, dynamic>;
    final minX = (b['minX'] as num).toDouble(), maxX = (b['maxX'] as num).toDouble();
    final minZ = (b['minZ'] as num).toDouble(), maxZ = (b['maxZ'] as num).toDouble();
    List<XZ> uv(dynamic l) => [
          for (final p in l as List<dynamic>)
            XZ(minX + (p[0] as num) * (maxX - minX),
                minZ + (p[1] as num) * (maxZ - minZ)),
        ];
    List<List<XZ>> uvLines(dynamic list) {
      if (list is! List || list.isEmpty) return [];
      if (list.first is List && (list.first as List).first is num) {
        return [uv(list)];
      }
      return [for (final l in list) uv(l)];
    }

    roads = uvLines(level.minimap['roads']);
    rails = uvLines(level.minimap['rails']);
    river = uvLines(level.minimap['river']);
    if (river.isEmpty) {
      river = [
        ShibuyaLevel.pts((level.meta['shibuyaRiver'] as Map)['points']),
      ];
    }
    for (final bd in level.buildings) {
      final fp = bd['footprint'];
      if (fp is! List || fp.length < 3) continue;
      if (bd['isGoogleHero'] == true) {
        googleHero = ShibuyaLevel.pts(fp);
      } else {
        buildings.add(ShibuyaLevel.pts(fp));
      }
    }
    parks = [
      for (final p in level.overview['parks'] as List<dynamic>)
        ShibuyaLevel.pts(p['points']),
    ];
    route = [for (final w in level.waypoints) XZ(w.x, w.z)];
    routeS = [for (final w in level.waypoints) w.s];
    length = level.routeLength;
    final first = level.waypoints.first;
    start = XZ(first.x, first.z);
    startHeading = math.atan2(first.tx, first.tz);
    final fb = level.route['finalBeacon'] as Map<String, dynamic>;
    final pos = fb['pos'] as List<dynamic>;
    finalBeacon = XZ((pos[0] as num).toDouble(), (pos[2] as num).toDouble());
    finalBeaconYaw = (fb['yaw'] as num?)?.toDouble() ?? -1.925;
    final gt = (level.meta['googleTower'] as Map)['position'] as List<dynamic>;
    googleTower = XZ((gt[0] as num).toDouble(), (gt[2] as num).toDouble());
    for (final g in level.route['pinGates'] as List<dynamic>) {
      final p = g['pos'] as List<dynamic>;
      pinGates.add((
        (g['s'] as num).toDouble(),
        XZ((p[0] as num).toDouble(), (p[2] as num).toDouble()),
      ));
    }
    const priority = {
      'lm_google': 0,
      'lm_scramble': 1,
      'pk_miyashita': 2,
      'tr_yamanote': 3,
      'st_meiji': 4,
      'st_jingu': 5,
      'expy_shuto3': 6,
      'st_inokashira': 7,
      'wt_river': 8,
      'st_tamagawa': 9,
      'st_dogenzaka': 10,
      'tr_shibuya_sta': 11,
    };
    final src = (level.meta['mapLabels'] as List<dynamic>?) ??
        (level.minimap['landmarks'] as List<dynamic>);
    for (final e in src) {
      final id = (e['id'] ?? e['shortLabel'] ?? e['label']) as String;
      if (!priority.containsKey(id)) continue;
      final isGoogle = id == 'lm_google';
      labels.add(_MinimapLabel(
        id,
        isGoogle ? 'STREAM' : ((e['shortLabel'] ?? e['label']) as String).toUpperCase(),
        (e['kind'] ?? 'landmark') as String,
        (e['x'] as num).toDouble(),
        (e['z'] as num).toDouble(),
        _hex((e['color'] as String?) ?? '#8AB4F8'),
      ));
    }
    labels.sort((a, b) => priority[a.id]!.compareTo(priority[b.id]!));
  }

  static final Map<ShibuyaLevel, _MinimapData> _cache = {};
  static _MinimapData of(ShibuyaLevel l) =>
      _cache.putIfAbsent(l, () => _MinimapData._(l));

  late final List<List<XZ>> roads, rails;
  late List<List<XZ>> river;
  final List<List<XZ>> buildings = [];
  List<XZ>? googleHero;
  late final List<List<XZ>> parks;
  late final List<XZ> route;
  late final List<double> routeS;
  late final double length;
  late final XZ start, finalBeacon, googleTower;
  late final double startHeading, finalBeaconYaw;
  final List<(double, XZ)> pinGates = [];
  final List<_MinimapLabel> labels = [];
}

Color _hex(String s) {
  var h = s.replaceFirst('#', '');
  if (h.length == 6) h = 'FF$h';
  return Color(int.parse(h, radix: 16));
}

class _MinimapPainter extends CustomPainter {
  _MinimapPainter({
    required this.data,
    required this.cx,
    required this.cz,
    required this.zoom,
    required this.finale,
    required this.routeS,
    required this.heroX,
    required this.heroZ,
    required this.heading,
    required this.skyDropSweep,
  });

  final _MinimapData data;
  final double cx, cz, zoom, routeS, heroX, heroZ, heading;
  final bool finale;
  final double? skyDropSweep;

  static const double w = 244, h = 136;

  double tX(double x) => w * .5 + (x - cx) * zoom;
  double tZ(double z) => h * .5 + (z - cz) * zoom;
  Offset t(XZ p) => Offset(tX(p.x), tZ(p.z));

  Path _lines(List<List<XZ>> lines, {bool close = false}) {
    final p = Path();
    for (final l in lines) {
      if (l.length < 2) continue;
      p.moveTo(tX(l[0].x), tZ(l[0].z));
      for (int i = 1; i < l.length; i++) {
        p.lineTo(tX(l[i].x), tZ(l[i].z));
      }
      if (close) p.close();
    }
    return p;
  }

  Paint _stroke(Color c, double width, {StrokeCap cap = StrokeCap.round}) =>
      Paint()
        ..style = PaintingStyle.stroke
        ..color = c
        ..strokeWidth = width
        ..strokeCap = cap
        ..strokeJoin = StrokeJoin.round;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Ui.surfaceMaps);
    final grid = _stroke(const Color.fromRGBO(138, 180, 248, 0.045), .75,
        cap: StrokeCap.butt);
    for (double e = -200; e <= 350; e += 50) {
      final n = tX(e);
      if (n >= -2 && n <= 246) canvas.drawLine(Offset(n, 0), Offset(n, h), grid);
    }
    for (double e = -250; e <= 350; e += 50) {
      final n = tZ(e);
      if (n >= -2 && n <= 138) canvas.drawLine(Offset(0, n), Offset(w, n), grid);
    }
    canvas.drawPath(_lines(data.parks, close: true),
        Paint()..color = const Color(0xFF1B342A));
    final riverPath = _lines(data.river);
    canvas.drawPath(riverPath, _stroke(const Color(0xFF294D7A), 6));
    canvas.drawPath(riverPath, _stroke(const Color(0xFF1D3A5F), 4.4));
    final bPath = _lines(data.buildings, close: true);
    canvas.drawPath(bPath, Paint()..color = const Color(0xFF283345));
    canvas.drawPath(bPath, _stroke(const Color.fromRGBO(100, 122, 152, 0.24), .65));
    if (data.googleHero != null) {
      final g = _lines([data.googleHero!], close: true);
      canvas.drawPath(g, Paint()..color = const Color.fromRGBO(66, 133, 244, 0.30));
      canvas.drawPath(g, _stroke(const Color.fromRGBO(138, 180, 248, 0.72), 1.05));
    }
    final roads = _lines(data.roads);
    canvas.drawPath(roads, _stroke(const Color(0xFF151B25), 2.3));
    canvas.drawPath(roads, _stroke(const Color(0xFF3A475C), 1.3));
    final rails = _lines(data.rails);
    canvas.drawPath(
        rails, _stroke(const Color.fromRGBO(52, 168, 83, 0.28), 2, cap: StrokeCap.butt));
    canvas.drawPath(_dash(rails, 4, 3),
        _stroke(const Color.fromRGBO(52, 168, 83, 0.72), 1.1, cap: StrokeCap.butt));

    // Route: travelled (orange) + remaining (blue).
    final pts = data.route;
    final n = pts.length;
    double k = 0;
    if (n >= 2) {
      final s = routeS.clamp(0.0, data.length);
      int i = 0;
      while (i < n - 2 && data.routeS[i + 1] <= s) {
        i++;
      }
      final seg = math.max(1e-6, data.routeS[i + 1] - data.routeS[i]);
      k = finale ? (n - 1).toDouble() : i + ((s - data.routeS[i]) / seg).clamp(0.0, 1.0);
    }
    final a = math.min(n - 1, math.max(0, k.floor()));
    final j = k - a;
    var mx = pts[a].x, mz = pts[a].z;
    if (a < n - 1 && j > 0) {
      mx += (pts[a + 1].x - mx) * j;
      mz += (pts[a + 1].z - mz) * j;
    }
    if (!finale && a < n - 1) {
      final p = Path()..moveTo(tX(mx), tZ(mz));
      for (int e = a + 1; e < n; e++) {
        p.lineTo(tX(pts[e].x), tZ(pts[e].z));
      }
      canvas.drawPath(p, _stroke(const Color.fromRGBO(66, 133, 244, 0.28), 5.2));
      canvas.drawPath(p, _stroke(const Color(0xFF4285F4), 2.5));
      canvas.drawPath(p, _stroke(const Color.fromRGBO(138, 180, 248, 0.85), .85));
    }
    if (k > .02 || finale) {
      final p = Path()..moveTo(tX(pts[0].x), tZ(pts[0].z));
      for (int e = 1; e <= a; e++) {
        p.lineTo(tX(pts[e].x), tZ(pts[e].z));
      }
      if (!finale && a < n - 1) p.lineTo(tX(mx), tZ(mz));
      canvas.drawPath(p, _stroke(const Color.fromRGBO(255, 79, 0, 0.34), 5.8));
      canvas.drawPath(p, _stroke(const Color(0xFFFF4F00), 2.6));
      canvas.drawPath(p, _stroke(const Color.fromRGBO(255, 198, 166, 0.88), .9));
    }
    final travelled = finale ? data.length : routeS;
    for (final (gs, gp) in data.pinGates) {
      final x = tX(gp.x), y = tZ(gp.z);
      if (x < -6 || x > 250 || y < -6 || y > 142) continue;
      final lit = finale || travelled >= gs;
      canvas.drawCircle(Offset(x, y), lit ? 2.3 : 1.6,
          Paint()..color = lit ? const Color(0xFFFF4F00) : const Color(0xFF8AB4F8));
    }

    // Google tower 4-colour ring.
    final ee = tX(data.googleTower.x), te = tZ(data.googleTower.z);
    if (ee >= -12 && ee <= 256 && te >= -12 && te <= 148) {
      const cols = [Ui.gBlue, Ui.gRed, Ui.gYellow, Ui.gGreen];
      for (int i = 0; i < 4; i++) {
        canvas.drawArc(Rect.fromCircle(center: Offset(ee, te), radius: 5.2),
            i * math.pi * .5, math.pi * .5, false, _stroke(cols[i], 1.9, cap: StrokeCap.butt));
      }
      canvas.drawCircle(Offset(ee, te), 2.2,
          Paint()..color = finale ? const Color(0xFFFFF3EC) : const Color(0xFFE2E8F0));
    }

    // Labels (max 3), avoiding hero, tower, credit box and the route.
    final ne = tX(heroX), re = tZ(heroZ);
    final placed = <Rect>[
      Rect.fromLTRB(ne - 12, re - 12, ne + 12, re + 12),
      Rect.fromLTRB(ee - 10, te - 10, ee + 10, te + 10),
      const Rect.fromLTRB(130 - 4, 113 - 4, w, h),
    ];
    int drawn = 0;
    for (final l in data.labels) {
      if (drawn >= 3) break;
      final c = tX(l.x), y = tZ(l.z);
      if (c < -4 || c > 248 || y < -4 || y > 140) continue;
      final isGoogle = l.id == 'lm_google';
      if (isGoogle && c >= 126 && y >= 109) continue;
      final tp = _label(l.text, null, isGoogle, l);
      final d = (tp.width + 8) * .5;
      List<List<double>> cand;
      if (l.id == 'lm_scramble') {
        final e = (d + 10).ceilToDouble();
        cand = [[-e, 0], [-e, 12], [-e, -12], [0, 22], [0, -22], [-(e * .72).roundToDouble(), 20], [e, 10], [0, 26]];
      } else if (isGoogle) {
        final e = (d + 15).ceilToDouble();
        cand = [[e, -4], [e, -13], [e, 4], [e - 2, -20], [-e, -6], [-e, -14], [0, -21]];
      } else if (l.id == 'pk_miyashita') {
        final e = (d + 10).ceilToDouble();
        cand = [[0, 0], [e, 0], [e, 4], [e, -6], [0, -14], [0, 14], [-e, 0]];
      } else {
        final e = (d + 9).ceilToDouble();
        cand = [[0, 0], [0, -14], [0, 14], [e, 0], [-e, 0], [e, -12], [-e, -12], [e, 12], [-e, 12], [e + 7, 0], [e + 7, -12], [-e - 7, 0], [0, -20], [0, 20]];
      }
      Rect? hit;
      Offset? at;
      for (final o in cand) {
        final px = c + o[0], py = y + o[1];
        final r = Rect.fromLTRB(px - d, py - 6.5, px + d, py + 6.5);
        if (r.left < 6 || r.right > 238 || r.top < 6 || r.bottom > 130) continue;
        final inflated = r.inflate(4);
        if (placed.any((p) => p.overlaps(inflated))) continue;
        if (_routeCrosses(r.inflate(5))) continue;
        hit = r;
        at = Offset(px, py);
        break;
      }
      if (hit == null || at == null) continue;
      placed.add(hit);
      drawn++;
      final outline = _label(
          l.text,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.2
            ..strokeJoin = StrokeJoin.round
            ..color = const Color.fromRGBO(17, 23, 34, 0.92),
          isGoogle,
          l);
      outline.paint(canvas, at - Offset(outline.width / 2, outline.height / 2));
      tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
    }

    // Hero marker.
    canvas.save();
    canvas.translate(ne, re);
    canvas.drawCircle(Offset.zero, 8.6, Paint()..color = const Color.fromRGBO(253, 191, 45, 0.28));
    canvas.save();
    canvas.rotate(-heading);
    final arrow = Path()
      ..moveTo(0, 8)
      ..lineTo(-4.2, -2.2)
      ..lineTo(0, .5)
      ..lineTo(4.2, -2.2)
      ..close();
    canvas.drawPath(arrow, Paint()..color = const Color(0xFFFDBF2D));
    canvas.drawPath(arrow, _stroke(Ui.surfaceMaps, 1.4)..strokeCap = StrokeCap.butt);
    canvas.restore();
    canvas.drawCircle(Offset.zero, 3.8, Paint()..color = const Color(0xFFFDBF2D));
    canvas.drawCircle(Offset.zero, 3.8, _stroke(Ui.surfaceMaps, 1.3));
    canvas.drawCircle(Offset.zero, 1.4, Paint()..color = const Color(0xFFCE592C));
    canvas.restore();

    // Sky-drop scan sweep.
    final sw = skyDropSweep;
    if (sw != null && !finale) {
      final nn = (sw / .84).clamp(0.0, 1.0);
      final r = sw > .8 ? (1 - (sw - .8) / .2).clamp(0.0, 1.0) : 1.0;
      final i = nn * 272 - 14;
      // Drawn at its true position (the canvas clips it), so the gradient
      // never clamps into a solid block while the sweep enters from the left.
      final rect = Rect.fromLTWH(i - 50, 0, 50, h);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(colors: [
            const Color.fromRGBO(255, 79, 0, 0),
            Color.fromRGBO(255, 79, 0, .16 * r),
            Color.fromRGBO(66, 133, 244, .36 * r),
          ], stops: const [0, .55, 1])
              .createShader(Rect.fromLTWH(i - 50, 0, 50, h)),
      );
      if (i >= 0 && i <= w) {
        canvas.drawLine(Offset(i, 0), Offset(i, h),
            _stroke(Color.fromRGBO(138, 180, 248, .95 * r), 1.5, cap: StrokeCap.butt));
      }
      if (sw > .65) {
        final q = ((sw - .65) / .35).clamp(0.0, 1.0);
        canvas.drawCircle(Offset(ne, re), 6 + q * 14,
            _stroke(Color.fromRGBO(253, 191, 45, (1 - q) * .85), 1.4));
      }
    }
  }

  bool _routeCrosses(Rect r) {
    final pts = data.route;
    for (int i = 1; i < pts.length; i++) {
      final a = t(pts[i - 1]), b = t(pts[i]);
      if (_segRect(a, b, r)) return true;
    }
    return false;
  }

  static bool _segRect(Offset a, Offset b, Rect r) {
    if (r.contains(a) || r.contains(b)) return true;
    bool inter(Offset p, Offset q, Offset c, Offset d) {
      double cross(Offset o, Offset u, Offset v) =>
          (u.dx - o.dx) * (v.dy - o.dy) - (u.dy - o.dy) * (v.dx - o.dx);
      final d1 = cross(c, d, p), d2 = cross(c, d, q);
      final d3 = cross(p, q, c), d4 = cross(p, q, d);
      return (d1 * d2 < 0) && (d3 * d4 < 0);
    }

    final tl = r.topLeft, tr = r.topRight, bl = r.bottomLeft, br = r.bottomRight;
    return inter(a, b, tl, tr) ||
        inter(a, b, tr, br) ||
        inter(a, b, br, bl) ||
        inter(a, b, bl, tl);
  }

  TextPainter _label(String text, Paint? fg, bool isGoogle, _MinimapLabel l) {
    final color = isGoogle
        ? const Color(0xFFE8F0FE)
        : l.kind == 'water'
            ? const Color(0xFF7DD3FC)
            : l.id == 'lm_scramble'
                ? const Color(0xFFFF6B2B)
                : l.color;
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: Ui.fontUi,
          fontFamilyFallback: Ui.fontFallback,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          height: 1,
          color: fg == null ? color : null,
          foreground: fg,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  static Path _dash(Path src, double on, double off) {
    final out = Path();
    for (final m in src.computeMetrics()) {
      double d = 0;
      while (d < m.length) {
        out.addPath(m.extractPath(d, math.min(d + on, m.length)), Offset.zero);
        d += on + off;
      }
    }
    return out;
  }

  @override
  bool shouldRepaint(_MinimapPainter o) => true;
}
