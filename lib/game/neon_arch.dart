import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;

import 'glb_library.dart';
import 'world_builder.dart' show hexColor;

/// One NEON slide arch: the demo's `_buildNeonSlideArches` rig plus its
/// `NeonArchLaserCurtains` (3 lane panels) and `_applyNeonArchMaterials` /
/// `_syncNeonSlideArches` animation.
class NeonArchRig {
  NeonArchRig._(this.index, this.s, this.x, this.groundY, this.z, this.yaw, this.jp);

  final int index;
  final double s, x, groundY, z, yaw;
  final bool jp;

  late final vm.Vector3 orangeColor, cyanColor, crestColor;
  fs.PhysicallyBasedMaterial? orangeMat, cyanMat, crestMat, glassMat;
  final List<ArchCurtain> lanes = [];

  bool lit = false;
  double flash = 0, ignite = 0;

  double get rightX => -math.cos(yaw);
  double get rightZ => math.sin(yaw);
  double get fwdX => math.sin(yaw);
  double get fwdZ => math.cos(yaw);

  static const _laneBounds = [
    (minX: -5.45, maxX: -1.8, cx: -3.625, w: 3.65),
    (minX: -1.8, maxX: 1.8, cx: 0.0, w: 3.6),
    (minX: 1.8, maxX: 5.45, cx: 3.625, w: 3.65),
  ];

  static final Map<bool, (fs.Texture2D, fs.Texture2D)> _tex = {};

