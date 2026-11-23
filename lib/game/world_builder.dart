import 'dart:math' as math;

import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;

import 'glb_library.dart';
import 'level_data.dart';
import 'mesh_buf.dart';
import 'neon_arch.dart';
import 'osm_city.dart';
import 'route_spline.dart';
import 'world_glb.dart';
import 'world_textures.dart';

vm.Vector4 hexColor(String hex, [double scale = 1.0, double alpha = 1.0]) {
  final h = hex.replaceAll('#', '');
  final v = int.parse(h.substring(0, 6), radix: 16);
  double lin(int c) {
    final s = c / 255.0;
    return s <= 0.04045 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
  }

  return vm.Vector4(lin((v >> 16) & 255) * scale, lin((v >> 8) & 255) * scale,
      lin(v & 255) * scale, alpha);
}

fs.PhysicallyBasedMaterial pbr(vm.Vector4 base,
    {vm.Vector4? emissive,
    double metallic = 0.0,
    double roughness = 0.6,
    bool doubleSided = true}) {
  final m = fs.PhysicallyBasedMaterial()
    ..baseColorFactor = base
    ..metallicFactor = metallic
    ..roughnessFactor = roughness
    ..doubleSided = doubleSided;
  if (emissive != null) m.emissiveFactor = emissive;
  return m;
}

fs.UnlitMaterial unlit(vm.Vector4 color) => fs.UnlitMaterial()
  ..baseColorFactor = color
  ..doubleSided = true;

/// A neon prop whose glow can be ignited at runtime.
class GlowProp {
  GlowProp(this.material, this.baseEmissive,
      {this.litScale = 2.2, this.letterIndex = -1, this.core = false});

  /// Google sign: true for a letter's core, false for its glass shell.
  final bool core;
  final fs.PhysicallyBasedMaterial material;
  final vm.Vector4 baseEmissive;
  final double litScale;
  final int letterIndex;
  bool lit = false;

  /// Plasma tube state (`aGlow` attribute + flash), ring/gate colour.
  double glow = 0, flash = 0;
  vm.Vector3 color = vm.Vector3(0.0, 0.5, 1.0);

  void setLit(bool v, [double pulse = 1.0]) {
    lit = v;
    final k = v ? litScale * pulse : 1.0;
    material.emissiveFactor = vm.Vector4(
        baseEmissive.x * k, baseEmissive.y * k, baseEmissive.z * k, 1);
  }
}

class RingProp {
  RingProp(this.node, this.glow, this.data);
  final fs.Node node;
  final GlowProp glow;
  final Map<String, dynamic> data;
}

/// Static + semi-static 3D content of the Shibuya route, built once from
/// [ShibuyaLevel] data in the reference's coordinates (mirrored via [w3]).
class ShibuyaWorld {
  ShibuyaWorld(this.level, this.spline, this.tex, this.glb);

  final ShibuyaLevel level;
  final RouteSpline spline;
  final WorldTextures tex;
  final GlbLibrary glb;

  final fs.Node root = fs.Node(name: 'shibuya_world');

  /// Holds content placed directly in the demo's right-handed three.js
  /// coordinates (glTF models); mirrors Z into Flutter Scene's view frame.
  final fs.Node refRoot = fs.Node(name: 'ref_frame')
    ..localTransform = vm.Matrix4.diagonal3Values(1, 1, -1);
  late final GlbWorld glbWorld;
  final List<RingProp> rings = [];
  final List<GlowProp> pinGates = [];
  final List<GlowProp> slidePortals = [];
  final List<NeonArchRig> archRigs = [];
  final List<GlowProp> googleLetters = [];
  final List<GlowProp> bladeSigns = [];
  /// One material per grind rail (index = route grindRails order).
  final List<fs.PhysicallyBasedMaterial> railMats = [];
  final List<fs.PhysicallyBasedMaterial> wallRunMats = [];
  fs.PhysicallyBasedMaterial? beaconMat;
  final List<List<double>> _footprintBoxes = [];

  void build() {
    root.add(refRoot);
    _ground();
    _grindRails();
    _wallRuns();
    _river();
    _secondaryRoads();
    _transferGuides();
    _ringPiers();
    _barriers();
    _distantSkyline();
    glbWorld = GlbWorld(this, glb)..build();
  }

  /// Builds the OSM city (async: paints the facade textures).
  Future<void> buildCity() async {
    final city = OsmCity(this);
    await city.build();
    _footprintBoxes.addAll(city.bounds);
  }

  /// Photo-camera colliders: [minX,maxX,minY,maxY,minZ,maxZ] (demo's
  /// `_photoColliders`), from the OSM city plus the hero arch boxes.
  List<List<double>> get photoColliders => [
        for (final b in _footprintBoxes)
          [b[0], b[1], 0.0, b.length > 4 ? b[4] : 30.0, b[2], b[3]],
        [209, 260, 0, 182, 254, 295],
        [223, 269, 0, 22.1, 237, 262],
        ...glbWorld.colliders,
      ];

  /// Rough footprint test (axis-aligned boxes of the OSM buildings).
  bool insideBuilding(double x, double z, double pad) {
    for (final b in _footprintBoxes) {
      if (x > b[0] - pad && x < b[1] + pad && z > b[2] - pad && z < b[3] + pad) {
        return true;
      }
    }
    return false;
  }

  void _add(MeshBuf b, fs.Material m, [String name = '']) {
    if (b.isEmpty) return;
    root.add(fs.Node(name: name, mesh: fs.Mesh(b.build(), m)));
  }

  // ---------------------------------------------------------------- ground
  late final fs.PhysicallyBasedMaterial mapsOverlayMat;
  late final fs.Node mapsOverlay;
  final List<fs.Node> dropPin = [];

  /// `_isInsideScramblePlaza`: the demo's axis-aligned plaza box.
  bool inScramblePlaza(double x, double z) => x >= -24 && x <= 38 && z >= -24 && z <= 24;


