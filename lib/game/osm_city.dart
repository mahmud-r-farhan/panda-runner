import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;

import 'level_data.dart';
import 'mesh_buf.dart';
import 'world_builder.dart';

double _d(dynamic v, [double fb = 0]) => (v as num?)?.toDouble() ?? fb;

/// Mulberry32 PRNG, identical to the demo's `Jm()`.
double Function() mulberry32(int seed) {
  var t = seed & 0xFFFFFFFF;
  // Math.imul, exact on the web too (split into 16-bit halves).
  int imul(int a, int b) {
    final ah = (a >> 16) & 0xFFFF, al = a & 0xFFFF;
    final bh = (b >> 16) & 0xFFFF, bl = b & 0xFFFF;
    return (al * bl + ((((ah * bl + al * bh) & 0xFFFF) * 65536))) & 0xFFFFFFFF;
  }
  return () {
    t = (t + 1831565813) & 0xFFFFFFFF;
    var e = imul(t ^ (t >> 15), 1 | t);
    e = ((e + imul(e ^ (e >> 7), 61 | e)) & 0xFFFFFFFF) ^ e;
    return ((e ^ (e >> 14)) & 0xFFFFFFFF) / 4294967296.0;
  };
}

/// The demo's `lg()` hash noise.
double _lg(double e, double t) {
  final n = math.sin(e * 127.1 + t * 311.7) * 43758.5453123;
  return n - n.floorToDouble();
}

/// Facade texture pair (base colour + emissive) — port of the demo's `jg()`.
class FacadeTex {
  FacadeTex(this.map, this.emissive, this.roughness);
  final fs.Texture2D map;
  final fs.Texture2D emissive;

  /// glTF metallic-roughness texture: G = the demo's roughnessMap canvas
  /// (#C2C2C2 walls, #212121/#292929 glass, #B8B8B8 mullions), B = 1 so
  /// metalness stays the material's constant factor like three.js.
  final fs.Texture2D roughness;

