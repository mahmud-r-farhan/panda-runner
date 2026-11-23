import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;

/// Small CPU-side triangle accumulator used to merge many procedural pieces
/// (buildings, decks, props) into a few GPU meshes.
class MeshBuf {
  final List<double> _p = [];
  final List<double> _n = [];
  final List<double> _uv = [];
  final List<double> _c = [];
  final List<int> _i = [];
  bool useColors = false;

  int get vertexCount => _p.length ~/ 3;
  bool get isEmpty => _i.isEmpty;

  int vertex(vm.Vector3 p, vm.Vector3 n, double u, double v,
      [vm.Vector4? color]) {
    _p..add(p.x)..add(p.y)..add(p.z);
    _n..add(n.x)..add(n.y)..add(n.z);
    _uv..add(u)..add(v);
    final c = color ?? _white;
    _c..add(c.x)..add(c.y)..add(c.z)..add(c.w);
    return vertexCount - 1;
  }

  static final vm.Vector4 _white = vm.Vector4(1, 1, 1, 1);

  void tri(int a, int b, int c) {
    _i..add(a)..add(b)..add(c);
  }

  /// Adds a quad a-b-c-d; the winding is chosen so the face points along [n].
  void quad(vm.Vector3 a, vm.Vector3 b, vm.Vector3 c, vm.Vector3 d,
      vm.Vector3 n,
      {double u0 = 0, double v0 = 0, double u1 = 1, double v1 = 1,
      vm.Vector4? color}) {
    final ia = vertex(a, n, u0, v0, color);
    final ib = vertex(b, n, u1, v0, color);
    final ic = vertex(c, n, u1, v1, color);
    final id = vertex(d, n, u0, v1, color);
    final faceN = (b - a).cross(c - a);
    if (faceN.dot(n) >= 0) {
      tri(ia, ib, ic);
      tri(ia, ic, id);
    } else {
      tri(ia, ic, ib);
      tri(ia, id, ic);
    }
  }

  /// A capped frustum (three.js `CylinderGeometry(rTop, rBottom, |b-a|, seg)`)
  /// from [a] (bottom) to [b] (top).
  void cylinder(vm.Vector3 a, vm.Vector3 b, double rTop, double rBottom, {int seg = 8}) {
    final axis = b - a;
    final len = axis.length;
    if (len < 1e-5) return;
    final up = axis / len;
    final ref = up.y.abs() < 0.9 ? vm.Vector3(0, 1, 0) : vm.Vector3(1, 0, 0);
    final ex = ref.cross(up)..normalize();
    final ez = up.cross(ex)..normalize();
    final slope = (rBottom - rTop) / len;
    for (int i = 0; i < seg; i++) {
      final t0 = i / seg * math.pi * 2, t1 = (i + 1) / seg * math.pi * 2;
      vm.Vector3 dir(double t) => ex * math.cos(t) + ez * math.sin(t);
      final d0 = dir(t0), d1 = dir(t1);
      final n0 = (d0 + up * slope)..normalize(), n1 = (d1 + up * slope)..normalize();
      final i0 = vertex(a + d0 * rBottom, n0, i / seg, 1);
      final i1 = vertex(a + d1 * rBottom, n1, (i + 1) / seg, 1);
      final i2 = vertex(b + d1 * rTop, n1, (i + 1) / seg, 0);
      final i3 = vertex(b + d0 * rTop, n0, i / seg, 0);
      tri(i0, i2, i1);
      tri(i0, i3, i2);
      // caps
      final c0 = vertex(b, up, 0.5, 0.5);
      final c1 = vertex(b + d0 * rTop, up, 0.5, 0.5), c2 = vertex(b + d1 * rTop, up, 0.5, 0.5);
      tri(c0, c2, c1);
      final down = -up;
      final c3 = vertex(a, down, 0.5, 0.5);
      final c4 = vertex(a + d0 * rBottom, down, 0.5, 0.5), c5 = vertex(a + d1 * rBottom, down, 0.5, 0.5);
      tri(c3, c4, c5);
    }
  }