  void _ground() {
    final up = vm.Vector3(0, 1, 0);
    // ShibuyaMirrorWetAsphalt: 1180 m dark slate tarmac (#111C2D).
    final asphalt = MeshBuf();
    asphalt.quad(w3(-590, 0, -590), w3(590, 0, -590), w3(590, 0, 590),
        w3(-590, 0, 590), up,
        u0: 0, v0: 0, u1: 1180 / 72, v1: 1180 / 72);
    _add(
        asphalt,
        // roughness 1 x puddle map (A/B'd against the demo at 320/410).
        pbr(hexColor('#111C2D'), emissive: hexColor('#08101E', 0.24), roughness: 1.0, metallic: 1.0)
          ..metallicRoughnessTexture = tex.wetAsphalt
          // world-space puddle map: one texture spans the whole plane
          ..metallicRoughnessTextureTransform = fs.TextureTransform(scale: vm.Vector2.all(72 / 1180))
          // wg() normal map, repeat 280 over 1180 m (one tile / 4.2 m), scale .1
          ..normalTexture = tex.asphaltNormal
          ..normalScale = 0.1
          ..normalTextureTransform = fs.TextureTransform(scale: vm.Vector2.all(72 / (1180 / 280)))
          // three.js envMapIntensity .24 has no per-material twin here; specular
          // .5 matches the demo's ground reflections best (A/B'd at 320/680 m).
          ..specular = 0.5,
        'ShibuyaMirrorWetAsphalt');

    // DarkModeGoogleMapsGround overlay; fades out during the sky drop.
    final b = level.overview['bounds'] as Map<String, dynamic>;
    final minX = (b['minX'] as num).toDouble();
    final maxX = (b['maxX'] as num).toDouble();
    final minZ = (b['minZ'] as num).toDouble();
    final maxZ = (b['maxZ'] as num).toDouble();
    final buf = MeshBuf();
    buf.quad(w3(minX, 0.055, minZ), w3(maxX, 0.055, minZ), w3(maxX, 0.055, maxZ),
        w3(minX, 0.055, maxZ), up,
        u0: 0, v0: 0, u1: 1, v1: 1);
    mapsOverlayMat = fs.PhysicallyBasedMaterial(baseColorTexture: tex.ground, emissiveTexture: tex.ground)
      ..baseColorFactor = vm.Vector4(0, 0, 0, 1)
      ..emissiveFactor = vm.Vector4(1, 1, 1, 1)
      ..alphaMode = fs.AlphaMode.blend
      ..doubleSided = true;
    mapsOverlay = fs.Node(name: 'maps_overlay', mesh: fs.Mesh(buf.build(), mapsOverlayMat));
    root.add(mapsOverlay);

    // Google Maps drop-pin rings at the start waypoint.
    final w0 = level.waypoints.first;
    fs.Node ring(double r0, double r1, String hex, double op, double y) {
      final g = r0 <= 0
          ? fs.DiscGeometry(radius: r1, segments: 64)
          : fs.RingGeometry(innerRadius: r0, outerRadius: r1, segments: 64);
      final m = fs.UnlitMaterial()
        ..baseColorFactor = hexColor(hex, 1, op)
        ..alphaMode = fs.AlphaMode.blend
        ..doubleSided = true;
      final n = fs.Node(mesh: fs.Mesh(g, m))..position = w3(w0.x, y, w0.z);
      root.add(n);
      dropPin.add(n);
      return n;
    }

    ring(0, 10.5, '#FBBC05', 0.22, 0.095);
    ring(9.2, 10.6, '#FBBC05', 0.96, 0.096);
    ring(10.8, 11.6, '#FDE68A', 0.56, 0.097);
    ring(0, 3.4, '#FF4F00', 0.98, 0.098);
    ring(3.4, 4.0, '#FFFFFF', 0.92, 0.099);

    _sidewalksAndMarkings();
  }