  static Future<FacadeTex> create(int seed, String kind) async {
    final r = mulberry32(seed);
    const i = 1024.0, a = 1024.0;
    final rb = ui.PictureRecorder(), re = ui.PictureRecorder(), rr = ui.PictureRecorder();
    final s = Canvas(rb), l = Canvas(re), dd = Canvas(rr);
    dd.drawRect(const Rect.fromLTWH(0, 0, i, a), Paint()..color = const Color(0xFFC2C2C2));
    final tower = kind == 'tower', commercial = kind == 'commercial';
    s.drawRect(const Rect.fromLTWH(0, 0, i, a),
        Paint()..color = Color(tower ? 0xFF2E405E : commercial ? 0xFF31425C : 0xFF324056));
    l.drawRect(const Rect.fromLTWH(0, 0, i, a),
        Paint()..color = Color(kind == 'low' ? 0xFF10141C : 0xFF151D2C));
    final f = tower ? 16 : commercial ? 12 : 8;
    final p = tower ? 20 : commercial ? 16 : 12;
    final m = i / f, h = a / p;
    for (int e = 0; e < f; e++) {
      final t = e * m;
      final n = e % 4 == 0;
      s.drawRect(Rect.fromLTWH(t, 0, n ? 9 : 5, a), Paint()..color = Color(n ? 0xFF1A2538 : 0xFF1F2B40));
      s.drawRect(Rect.fromLTWH(t + (n ? 9 : 5), 0, 2, a), Paint()..color = const Color(0xFF364A6B));
    }
    Color hex(String x) => Color(int.parse('FF${x.substring(1)}', radix: 16));
    for (int e = 0; e < p; e++) {
      final t = e * h;
      final band = tower && (e == 6 || e == 13);
      final lit = tower && (e == 5 || e == 12);
      final c = lit ? 0.82 : tower ? 0.46 : commercial ? 0.36 : 0.28;
      final u = !band && (lit || r() < 0.7);
      final pr = r();
      final g = lit
          ? '#DCEBFF'
          : pr < 0.44
              ? '#CBE2FF'
              : pr < 0.76
                  ? '#FFD699'
                  : pr < 0.9
                      ? '#9AD0FF'
                      : '#FFB57A';
      final bh = band ? h * 0.84 : (lit ? h * 0.16 : h * 0.26);
      s.drawRect(Rect.fromLTWH(0, t, i, bh),
          Paint()..color = Color(band ? 0xFF162033 : (tower ? 0xFF1B2A42 : 0xFF1D293E)));
      s.drawRect(Rect.fromLTWH(0, t + bh - 3, i, 3), Paint()..color = Color(tower ? 0xFF435C82 : 0xFF354868));
      dd.drawRect(Rect.fromLTWH(0, t, i, bh + 2), Paint()..color = const Color(0xFFC2C2C2));
      if (band) {
        for (double y = t + 8; y < t + bh - 6; y += 6) {
          s.drawRect(Rect.fromLTWH(4, y, 1016, 2), Paint()..color = const Color(0xFF101726));
        }
        continue;
      }
      for (int k = 0; k < f; k++) {
        final ii = k % 4 == 0 ? 11.0 : 7.0;
        final ax = k * m + ii;
        final fy = t + bh + 2;
        final pw = math.max(8.0, m - ii - 4);
        final vh = math.max(10.0, h - bh - 5);
        final rect = Rect.fromLTWH(ax, fy, pw, vh);
        if (tower) {
          s.drawRect(
              rect,
              Paint()
                ..shader = ui.Gradient.linear(Offset(0, fy), Offset(0, fy + vh),
                    const [Color(0xFF152544), Color(0xFF20365D), Color(0xFF12203A)], const [0, 0.55, 1]));
        } else {
          s.drawRect(rect, Paint()..color = const Color(0xFF1D2C45));
        }
        dd.drawRect(rect, Paint()..color = Color(tower ? 0xFF212121 : 0xFF292929));
        if (pw > 28) {
          s.drawRect(Rect.fromLTWH((ax + pw * 0.5).roundToDouble(), fy, 2, vh),
              Paint()..color = const Color(0xFF182336));
          dd.drawRect(Rect.fromLTWH((ax + pw * 0.5).roundToDouble(), fy, 2, vh),
              Paint()..color = const Color(0xFFB8B8B8));
        }
        if (u && r() < c) {
          final col = hex(tower && !lit && r() < 0.25 ? '#FFD699' : g);
          final alpha = lit ? 0.44 + r() * 0.28 : 0.22 + r() * 0.5;
          final inner = Rect.fromLTWH(ax + 2, fy + 2, pw - 4, vh - 4);
          l.drawRect(
              inner,
              Paint()
                ..shader = ui.Gradient.linear(
                    Offset(0, fy), Offset(0, fy + vh),
                    [const Color(0xFFF3F8FF), col, col, const Color(0xFF202D44)].map((c) => c.withValues(alpha: alpha)).toList(),
                    const [0, 0.22, 0.76, 1]));
          if (tower && !lit && r() < 0.45) {
            l.drawRect(Rect.fromLTWH(ax + 2, fy + vh * 0.68, pw - 4, math.max(3, vh * 0.3)),
                Paint()..color = const Color(0xFF080E1A).withValues(alpha: 0.26));
          }
          if (r() < 0.38) {
            l.drawRect(Rect.fromLTWH(ax + 2, fy + 2, pw - 4, math.max(4, vh * (0.24 + r() * 0.25))),
                Paint()..color = const Color(0xFF070B14).withValues(alpha: 0.42));
          }
          if (pw > 28) {
            l.drawRect(Rect.fromLTWH((ax + pw * 0.5).roundToDouble(), fy, 2, vh),
                Paint()..color = const Color(0xFF000000).withValues(alpha: 0.85));
          }
        }
      }
    }
    final mi = await rb.endRecording().toImage(i.toInt(), a.toInt());
    final ei = await re.endRecording().toImage(i.toInt(), a.toInt());
    final ri = await rr.endRecording().toImage(i.toInt(), a.toInt());
    final rbytes = (await ri.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!.buffer.asUint8List();
    final mr = Uint8List(rbytes.length);
    for (int k = 0; k < rbytes.length; k += 4) {
      mr[k] = 255;
      mr[k + 1] = rbytes[k + 1];
      mr[k + 2] = 255;
      mr[k + 3] = 255;
    }
    // three.js: texture.anisotropy = 4 (flutter_scene defaults to 8, which
    // keeps distant windows sharper and noisier than the demo).
    const smp = fs.TextureSampling(maxAnisotropy: 4);
    return FacadeTex(await fs.Texture2D.fromImage(mi, sampling: smp),
        await fs.Texture2D.fromImage(ei, sampling: smp),
        fs.Texture2D.fromPixels(mr, i.toInt(), a.toInt(), content: fs.TextureContent.data, sampling: smp));
  }
}

/// Port of `_buildOsmSkylineAndStorefronts`: extruded OSM buildings in three
/// facade classes, rooftop crowns + parapets, aviation beacons, and the
/// demo's procedural filler blocks. Built in the reference frame.
class OsmCity {
  OsmCity(this.world);
  final ShibuyaWorld world;
  ShibuyaLevel get level => world.level;

