import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;

import 'fx.dart';
import 'glb_library.dart';
import 'world_builder.dart' show hexColor;

/// Wet-asphalt neon bounce: a port of the demo's `ShibuyaMirrorWetAsphalt`
/// fragment additions (`neonBounce`), drawn as additive ground decals.
///
/// The demo evaluates, per asphalt fragment,
///   wetRefl = mix(.10, .54, pMask) * (.14 + .86 fresnel) * (.12 + .88 altAtten)
/// and adds, stretched along the horizontal view direction:
///  1. the hero bounce   uHeroColor * uHeroPower * .56 / hDistSq
///  3. 12 sign lights    uSignCol * 2.4 / distSq  (`_pushSignLight` ring)
///  4. the Google beacon gCol * uTowerPower * 52 / (d^2 + 260)
/// Each term is `k / (a perp^2 + (b along)^2 + c)`, i.e. a scaled
/// `1 / (1 + x^2 + y^2)` profile, so one falloff texture serves all of them.
/// wetRefl and the ripple are evaluated per decal at its light origin.
class GroundBounce {
  GroundBounce(this.parent) {
    final tex = _falloffTexture();
    final geo = NeonFx.rectXZ(1, 1);
    for (int i = 0; i < _slots + 2; i++) {
      final m = fs.UnlitMaterial(colorTexture: tex)
        ..alphaMode = fs.AlphaMode.blend
        ..baseColorFactor = vm.Vector4.zero();
      final n = fs.Node(name: 'NeonBounce_$i', mesh: fs.Mesh(geo, m))..visible = false;
      parent.add(n);
      _nodes.add(n);
      _mats.add(m);
    }
    reset();
  }

  static const _slots = 12; // qh
  /// Texture spans x, y in [-_ext, _ext] of the normalised profile.
  static const double _ext = 6;
  /// Premultiplied "over" with a tiny alpha is additive: dst * (1 - eps)
  /// leaves the asphalt untouched, and fog adds only eps * fogColor.
  static const double _eps = 1 / 512;

  final fs.Node parent;
  final List<fs.Node> _nodes = [];
  final List<fs.UnlitMaterial> _mats = [];
  final List<vm.Vector3?> _pos = List.filled(_slots, null);
  final List<vm.Vector4> _col = List.generate(_slots, (_) => vm.Vector4.zero());
  int _cursor = 0;

  /// `resetDynamicState`: every slot back to y = -999.
  void reset() {
    _cursor = 0;
    for (int i = 0; i < _slots; i++) {
      _pos[i] = null;
    }
  }

  /// `_pushSignLight(pos, color)`.
  void push(double x, double z, vm.Vector4 linearColor) {
    final n = _cursor % _slots;
    _cursor++;
    _pos[n] = vm.Vector3(x, 0, z);
    _col[n].setFrom(linearColor);
  }

  void pushHex(double x, double z, String hex) => push(x, z, hexColor(hex));

  /// Per-frame update. [cam] is the camera position, [hero] the hero
  /// uniform position (hero + .9 m), [heroColor] linear uHeroColor.
  void sync({
    required bool visible,
    required vm.Vector3 cam,
    required vm.Vector3 hero,
    required vm.Vector4 heroColor,
    required double heroPower,
    required double towerPower,
    required double finalePower,
    required double time,
  }) {
    if (!visible) {
      for (final n in _nodes) {
        n.visible = false;
      }
      return;
    }
    final altAtten = 1 - _smoothstep(18, 75, cam.y);
    final boost = 1 + 0.18 * finalePower;

    // Places decal [i]: profile k / (a perp^2 + (b along)^2 + c).
    void place(int i, double x, double z, double a, double b, double c, double k,
        double r, double g, double bl) {
      final dx = cam.x - x, dz = cam.z - z;
      final dist = math.sqrt(dx * dx + dz * dz + cam.y * cam.y);
      final vy = (cam.y / math.max(dist, 1e-3)).clamp(0.0, 1.0);
      final fresnel = math.pow(math.max(1 - vy, 1e-4), 3.6).toDouble();
      final pMask = _wetSheen(x, z);
      final wet = _lerp(0.10, 0.54, pMask) * (0.14 + 0.86 * fresnel) * (0.12 + 0.88 * altAtten);
      final ripple = 0.93 + 0.07 * math.sin(x * 4.2 + time * 3.4) * math.cos(z * 3.9 - time * 2.8);
      // Peak = k / c; x-unit = sqrt(c / a) m across, y-unit = sqrt(c) / b m along.
      var amp = k / c * wet * ripple * boost;
      if (amp < 1e-5) {
        _nodes[i].visible = false;
        return;
      }
      // Highlight shoulder b / (1 + .55 b), applied at the peak.
      final peak = amp * math.max(r, math.max(g, bl));
      if (peak > 0) amp *= 1 / (1 + peak * 0.55);
      final sx = 2 * _ext * math.sqrt(c / a), sz = 2 * _ext * math.sqrt(c) / b;
      final yaw = math.atan2(dx, dz);
      final n = _nodes[i]..visible = true;
      n.localTransform = GlbLibrary.slot(x, 0.045, z, yaw, vm.Vector3(sx, 1, sz));
      final s = amp / _eps;
      _mats[i].baseColorFactor = vm.Vector4(r * s, g * s, bl * s, _eps);
    }

    for (int i = 0; i < _slots; i++) {
      final p = _pos[i];
      if (p == null) {
        _nodes[i].visible = false;
        continue;
      }
      final c = _col[i];
      place(i, p.x, p.z, 4.6, 0.48, 28, 2.4, c.x, c.y, c.z);
    }
    // 1. Hero bounce: hPerp^2 3.8 + (hAlong .62)^2 + max(0, y) 4.4 + 8.5.
    place(_slots, hero.x, hero.z, 3.8, 0.62, math.max(0, hero.y) * 4.4 + 8.5,
        heroPower * 0.56, heroColor.x, heroColor.y, heroColor.z);
    // 4. Google beacon (radial), colour cycling blue / amber / red.
    if (towerPower > 0.001) {
      final t1 = 0.5 + 0.5 * math.sin(241.1 * 0.14 + time * 1.6);
      final t2 = 0.5 + 0.5 * math.cos(260.9 * 0.12 - time * 1.4);
      final r = _lerp(_lerp(0.08, 0.92, t1), 0.78, t2),
          g = _lerp(_lerp(0.28, 0.52, t1), 0.10, t2),
          b = _lerp(_lerp(0.88, 0.01, t1), 0.07, t2);
      place(_slots + 1, 241.1, 260.9, 1, 1, 260, towerPower * 52, r, g, b);
    } else {
      _nodes[_slots + 1].visible = false;
    }
  }

