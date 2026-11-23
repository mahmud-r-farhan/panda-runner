import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;

/// Port of the demo's `Vg()` image-based-lighting scene: a PMREM baked from
/// a 60 m sky sphere (moonlit gradient) ringed by sixteen 2.4 x 12.5 m neon
/// panels at r = 42 m (colour x 0.58). Specular reflections on glossy
/// surfaces (wall-run glass, car paint, rails) pick up these neon panels.
///
/// three.js additionally lights everything with a HemisphereLight
/// (#7AA4E6 / #384B6B @ 0.42), which only adds diffuse; flutter_scene has no
/// hemisphere light, so it is folded into the diffuse spherical harmonics
/// while the specular radiance stays pure `Vg`.
class NeonEnvironment {
  static const List<int> _panelColors = [
    16731904, 3718648, 4359668, 16497669, 15352629, 3450963, 16734751, 3900150, //
    16731904, 3718648, 4359668, 16497669, 4359668, 15352629, 3450963, 16731904,
  ];

  static double _s2l(int v) {
    final s = v / 255.0;
    return s <= 0.04045 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
  }

  static double _ss(double a, double b, double x) {
    final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  static double _mix(double a, double b, double t) => a + (b - a) * t;

  /// Radiance of the `Vg` scene seen from the origin along reference-frame
  /// direction (x, y, z).
  static void _vg(double x, double y, double z, List<double> out) {
    // Panels (MeshBasicMaterial, colour x 0.58).
    for (int e = 0; e < 16; e++) {
      final t = e / 16 * math.pi * 2;
      final nx = math.cos(t), nz = math.sin(t);
      final dn = x * nx + z * nz;
      if (dn <= 1e-4) continue;
      final s = 42 / dn;
      final px = x * s, py = y * s, pz = z * s;
      final h = px * -nz + pz * nx;
      final yc = 6.4 + (e % 3) * 2.6;
      if (h.abs() <= 1.2 && (py - yc).abs() <= 6.25) {
        final c = _panelColors[e];
        out[0] = _s2l((c >> 16) & 255) * 0.58;
        out[1] = _s2l((c >> 8) & 255) * 0.58;
        out[2] = _s2l(c & 255) * 0.58;
        return;
      }
    }
    // Sky sphere shader.
    final hh = y.clamp(-1.0, 1.0);
    const zen = [0.0065, 0.0175, 0.0580], mid = [0.0175, 0.0480, 0.1580];
    const hor = [0.0380, 0.0980, 0.2680], gnd = [0.0055, 0.0095, 0.0220];
    for (int k = 0; k < 3; k++) {
      if (hh >= 0) {
        out[k] = _mix(hor[k], _mix(mid[k], zen[k], _ss(0.14, 0.72, hh)), _ss(0, 0.45, hh));
      } else {
        final below = 1 - _ss(-0.35, 0, hh);
        out[k] = _mix(hor[k] * 0.5, gnd[k], below);
      }
    }
  }

  static Future<fs.EnvironmentMap> build({int width = 512, int height = 256}) async {
    final px = Float32List(width * height * 4);
    final c = [0.0, 0.0, 0.0];
    const ss = 2; // supersample the thin panels
    for (int j = 0; j < height; j++) {
      for (int i = 0; i < width; i++) {
        double r = 0, g = 0, b = 0;
        for (int sj = 0; sj < ss; sj++) {
          for (int si = 0; si < ss; si++) {
            final u = (i + (si + 0.5) / ss) / width;
            final v = (j + (sj + 0.5) / ss) / height;
            final lat = (0.5 - v) * math.pi; // row 0 = up
            final lon = (u - 0.5) * 2 * math.pi; // atan2(z, x), Flutter frame
            final fx = math.cos(lat) * math.cos(lon), fy = math.sin(lat), fz = math.cos(lat) * math.sin(lon);
            _vg(fx, fy, -fz, c); // Flutter world -> reference frame (z mirrored)
            r += c[0];
            g += c[1];
            b += c[2];
          }
        }
        final o = (j * width + i) * 4;
        px[o] = r / (ss * ss);
        px[o + 1] = g / (ss * ss);
        px[o + 2] = b / (ss * ss);
        px[o + 3] = 1;
      }
    }
    return fs.EnvironmentMap.fromEquirectHdr(
      linearPixels: px,
      width: width,
      height: height,
      diffuseSphericalHarmonics: _diffuseSh(px, width, height),
    );
  }

  /// Same projection as flutter_scene's `_projectLinearEquirectToSphericalHarmonics`,
  /// with the hemisphere light's sky/ground gradient added to the radiance.
  static List<vm.Vector3> _diffuseSh(Float32List px, int width, int height) {
    final co = List.generate(9, (_) => vm.Vector3.zero());
    const numPhi = 128, numTheta = 64;
    final cell = 2 * math.pi * math.pi / (numPhi * numTheta);
    // HemisphereLight #7AA4E6 / #384B6B @ 0.42. three.js shades it as
    // albedo * irradiance / pi, so as an SH radiance field it is / pi.
    final sky = vm.Vector3(0.195, 0.371, 0.791) * (0.42 / math.pi);
    final gnd = vm.Vector3(0.040, 0.069, 0.147) * (0.42 / math.pi);
    for (int j = 0; j < numTheta; j++) {
      final v = (j + 0.5) / numTheta;
      final lat = (v - 0.5) * math.pi;
      final cl = math.cos(lat), y = math.sin(lat);
      final w = cl * cell;
      final py = ((1 - v) * height).floor().clamp(0, height - 1);
      for (int i = 0; i < numPhi; i++) {
        final u = (i + 0.5) / numPhi;
        final lon = (u - 0.5) * 2 * math.pi;
        final x = cl * math.cos(lon), z = cl * math.sin(lon);
        final pxi = (u * width).floor().clamp(0, width - 1);
        final o = (py * width + pxi) * 4;
        final t = 0.5 * y + 0.5;
        final r = px[o] + _mix(gnd.x, sky.x, t);
        final g = px[o + 1] + _mix(gnd.y, sky.y, t);
        final b = px[o + 2] + _mix(gnd.z, sky.z, t);
        final basis = [
          0.282095,
          0.488603 * y,
          0.488603 * z,
          0.488603 * x,
          1.092548 * x * y,
          1.092548 * y * z,
          0.315392 * (3.0 * z * z - 1.0),
          1.092548 * x * z,
          0.546274 * (x * x - y * y),
        ];
        for (int k = 0; k < 9; k++) {
          final bw = basis[k] * w;
          co[k].x += r * bw;
          co[k].y += g * bw;
          co[k].z += b * bw;
        }
      }
    }
    for (int k = 1; k <= 3; k++) {
      co[k].scale(2 / 3);
    }
    for (int k = 4; k <= 8; k++) {
      co[k].scale(0.25);
    }
    return co;
  }

  // ------------------------------------------------ ShibuyaNightSkyDome
  static double _fract(double v) => v - v.floorToDouble();
  static double _hash21(double x, double y) {
    x = _fract(x * 123.34);
    y = _fract(y * 456.21);
    final d = x * (x + 45.32) + y * (y + 45.32);
    x += d;
    y += d;
    return _fract(x * y);
  }

  static double _vnoise(double x, double y) {
    final ix = x.floorToDouble(), iy = y.floorToDouble();
    var fx = x - ix, fy = y - iy;
    fx = fx * fx * (3 - 2 * fx);
    fy = fy * fy * (3 - 2 * fy);
    final a = _hash21(ix, iy), b = _hash21(ix + 1, iy), c = _hash21(ix, iy + 1), d = _hash21(ix + 1, iy + 1);
    return _mix(_mix(a, b, fx), _mix(c, d, fx), fy);
  }

  /// The demo's sky-dome fragment shader (reference-frame direction).
  static void _sky(double dx, double dy, double dz, List<double> out) {
    final h = dy.clamp(0.0, 1.0);
    const zen = [0.0085, 0.0220, 0.0680], mid = [0.0240, 0.0620, 0.1760], hor = [0.0520, 0.1220, 0.2960];
    final cuX = dx / (dy + 0.26) * 1.4, cuY = dz / (dy + 0.26) * 1.4;
    final cloud = dy > -0.25 ? _vnoise(cuX * 2.1, cuY * 2.1) * 0.65 + _vnoise(cuX * 4.6, cuY * 4.6) * 0.35 : 0.0;
    final band = _ss(0.03, 0.34, h) * (1 - _ss(0.45, 0.88, h));
    final cl = _ss(0.40, 0.76, cloud) * band;
    final az = math.atan2(dz, dx);
    final glow = math.exp(-h * 7.2);
    final warm = 0.5 + 0.5 * math.sin(az * 2.0 + 0.6);
    final cool = 0.5 + 0.5 * math.cos(az * 3.0 - 1.1);
    const cc = [0.014, 0.028, 0.062], wc = [0.048, 0.016, 0.008], kc = [0.018, 0.045, 0.105];
    for (int k = 0; k < 3; k++) {
      var c = _mix(hor[k], mid[k], _ss(0.0, 0.26, h));
      c = _mix(c, zen[k], _ss(0.20, 0.78, h));
      c += cc[k] * cl;
      c += wc[k] * glow * (0.24 + 0.24 * warm);
      c += kc[k] * glow * (0.32 + 0.24 * cool);
      out[k] = c;
    }
  }

  /// A camera-centred unlit sky sphere (radius [radius], viewed from inside)
  /// carrying the demo's `ShibuyaNightSkyDome` shader baked to an equirect.
  /// Lives in the reference frame (add under `refRoot`).
  static fs.Node buildSkyDome({double radius = 1100, int w = 1024, int h = 512}) {
    final px = Uint8List(w * h * 4);
    final c = [0.0, 0.0, 0.0];
    int enc(double v) {
      v = v.clamp(0.0, 1.0);
      final sv = v <= 0.0031308 ? v * 12.92 : 1.055 * math.pow(v, 1 / 2.4) - 0.055;
      return (sv * 255).round().clamp(0, 255);
    }

    for (int j = 0; j < h; j++) {
      final lat = (0.5 - (j + 0.5) / h) * math.pi;
      for (int i = 0; i < w; i++) {
        final lon = ((i + 0.5) / w) * 2 * math.pi;
        final dx = math.cos(lat) * math.cos(lon), dy = math.sin(lat), dz = math.cos(lat) * math.sin(lon);
        _sky(dx, dy, dz, c);
        final o = (j * w + i) * 4;
        px[o] = enc(c[0]);
        px[o + 1] = enc(c[1]);
        px[o + 2] = enc(c[2]);
        px[o + 3] = 255;
      }
    }
    final tex = fs.Texture2D.fromPixels(px, w, h);
    // UV sphere matching the equirect parameterisation above.
    const seg = 64, rings = 32;
    final pos = <double>[], uv = <double>[], nrm = <double>[];
    final idx = <int>[];
    for (int r = 0; r <= rings; r++) {
      final v = r / rings;
      final lat = (0.5 - v) * math.pi;
      for (int sgi = 0; sgi <= seg; sgi++) {
        final u = sgi / seg;
        final lon = u * 2 * math.pi;
        final x = math.cos(lat) * math.cos(lon), y = math.sin(lat), z = math.cos(lat) * math.sin(lon);
        pos.addAll([x * radius, y * radius, z * radius]);
        nrm.addAll([-x, -y, -z]);
        uv.addAll([u, v]);
      }
    }
    for (int r = 0; r < rings; r++) {
      for (int sgi = 0; sgi < seg; sgi++) {
        final a = r * (seg + 1) + sgi, b = a + seg + 1;
        idx.addAll([a, b, a + 1, a + 1, b, b + 1, a, a + 1, b, a + 1, b + 1, b]);
      }
    }
    final geo = fs.MeshGeometry.fromArrays(
      positions: Float32List.fromList(pos),
      normals: Float32List.fromList(nrm),
      texCoords: Float32List.fromList(uv),
      indices: idx,
    );
    final m = fs.UnlitMaterial(colorTexture: tex)..doubleSided = true;
    return fs.Node(name: 'ShibuyaNightSkyDome', mesh: fs.Mesh(geo, m));
  }
}