  final List<List<double>> bounds = []; // minX,maxX,minZ,maxZ

  Future<void> build() async {
    final towers = MeshBuf(), mids = MeshBuf(), lows = MeshBuf(), crowns = MeshBuf();
    final beacons = <vm.Vector3>[];

    void wallQuad(MeshBuf b, double ax, double az, double bx, double bz, double y0, double y1,
        double nx, double nz) {
      final n = vm.Vector3(nx, 0, nz);
      final useZ = nx.abs() > 0.5;
      final ua = (useZ ? az : ax) / 18, ub = (useZ ? bz : bx) / 18;
      b.quad(vm.Vector3(ax, y0, az), vm.Vector3(bx, y0, bz), vm.Vector3(bx, y1, bz),
          vm.Vector3(ax, y1, az), n,
          u0: ua, u1: ub, v0: -y0 / 22, v1: -y1 / 22);
    }

    void extrude(MeshBuf b, List<XZ> pts0, double h) {
      final pts = List<XZ>.from(pts0);
      if (pts.length > 3 &&
          (pts.first.x - pts.last.x).abs() < 1e-3 &&
          (pts.first.z - pts.last.z).abs() < 1e-3) {
        pts.removeLast();
      }
      double area = 0;
      for (int i = 0, j = pts.length - 1; i < pts.length; j = i++) {
        area += pts[j].x * pts[i].z - pts[i].x * pts[j].z;
      }
      final sg = area >= 0 ? 1.0 : -1.0;
      for (int i = 0; i < pts.length; i++) {
        final a = pts[i], c = pts[(i + 1) % pts.length];
        final dx = c.x - a.x, dz = c.z - a.z;
        final len = math.sqrt(dx * dx + dz * dz);
        if (len < 0.05) continue;
        wallQuad(b, a.x, a.z, c.x, c.z, 0, h, dz / len * sg, -dx / len * sg);
      }
      final tris = triangulatePolygon([for (final q in pts) ...[q.x, q.z]]);
      final base = b.vertexCount;
      for (final q in pts) {
        b.vertex(vm.Vector3(q.x, h, q.z), vm.Vector3(0, 1, 0), q.x * 0.04, q.z * 0.04);
      }
      for (int i = 0; i + 2 < tris.length; i += 3) {
        b.tri(base + tris[i], base + tris[i + 1], base + tris[i + 2]);
      }
    }

    for (final o in level.buildings) {
      if (o['isGoogleHero'] == true || o['replacedByHeroArch'] == true) continue;
      final s = ShibuyaLevel.pts(o['footprint']);
      if (s.length < 3) continue;
      final c = _d(o['height'], 22).clamp(10.0, 235.0);
      final hero = o['isHeroSkyscraper'] == true;
      final style = o['archStyle'];
      final target = (style == 'modern_glass_tower' || hero || c >= 58)
          ? towers
          : (style == 'commercial_midrise' || c >= 26)
              ? mids
              : lows;
      extrude(target, s, c);
      double mnx = 1e9, mxx = -1e9, mnz = 1e9, mxz = -1e9;
      for (final q in s) {
        mnx = math.min(mnx, q.x);
        mxx = math.max(mxx, q.x);
        mnz = math.min(mnz, q.z);
        mxz = math.max(mxz, q.z);
      }
      bounds.add([mnx, mxx, mnz, mxz, c + (o['isHeroSkyscraper'] == true ? 7.4 : (c >= 58 ? 4.8 : 2.2))]);
      final cen = o['center'] as List<dynamic>;
      final v = _d(cen[0]), y = _d(cen[1]);
      final b = (math.sqrt(_d(o['area'], 250)) * 0.34).clamp(3.0, 14.0);
      final S = hero ? 7.4 : (c >= 58 ? 4.8 : 2.2);
      final fy = _d(o['facingYaw']);
      if (hero) {
        final e = math.max(8.0, (mxx - mnx) * 0.68), t = math.max(8.0, (mxz - mnz) * 0.68);
        const a = 3.2, l = 2.6, p = 1.6;
        crowns.box(vm.Vector3(v, c + a * 0.5, y), vm.Vector3(math.min(b * 1.45, e), a, math.min(b * 1.25, t)), fy);
        final u = math.min(b * 1.05, e * 0.72), d = math.min(b * 0.92, t * 0.72);
        crowns.box(vm.Vector3(v, c + a + l * 0.5, y), vm.Vector3(u, l, d), fy);
        crowns.box(vm.Vector3(v, c + a + l + p * 0.5, y), vm.Vector3(u * 0.48, p, d * 0.48), fy);
        final sw = math.min(b * 1.56, e * 1.04), cw = math.min(b * 1.36, t * 1.04);
        final ce = math.cos(fy), se = math.sin(fy);
        vm.Vector3 rot(double lx, double ly, double lz) =>
            vm.Vector3(v + lx * ce + lz * se, ly, y - lx * se + lz * ce);
        for (final k in [-1.0, 1.0]) {
          crowns.box(rot(0, c + a + 0.15, k * cw * 0.5), vm.Vector3(sw, 0.55, 0.55), fy);
          crowns.box(rot(k * sw * 0.5, c + a + 0.15, 0), vm.Vector3(0.55, 0.55, cw), fy);
        }
        final w = u * 0.46, tt = d * 0.46, oy = c + a + l + 0.55;
        for (final ex in [-1.0, 1.0]) {
          for (final ez in [-1.0, 1.0]) {
            beacons.add(rot(ex * w, oy, ez * tt));
          }
        }
      } else {
        crowns.box(vm.Vector3(v, c + S * 0.5, y), vm.Vector3(b, S, b * 0.85), fy);
      }
      final C = hero ? 1.65 : (c >= 58 ? 1.15 : 0.72);
      for (int e = 0; e < s.length; e++) {
        final t = s[e], n = s[(e + 1) % s.length];
        final dx = n.x - t.x, dz = n.z - t.z;
        final len = math.sqrt(dx * dx + dz * dz);
        if (len < 1.2) continue;
        crowns.box(vm.Vector3((t.x + n.x) * 0.5, c + C * 0.5, (t.z + n.z) * 0.5),
            vm.Vector3(0.42, C, len + 0.18), math.atan2(dx, dz));
      }
      if (!hero && c >= 55) beacons.add(vm.Vector3(v, c + S + 0.65, y));
    }

    // ---- procedural filler blocks
    final fillers = <List<double>>[
      [17.5, -195.5, 15.5, 20, 36], [17.5, -218.5, 15.5, 20, 27], [17.5, -241.5, 15.5, 20, 42],
      [18, -265, 16, 20, 34], [-5.5, -232, 18, 20, 38], [-4.5, -257, 19, 22, 48],
      [-31, -260, 20, 22, 54], [-48, -234, 20, 22, 46], [-6, -284, 20, 20, 44],
      [-32, -288, 22, 22, 58], [16, -292, 18, 20, 46], [42, -299, 22, 18, 38],
      [61.5, -213, 14, 18, 34], [64.5, -236, 14, 18, 28], [4, 46, 24, 20, 42],
      [34, 46, 22, 22, 52], [-24, 44, 20, 18, 38], [52, 48, 18, 22, 64],
    ];
    const grids = [
      [-48, 66, 36, 215, 24, 24, 24, 68], [102, 174, 24, 96, 23, 22, 26, 58],
      [104, 224, -268, -26, 25, 25, 22, 62], [112, 230, -32, -18, 24, 20, 26, 52],
      [-70, 12, -282, -206, 24, 24, 26, 54], [-60, 8, -194, -48, 23, 23, 24, 52],
      [274, 356, 82, 332, 25, 25, 24, 72], [148, 218, 162, 295, 23, 24, 28, 64],
      [212, 330, 302, 350, 26, 22, 30, 78],
    ];
    for (int e = 0; e < grids.length; e++) {
      final t = grids[e];
      for (double n = t[2].toDouble(); n <= t[3]; n += t[5]) {
        for (double r = t[0].toDouble(); r <= t[1]; r += t[4]) {
          final i = _lg(r * 0.37 + e * 13, n * 0.41 + 7), a = _lg(r * 0.53 + 19, n * 0.29 + e * 31);
          final c = 15.5 + 5 * _lg(r + 3, n + 11), l = 15.5 + 5 * _lg(r + 17, n + 5);
          final u = t[6] + (t[7] - t[6]) * math.pow(_lg(r * 1.1 + 29, n * 1.3 + 43), 0.85);
          fillers.add([r + (i - 0.5) * 4.5, n + (a - 0.5) * 4.5, c, l, u.roundToDouble()]);
        }
      }
    }
    for (final o in fillers) {
      final cx = o[0], cz = o[1], w = o[2], dd = o[3], h = o[4];
      final s = w * 0.5, c = dd * 0.5;
      if (!_fillerOk(cx, cz, s, c)) continue;
      final target = h >= 58 ? towers : (h >= 26 ? mids : lows);
      extrude(target, [XZ(cx - s, cz - c), XZ(cx + s, cz - c), XZ(cx + s, cz + c), XZ(cx - s, cz + c)], h);
      final p = h >= 55 ? 3.8 : (h >= 40 ? 3.0 : 2.1);
      crowns.box(vm.Vector3(cx, h + p * 0.5, cz), vm.Vector3(w * 0.52, p, dd * 0.48), 0);
      crowns.box(vm.Vector3(cx, 0.09, cz), vm.Vector3(w + 1.8, 0.18, dd + 1.8), 0);
      final g = h >= 58 ? 1.05 : 0.82;
      for (final e in [-1.0, 1.0]) {
        crowns.box(vm.Vector3(cx, h + g * 0.5, cz + e * c), vm.Vector3(w + 0.2, g, 0.44), 0);
        crowns.box(vm.Vector3(cx + e * s, h + g * 0.5, cz), vm.Vector3(0.44, g, dd + 0.2), 0);
      }
      if (h >= 60) beacons.add(vm.Vector3(cx, h + p + 0.65, cz));
      bounds.add([cx - s, cx + s, cz - c, cz + c, h + p]);
    }

    final tw = await FacadeTex.create(14598366 + 11, 'tower');
    final cm = await FacadeTex.create(14598366 + 23, 'commercial');
    final lo = await FacadeTex.create(14598366 + 37, 'low');
    fs.PhysicallyBasedMaterial mat(FacadeTex t, String base, String em, double ei, double metal) =>
        fs.PhysicallyBasedMaterial(
            baseColorTexture: t.map, emissiveTexture: t.emissive, metallicRoughnessTexture: t.roughness)
          ..baseColorFactor = hexColor(base)
          ..emissiveFactor = hexColor(em, ei)
          ..roughnessFactor = 1
          ..metallicFactor = metal
          ..doubleSided = true;
    void add(MeshBuf b, fs.Material m, String name) {
      if (b.isEmpty) return;
      world.refRoot.add(fs.Node(name: name, mesh: fs.Mesh(b.build(), m)));
    }

    if (Uri.base.queryParameters['dumpb'] == '1') {
      // ignore: avoid_print
      print('BOUNDS ${bounds.map((b) => b.map((v) => v.toStringAsFixed(1)).join(',')).join(';')}');
    }
    add(towers, mat(tw, '#9AB4DC', '#A8CEFF', 0.78, 0.3), 'OsmSkyscrapers230m');
    add(mids, mat(cm, '#90A8CC', '#CFE2FF', 0.66, 0.22), 'OsmCommercialMidrise');
    add(lows, mat(lo, '#8EA2C2', '#FFE0B2', 0.58, 0.14), 'OsmShibuyaBlocks');
    add(crowns, pbr(hexColor('#243045'), roughness: 0.72, metallic: 0.3, emissive: hexColor('#0C1220')),
        'OsmRooftopCrowns');
    if (beacons.isNotEmpty) {
      final im = fs.InstancedMesh(
          geometry: fs.SphereGeometry(radius: 0.62),
          material: pbr(hexColor('#FF2222'), emissive: hexColor('#FF1E1E', 4.2), roughness: 0.2));
      for (final b in beacons) {
        im.addInstance(vm.Matrix4.translation(b));
      }
      world.refRoot.add(fs.Node(name: 'SkyscraperAviationBeacons')
        ..addComponent(fs.InstancedMeshComponent(im)));
    }
  }