  /// Builds the arch from the `NeonSlideArch` GLB template under [parent]
  /// (reference frame).
  static NeonArchRig? build(fs.Node props, fs.Node parent, Map<String, dynamic> r, int index) {
    final t = GlbLibrary.template(props, 'NeonSlideArch');
    if (t == null) return null;
    double d(dynamic v, [double f = 0]) => (v as num?)?.toDouble() ?? f;
    final p = r['pos'] as List<dynamic>;
    final gy = r['groundY'] != null ? d(r['groundY']) : d(p[1]);
    final yaw = d(r['yaw']);
    final jp = r['style'] == 'torii_neon_jp' || r['crestNodeName'] == 'NeonArch_CrestJP';
    final rig = NeonArchRig._(index, d(r['s']), d(p[0]), gy, d(p[2]), yaw, jp);
    t.localTransform = GlbLibrary.slot(rig.x, gy, rig.z, yaw + math.pi);
    t.getChildByName('NeonArch_CrestEN')?.visible = !jp;
    t.getChildByName('NeonArch_CrestJP')?.visible = jp;

    vm.Vector3 c3(String h) {
      final v = hexColor(h);
      return vm.Vector3(v.x, v.y, v.z);
    }

    rig.cyanColor = c3(jp ? '#00C8FF' : '#00E5FF');
    rig.orangeColor = c3(jp ? '#FF6200' : '#FF3D00');
    rig.crestColor = c3(jp ? '#FFB300' : '#FF3D00');

    fs.PhysicallyBasedMaterial mat(String name, {double rough = 0.16, double metal = 0.06}) {
      final n = t.getChildByName(name);
      final m = n?.mesh != null
          ? GlbLibrary.clonePbr(n!.mesh!.primitives.first.material)
          : fs.PhysicallyBasedMaterial();
      m
        ..baseColorTexture = null
        ..emissiveTexture = null
        ..roughnessFactor = rough
        ..metallicFactor = metal
        ..emissiveStrength = 1;
      if (n?.mesh != null) {
        for (final pr in n!.mesh!.primitives) {
          pr.material = m;
        }
      }
      return m;
    }

    rig.orangeMat = mat('NeonArch_PlasmaOrange');
    rig.cyanMat = mat('NeonArch_PlasmaCyan');
    rig.crestMat = mat(jp ? 'NeonArch_CrestJP' : 'NeonArch_CrestEN', metal: 0.08);
    rig.glassMat = mat('NeonArch_GlassShell', rough: 0.08, metal: 0.12)
      ..baseColorFactor = hexColor('#DCEEFF', 1, 0.22)
      ..alphaMode = fs.AlphaMode.blend;
    parent.add(t);

    // Laser curtains: PlaneGeometry(1, 1.32) per lane at groundY + 1.84,
    // rotated yaw + pi, scaled to the lane width.
    final tex = _tex.putIfAbsent(jp, () => _curtainTextures(jp));
    final geo = _plane();
    for (int k = 0; k < 3; k++) {
      final lb = _laneBounds[k];
      final cx = rig.x + rig.rightX * lb.cx, cz = rig.z + rig.rightZ * lb.cx;
      final xf = vm.Matrix4.compose(
          vm.Vector3(cx, gy + 1.84, cz),
          vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), yaw + math.pi),
          vm.Vector3(lb.w, 1, 1));
      final rail = fs.UnlitMaterial(colorTexture: tex.$1)..alphaMode = fs.AlphaMode.blend;
      final chev = fs.UnlitMaterial(colorTexture: tex.$2)..alphaMode = fs.AlphaMode.blend;
      chev.baseColorTextureTransform.scale = vm.Vector2(2, 2.1);
      final n1 = fs.Node(name: 'NeonArchLaserCurtain_${index}_$k', mesh: fs.Mesh(geo, rail))
        ..localTransform = xf;
      final n2 = fs.Node(name: 'NeonArchLaserChevrons_${index}_$k', mesh: fs.Mesh(geo, chev))
        ..localTransform = xf;
      parent
        ..add(n1)
        ..add(n2);
      rig.lanes.add(ArchCurtain(k - 1, lb.minX, lb.maxX, rail, chev, [n1, n2]));
    }
    rig.apply(0, 0);
    return rig;
  }

  /// `_applyNeonArchMaterials(arch, ignite, pulse)`.
  void apply(double r, double n) {
    r = r.clamp(0.0, 1.0);
    final f = flash.clamp(0.0, 1.0);
    vm.Vector4 base(String dark, vm.Vector3 c, double t) {
      final d = hexColor(dark);
      final k = t.clamp(0.0, 1.0);
      return vm.Vector4(d.x + (c.x - d.x) * k, d.y + (c.y - d.y) * k, d.z + (c.z - d.z) * k, 1);
    }

    double lerp(double a, double b, double t) => a + (b - a) * t;
    vm.Vector4 em(vm.Vector3 c, double k) => vm.Vector4(c.x * k, c.y * k, c.z * k, 1);
    orangeMat
      ?..baseColorFactor = base('#2A1A14', orangeColor, 0.28 + r * 0.72)
      ..emissiveFactor = em(orangeColor, lerp(0.42 + n * 0.16, 2.15, r) + f * 0.45);
    cyanMat
      ?..baseColorFactor = base('#122436', cyanColor, 0.28 + r * 0.72)
      ..emissiveFactor = em(cyanColor, lerp(0.36 + n * 0.14, 2.05, r) + f * 0.4);
    crestMat
      ?..baseColorFactor = base('#2A1F18', crestColor, 0.32 + r * 0.68)
      ..emissiveFactor = em(crestColor, lerp(0.45 + n * 0.12, 2.35, r) + f * 0.45);
    final g = glassMat;
    if (g != null) {
      g.baseColorFactor.w = lerp(0.18, 0.24, r) + f * 0.06;
      final e = hexColor('#60A5FA', lerp(0.04, 0.18, r) + f * 0.14);
      g.emissiveFactor = e;
    }
  }

  /// `_syncNeonSlideArches` for this arch.
  void sync(double dt, double time, double heroS, bool finale, bool portalDone, double mapsMorph,
      List<({double x, double z})> cars) {
    final a = s - heroS;
    if (finale) {
      lit = true;
      flash = 0;
      ignite = 1;
    } else {
      if (portalDone) lit = true;
      if (flash > 0) flash = math.max(0, flash - dt * 2.1);
      final pre = a <= 35 ? (1 - math.max(0.0, a) / 35).clamp(0.0, 1.0) : 0.0;
      final target = lit ? 1.0 : pre * 0.85;
      ignite += (target - ignite) * (dt * 8).clamp(0.12, 1.0);
      if (a < 0 && a > -45 && !lit && mapsMorph > 0.35) {
        lit = true;
        ignite = 1;
      }
    }
    final pulse = 0.5 + 0.5 * math.sin(time * 4.4 - index * 1.3);
    apply(ignite, pulse);

    // Lanes fade out where a car is passing under the arch.
    final want = [1.0, 1.0, 1.0];
    for (final c in cars) {
      final dx = c.x - x, dz = c.z - z;
      if (dx * dx + dz * dz > 324) continue;
      final along = (dx * fwdX + dz * fwdZ).abs();
      if (along >= 6.2) continue;
      final lat = dx * rightX + dz * rightZ;
      final u = along <= 4.1 ? 0.0 : _ss(4.1, 6.2, along);
      for (int k = 0; k < 3; k++) {
        final l = lanes[k];
        if (lat + 1.35 >= l.minX && lat - 1.35 <= l.maxX && u < want[k]) want[k] = u;
      }
    }
    final ig = (ignite * 0.7 + flash * 0.45).clamp(0.0, 1.15);
    for (int k = 0; k < 3; k++) {
      final l = lanes[k];
      final w = want[k];
      if (dt <= 0 || w == 0) {
        l.alpha = w;
      } else {
        l.alpha += (w - l.alpha) * (dt * (w < l.alpha ? 28 : 12)).clamp(0.0, 1.0);
        if ((l.alpha - w).abs() < 0.01) l.alpha = w;
      }
      final pulseL = 0.88 + 0.12 * math.sin(time * 5.2 + l.lane * 1.1);
      final boost = 1.08 + ig * 0.46;
      final alphaK = (l.alpha * (0.64 + 0.22 * ig) * pulseL).clamp(0.0, 0.86 / 0.92);
      // warm-white wash with ignite (mix toward 1,.92,.78 by ig*.06)
      for (final m in [l.rail, l.chev]) {
        m.baseColorFactor = vm.Vector4(boost, boost, boost, alphaK);
      }
      // gy = fract(v * 2.1 + t * 1.35 + lane * .14): scrolls downward
      // (texture v runs top -> bottom here, hence the sign).
      l.chev.baseColorTextureTransform.offset =
          vm.Vector2(0, -((time * 1.35 + l.lane * 0.14) % 1.0));
      for (final nd in l.nodes) {
        nd.visible = l.alpha > 0.008 && mapsMorph > 0.03;
      }
    }
  }

  void reset() {
    lit = false;
    flash = 0;
    ignite = 0;
    for (final l in lanes) {
      l.alpha = 1;
    }
  }

  void igniteNow() {
    lit = true;
    flash = 1;
    ignite = 1;
  }

  static double _ss(double a, double b, double x) {
    final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  /// Unit plane (x -0.5..0.5, y -0.66..0.66) with both windings, since
  /// flutter_scene back-face culls translucent materials.
  static fs.MeshGeometry _plane() {
    const hw = 0.5, hh = 0.66;
    final pos = Float32List.fromList([
      -hw, -hh, 0, hw, -hh, 0, hw, hh, 0, -hw, hh, 0, //
      -hw, -hh, 0, hw, -hh, 0, hw, hh, 0, -hw, hh, 0,
    ]);
    final nrm = Float32List.fromList([
      0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1, //
      0, 0, -1, 0, 0, -1, 0, 0, -1, 0, 0, -1,
    ]);
    // three.js PlaneGeometry: v = 0 at the bottom; our textures store row 0
    // at the top, so v runs 1 -> 0 bottom -> top in texture space.
    final uv = Float32List.fromList([0, 1, 1, 1, 1, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0]);
    return fs.MeshGeometry.fromArrays(
      positions: pos,
      normals: nrm,
      texCoords: uv,
      indices: [0, 1, 2, 0, 2, 3, 4, 6, 5, 4, 7, 6],
    );
  }

  /// (rails + scanlines layer, chevron layer) for the curtain shader.
  static (fs.Texture2D, fs.Texture2D) _curtainTextures(bool jp) {
    vm.Vector3 c3(String h) {
      final v = hexColor(h);
      return vm.Vector3(v.x, v.y, v.z);
    }

    final a = c3(jp ? '#1E88FF' : '#00D4FF');
    final b = c3(jp ? '#FF6200' : '#FF3D00');
    int enc(double v) {
      v = v.clamp(0.0, 1.0);
      final s = v <= 0.0031308 ? v * 12.92 : 1.055 * math.pow(v, 1 / 2.4) - 0.055;
      return (s * 255).round().clamp(0, 255);
    }

    const w = 64, h = 128;
    final rails = Uint8List(w * h * 4);
    for (int y = 0; y < h; y++) {
      final v = 1 - (y + 0.5) / h; // three.js uv.y (0 bottom)
      final bottom = 1 - _ss(0, 0.11, v);
      final top = _ss(0.89, 1, v);
      final rl = math.max(bottom, top * 0.85);
      final scan = 0.72 + 0.28 * math.sin(v * 56);
      final k = (bottom * 0.88).clamp(0.0, 1.0);
      var r = a.x + (b.x - a.x) * k, g = a.y + (b.y - a.y) * k, bl = a.z + (b.z - a.z) * k;
      final wk = (bottom * 0.12).clamp(0.0, 0.18);
      r += (1.0 - r) * wk;
      g += (0.92 - g) * wk;
      bl += (0.78 - bl) * wk;
      for (int x = 0; x < w; x++) {
        final u = (x + 0.5) / w;
        final edge = _ss(0, 0.055, u) * (1 - _ss(0.945, 1, u));
        final dens = (0.14 + 0.78 * rl) * scan * edge;
        final o = (y * w + x) * 4;
        rails[o] = enc(r);
        rails[o + 1] = enc(g);
        rails[o + 2] = enc(bl);
        rails[o + 3] = (dens.clamp(0.0, 1.0) * 255).round();
      }
    }
    // One chevron cell: gx = u - .5, gy = v - .5 (tiled 2 x 2.1 per panel).
    const cw = 64, ch = 64;
    final chev = Uint8List(cw * ch * 4);
    for (int y = 0; y < ch; y++) {
      final gy = (1 - (y + 0.5) / ch) - 0.5;
      for (int x = 0; x < cw; x++) {
        final gx = (x + 0.5) / cw - 0.5;
        final d = (gy - gx.abs() * 0.68).abs();
        final c = 1 - _ss(0.035, 0.115, d);
        final k = (c * 0.78).clamp(0.0, 1.0);
        final o = (y * cw + x) * 4;
        chev[o] = enc(a.x + (b.x - a.x) * k);
        chev[o + 1] = enc(a.y + (b.y - a.y) * k);
        chev[o + 2] = enc(a.z + (b.z - a.z) * k);
        chev[o + 3] = (0.48 * c * 0.86 * 255).round();
      }
    }
    return (fs.Texture2D.fromPixels(rails, w, h), fs.Texture2D.fromPixels(chev, cw, ch));
  }
}

class ArchCurtain {
  ArchCurtain(this.lane, this.minX, this.maxX, this.rail, this.chev, this.nodes);
  final int lane;
  final double minX, maxX;
  final fs.UnlitMaterial rail, chev;
  final List<fs.Node> nodes;
  double alpha = 1;
}