  // ---------------------------------------------------------------- helpers

  /// `1 / (1 + x^2 + y^2)` over [-6, 6]^2, windowed to 0 at the border,
  /// sRGB-encoded so the unlit shader's decode returns the linear profile.
  static fs.Texture2D _falloffTexture() {
    const n = 192;
    final px = Uint8List(n * n * 4);
    for (int j = 0; j < n; j++) {
      for (int i = 0; i < n; i++) {
        final x = ((i + 0.5) / n * 2 - 1) * _ext, y = ((j + 0.5) / n * 2 - 1) * _ext;
        final edge = math.max(x.abs(), y.abs());
        final v = (1 / (1 + x * x + y * y)) * (1 - _smoothstep(_ext * 0.72, _ext, edge));
        final e = v <= 0.0031308 ? v * 12.92 : 1.055 * math.pow(v, 1 / 2.4) - 0.055;
        final b = (e * 255).round().clamp(0, 255);
        final k = (j * n + i) * 4;
        px[k] = b;
        px[k + 1] = b;
        px[k + 2] = b;
        px[k + 3] = 255;
      }
    }
    return fs.Texture2D.fromPixels(px, n, n);
  }

  static double _fract(double v) => v - v.floorToDouble();

  /// `shibuyaHash21`.
  static double _hash(double px, double py) {
    var x = _fract(px * 127.1), y = _fract(py * 311.7);
    final d = x * (x + 34.12) + y * (y + 34.12);
    x += d;
    y += d;
    return _fract(x * y);
  }

  /// `shibuyaValNoise`.
  static double _valNoise(double px, double py) {
    final ix = px.floorToDouble(), iy = py.floorToDouble();
    final fx = px - ix, fy = py - iy;
    final ux = fx * fx * (3 - 2 * fx), uy = fy * fy * (3 - 2 * fy);
    final a = _hash(ix, iy), b = _hash(ix + 1, iy);
    final c = _hash(ix, iy + 1), d = _hash(ix + 1, iy + 1);
    return _lerp(_lerp(a, b, ux), _lerp(c, d, ux), uy);
  }

  /// `shibuyaWetSheen` (4-octave rotated value noise, smoothstep .28 .. .78).
  static double _wetSheen(double x, double z) {
    // GLSL mat2(0.80, -0.60, 0.60, 0.80) is column-major: rot * q =
    // (0.8 qx + 0.6 qy, -0.6 qx + 0.8 qy).
    var qx = x * 0.028, qy = z * 0.028;
    var v = _valNoise(qx, qy) * 0.44;
    const oct = [
      (2.15, 11.3, 7.1, 0.30),
      (2.08, 23.7, 17.9, 0.17),
      (2.12, 5.1, 13.4, 0.09),
    ];
    for (final o in oct) {
      final rx = 0.8 * qx + 0.6 * qy, ry = -0.6 * qx + 0.8 * qy;
      qx = rx * o.$1 + o.$2;
      qy = ry * o.$1 + o.$3;
      v += _valNoise(qx, qy) * o.$4;
    }
    return _smoothstep(0.28, 0.78, v);
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
  static double _smoothstep(double a, double b, double x) {
    final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }
}