  double _segDist(double e, double t, double n, double r, double i, double a) {
    final o = i - n, s = a - r, c = o * o + s * s;
    final l = c > 1e-6 ? (((e - n) * o + (t - r) * s) / c).clamp(0.0, 1.0) : 0.0;
    final dx = e - (n + l * o), dz = t - (r + l * s);
    return math.sqrt(dx * dx + dz * dz);
  }

  /// `_` in the demo: true when the box stays clear of the segment.
  bool _clear(double x0, double x1, double z0, double z1, double ax, double az, double bx, double bz, double c) {
    final l = (x0 + x1) * 0.5, u = (z0 + z1) * 0.5;
    final p = math.sqrt(math.pow((x1 - x0) * 0.5, 2) + math.pow((z1 - z0) * 0.5, 2));
    if (_segDist(l, u, ax, az, bx, bz) > p + c) return true;
    for (final q in [[l, u], [x0, z0], [x1, z0], [x0, z1], [x1, z1]]) {
      if (_segDist(q[0], q[1], ax, az, bx, bz) < c) return false;
    }
    final hx = (ax + bx) * 0.5, hz = (az + bz) * 0.5;
    return !(hx > x0 - c && hx < x1 + c && hz > z0 - c && hz < z1 + c);
  }

  /// Port of the demo's filler placement test `x()`.
  bool _fillerOk(double e, double t, double n, double r) {
    final i = e - n, d = e + n, g = t - r, x = t + r;
    final slots = level.meta['heroArchSlots'] as Map<String, dynamic>;
    final v = slots['scrambleCorner'] as Map<String, dynamic>?;
    final y = slots['shibuya109'] as Map<String, dynamic>?;
    final b = slots['scrambleMediaFacade'] as Map<String, dynamic>?;
    List<dynamic> pos(Map<String, dynamic> m) => m['pos'] as List<dynamic>;
    double f = -15.0, p = 24.0, m = -18.0, h = 16.0; // drift loop bounds
    final dl = (level.route['scrambleDriftLoop'] as Map<String, dynamic>)['points'] as List<dynamic>?;
    if (dl != null && dl.isNotEmpty) {
      f = 1e9;
      p = -1e9;
      m = 1e9;
      h = -1e9;
      for (final q in dl) {
        final qx = _d(q[0]), qz = _d((q as List).length >= 3 ? q[2] : q[1]);
        f = math.min(f, qx);
        p = math.max(p, qx);
        m = math.min(m, qz);
        h = math.max(h, qz);
      }
    }
    if ((d > -26 && i < 40 && x > -26 && g < 26) ||
        (d > f - 8.5 && i < p + 8.5 && x > m - 8.5 && g < h + 8.5) ||
        (v != null && d > _d(pos(v)[0]) - 17.5 && i < _d(pos(v)[0]) + 17.5 && x > _d(pos(v)[2]) - 15.5 && g < _d(pos(v)[2]) + 15.5) ||
        (y != null && math.sqrt(math.pow(e - _d(pos(y)[0]), 2) + math.pow(t - _d(pos(y)[2]), 2)) < math.sqrt(n * n + r * r) + 17.5) ||
        (b != null && d > _d(pos(b)[0]) - 20 && i < _d(pos(b)[0]) + 20 && x > _d(pos(b)[2]) - 13 && g < _d(pos(b)[2]) + 13) ||
        (d > 204 && i < 274 && x > 224 && g < 300) ||
        !_clear(i, d, g, x, 242.89, 257.3, 266, 190, 26)) {
      return false;
    }
    final a = level.waypoints;
    for (int k = 0; k < a.length - 1; k++) {
      if (!_clear(i, d, g, x, a[k].x, a[k].z, a[k + 1].x, a[k + 1].z, 12.6)) return false;
    }
    for (final w in level.route['wallRuns'] as List<dynamic>) {
      for (final q in w['points'] as List<dynamic>) {
        final qx = _d(q[0]), qz = _d(q[2]);
        if (qx > i - 6 && qx < d + 6 && qz > g - 6 && qz < x + 6) return false;
      }
    }
    for (final w in level.route['grindRails'] as List<dynamic>) {
      for (final q in w['points'] as List<dynamic>) {
        final qx = _d(q[0]), qz = _d(q[2]);
        if (qx > i - 5.5 && qx < d + 5.5 && qz > g - 5.5 && qz < x + 5.5) return false;
      }
    }
    final bays = slots['yamanoteViaductBays'] as List<dynamic>? ?? const [];
    for (int k = 0; k < bays.length; k++) {
      final tp = bays[k]['pos'] as List<dynamic>;
      if (_d(tp[0]) > i - 13 && _d(tp[0]) < d + 13 && _d(tp[2]) > g - 13.5 && _d(tp[2]) < x + 13.5) return false;
      if (k < bays.length - 1) {
        final np = bays[k + 1]['pos'] as List<dynamic>;
        if (!_clear(i, d, g, x, _d(tp[0]), _d(tp[2]), _d(np[0]), _d(np[2]), 12.2)) return false;
      }
    }
    final river = (level.meta['shibuyaRiver'] as Map<String, dynamic>)['points'] as List<dynamic>;
    for (int k = 0; k < river.length - 1; k++) {
      if (!_clear(i, d, g, x, _d(river[k][0]), _d(river[k][1]), _d(river[k + 1][0]), _d(river[k + 1][1]), 11)) {
        return false;
      }
    }
    for (final bb in bounds) {
      if (d + 2.4 > bb[0] && i - 2.4 < bb[1] && x + 2.4 > bb[2] && g - 2.4 < bb[3]) return false;
    }
    for (final sb in slots['shopfrontBlocks'] as List<dynamic>? ?? const []) {
      final tp = sb['pos'] as List<dynamic>;
      if (_d(tp[0]) > i - 13.5 && _d(tp[0]) < d + 13.5 && _d(tp[2]) > g - 13.5 && _d(tp[2]) < x + 13.5) return false;
    }
    return true;
  }
}