  /// Axis-aligned-in-local-space box, rotated by [yaw] about Y.
  void box(vm.Vector3 center, vm.Vector3 size, double yaw,
      {vm.Vector4? color, double uScale = 1, double vScale = 1}) {
    final hx = size.x / 2, hy = size.y / 2, hz = size.z / 2;
    final cy = math.cos(yaw), sy = math.sin(yaw);
    vm.Vector3 tr(double x, double y, double z) =>
        vm.Vector3(center.x + x * cy + z * sy, center.y + y,
            center.z - x * sy + z * cy);
    vm.Vector3 rn(double x, double y, double z) =>
        vm.Vector3(x * cy + z * sy, y, -x * sy + z * cy);
    final p = [
      for (final z in [-hz, hz])
        for (final y in [-hy, hy])
          for (final x in [-hx, hx]) tr(x, y, z),
    ];
    // index = zi*4 + yi*2 + xi
    void face(int a, int b, int c, int d, vm.Vector3 n) =>
        quad(p[a], p[b], p[c], p[d], n, color: color, u1: uScale, v1: vScale);
    face(0, 1, 3, 2, rn(0, 0, -1));
    face(4, 5, 7, 6, rn(0, 0, 1));
    face(0, 4, 6, 2, rn(-1, 0, 0));
    face(1, 5, 7, 3, rn(1, 0, 0));
    face(2, 3, 7, 6, rn(0, 1, 0));
    face(0, 1, 5, 4, rn(0, -1, 0));
  }

  fs.MeshGeometry build() {
    return fs.MeshGeometry.fromArrays(
      positions: Float32List.fromList(_p),
      normals: Float32List.fromList(_n),
      texCoords: Float32List.fromList(_uv),
      colors: useColors ? Float32List.fromList(_c) : null,
      indices: _i,
    );
  }
}

/// Ear-clipping triangulation of a simple polygon given as flat (x, z)
/// coordinates. Returns index triples into the polygon.
List<int> triangulatePolygon(List<double> xz) {
  final n = xz.length ~/ 2;
  if (n < 3) return const [];
  double area = 0;
  for (int i = 0, j = n - 1; i < n; j = i++) {
    area += xz[j * 2] * xz[i * 2 + 1] - xz[i * 2] * xz[j * 2 + 1];
  }
  final idx = List<int>.generate(n, (i) => i);
  if (area < 0) {
    // ensure counter-clockwise in (x, z)
    idx.setAll(0, idx.reversed.toList());
  }
  final out = <int>[];
  int guard = 0;
  bool isEar(int ia, int ib, int ic, List<int> poly) {
    final ax = xz[ia * 2], az = xz[ia * 2 + 1];
    final bx = xz[ib * 2], bz = xz[ib * 2 + 1];
    final cx = xz[ic * 2], cz = xz[ic * 2 + 1];
    final cross = (bx - ax) * (cz - az) - (bz - az) * (cx - ax);
    if (cross <= 1e-9) return false;
    for (final p in poly) {
      if (p == ia || p == ib || p == ic) continue;
      final px = xz[p * 2], pz = xz[p * 2 + 1];
      final d1 = (bx - ax) * (pz - az) - (bz - az) * (px - ax);
      final d2 = (cx - bx) * (pz - bz) - (cz - bz) * (px - bx);
      final d3 = (ax - cx) * (pz - cz) - (az - cz) * (px - cx);
      if (d1 >= 0 && d2 >= 0 && d3 >= 0) return false;
    }
    return true;
  }

  final poly = List<int>.from(idx);
  while (poly.length > 3 && guard++ < 10000) {
    bool clipped = false;
    for (int i = 0; i < poly.length; i++) {
      final a = poly[(i + poly.length - 1) % poly.length];
      final b = poly[i];
      final c = poly[(i + 1) % poly.length];
      if (isEar(a, b, c, poly)) {
        out..add(a)..add(b)..add(c);
        poly.removeAt(i);
        clipped = true;
        break;
      }
    }
    if (!clipped) break; // degenerate; fall back to a fan below
  }
  if (poly.length == 3) {
    out..add(poly[0])..add(poly[1])..add(poly[2]);
  } else if (poly.length > 3) {
    for (int i = 1; i < poly.length - 1; i++) {
      out..add(poly[0])..add(poly[i])..add(poly[i + 1]);
    }
  }
  return out;
}