  /// `_buildGraniteSidewalks` + `_buildScrambleCrosswalks` (road paint).
  void _sidewalksAndMarkings() {
    final wps = level.waypoints;
    final side = MeshBuf();
    final paint = MeshBuf();
    const n = 7.25, r = 4.4, i = 0.18, a = 0.24;
    for (int o = 0; o < wps.length - 1; o++) {
      final s0 = wps[o], c = wps[o + 1];
      if (s0.y > 0.25 || c.y > 0.25) continue;
      final l = (s0.x + c.x) * 0.5, u = (s0.z + c.z) * 0.5;
      if (inScramblePlaza(l, u) || (l > 230 && u > 205)) continue;
      final dx = c.x - s0.x, dz = c.z - s0.z;
      final p = math.sqrt(dx * dx + dz * dz);
      if (p < 0.8) continue;
      final m = dx / p, h = dz / p, g = -h, gz = m;
      final yaw = mirrorYaw(math.atan2(m, h));
      final y = p + 0.85;
      for (final e in [-1.0, 1.0]) {
        final ox = l + g * e * 9.45, oz = u + gz * e * 9.45;
        if (inScramblePlaza(ox, oz)) continue;
        // BoxGeometry uvs scaled (r / 2.2, y / 2.2): one Eg tile per 2.2 m.
        side.box(w3(ox, i * 0.5, oz), vm.Vector3(r, i, y), yaw, uScale: r / 2.2, vScale: y / 2.2);
        final fx = l + g * e * (n - a * 0.35), fz = u + gz * e * (n - a * 0.35);
        side.box(w3(fx, i * 0.42, fz), vm.Vector3(a, i * 0.84, y), yaw);
      }
    }
    // color #1E2736 x Eg paving map, roughness .78 x Eg roughness map
    // (72..130 per slab -> .22..40: each slab catches the moon), metal .06.
    _add(
        side,
        fs.PhysicallyBasedMaterial(baseColorTexture: tex.sidewalk, metallicRoughnessTexture: tex.sidewalkRough)
          ..baseColorFactor = hexColor('#1E2736')
          ..roughnessFactor = 0.78
          ..metallicFactor = 0.06
          ..emissiveFactor = hexColor('#0A101A')
          ..doubleSided = true,
        'ShibuyaGraniteSidewalks');

    void flat(double x, double z, double w, double len, double yawRef, [double y = 0.025]) {
      paint.box(w3(x, y, z), vm.Vector3(w, 0.004, len), mirrorYaw(yawRef));
    }

    // Scramble crosswalk stripes.
    for (final cw in level.streets['crosswalks'] as List<dynamic>) {
      final st = cw['start'] as List<dynamic>, en = cw['end'] as List<dynamic>;
      final ax = (st[0] as num).toDouble(), az = (st[1] as num).toDouble();
      final sx = (en[0] as num).toDouble() - ax, sz = (en[1] as num).toDouble() - az;
      final len = math.sqrt(sx * sx + sz * sz);
      if (len < 1.5) continue;
      final ux = sx / len, uz = sz / len;
      final w = ((cw['width'] as num?)?.toDouble() ?? 8).clamp(3.5, 10.5);
      final cnt = (cw['stripeCount'] as num?)?.toInt() ?? math.max(4, (len / 1.65).floor());
      final g = (len / math.max(1, cnt) * 0.48).clamp(0.56, 0.9);
      final yaw = math.atan2(ux, uz);
      for (int e = 0; e < cnt; e++) {
        final t = (e + 0.5) / cnt;
        // stripe: width w across the walk, depth g along it
        paint.box(w3(ax + sx * t, 0.025, az + sz * t), vm.Vector3(w, 0.004, g),
            mirrorYaw(yaw));
      }
    }
    // Lane dashes (±1.8) and edge lines (±5.4) every 7.5 m along the route.
    double acc = 0;
    for (int e = 0; e < wps.length - 1; e++) {
      final p0 = wps[e], p1 = wps[e + 1];
      if (p0.y > 0.25 || p1.y > 0.25) continue;
      final dx = p1.x - p0.x, dz = p1.z - p0.z;
      final c = math.sqrt(dx * dx + dz * dz);
      if (c < 0.5) continue;
      final l = dx / c, u = dz / c, d = -u, f = l, yaw = math.atan2(l, u);
      for (double k = 0; k < c; k += 1.5) {
        acc += 1.5;
        if (acc < 7.5) continue;
        acc = 0;
        final rx = p0.x + l * k, rz = p0.z + u * k;
        if (inScramblePlaza(rx, rz)) continue;
        for (final o in [-1.8, 1.8, -5.4, 5.4]) {
          final edge = o.abs() > 4;
          flat(rx + d * o, rz + f * o, edge ? 0.16 : 0.18, edge ? 4.4 : 2.6, yaw, 0.022);
        }
      }
    }
    // Lane arrows every 40 m, stop bars every 95 m.
    double o = 0, sb = 0;
    for (int e = 0; e < wps.length - 1; e++) {
      final p0 = wps[e], p1 = wps[e + 1];
      if (p0.y > 0.25 || p1.y > 0.25) continue;
      final dx = p1.x - p0.x, dz = p1.z - p0.z;
      final u = math.sqrt(dx * dx + dz * dz);
      if (u < 0.8) continue;
      final d = dx / u, f = dz / u, px = -f, pz = d, yaw = math.atan2(d, f);
      o += u;
      sb += u;
      final gx = (p0.x + p1.x) * 0.5, gz = (p0.z + p1.z) * 0.5;
      if (inScramblePlaza(gx, gz)) continue;
      if (o >= 40) {
        o = 0;
        for (final lat in [-3.6, 0.0, 3.6]) {
          final ax = gx + px * lat, az = gz + pz * lat;
          const k = 0.96;
          flat(ax - d * 0.55 * k, az - f * 0.55 * k, 0.32 * k, 2.55 * k, yaw, 0.024);
          // arrow head: ShapeGeometry triangle (-.74,.45) (0,1.95) (.74,.45)
          vm.Vector3 hp(double lat, double fwd) =>
              w3(ax + px * lat * k + d * fwd * k, 0.024, az + pz * lat * k + f * fwd * k);
          final up = vm.Vector3(0, 1, 0);
          final q0 = hp(-0.74, 0.45), q1 = hp(0, 1.95), q2 = hp(0.74, 0.45);
          final h0 = paint.vertex(q0, up, 0, 0);
          final h1 = paint.vertex(q1, up, 0.5, 1);
          final h2 = paint.vertex(q2, up, 1, 0);
          // single winding facing +Y (a doubled back face would z-fight
          // with a flipped normal and read dark)
          if ((q1 - q0).cross(q2 - q0).y >= 0) {
            paint.tri(h0, h1, h2);
          } else {
            paint.tri(h0, h2, h1);
          }
        }
      }
      if (sb >= 95) {
        sb = 0;
        flat(gx, gz, 10.8, 0.46, yaw, 0.023);
      }
    }
    _add(paint, pbr(hexColor('#DCE4EE'), emissive: hexColor('#1A2438', 0.12), roughness: 0.34, metallic: 0.04),
        'ScrambleCrosswalksSAT');
  }



  /// Warm ground-floor shopfront band on walls facing within 40 m of the route.



  /// Extrudes a footprint into walls (UV-tiled windows) and a flat roof.
  void _prism(MeshBuf walls, MeshBuf roofs, List<XZ> fp, double y0, double y1) {
    final pts = List<XZ>.from(fp);
    if (pts.length > 3 &&
        (pts.first.x - pts.last.x).abs() < 1e-3 &&
        (pts.first.z - pts.last.z).abs() < 1e-3) {
      pts.removeLast();
    }
    if (pts.length < 3) return;
    // Signed area to orient outward normals.
    double area = 0;
    for (int i = 0, j = pts.length - 1; i < pts.length; j = i++) {
      area += pts[j].x * pts[i].z - pts[i].x * pts[j].z;
    }
    final sign = area >= 0 ? 1.0 : -1.0;
    double u = 0;
    const tileW = 5.6; // 8 windows across 5.6 m
    const tileH = 28.8; // 16 floors (1.8 m) per texture tile
    for (int i = 0; i < pts.length; i++) {
      final a = pts[i], b = pts[(i + 1) % pts.length];
      final dx = b.x - a.x, dz = b.z - a.z;
      final len = math.sqrt(dx * dx + dz * dz);
      if (len < 0.05) continue;
      // outward normal in reference frame, then mirror z
      final nx = dz / len * sign, nz = -dx / len * sign;
      final n = vm.Vector3(-nx, 0, nz);
      walls.quad(w3(a.x, y0, a.z), w3(b.x, y0, b.z), w3(b.x, y1, b.z),
          w3(a.x, y1, a.z), n,
          u0: u / tileW,
          u1: (u + len) / tileW,
          v0: 1 - y0 / tileH,
          v1: 1 - y1 / tileH);
      u += len;
    }
    final flat = <double>[for (final q in pts) ...[q.x, q.z]];
    final tris = triangulatePolygon(flat);
    final base = roofs.vertexCount;
    final up = vm.Vector3(0, 1, 0);
    for (final q in pts) {
      roofs.vertex(w3(q.x, y1, q.z), up, q.x / 20, q.z / 20);
    }
    for (int i = 0; i + 2 < tris.length; i += 3) {
      roofs.tri(base + tris[i], base + tris[i + 1], base + tris[i + 2]);
    }
  }




