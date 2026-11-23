import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' as vm;

import 'level_data.dart';

/// Converts a point from the web demo's right-handed three.js frame
/// (+X east, +Y up, -Z north) to Flutter Scene's left-handed view frame by
/// mirroring Z, so the rendered image is not flipped left/right.
vm.Vector3 w3(double x, double y, double z) => vm.Vector3(x, y, -z);

/// Converts a three.js yaw (rotation about +Y, where yaw 0 faces +Z) into the
/// equivalent Flutter Scene yaw after the Z mirror.
double mirrorYaw(double yaw) => math.pi - yaw;

/// Yaw that turns local +Z toward the reference-frame direction (dx, dz).
double yawFromDir(double dx, double dz) => math.atan2(dx, -dz);

vm.Quaternion yawQuat(double flutterYaw) =>
    vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), flutterYaw);

/// Sample of the route spline in reference (three.js) coordinates.
class RouteSample {
  double s = 0, x = 0, y = 0, z = 0;

  /// Unit tangent on the ground plane.
  double tx = 1, tz = 0;

  /// Unit right vector (lateral +) on the ground plane.
  double rx = 0, rz = 1;
  double halfWidth = 6.8;
  double yaw = 0;
  double pitch = 0;
  double ty = 0;
  /// Signed ground-plane curvature (rad/m), positive turning right.
  double kappa = 0;
  String surface = 'street';
}

/// Arc-length parameterised route polyline built from the exported
/// 8 m-spaced waypoints (`uh()` in the web demo).
class RouteSpline {
  RouteSpline(List<RouteWaypoint> wps) : _w = wps {
    length = _w.last.s;
  }

  final List<RouteWaypoint> _w;
  late final double length;

  List<RouteWaypoint> get waypoints => _w;

  RouteSample sample(double s, [RouteSample? out]) {
    final o = out ?? RouteSample();
    final sc = s.clamp(0.0, length);
    int lo = 0, hi = _w.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (_w[mid].s <= sc) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final a = _w[lo], b = _w[hi];
    final span = math.max(1e-6, b.s - a.s);
    final t = ((sc - a.s) / span).clamp(0.0, 1.0);
    o.s = sc;
    o.x = a.x + (b.x - a.x) * t;
    o.y = a.y + (b.y - a.y) * t;
    o.z = a.z + (b.z - a.z) * t;
    var tx = a.tx + (b.tx - a.tx) * t;
    var tz = a.tz + (b.tz - a.tz) * t;
    final l = math.sqrt(tx * tx + tz * tz);
    if (l > 1e-6) {
      tx /= l;
      tz /= l;
    }
    o.tx = tx;
    o.tz = tz;
    o.rx = -tz;
    o.rz = tx;
    o.halfWidth = (a.width + (b.width - a.width) * t) * 0.5;
    o.yaw = math.atan2(tx, tz);
    o.ty = (b.y - a.y) / span;
    o.pitch = math.atan(o.ty);
    o.surface = t < 0.5 ? a.surface : b.surface;
    // curvature from the heading change across the neighbouring segment
    final j = hi < _w.length - 1 ? hi + 1 : hi;
    final ya = math.atan2(_w[lo].tx, _w[lo].tz), yb = math.atan2(_w[j].tx, _w[j].tz);
    var dy = yb - ya;
    while (dy > math.pi) {
      dy -= 2 * math.pi;
    }
    while (dy < -math.pi) {
      dy += 2 * math.pi;
    }
    o.kappa = dy / math.max(1e-3, _w[j].s - _w[lo].s);
    return o;
  }
}

/// A polyline in 3D (reference coordinates) parameterised by 0..1.
class Polyline3 {
  Polyline3(this.points) {
    _cum = [0];
    for (int i = 1; i < points.length; i++) {
      _cum.add(_cum.last + (points[i] - points[i - 1]).length);
    }
  }

  final List<vm.Vector3> points;
  late final List<double> _cum;

  double get length => _cum.last;

  /// Position at normalised parameter u (0..1) with tangent.
  vm.Vector3 at(double u, [vm.Vector3? tangentOut]) {
    final d = u.clamp(0.0, 1.0) * length;
    int i = 1;
    while (i < _cum.length - 1 && _cum[i] < d) {
      i++;
    }
    final seg = math.max(1e-6, _cum[i] - _cum[i - 1]);
    final t = ((d - _cum[i - 1]) / seg).clamp(0.0, 1.0);
    final a = points[i - 1], b = points[i];
    if (tangentOut != null) {
      tangentOut.setFrom((b - a).normalized());
    }
    return a + (b - a) * t;
  }
}