  // ------------------------------------------------------------ grind rails
  void _grindRails() {
    // _buildGrindRailsAndSupportPiers: steel piers r (#336455 x? -> #334155
    // rough .42 metal .78), concrete i (#2B3952 rough .74), girders a under
    // hero / ramp / sky rails (#1E2A3F rough .48 metal .68).
    final steel = MeshBuf(), concrete = MeshBuf(), girders = MeshBuf();
    vm.Vector3 v(double x, double y, double z) => w3(x, y, z);
    void bar(MeshBuf m, double x0, double y0, double z0, double x1, double y1, double z1, [double c = 0.095]) {
      if (math.sqrt(math.pow(x1 - x0, 2) + math.pow(y1 - y0, 2) + math.pow(z1 - z0, 2)) < 0.08) return;
      m.cylinder(v(x0, y0, z0), v(x1, y1, z1), c, c * 1.12);
    }

    for (final r in level.route['grindRails'] as List<dynamic>) {
      final raw = [
        for (final p in r['points'] as List<dynamic>)
          vm.Vector3((p[0] as num).toDouble(), (p[1] as num).toDouble(), (p[2] as num).toDouble()),
      ];
      final pts = [for (final p in raw) w3(p.x, p.y, p.z)];
      final isHero = r['heroRailLaunch'] == true;
      final radius = isHero ? 0.14 : 0.105;
      final rb = MeshBuf();
      _tube(rb, pts, radius * 1.06);
      final rm = pbr(isHero ? hexColor('#38BDF8') : hexColor('#2E405E'),
          emissive: isHero ? hexColor('#38BDF8', 1.55) : hexColor('#FF4F00', 0.72),
          metallic: 0.72, roughness: 0.18);
      railMats.add(rm);
      _add(rb, rm, 'GrindRail_${r['id']}');
      if (isHero || r['kind'] == 'ramp_rail' || r['kind'] == 'yamanote_sky_rail') {
        _tube(girders, [for (final p in raw) w3(p.x, math.max(0.14, p.y - 0.28), p.z)], isHero ? 0.28 : 0.15,
            sides: 6);
      }
      for (final p in (r['posts'] as List<dynamic>? ?? const [])) {
        double d(String k, double f) => (p[k] as num?)?.toDouble() ?? f;
        final x = d('x', 0), z = d('z', 0);
        final n = d('yBase', 0), a = d('yTop', 1);
        final o = math.max(0.18, a - n);
        if (p['cantilevered'] == true && p['railX'] != null && p['railZ'] != null) {
          final rx = d('railX', x), rz = d('railZ', z);
          concrete.box(v(x, n + 0.17, z), vm.Vector3(0.68, 0.34, 0.68), 0);
          final c = math.max(0.4, o - 0.12);
          steel.cylinder(v(x, n + 0.24, z), v(x, n + 0.24 + c, z), 0.15, 0.2);
          final u = a - 0.12;
          bar(steel, x, u, z, rx, u, rz, 0.095);
          final mx = x + (rx - x) * 0.64, mz = z + (rz - z) * 0.64;
          bar(steel, x, math.max(n + 2.65, u - 0.95), z, mx, u - 0.04, mz, 0.068);
          steel.cylinder(v(rx, a - 0.14, rz), v(rx, a, rz), 0.11, 0.13);
        } else if (o > 2.2) {
          concrete.box(v(x, n + 0.225, z), vm.Vector3(1.85, 0.45, 1.85), 0);
          final top = a - (isHero ? 0.34 : 0.16);
          final cap = math.max(n + 0.55, top - 0.44);
          final sh = math.max(0.28, cap - (n + 0.45));
          concrete.cylinder(v(x, n + 0.45, z), v(x, n + 0.45 + sh, z), 0.36, 0.52);
          final ch = math.max(0.18, top - cap);
          concrete.cylinder(v(x, (top + cap) / 2 - ch / 2, z), v(x, (top + cap) / 2 + ch / 2, z),
              isHero ? 0.42 : 0.52, 0.36);
        } else if (isHero && n >= 20) {
          steel.cylinder(v(x, n, z), v(x, n + 0.14, z), 0.26, 0.34, seg: 12);
          final h = math.max(0.14, o - 0.16);
          steel.cylinder(v(x, n, z), v(x, n + h, z), 0.11, 0.14);
        } else {
          steel.cylinder(v(x, n, z), v(x, n + 0.06, z), 0.16, 0.18);
          final h = math.max(0.14, o - (isHero ? 0.16 : 0.06));
          steel.cylinder(v(x, n, z), v(x, n + h, z), 0.065, 0.085, seg: 6);
        }
      }
    }
    _add(steel, pbr(hexColor('#334155'), metallic: 0.78, roughness: 0.42), 'GrindRailCantileverPiers');
    _add(girders, pbr(hexColor('#1E2A3F'), metallic: 0.68, roughness: 0.48), 'GrindRailStructuralGirders');
    _add(concrete, pbr(hexColor('#2B3952'), metallic: 0.16, roughness: 0.74), 'HeroLaunchConcretePiers');
  }

  void _tube(MeshBuf buf, List<vm.Vector3> pts, double r, {int sides = 8}) {
    // densify with Catmull-Rom for smooth bends
    final dense = <vm.Vector3>[];
    for (int i = 0; i + 1 < pts.length; i++) {
      final p0 = pts[math.max(0, i - 1)], p1 = pts[i], p2 = pts[i + 1];
      final p3 = pts[math.min(pts.length - 1, i + 2)];
      for (int k = 0; k < 4; k++) {
        final t = k / 4;
        final t2 = t * t, t3 = t2 * t;
        dense.add((p1 * 2 +
                (p2 - p0) * t +
                (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2 +
                (p1 * 3 - p0 - p2 * 3 + p3) * t3) *
            0.5);
      }
    }
    dense.add(pts.last);
    vm.Vector3 prevN = vm.Vector3(0, 1, 0);
    final rings = <List<int>>[];
    for (int i = 0; i < dense.length; i++) {
      final t = (dense[math.min(dense.length - 1, i + 1)] -
              dense[math.max(0, i - 1)])
          .normalized();
      var side = t.cross(prevN);
      if (side.length2 < 1e-6) side = t.cross(vm.Vector3(1, 0, 0));
      side.normalize();
      final nrm = side.cross(t).normalized();
      prevN = nrm;
      final ring = <int>[];
      for (int k = 0; k < sides; k++) {
        final a = k / sides * math.pi * 2;
        final dir = nrm * math.cos(a) + side * math.sin(a);
        ring.add(buf.vertex(dense[i] + dir * r, dir, k / sides, i / 4));
      }
      rings.add(ring);
    }
    for (int i = 0; i + 1 < rings.length; i++) {
      for (int k = 0; k < sides; k++) {
        final a = rings[i][k], b = rings[i][(k + 1) % sides];
        final c = rings[i + 1][(k + 1) % sides], d = rings[i + 1][k];
        buf.tri(a, b, c);
        buf.tri(a, c, d);
      }
    }
  }

  // ------------------------------------------------------------- wall runs
  void _wallRuns() {
    // _buildWallRunsAndTransferArcs: 0.18 m chevron panels (Lg texture),
    // centre at y + h*0.46, height h*0.78, plus support pylons.
    final pylons = MeshBuf();
    for (final wr in level.route['wallRuns'] as List<dynamic>) {
      final panels = MeshBuf();
      final a = wr['points'] as List<dynamic>;
      final sH = (wr['height'] as num?)?.toDouble() ?? 5.4;
      for (int e = 0; e + 1 < a.length; e++) {
        final t = a[e], n = a[e + 1];
        double v(dynamic x) => (x as num).toDouble();
        final ix = v(n[0]) - v(t[0]), cz = v(n[2]) - v(t[2]);
        final l = math.sqrt(ix * ix + cz * cz);
        if (l < 0.2) continue;
        final u = math.atan2(ix, cz);
        final dx = (v(t[0]) + v(n[0])) * 0.5, fy = (v(t[1]) + v(n[1])) * 0.5 + sH * 0.46;
        final pz = (v(t[2]) + v(n[2])) * 0.5;
        // two big faces with u running along the wall (repeat every 10 m)
        final hw = 0.09, hh = sH * 0.39, hl = (l + 0.15) / 2;
        final ca = math.cos(u), sa = math.sin(u);
        vm.Vector3 p(double lx, double ly, double lz) =>
            vm.Vector3(dx + lx * ca + lz * sa, fy + ly, pz - lx * sa + lz * ca);
        for (final sd in [-1.0, 1.0]) {
          final nrm = vm.Vector3(sd * ca, 0, -sd * sa);
          panels.quad(p(sd * hw, -hh, -hl), p(sd * hw, -hh, hl), p(sd * hw, hh, hl), p(sd * hw, hh, -hl),
              nrm, u0: l / 10, u1: 0, v0: 1, v1: 0);
        }
        if (e % 2 == 0 || e == a.length - 2) {
          final base = v(t[1]) > 5 ? 7.5 : 0.0;
          final h = math.max(1.0, v(t[1]) + sH * 0.85 - base);
          pylons.box(vm.Vector3(v(t[0]), base + h * 0.5, v(t[2])), vm.Vector3(0.32, h, 0.32), 0);
        }
      }
      // color #0F1C32 x map, emissive #38BDF8 x map @0.95 (2.6 while the
      // hero runs on it: uActiveWallIdx), transparent 0.84.
      final m = fs.PhysicallyBasedMaterial(baseColorTexture: tex.wallRun, emissiveTexture: tex.wallRun)
        ..baseColorFactor = hexColor('#0F1C32', 1, 0.84)
        ..emissiveFactor = hexColor('#38BDF8', 0.95)
        ..roughnessFactor = 0.14
        ..metallicFactor = 0.35
        ..alphaMode = fs.AlphaMode.blend
        ..doubleSided = true;
      wallRunMats.add(m);
      if (!panels.isEmpty) {
        refRoot.add(fs.Node(name: 'WallRunPanel_${wr['id']}', mesh: fs.Mesh(panels.build(), m)));
      }
    }
    if (!pylons.isEmpty) {
      refRoot.add(fs.Node(
          name: 'WallRunSupportPylons',
          mesh: fs.Mesh(pylons.build(), pbr(hexColor('#1C2536'), roughness: 0.5, metallic: 0.72))));
    }
  }



  // ----------------------------------- BoostRingCantileverPiers (demo)
  /// Steel cantilever piers for rings elevated over traffic (#1B2434,
  /// rough .42, metal .78).
  void _ringPiers() {
    final o = MeshBuf();
    double d(dynamic v, [double f = 0]) => (v as num?)?.toDouble() ?? f;
    double lerp(double a, double b, double t) => a + (b - a) * t;
    void bar(double x0, double y0, double z0, double x1, double y1, double z1, double c) {
      o.cylinder(vm.Vector3(x0, y0, z0), vm.Vector3(x1, y1, z1), c, c);
    }

    for (final t in level.route['boostRings'] as List<dynamic>) {
      if (t['elevatedOverTraffic'] != true || t['pierX'] == null || t['pierZ'] == null) continue;
      final pos = t['pos'] as List<dynamic>;
      final gy = t['groundY'] != null ? d(t['groundY']) : (d(pos[1]) > 7.8 ? 7.5 : 0.0);
      final r = t['bottomY'] != null ? d(t['bottomY']) : gy;
      final s = r - gy;
      if (s < 0.5) continue;
      final l = d(pos[0]), u = d(pos[2]), px = d(t['pierX']), pz = d(t['pierZ']), yaw = d(t['yaw']);
      final m = s + 0.34;
      o.box(vm.Vector3(px, gy + m * 0.5, pz), vm.Vector3(0.28, m, 0.28), yaw);
      o.box(vm.Vector3(px, gy + 0.11, pz), vm.Vector3(0.62, 0.22, 0.62), yaw);
      final yb = r + 0.08, vx = l - px, vz = u - pz, b = math.sqrt(vx * vx + vz * vz);
      if (b > 0.1) {
        o.box(vm.Vector3((px + l) / 2, yb, (pz + u) / 2), vm.Vector3(0.24, 0.2, b + 0.36), math.atan2(vx, vz));
        final tt = gy + (s >= 2.2 ? 1.94 : 1.69);
        bar(px, math.max(tt, r - 0.31), pz, lerp(px, l, 0.48), r + 0.04, lerp(pz, u, 0.48), 0.075);
        bar(px, r + 0.3, pz, lerp(px, l, 0.62), yb + 0.06, lerp(pz, u, 0.62), 0.055);
      }
      o.box(vm.Vector3(l, r + 0.06, u), vm.Vector3(0.84, 0.16, 0.48), yaw);
    }
    if (o.isEmpty) return;
    refRoot.add(fs.Node(
        name: 'BoostRingCantileverPiers',
        mesh: fs.Mesh(o.build(), pbr(hexColor('#1B2434'), metallic: 0.78, roughness: 0.42))));
  }

  // ---------------------------------- WallToRailTransferGuides (demo)
  /// Six faint cyan dashes (r .032 tubes, #38BDF8 @ .3 additive) along each
  /// wall-to-rail jump's quadratic arc (launch -> apex -> land).
  void _transferGuides() {
    final buf = MeshBuf();
    for (final t in (level.route['wallToRailTransfers'] as List<dynamic>? ?? const [])) {
      vm.Vector3? v(String k) {
        final p = t[k] as List<dynamic>?;
        return p == null
            ? null
            : vm.Vector3((p[0] as num).toDouble(), (p[1] as num).toDouble(), (p[2] as num).toDouble());
      }

      final a = v('launchPos'), b = v('apexPos'), c = v('landPos');
      if (a == null || b == null || c == null || a.distanceTo(c) > 28) continue;
      vm.Vector3 q(double u) => a * ((1 - u) * (1 - u)) + b * (2 * u * (1 - u)) + c * (u * u);
      for (int e = 0; e < 6; e++) {
        final t0 = 0.14 + e / 6 * 0.72, t1 = math.min(0.88, t0 + 0.068);
        final pts = [for (int k = 0; k <= 4; k++) q(t0 + (t1 - t0) * k / 4)];
        _tube(buf, [for (final p in pts) w3(p.x, p.y, p.z)], 0.032, sides: 5);
      }
    }
    if (buf.isEmpty) return;
    _add(buf, unlit(hexColor('#38BDF8', 1.4, 0.3))..alphaMode = fs.AlphaMode.blend,
        'WallToRailTransferGuides');
  }

  // ------------------------------------------ SecondaryOsmRoads (demo)
  /// `_buildSecondaryOsmRoads`: 14 m tiles of the OSM side streets (width
  /// clamped 5.2..15.5) away from the route (>= 11.5 m) and the Scramble
  /// plaza / Stream podium; damp #16222E tarmac (rough .48) that reads much
  /// darker than the moonlit wet asphalt around it.
  void _secondaryRoads() {
    final ways = (level.streets['ways'] as List<dynamic>?) ?? const [];
    final wps = level.waypoints;
    double routeDist(double x, double z) {
      var best = double.infinity;
      for (int i = 0; i + 1 < wps.length; i++) {
        final a = wps[i], o = wps[i + 1];
        if (a.y > 0.35 && o.y > 0.35) continue;
        final sx = o.x - a.x, sz = o.z - a.z, l = sx * sx + sz * sz;
        final u = l > 1e-6 ? (((x - a.x) * sx + (z - a.z) * sz) / l).clamp(0.0, 1.0) : 0.0;
        final dx = x - (a.x + u * sx), dz = z - (a.z + u * sz);
        best = math.min(best, dx * dx + dz * dz);
      }
      return math.sqrt(best);
    }

    final buf = MeshBuf();
    final marks = MeshBuf();
    final up = vm.Vector3(0, 1, 0);
    // Flat w x l rectangle centred at (x, z), long axis along (l, u).
    void rect(MeshBuf m, double x, double z, double l, double u, double w, double len, double y) {
      final hw = w / 2, hl = len / 2;
      vm.Vector3 p(double a, double b) => vm.Vector3(x + u * a + l * b, y, z - l * a + u * b);
      m.quad(p(-hw, -hl), p(hw, -hl), p(hw, hl), p(-hw, hl), up);
    }

    for (final w in ways) {
      // Only the demo's SecondaryOsmRoads list (`Pf`) carries lane data.
      if (w['lanes'] == null) continue;
      final pts = w['points'] as List<dynamic>?;
      if (pts == null || pts.length < 2) continue;
      final width = ((w['width'] as num?)?.toDouble() ?? 9).clamp(5.2, 15.5);
      // Centre dashes + Scramble stop bar (`_buildScrambleCrosswalks`).
      final radiates = w['radiatesFromScramble'] == true;
      if (radiates || ((w['lanes'] as num?) ?? 0) >= 2 || ((w['width'] as num?) ?? 0) >= 9) {
        for (int e = 0; e + 1 < pts.length; e++) {
          final i0 = pts[e] as List<dynamic>, a0 = pts[e + 1] as List<dynamic>;
          final ix = (i0[0] as num).toDouble(), iz = (i0[1] as num).toDouble();
          final ox = (a0[0] as num).toDouble() - ix, oz = (a0[1] as num).toDouble() - iz;
          final c = math.sqrt(ox * ox + oz * oz);
          if (c < 4.5) continue;
          final l = ox / c, u = oz / c;
          for (double t = 3; t < c - 3; t += 11.5) {
            final nx = ix + l * t, nz = iz + u * t;
            if (inScramblePlaza(nx, nz) || (nx > 218 && nx < 268 && nz > 186 && nz < 265) || routeDist(nx, nz) < 11.5) {
              continue;
            }
            rect(marks, nx, nz, l, u, 0.22, 3.4, 0.021);
          }
          if (radiates && e == 0 && c >= 10) {
            final sx = ix + l * 4, sz = iz + u * 4;
            if (!inScramblePlaza(sx, sz) && routeDist(sx, sz) >= 12.5) {
              rect(marks, sx, sz, l, u, (width * 0.78).clamp(5.0, 10.0), 0.42, 0.021);
            }
          }
        }
      }
      for (int e = 0; e + 1 < pts.length; e++) {
        final n = pts[e] as List<dynamic>, r = pts[e + 1] as List<dynamic>;
        final nx = (n[0] as num).toDouble(), nz = (n[1] as num).toDouble();
        final ox = (r[0] as num).toDouble() - nx, oz = (r[1] as num).toDouble() - nz;
        final c = math.sqrt(ox * ox + oz * oz);
        if (c < 1.2) continue;
        final l = ox / c, u = oz / c;
        final f = math.max(1, (c / 14).ceil());
        final pl = c / f;
        for (int k = 0; k < f; k++) {
          final rr = (k + 0.5) * pl;
          final cx = nx + l * rr, cz = nz + u * rr;
          if (inScramblePlaza(cx, cz) || (cx > 218 && cx < 268 && cz > 186 && cz < 265) || routeDist(cx, cz) < 11.5) {
            continue;
          }
          final hw = width / 2, hl = (pl + 0.9) / 2;
          // right = (u, -l) in the reference frame
          vm.Vector3 p(double a, double b) => vm.Vector3(cx + u * a + l * b, 0.012, cz - l * a + u * b);
          buf.quad(p(-hw, -hl), p(hw, -hl), p(hw, hl), p(-hw, hl), vm.Vector3(0, 1, 0));
        }
      }
    }
    if (!marks.isEmpty) {
      refRoot.add(fs.Node(
          name: 'SecondaryRoadMarkings',
          mesh: fs.Mesh(marks.build(),
              pbr(hexColor('#DCE4EE'), emissive: hexColor('#1A2438', 0.12), roughness: 0.34, metallic: 0.04))));
    }
    if (buf.isEmpty) return;
    refRoot.add(fs.Node(
        name: 'SecondaryOsmRoads',
        mesh: fs.Mesh(buf.build(),
            pbr(hexColor('#162236'), emissive: hexColor('#0A1221', 0.22), roughness: 0.48, metallic: 0.06)
              ..specular = 0.5)));
  }

  // ------------------------------------------- ShibuyaRiverWater (demo)
  /// `_buildShibuyaRiverCanal`: 12 m glossy water panels along the OSM river
  /// way (#07182F, emissive #0C284D x.34, roughness .08, metalness .28) plus
  /// .65 x .42 m curbs on both banks.
  final List<fs.PhysicallyBasedMaterial> riverMats = [];
  void _river() {
    final r = level.meta['shibuyaRiver'] as Map<String, dynamic>?;
    final pts = (r?['points'] as List<dynamic>?) ?? const [];
    if (pts.length < 2) return;
    final n = ((r!['width'] as num?)?.toDouble() ?? 12) * 0.5;
    final water = MeshBuf();
    final curbs = MeshBuf();
    for (int e = 0; e + 1 < pts.length; e++) {
      double v(dynamic x) => (x as num).toDouble();
      final a = pts[e] as List<dynamic>, o = pts[e + 1] as List<dynamic>;
      final dx = v(o[0]) - v(a[0]), dz = v(o[1]) - v(a[1]);
      final l = math.sqrt(dx * dx + dz * dz);
      if (l < 1) continue;
      final u = math.atan2(dx, dz);
      final cx = (v(a[0]) + v(o[0])) * 0.5, cz = (v(a[1]) + v(o[1])) * 0.5;
      final ca = math.cos(u), sa = math.sin(u);
      final hl = (l + 2) / 2;
      vm.Vector3 p(double lx, double lz) => vm.Vector3(cx + lx * ca + lz * sa, 0.014, cz - lx * sa + lz * ca);
      water.quad(p(-n, -hl), p(n, -hl), p(n, hl), p(-n, hl), vm.Vector3(0, 1, 0),
          u0: 0, v0: 0, u1: n * 2 / 6, v1: (l + 2) / 6);
      for (final sd in [-1.0, 1.0]) {
        final off = sd * (n + 0.35);
        curbs.box(vm.Vector3(cx + off * ca, 0.21, cz - off * sa), vm.Vector3(0.65, 0.42, l + 1.2), u);
      }
    }
    final m = pbr(hexColor('#07182F'), emissive: hexColor('#0C284D', 0.34), metallic: 0.28, roughness: 0.08);
    riverMats.add(m);
    refRoot.add(fs.Node(name: 'ShibuyaRiverWater', mesh: fs.Mesh(water.build(), m)));
    refRoot.add(fs.Node(
        name: 'ShibuyaRiverCurbs',
        mesh: fs.Mesh(curbs.build(), pbr(hexColor('#243045'), roughness: 0.72, metallic: 0.3))));
  }

  // ------------------------------------- DistantTokyoSkyline360 (demo)
  void _distantSkyline() {
    // Mulberry32-seeded ring of 96 towers at r = 420..565 around the origin.
    final rnd = mulberry32(14598366 + 77);

    final walls = MeshBuf();
    for (int e = 0; e < 96; e++) {
      final t = e / 96 * math.pi * 2 + (rnd() - 0.5) * 0.035;
      final r = 420 + rnd() * 145;
      final a = 18 + rnd() * 28, o = 16 + rnd() * 24;
      final h = 42 + math.pow(rnd(), 1.25) * 185;
      final cx = math.cos(t) * r, cz = math.sin(t) * r;
      // box rotated by -t about Y (three.js rotateY(-t))
      final ca = math.cos(-t), sa = math.sin(-t);
      XZ c(double lx, double lz) => XZ(cx + lx * ca + lz * sa, cz - lx * sa + lz * ca);
      final fp = [c(-a / 2, -o / 2), c(a / 2, -o / 2), c(a / 2, o / 2), c(-a / 2, o / 2)];
      _prism(walls, MeshBuf(), fp, -0.5, h - 0.5);
    }
    _add(
        walls,
        pbr(hexColor('#243656'), roughness: 0.68, metallic: 0.24)
          ..baseColorTexture = tex.glassBase
          ..emissiveTexture = tex.glassGlow
          ..emissiveFactor = hexColor('#7FB3F2', 0.52 * 1.6),
        'DistantTokyoSkyline360');
  }

  // ---------------------------------------------------------- barriers
  void _barriers() {
    // _buildRouteHazards: Jersey-barrier profile (#202B3D), yellow-black
    // hazard stripe panels on both slopes (Tg texture, emissive #F59E0B
    // x.52), orange warning beacon cap (#FF5A1A, emissive x2.2), feet.
    final frame = MeshBuf(), stripes = MeshBuf(), beacons = MeshBuf();
    for (final b in level.route['streetBarriers'] as List<dynamic>) {
      final pos = b['pos'] as List<dynamic>?;
      if (pos == null) continue;
      double d0(dynamic v, double f) => (v as num?)?.toDouble() ?? f;
      final o = d0(pos[0], 0), c = d0(pos[2], 0);
      final l = b['groundY'] != null ? d0(b['groundY'], 0) : d0(pos[1], 0);
      final u = d0(b['yaw'], 0);
      final d = d0(b['width'], 2.8), f = d0(b['height'], 1.15), p = d0(b['depth'], 0.9);
      final m = p * 0.48, h = p * 0.34, g = p * 0.19, top = f - 0.14;
      final cu = math.cos(u), su = math.sin(u);
      // barrier-local (X along width, Y up, Z across depth) -> reference
      vm.Vector3 w(double x, double y, double z) => vm.Vector3(o + x * cu + z * su, l + y, c - x * su + z * cu);
      vm.Vector3 dirW(double x, double y, double z) => vm.Vector3(x * cu + z * su, y, -x * su + z * cu);
      // profile (depth z, height y); the extrusion runs along X
      final prof = [
        (m, 0.0), (m, 0.16), (h, 0.36), (g, top), (-g, top), (-h, 0.36), (-m, 0.16), (-m, 0.0)
      ];
      final ex = math.max(0.8, d - 0.18) / 2;
      for (int k = 0; k < prof.length; k++) {
        final a = prof[k], bq = prof[(k + 1) % prof.length];
        final nz = bq.$2 - a.$2, ny = -(bq.$1 - a.$1);
        final nl = math.sqrt(nz * nz + ny * ny);
        if (nl < 1e-6) continue;
        frame.quad(w(-ex, a.$2, a.$1), w(ex, a.$2, a.$1), w(ex, bq.$2, bq.$1), w(-ex, bq.$2, bq.$1),
            dirW(0, ny / nl, nz / nl));
      }
      for (final sx in [-ex, ex]) {
        final n = dirW(sx.sign, 0, 0);
        final cIdx = frame.vertex(w(sx, top * 0.5, 0), n, 0.5, 0.5);
        final ring = [for (final q in prof) frame.vertex(w(sx, q.$2, q.$1), n, 0, 0)];
        for (int k = 0; k < ring.length; k++) {
          final i0 = ring[k], i1 = ring[(k + 1) % ring.length];
          if (sx > 0) {
            frame.tri(cIdx, i0, i1);
          } else {
            frame.tri(cIdx, i1, i0);
          }
        }
      }
      for (final e in [-1.0, 1.0]) {
        frame.box(w(d * 0.45 * e, 0.09, 0), vm.Vector3(0.2, 0.18, p * 1.04), u);
      }
      // hazard stripe panels on both slopes
      final sw = d * 0.88, sh = 0.36;
      final sY = 0.36 + (top - 0.36) * 0.44, sZ = h + (g - h) * 0.44 + 0.068;
      final ang = math.atan2(h - g, math.max(0.2, top - 0.36));
      for (final e in [1.0, -1.0]) {
        // plane up axis tilts toward the centre: (0, cos a, -sin a) on +Z
        final upY = math.cos(ang), upZ = -math.sin(ang) * e;
        final nY = math.sin(ang), nZ = math.cos(ang) * e;
        vm.Vector3 q(double x, double y) => w(x * e, sY + y * upY, sZ * e + y * upZ);
        stripes.quad(q(-sw / 2, -sh / 2), q(sw / 2, -sh / 2), q(sw / 2, sh / 2), q(-sw / 2, sh / 2),
            dirW(0, nY, nZ), u0: 0, u1: 2.2, v0: 1, v1: 0);
      }
      beacons.box(w(0, f - 0.08, 0), vm.Vector3(d * 0.94, 0.14, g * 1.85), u);
    }
    void add(MeshBuf b, fs.Material mat, String name) {
      if (!b.isEmpty) refRoot.add(fs.Node(name: name, mesh: fs.Mesh(b.build(), mat)));
    }

    add(frame, pbr(hexColor('#202B3D'), roughness: 0.56, metallic: 0.38), 'StreetBarrierFrames');
    add(
        stripes,
        fs.PhysicallyBasedMaterial(baseColorTexture: tex.hazardStripe, emissiveTexture: tex.hazardStripe)
          ..emissiveFactor = hexColor('#F59E0B', 0.52)
          ..roughnessFactor = 0.34
          ..metallicFactor = 0.18
          ..doubleSided = true,
        'StreetBarrierHazardStripes');
    add(beacons, pbr(hexColor('#FF5A1A'), emissive: hexColor('#FF4F00', 2.2), roughness: 0.24),
        'StreetBarrierWarningBeacons');
  }





}
