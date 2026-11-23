// Faithful Dart port of the Neon Scramble web demo's Pegman pose / IK solver
// (minified bundle `index-Crd_y_lF.js`, bytes ~899844..921800: `Rf`, `Mp`,
// `Np`, `kp`, `pm`, `mm` and their vector/quaternion helpers).
//
// Conventions are kept exactly as in the reference:
//  * vectors are `List<double>` of length 3, quaternions `[x, y, z, w]`
//    (three.js order);
//  * `ip()` builds a quaternion from Euler angles using the reference's own
//    formula (it is NOT three.js's default 'XYZ' order; ported verbatim);
//  * coordinates are the GLB rig's local frame (+Y up, +Z forward, +X = the
//    rig's left side), i.e. the pose is applied to the `pegman_rig.glb`
//    node hierarchy unchanged.
//
// Each Dart helper is annotated with the minified JS name it ports.

import 'dart:math' as math;

// ---------------------------------------------------------------- constants

/// `zf` — epsilon used throughout the reference.
const double _zf = 1e-9;

/// `Rf` — rig specification (proportions of `pegman_rig.glb`).
abstract final class PegmanRigSpec {
  static const double totalHeightM = 1.72;
  static const double restPelvisY = 0.64;
  static const List<double> torsoLocal = [0, 0.04, 0];
  static const List<double> filamentLocal = [0, 0.32, 0];
  static const List<double> collarLocal = [0, 0.488, 0];
  static const List<double> chestVLocal = [0, 0.32, 0];
  static const List<double> headLocal = [0, 0.766, 0];
  static const List<double> hipOffsetL = [0.123, 0, 0];
  static const List<double> hipOffsetR = [-0.123, 0, 0];
  static const List<double> shoulderOffsetL = [0.232, 0.376, 0];
  static const List<double> shoulderOffsetR = [-0.232, 0.376, 0];
  static const List<double> thighRestVec = [0, -0.29, 0];
  static const List<double> shinRestVec = [0, -0.26, 0];
  static const List<double> upperArmRestVecL = [0.068, -0.25, 0];
  static const List<double> upperArmRestVecR = [-0.068, -0.25, 0];
  static const List<double> forearmRestVecL = [0.065, -0.244, 0];
  static const List<double> forearmRestVecR = [-0.065, -0.244, 0];
  static const double legL1 = 0.29;
  static const double legL2 = 0.26;
  static const double legReach = 0.55;
  static const double legMaxReachRatio = 0.846;
  static final double armL1 = _hypot3(0.068, 0.25, 0);
  static final double armL2 = _hypot3(0.065, 0.244, 0);
  static final double armReach = armL1 + armL2;
  static const double armMaxReachRatio = 0.844;
  static const double bootSoleHeight = 0.09;
  static const double slideTorsoHeightM = 0.36;
  static const double wallRunBankRad = 42 * math.pi / 180;
  static const double sprintLeanMinRad = 18 * math.pi / 180;
  static const double sprintLeanMaxRad = 26 * math.pi / 180;
  static const double flipPivotLocalY = 0.84;
  static const double gravityMps2 = 9.81;
}

/// `q` — hero move enum (string values in the reference).
enum PoseMove {
  skyDrop,
  dropIn,
  sprint,
  vault,
  slide,
  railGrind,
  wallRun,
  stumble,
  pinBeacon,
  finaleOrbit,
}

// ------------------------------------------------------- scalar helpers

double _hypot3(double a, double b, double c) => math.sqrt(a * a + b * b + c * c);
double _hypot4(double a, double b, double c, double d) =>
    math.sqrt(a * a + b * b + c * c + d * d);

/// `Bf` — finite-or-default.
double _bf(double? e, [double t = 0]) => (e != null && e.isFinite) ? e : t;

/// `J` — clamp with the reference's NaN/Infinity handling.
double _j(double e, double t, double n) {
  final r = t.isFinite ? t : 0.0;
  final i = n.isFinite ? n : r;
  if (e.isFinite) return e < r ? r : (e > i ? i : e);
  if (e == double.infinity) return i;
  if (e == double.negativeInfinity) return r;
  return (r <= 0 && i >= 0) ? 0 : r;
}

/// `Y` — lerp.
double _y(double e, double t, double n) {
  final r = _bf(e, 0), i = _bf(t, r), a = _bf(n, 0);
  return r + (i - r) * a;
}

/// `Vf` — smoothstep(e, t, n).
double _vf(double e, double t, double n) {
  final r = t - e;
  if (!r.isFinite || r.abs() < _zf) return n >= t ? 1 : 0;
  final i = _j((_bf(n, e) - e) / r, 0, 1);
  return i * i * (3 - 2 * i);
}

/// `Hf` — banking angle from speed & curvature.
double _hf(double e, double t, [double n = 0.42, double r = 9.81]) {
  final i = n.isFinite ? n.abs() : 0.42;
  final a = (r.isFinite && r > _zf) ? r : 9.81;
  if (!t.isFinite) {
    return t == double.infinity ? i : (t == double.negativeInfinity ? -i : 0);
  }
  if (t.abs() < _zf) return 0;
  final double o = e.isFinite
      ? math.min(200, e.abs())
      : ((e == double.infinity || e == double.negativeInfinity) ? 200 : 0);
  return o <= 0 ? 0 : _j(math.atan(o * o * t / a), -i, i);
}

/// `Uf` — damped landing squash oscillation.
double _uf(double e, [double t = 0.085, double n = 6.5, double r = 22]) {
  if (!e.isFinite || e <= 0 || e > 1.2) return 0;
  return _bf(t, 0.085) * math.exp(-_bf(n, 6.5) * e) * math.sin(_bf(r, 22) * e);
}

// ------------------------------------------------------- vector helpers

/// `X` — set.
List<double> _x(List<double> e, double t, double n, double r) {
  e[0] = t;
  e[1] = n;
  e[2] = r;
  return e;
}

/// `Wf` — copy.
List<double> _wf(List<double> e, List<double> t) {
  e[0] = t[0];
  e[1] = t[1];
  e[2] = t[2];
  return e;
}

/// `Gf` — add.
List<double> _gf(List<double> e, List<double> t, List<double> n) {
  e[0] = t[0] + n[0];
  e[1] = t[1] + n[1];
  e[2] = t[2] + n[2];
  return e;
}

/// `Kf` — subtract.
List<double> _kf(List<double> e, List<double> t, List<double> n) {
  e[0] = t[0] - n[0];
  e[1] = t[1] - n[1];
  e[2] = t[2] - n[2];
  return e;
}

/// `qf` — e = t + n * r.
List<double> _qf(List<double> e, List<double> t, List<double> n, double r) {
  e[0] = t[0] + n[0] * r;
  e[1] = t[1] + n[1] * r;
  e[2] = t[2] + n[2] * r;
  return e;
}

/// `Jf` — cross product.
List<double> _jf(List<double> e, List<double> t, List<double> n) {
  final r = t[0], i = t[1], a = t[2], o = n[0], s = n[1], c = n[2];
  e[0] = i * c - a * s;
  e[1] = a * o - r * c;
  e[2] = r * s - i * o;
  return e;
}

/// `Yf` — length.
double _yf(List<double> e) => _hypot3(e[0], e[1], e[2]);

/// `Xf` — normalize into e (returns original length; zero → [0,-1,0]).
double _xf(List<double> e, List<double> t) {
  final n = _hypot3(t[0], t[1], t[2]);
  if (n < _zf) {
    e[0] = 0;
    e[1] = -1;
    e[2] = 0;
    return 0;
  }
  final r = 1 / n;
  e[0] = t[0] * r;
  e[1] = t[1] * r;
  e[2] = t[2] * r;
  return n;
}

/// `Zf` — distance.
double _zfDist(List<double> e, List<double> t) =>
    _hypot3(e[0] - t[0], e[1] - t[1], e[2] - t[2]);

/// `Qf` — rotate vector t about unit axis n by angle r (Rodrigues).
List<double> _qfRot(List<double> e, List<double> t, List<double> n, double r) {
  final i = t[0], a = t[1], o = t[2], s = n[0], c = n[1], l = n[2];
  final u = math.cos(r), d = math.sin(r);
  final f = s * i + c * a + l * o;
  final p = c * o - l * a, m = l * i - s * o, h = s * a - c * i;
  final g = 1 - u;
  e[0] = i * u + p * d + s * f * g;
  e[1] = a * u + m * d + c * f * g;
  e[2] = o * u + h * d + l * f * g;
  return e;
}

// --------------------------------------------------- quaternion helpers

/// `$f` — identity.
List<double> _qIdentity(List<double> e) {
  e[0] = 0;
  e[1] = 0;
  e[2] = 0;
  e[3] = 1;
  return e;
}

/// `ep` — e = t * n.
List<double> _ep(List<double> e, List<double> t, List<double> n) {
  final r = t[0], i = t[1], a = t[2], o = t[3];
  final s = n[0], c = n[1], l = n[2], u = n[3];
  e[0] = o * s + r * u + i * l - a * c;
  e[1] = o * c - r * l + i * u + a * s;
  e[2] = o * l + r * c - i * s + a * u;
  e[3] = o * u - r * s - i * c - a * l;
  return e;
}

/// `tp` — conjugate.
List<double> _tp(List<double> e, List<double> t) {
  e[0] = -t[0];
  e[1] = -t[1];
  e[2] = -t[2];
  e[3] = t[3];
  return e;
}

/// `np` — normalize (degenerate → identity).
List<double> _np(List<double> e, List<double> t) {
  final n = _hypot4(t[0], t[1], t[2], t[3]);
  if (!n.isFinite || n < _zf) return _qIdentity(e);
  final r = 1 / n;
  e[0] = t[0] * r;
  e[1] = t[1] * r;
  e[2] = t[2] * r;
  e[3] = t[3] * r;
  return e;
}

/// `rp` — rotate vector n by quaternion t.
List<double> _rp(List<double> e, List<double> t, List<double> n) {
  final r = t[0], i = t[1], a = t[2], o = t[3];
  final s = n[0], c = n[1], l = n[2];
  final u = 2 * (i * l - a * c), d = 2 * (a * s - r * l), f = 2 * (r * c - i * s);
  e[0] = s + o * u + (i * f - a * d);
  e[1] = c + o * d + (a * u - r * f);
  e[2] = l + o * f + (r * d - i * u);
  return e;
}

/// `ip` — Euler → quaternion, verbatim reference formula.
List<double> _ip(List<double> e, double t, double n, double r) {
  final i = math.cos(t * 0.5), a = math.sin(t * 0.5);
  final o = math.cos(n * 0.5), s = math.sin(n * 0.5);
  final c = math.cos(r * 0.5), l = math.sin(r * 0.5);
  e[0] = a * o * c + i * s * l;
  e[1] = i * s * c - a * o * l;
  e[2] = i * o * l - a * s * c;
  e[3] = i * o * c + a * s * l;
  return e;
}

/// `ap` — quaternion from basis columns (t, n, r).
List<double> _ap(List<double> e, List<double> t, List<double> n, List<double> r) {
  final i = t[0], a = n[0], o = r[0];
  final s = t[1], c = n[1], l = r[1];
  final u = t[2], d = n[2], f = r[2];
  final p = i + c + f;
  if (p > 0) {
    final tt = 0.5 / math.sqrt(p + 1);
    e[3] = 0.25 / tt;
    e[0] = (d - l) * tt;
    e[1] = (o - u) * tt;
    e[2] = (s - a) * tt;
  } else if (i > c && i > f) {
    final tt = 2 * math.sqrt(math.max(_zf, 1 + i - c - f));
    e[3] = (d - l) / tt;
    e[0] = 0.25 * tt;
    e[1] = (a + s) / tt;
    e[2] = (o + u) / tt;
  } else if (c > f) {
    final tt = 2 * math.sqrt(math.max(_zf, 1 + c - i - f));
    e[3] = (o - u) / tt;
    e[0] = (a + s) / tt;
    e[1] = 0.25 * tt;
    e[2] = (l + d) / tt;
  } else {
    final tt = 2 * math.sqrt(math.max(_zf, 1 + f - i - c));
    e[3] = (s - a) / tt;
    e[0] = (o + u) / tt;
    e[1] = (l + d) / tt;
    e[2] = 0.25 * tt;
  }
  return _np(e, e);
}

/// `op` — inverse of the bone-frame rotation for a rest vector.
List<double> _op(List<double> e) {
  final t = [0.0, 0.0, 0.0];
  _xf(t, e);
  final n = [-t[0], -t[1], -t[2]];
  final r = [0.0, 0.0, 1.0];
  final i = [0.0, 0.0, 0.0];
  _jf(i, n, r);
  _xf(i, i);
  final a = [0.0, 0.0, 0.0];
  _jf(a, i, n);
  _xf(a, a);
  final o = [0.0, 0.0, 0.0, 1.0];
  _ap(o, i, n, a);
  return _tp([0.0, 0.0, 0.0, 1.0], o);
}

List<double> _v3([double a = 0, double b = 0, double c = 0]) => [a, b, c];
List<double> _q4() => [0.0, 0.0, 0.0, 1.0];

// `sp`, `cp`, `lp`, `up` — rest-frame corrections for the arm bones.
final List<double> _sp = _op(PegmanRigSpec.upperArmRestVecL);
final List<double> _cp = _op(PegmanRigSpec.upperArmRestVecR);
final List<double> _lp = _op(PegmanRigSpec.forearmRestVecL);
final List<double> _up = _op(PegmanRigSpec.forearmRestVecR);

// Module-scope scratch (same names as the reference).
final _dp = _v3(), _fp = _v3(), _pp = _v3(), _mp = _v3(), _hp = _v3();
final _gp = _v3(), _vp = _v3(), _yp = _v3(), _bp = _v3();
final _xp = _v3(0, 0, 1);
final _sP = _v3(), _cP = _v3(), _wp = _v3();
final _tP = _q4(), _eP = _q4();
final _dP = _v3();
final _oP = _v3(0, -PegmanRigSpec.bootSoleHeight, 0);

// ----------------------------------------------------------------- IK

/// `jp()` — two-bone IK chain result.
class IkChain {
  final List<double> root = _v3();
  final List<double> mid = _v3();
  final List<double> end = _v3();
  final List<double> effectiveTarget = _v3();
  final List<double> upperDir = _v3(0, -1, 0);
  final List<double> lowerDir = _v3(0, -1, 0);
  final List<double> bendAxis = _v3(-1, 0, 0);
  double alphaRad = 0;
  double bendAngleRad = 0;
  double rawDist = 0;
  double clampedDist = 0;
  double reachRatio = 0;
  double errorM = 0;
  bool clamped = false;
}

double _ikC(double e, [double t = 0]) => e.isFinite ? _j(e, -1e6, 1e6) : t;

/// `kp` — analytic two-bone IK (root e, target t, bone lengths n/r,
/// pole/bend hint i, output a, max reach ratio o).
IkChain _kp(List<double> e, List<double> t, double n, double r, List<double> i,
    IkChain s, [double o = 0.846]) {
  final f = _ikC(e[0], 0), p = _ikC(e[1], 0), m = _ikC(e[2], 0);
  _x(_yp, f, p, m);
  _x(_bp, _ikC(t[0], f), _ikC(t[1], p - 0.5), _ikC(t[2], m));
  _x(_xp, _ikC(i[0], 0), _ikC(i[1], 0), _ikC(i[2], 1));
  final h = _j(n.isFinite ? n : 0.35, 1e-4, 1e4);
  final g = _j(r.isFinite ? r : 0.35, 1e-4, 1e4);
  final ratio = _j(o.isFinite ? o : 0.846, 0.5, 0.848);
  _wf(s.root, _yp);
  _kf(_dp, _bp, _yp);
  final v = _yf(_dp);
  final y = v.isFinite;
  final b = y ? v : 0.0;
  final x = h + g;
  final sMax = math.max(1e-4, x * ratio);
  final c = math.min(sMax, (h - g).abs() + math.min(0.03, x * 0.25));
  final w = _j(b, c, sMax);
  if (!y || b < 1e-8) {
    _x(_fp, 0, -1, 0);
  } else {
    final inv = 1 / b;
    _x(_fp, _dp[0] * inv, _dp[1] * inv, _dp[2] * inv);
  }
  _qf(_vp, _yp, _fp, w);
  _wf(s.effectiveTarget, _vp);
  final tt = math.max(1e-12, 2 * h * w);
  final eCos = _j((h * h + w * w - g * g) / tt, -1, 1);
  final d = math.acos(eCos);
  final oo = math.max(1e-12, 2 * h * g);
  final k = _j((h * h + g * g - w * w) / oo, -1, 1);
  final a = math.pi - math.acos(k);
  _xf(_pp, _xp);
  _jf(_mp, _fp, _pp);
  if (_yf(_mp) < 1e-6) {
    _x(_dP, 0, 0, 1);
    _jf(_mp, _fp, _dP);
    if (_yf(_mp) < 1e-6) _x(_mp, -1, 0, 0);
  }
  _xf(_mp, _mp);
  _qfRot(_hp, _fp, _mp, d);
  _xf(_hp, _hp);
  _qf(s.mid, _yp, _hp, h);
  _kf(_gp, _vp, s.mid);
  final lowerTmp = _v3();
  _xf(lowerTmp, _gp);
  _qf(s.end, s.mid, lowerTmp, g);
  _wf(s.upperDir, _hp);
  _wf(s.lowerDir, lowerTmp);
  _wf(s.bendAxis, _mp);
  s.alphaRad = d.isFinite ? d : 0;
  s.bendAngleRad = a.isFinite ? a : 0;
  s.rawDist = b;
  s.clampedDist = w;
  s.reachRatio = w / x;
  s.clamped = !y || b > sMax + 1e-9 || b < c - 1e-9;
  final jErr = _zfDist(s.end, _bp);
  s.errorM = jErr.isFinite ? jErr : 0;
  return s;
}

/// `Ap` — bone rotation from IK direction t and bend axis n (sign r),
/// optionally post-multiplied by rest correction i.
List<double> _apBone(List<double> e, List<double> t, List<double> n, double r,
    [List<double>? i]) {
  _x(_cP, -t[0], -t[1], -t[2]);
  _x(_sP, n[0] * r, n[1] * r, n[2] * r);
  _xf(_sP, _sP);
  _jf(_wp, _sP, _cP);
  _xf(_wp, _wp);
  if (i != null) {
    _ap(_tP, _sP, _cP, _wp);
    _ep(e, _tP, i);
    return _np(e, e);
  }
  return _ap(e, _sP, _cP, _wp);
}

/// `pm` — clamp a target point e to reachable range from root t.
void _pm(List<double> e, List<double> t, double n, double r, double i) {
  final a = e[0] - t[0], o = e[1] - t[1], s = e[2] - t[2];
  final c = _hypot3(a, o, s);
  final l = (n + r) * i;
  final u = (n - r).abs() + 0.04;
  if (c > l && c > _zf) {
    final k = l / c;
    e[0] = t[0] + a * k;
    e[1] = t[1] + o * k;
    e[2] = t[2] + s * k;
  } else if (c < u) {
    if (c < _zf) {
      e[0] = t[0];
      e[1] = t[1] - u;
      e[2] = t[2];
    } else {
      final k = u / c;
      e[0] = t[0] + a * k;
      e[1] = t[1] + o * k;
      e[2] = t[2] + s * k;
    }
  }
}

/// `Np` — gait stepper: writes sole target i and boot euler a for gait
/// phase e (0..1), side t (+1 L / -1 R), half stride n, lift r.
/// Returns true while the foot is in stance.
bool _npGait(double e, double t, double n, double r, List<double> i, List<double> a) {
  final o = ((e % 1) + 1) % 1;
  const s = 0.48;
  final c = t * 0.124;
  if (o <= s) {
    final ee = o / s;
    final tt = _y(n, -n, ee);
    double rr = 0, l = 0;
    if (ee < 0.22) {
      final k = 1 - ee / 0.22;
      rr = -0.32 * k;
      l = 0.022 * k;
    } else if (ee > 0.72) {
      final k = (ee - 0.72) / 0.28;
      rr = 0.46 * k;
      l = 0.028 * k;
    }
    _x(i, c, l, tt);
    _x(a, rr, 0, 0);
    return true;
  }
  final ee = (o - s) / 0.52;
  final tt = ee - math.sin(ee * math.pi * 2) / (math.pi * 2);
  final l = _y(-n, n, tt);
  final u = math.sin(math.pi * ee);
  final d = r * u * u;
  final f = _y(0.42, -0.28, _vf(0.15, 0.9, ee));
  _x(i, c, d, l);
  _x(a, f, 0, 0);
  return false;
}

// ----------------------------------------------------------- public API

/// Inputs to the solver (`_poseParams` built in `_updateHeroPose`).
/// Defaults equal the reference's fallbacks for missing values.
class PoseParams {
  PoseMove move = PoseMove.sprint;
  double time = 0;
  double gaitPhase = 0;
  double speedMps = 24;
  double curvature = 0;
  double steerRate = 0;
  double futureYawDelta = 0;
  double verticalVel = 0;
  double dropInProgress = 1;
  double timeSinceLand = 99;
  double slideProgress = 0.5;
  double stumbleProgress = 0.35;
  double wallSide = 1;
  double railSide = 1;
  double railSlope = 0;
  double voltageKv = 5;
  double flipPhase = 0;

  /// null → derived from speed like the reference (`Bf(n.overchargeRatio,S)`).
  double? overchargeRatio;

  /// 'none' | 'front' | 'corkscrew'
  String flipStyle = 'none';
}

/// Local transform of one rig node (position + `[x,y,z,w]` quaternion).
class NodePose {
  NodePose(List<double> pos) : pos = List<double>.from(pos);
  final List<double> pos;
  final List<double> quat = [0.0, 0.0, 0.0, 1.0];
}

/// `Mp()` — the pose state object, mutated in place by [PegmanPoseSolver].
///
/// ## Applying it (port of the reference's `_syncPegmanRig`)
/// The reference builds this hierarchy around the GLB scene root
/// (`pegman_rig.glb`, top node `Pelvis`):
/// ```
/// PegmanWorldRoot  position = hero (x, y, z), rotation = (0, hero.yaw, 0)
///   └ PegmanFlipPivot   position = rootFlipPivotLocal  ([0, 0.84, 0])
///                       quaternion = rootFlipQuat
///       └ PegmanFlipOffset position = -rootFlipPivotLocal
///           └ GLB scene  (nodes named Pelvis, ThighL, ShinL, FootL, ThighR,
///                         ShinR, FootR, Torso, ArmL, ForearmL, ArmR,
///                         ForearmR, ChestV, CollarRim, Head)
/// ```
/// (The attach code initially sets the pivot to y 0.86 / offset −0.86, but
/// every frame overwrites them with `rootFlipPivotLocal`.)
/// Each frame, for every key of [v2Nodes] that exists in the GLB, set the
/// node's local position to `pos` and quaternion to `quat`. `HandL`/`HandR`
/// have no matching GLB node and are ignored. No bank/roll is applied to
/// the world root — banking is already baked into the pelvis rotation.
/// The reference also sets the body material: roughness .39, metalness 0,
/// envMapIntensity .34, emissiveMap = baseColor map, emissive #FFF4B2,
/// emissiveIntensity .36.
class PegmanPoseResult {
  PegmanPoseResult() {
    v2Nodes = {
      'Pelvis': pelvisRoot,
      'Torso': torsoGlassShell,
      'CollarRim': collarElectrode,
      'ChestV': chestV,
      'Head': headHelmet,
      'ThighL': thighL,
      'ShinL': shinL,
      'FootL': bootL,
      'ThighR': thighR,
      'ShinR': shinR,
      'FootR': bootR,
      'ArmL': upperArmL,
      'ForearmL': forearmL,
      'HandL': handL,
      'ArmR': upperArmR,
      'ForearmR': forearmR,
      'HandR': handR,
    };
  }

  // `nodes` (v1 names in the reference)
  final pelvisRoot = NodePose([0, 0.54, 0]);
  final torsoGlassShell = NodePose([0, 0.04, 0]);
  final collarElectrode = NodePose([0, 0.488, 0]);
  final chestV = NodePose([0, 0.32, 0]);
  final headHelmet = NodePose([0, 0.766, 0]);
  final thighL = NodePose([0.123, 0, 0]);
  final shinL = NodePose([0, -0.29, 0]);
  final bootL = NodePose([0, -0.26, 0]);
  final thighR = NodePose([-0.123, 0, 0]);
  final shinR = NodePose([0, -0.29, 0]);
  final bootR = NodePose([0, -0.26, 0]);
  final upperArmL = NodePose([0.232, 0.376, 0]);
  final forearmL = NodePose([0.068, -0.25, 0]);
  final handL = NodePose([0.065, -0.244, 0]);
  final upperArmR = NodePose([-0.232, 0.376, 0]);
  final forearmR = NodePose([-0.068, -0.25, 0]);
  final handR = NodePose([-0.065, -0.244, 0]);

  /// `v2Nodes` — GLB node name → local pose.
  late final Map<String, NodePose> v2Nodes;

  PoseMove move = PoseMove.sprint;
  final List<double> pelvisPos = [0, 0.54, 0];
  final List<double> pelvisEuler = [0, 0, 0];
  final List<double> torsoEuler = [0, 0, 0];
  final List<double> headEuler = [0, 0, 0];
  final List<double> collarLocalPos = [0, PegmanRigSpec.collarLocal[1], 0];
  final List<double> headLocalPos = [0, PegmanRigSpec.headLocal[1], 0];
  double collarGapM = 0;
  double helmetGapM = 0;
  double torsoHeightM = 0.54;
  double bankRad = 0;
  double squashM = 0;
  double filamentPulse = 1;
  final List<double> bootEulerL = [0, 0, 0];
  final List<double> bootEulerR = [0, 0, 0];
  final List<double> soleTargetL = [0.123, 0, 0];
  final List<double> soleTargetR = [-0.123, 0, 0];
  final List<double> soleActualL = [0.123, 0, 0];
  final List<double> soleActualR = [-0.123, 0, 0];
  final List<double> handTargetL = [0.34, 0.66, 0.14];
  final List<double> handTargetR = [-0.34, 0.66, -0.14];
  final List<double> sparksAnchorLocal = [0, 0.02, 0];
  bool sparksActive = false;
  final IkChain legL = IkChain(), legR = IkChain(), armL = IkChain(), armR = IkChain();
  double flipPhase = 0;
  String flipStyle = 'none';
  final List<double> flipEuler = [0, 0, 0];
  final List<double> rootFlipQuat = [0, 0, 0, 1];
  final List<double> rootFlipPivotLocal = [0, PegmanRigSpec.flipPivotLocalY, 0];
  double forwardLeanRad = 0;
  double railSlope = 0;
  double auraIntensity = 0.2;
  double mapsDangleWeight = 0;
  double stumbleWeight = 0;
  double dancePumpL = 0;
  double dancePumpR = 0;
  double ikSoleErrorL = 0;
  double ikSoleErrorR = 0;
  double ikSoleErrorM = 0;
  double maxReachRatio = 0;
  bool stanceFootL = false;
  bool stanceFootR = false;
}

/// `mm(params, pose)` — per-frame procedural pose + IK solve.
class PegmanPoseSolver {
  final PegmanPoseResult result = PegmanPoseResult();

  // Module-scope temporaries of the reference.
  final _pP = _q4(), _fP = _q4(), _iP = _q4(), _lP = _q4(), _rP = _q4(), _zP = _q4();
  final _bP = _q4(), _vP = _q4(), _hP = _q4(), _uP = _q4();
  final _wP = _q4(), _gP = _q4(), _kP = _q4(), _qP = _q4();
  final _jp = _v3(), _yP = _v3(), _xP = _v3(), _zp = _v3(), _qp = _v3();
  final _$p = _v3(), _em = _v3(), _tm = _v3(), _nm = _v3(), _rm = _v3(), _im = _v3();
  final _am = _v3(), _om = _v3(), _sm = _v3(), _cm = _v3();
  final _lm = _q4(), _um = _q4();
  final _dm = _v3(), _fm = _v3();

  PegmanPoseResult solve(PoseParams n) {
    final t = result;
    final r = n.move;
    final i = _bf(n.time, 0);
    final a = _bf(n.gaitPhase, 0);
    final o = n.speedMps;
    final double s = o.isFinite
        ? _j(o, 0, 120)
        : (o == double.infinity ? 120 : (o == double.negativeInfinity ? 0 : 24));
    final c = _j(
        _bf(
            n.curvature,
            n.curvature == double.infinity
                ? 0.5
                : (n.curvature == double.negativeInfinity ? -0.5 : 0)),
        -0.5,
        0.5);
    final l = _j(_bf(n.steerRate, 0), -1, 1);
    final u = _j(_bf(n.futureYawDelta, 0), -0.85, 0.85);
    final d = _j(_bf(n.verticalVel, 0), -120, 120);
    final f = _j(_bf(n.dropInProgress, 1), 0, 1);
    final p = _bf(n.timeSinceLand, 99);
    final m = _j(_bf(n.slideProgress, 0.5), 0, 1);
    final double h = _bf(n.wallSide, 1) >= 0 ? 1 : -1;
    final double g = _bf(n.railSide, 1) >= 0 ? 1 : -1;
    final vKv = _j(_bf(n.voltageKv, 5), 0, 15);
    final v = _j(_bf(n.flipPhase, 0), 0, 1);
    final y = n.flipStyle;
    final b = _j(_bf(n.railSlope, 0), -0.6, 0.6);
    final x = _j(_bf(n.stumbleProgress, 0.35), 0, 1);
    final sRatio = _j((s - 30) / 14, 0, 1);
    final cOver = _j(_bf(n.overchargeRatio, sRatio), 0, 1);

    t.move = r;
    t.railSlope = r == PoseMove.railGrind ? b : 0;
    t.sparksActive = false;
    t.mapsDangleWeight = 0;
    t.stumbleWeight = 0;
    t.dancePumpL = 0;
    t.dancePumpR = 0;
    t.flipPhase = v;
    t.flipStyle = (v > 0.001 && v < 0.999) ? y : 'none';

    var w = _j(_hf(s, c, 0.42) + l * 0.22, -0.44, 0.44);
    final tSq = _uf(p, 0.064, 6.5, 22);
    t.squashM = tSq;
    double eX = 0, dY = 0.54, oZ = 0, k = 0.24, aY = 0, jZ = w;
    double mT = 0.08, nT = 0, eeT = 0;
    double te = -0.18, ne = _j(u * 0.72 - l * 0.24, -0.58, 0.58), re = -w * 0.35;
    bool ie = false, ae = false;
    double oe = 0, se = 0;
    _x(_tm, 0.14, 0.22, 1);
    _x(_nm, -0.14, 0.22, 1);
    _x(_sm, 0.78, -0.32, -0.54);
    _x(_cm, -0.78, -0.32, -0.54);
    _x(_am, 0.48, 0.04, 0.1);
    _x(_om, -0.48, 0.04, 0.1);

    final ce = v > 0.001 && v < 0.999 && y != 'none';
    if (ce) {
      final e = v * v * (3 - 2 * v);
      final fx = e * math.pi * 2;
      final rr = math.sin(v * math.pi);
      final fy = y == 'corkscrew' ? e * math.pi * 2 * h : 0.0;
      final fz = y == 'corkscrew' ? rr * h * 0.42 : 0.0;
      _x(t.flipEuler, fx, fy, fz);
      _ip(t.rootFlipQuat, fx, fy, fz);
    } else {
      _x(t.flipEuler, 0, 0, 0);
      _qIdentity(t.rootFlipQuat);
    }

    final le = a / (math.pi * 2);
    final ue = le + 0.5;
    final pS = math.sin(a);
    final de = math.cos(2 * a);

    switch (r) {
      case PoseMove.skyDrop:
      case PoseMove.dropIn:
        if (f < 0.26) {
          final e = f / 0.26, nn = math.sin(i * 9.6), rr = math.sin(i * 4.8);
          t.mapsDangleWeight = 1 - _vf(0.65, 1, e);
          dY = 0.575 + 0.014 * math.cos(i * 6);
          k = 0.06 + 0.14 * e;
          aY = 0.14 * rr;
          jZ = 0.12 * rr;
          mT = 0.04 + 0.06 * e;
          nT = -0.1 * rr;
          eeT = -0.06 * rr;
          te = -0.22 - 0.12 * e;
          ne = 0.18 * math.cos(i * 3.4);
          re = -0.1 * rr;
          _x(t.soleTargetL, 0.132, 0.07 + 0.045 * math.max(0, nn), 0.11 * nn);
          _x(t.soleTargetR, -0.132, 0.07 + 0.045 * math.max(0, -nn), -0.11 * nn);
          _x(t.bootEulerL, 0.3 + 0.12 * nn, 0.05, 0);
          _x(t.bootEulerR, 0.3 - 0.12 * nn, -0.05, 0);
          _x(_am, 0.61, 0.44 + 0.04 * rr, 0.08 - 0.04 * nn);
          _x(_om, -0.61, 0.44 - 0.04 * rr, 0.08 + 0.04 * nn);
          _x(_sm, 0.72, -0.58, -0.38);
          _x(_cm, -0.72, -0.58, -0.38);
        } else if (f < 0.87) {
          final e = (f - 0.26) / 0.61;
          final nn = _vf(0, 0.25, e), rr = _vf(0.78, 1, e);
          final aa = math.sin(i * 24), oo = math.sin(i * 5.2);
          t.mapsDangleWeight = 0;
          dY = 0.575 + 0.02 * math.sin(e * math.pi);
          k = _y(_y(0.22, 0.76, nn), 0.34, rr);
          aY = 0.08 * oo;
          jZ = l * 0.28 + 0.07 * math.cos(i * 4.4);
          mT = _y(0.14 * nn, 0.16, rr);
          nT = -0.06 * oo;
          te = _y(-0.56 * nn, -0.26, rr);
          ne = _j(u * 0.55 - l * 0.22, -0.45, 0.45);
          re = -jZ * 0.4;
          _x(t.soleTargetL, 0.155, _y(0.16 + 0.025 * aa, 0.13, rr), _y(-0.19, 0.12, rr));
          _x(t.soleTargetR, -0.155, _y(0.14 - 0.025 * aa, 0.1, rr), _y(-0.15, -0.11, rr));
          _x(t.bootEulerL, _y(0.46, 0.14, rr), 0.08, 0);
          _x(t.bootEulerR, _y(0.4, 0.22, rr), -0.08, 0);
          _x(_am, 0.635, _y(0.4, 0.22, rr) + 0.022 * aa, _y(-0.08, 0.14, rr));
          _x(_om, -0.635, _y(0.4, 0.22, rr) - 0.022 * aa, _y(-0.08, -0.1, rr));
          _x(_sm, 0.76, -0.42, -0.5);
          _x(_cm, -0.76, -0.42, -0.5);
        } else if (f < 0.945) {
          final e = (f - 0.87) / 0.075;
          final nn = _uf(e * 0.24, 0.075, 6.5, 22);
          t.squashM = nn;
          dY = 0.455 - math.max(0, nn) * 0.36 + e * 0.042;
          k = 0.34 * (1 - e * 0.25);
          aY = 0.1 * (1 - e);
          jZ = 0;
          mT = 0.18 * (1 - e * 0.25);
          nT = -0.08 * (1 - e);
          te = -0.32 + e * 0.14;
          ne = u * 0.5;
          re = 0;
          _x(t.soleTargetL, 0.145, 0, 0.125);
          _x(t.soleTargetR, -0.145, 0, -0.115);
          _x(t.bootEulerL, 0, 0.08, 0);
          _x(t.bootEulerR, 0.2, -0.08, 0);
          ie = true;
          ae = true;
          _x(_am, 0.5, 0.08, 0.22);
          _x(_om, -0.52, 0.1, -0.18);
          _x(_sm, 0.78, -0.25, -0.58);
          _x(_cm, -0.78, -0.2, -0.58);
          t.sparksActive = true;
          _x(t.sparksAnchorLocal, 0, 0.02, 0.05);
        } else {
          final e = (f - 0.945) / 0.055;
          final nn = _vf(0, 1, e);
          dY = _y(0.49, 0.525, nn);
          k = _y(0.3, 0.24, nn);
          aY = _y(0.08, 0.14 * pS, nn);
          jZ = w * nn;
          mT = _y(0.14, 0.08, nn);
          nT = -0.75 * aY;
          te = _y(-0.22, -0.18, nn);
          ie = _npGait(le, 1, 0.165 * (0.65 + 0.35 * nn), 0.16, t.soleTargetL, t.bootEulerL);
          ae = _npGait(ue, -1, 0.165 * (0.65 + 0.35 * nn), 0.16, t.soleTargetR, t.bootEulerR);
          _x(_am, 0.49, 0.06 - 0.04 * pS, -0.18 * pS + 0.09);
          _x(_om, -0.49, 0.06 + 0.04 * pS, 0.18 * pS + 0.09);
          t.sparksActive = e < 0.65;
          _x(t.sparksAnchorLocal, 0, 0.02, -0.06);
        }
      case PoseMove.sprint:
        {
          final e = _j((s - 24) / 20, 0, 1);
          final nn = _y(PegmanRigSpec.sprintLeanMinRad, PegmanRigSpec.sprintLeanMaxRad, e);
          final rr = _j(0.164 + 0.022 * e, 0.145, 0.186);
          final ii = _j(0.155 + 0.038 * e, 0.14, 0.195);
          dY = 0.525 - 0.018 * e + 0.02 * de - tSq * 0.46;
          k = nn * 0.72 + tSq * 0.75;
          mT = nn * 0.28 + 0.026 * math.sin(a * 2) + tSq * 0.42;
          aY = (0.15 + 0.028 * e) * pS;
          nT = -0.75 * aY;
          eeT = -0.055 * pS;
          jZ = w;
          te = -(k + mT) * 0.68 - tSq * 0.35;
          ne = _j(u * 0.85 - l * 0.24 - (aY + nT) * 0.4, -0.62, 0.62);
          re = -w * 0.45;
          ie = _npGait(le, 1, rr, ii, t.soleTargetL, t.bootEulerL);
          ae = _npGait(ue, -1, rr, ii, t.soleTargetR, t.bootEulerR);
          final oo = 0.19 + 0.035 * e;
          _x(_am, 0.49, 0.06 - 0.045 * pS, -oo * pS + 0.08);
          _x(_om, -0.49, 0.06 + 0.045 * pS, oo * pS + 0.08);
          _x(_sm, 0.78, -0.3, -0.55);
          _x(_cm, -0.78, -0.3, -0.55);
          t.sparksActive = s >= 30 && (ie || ae);
          _x(t.sparksAnchorLocal, ie ? 0.123 : -0.123, 0.02, -0.13);
        }
      case PoseMove.vault:
        {
          final e = _j(d / 12, -1, 1);
          final nn = ce ? 0.85 + 0.15 * math.sin(v * math.pi) : 1 - e.abs() * 0.45;
          dY = 0.56 + 0.024 * nn;
          k = ce ? 0.34 : _j(-e * 0.24 + 0.2, -0.2, 0.42);
          aY = 0.14 * l;
          jZ = ce ? 0 : w * 0.75;
          mT = 0.18 * nn;
          nT = -0.1 * l;
          te = -0.18 - k * 0.4;
          ne = _j(u * 0.8, -0.6, 0.6);
          if (ce) {
            _x(t.soleTargetL, 0.132, 0.16 + 0.05 * nn, 0.13);
            _x(t.soleTargetR, -0.132, 0.13 + 0.05 * nn, -0.06);
            _x(t.bootEulerL, 0.4, 0, 0);
            _x(t.bootEulerR, 0.46, 0, 0);
            _x(_am, 0.61, 0.22, 0.14);
            _x(_om, -0.61, 0.22, 0.14);
            _x(_sm, 0.9, -0.32, -0.3);
            _x(_cm, -0.9, -0.32, -0.3);
            t.sparksActive = true;
            _x(t.sparksAnchorLocal, 0, dY, -0.12);
          } else {
            _x(t.soleTargetL, 0.132, 0.12 + 0.09 * nn, 0.16);
            _x(t.soleTargetR, -0.132, 0.08 + 0.07 * nn, -0.15);
            _x(t.bootEulerL, 0.24, 0, 0);
            _x(t.bootEulerR, 0.44, 0, 0);
            _x(_am, 0.64, 0.3 + 0.05 * e, 0.14);
            _x(_om, -0.64, 0.28 + 0.04 * e, -0.1);
            _x(_sm, 0.9, -0.36, -0.26);
            _x(_cm, -0.9, -0.36, -0.26);
          }
        }
      case PoseMove.slide:
        {
          final e = _vf(0, 0.08, m) * (1 - _vf(0.92, 1, m));
          dY = _y(0.465, PegmanRigSpec.slideTorsoHeightM, e);
          oZ = 0.04 * e;
          k = _y(-0.36, -0.96, e);
          aY = 0.28 * e;
          jZ = -0.18 * e + w * 0.25;
          mT = -0.06 * e;
          nT = -0.14 * e;
          te = 0.72 * e;
          ne = _j(u * 0.65 - 0.1 * e, -0.55, 0.55);
          re = 0.1 * e;
          _x(t.soleTargetL, 0.128, 0.032, 0.24);
          _x(t.soleTargetR, -0.148, 0.025, -0.08);
          _x(t.bootEulerL, -0.44 * e, 0.14 * e, 0);
          _x(t.bootEulerR, 0.36 * e, -0.24 * e, -0.2 * e);
          ie = true;
          ae = true;
          _x(_am, 0.56, 0.24, 0.2);
          _x(_om, -0.55, 0.08, -0.12);
          _x(_sm, 0.78, -0.35, -0.52);
          _x(_cm, -0.78, -0.24, -0.58);
          t.sparksActive = e > 0.25;
          _x(t.sparksAnchorLocal, -0.12, 0.02, -0.06);
        }
      case PoseMove.railGrind:
        {
          final e = _j((s - 28) / 16, 0, 1);
          final nn = math.sin(i * 7.8) * 0.04 + _j(c * 16, -0.18, 0.18);
          final rr = math.sin(i * 42) * 0.004;
          dY = 0.488 - 0.02 * e + rr - nn.abs() * 0.035;
          eX = nn * 0.11;
          k = 0.14 + 0.05 * e + _j(b * 0.28, -0.08, 0.12);
          aY = g * 0.58;
          jZ = _j(w * 0.65 - nn * 0.42, -0.34, 0.34);
          mT = 0.11 + 0.04 * e;
          nT = -g * 0.14;
          eeT = nn * 0.3;
          te = -0.16;
          ne = _j(-g * 0.44 + u * 0.68, -0.72, 0.72);
          re = -jZ * 0.55;
          final aa = g > 0 ? 0.168 : -0.168;
          final oo = g > 0 ? -0.168 : 0.168;
          final ll = math.tan(b);
          _x(t.soleTargetL, 0, aa * ll, aa);
          _x(t.soleTargetR, 0, oo * ll, oo);
          oe = g * 1.18;
          se = g * 1.05;
          _x(t.bootEulerL, -b * math.cos(oe), oe, -b * math.sin(oe));
          _x(t.bootEulerR, -b * math.cos(se), se, -b * math.sin(se));
          ie = true;
          ae = true;
          _x(_tm, g * 0.55, 0.25, 0.8);
          _x(_nm, g * 0.55, 0.25, 0.72);
          final dd = math.sin(i * 6.2) * 0.042;
          _x(_am, 0.64, 0.32 + dd, 0.11);
          _x(_om, -0.645, 0.29 - dd, 0.08);
          _x(_sm, 0.78, -0.45, -0.32);
          _x(_cm, -0.78, -0.45, -0.32);
          t.sparksActive = true;
          _x(t.sparksAnchorLocal, 0, -0.14 * ll + 0.01, -0.14);
        }
      case PoseMove.wallRun:
        {
          final e = -h * PegmanRigSpec.wallRunBankRad;
          w = e;
          const nn = 0.162, rr = 0.155;
          final ii = a * 1.32;
          final oo = math.sin(ii);
          final ss = ii / (math.pi * 2);
          final cc = ss + 0.5;
          dY = 0.518 + 0.018 * math.cos(2 * ii);
          k = 0.25;
          aY = 0.15 * oo - h * 0.08;
          jZ = e;
          mT = 0.1;
          nT = -0.72 * aY;
          eeT = h * 0.1;
          te = -0.19;
          ne = _j(u * 0.78 - h * 0.12, -0.58, 0.58);
          re = -e * 0.58;
          ie = _npGait(ss, 1, nn, rr, t.soleTargetL, t.bootEulerL);
          ae = _npGait(cc, -1, nn, rr, t.soleTargetR, t.bootEulerR);
          t.bootEulerL[2] = e * 0.85;
          t.bootEulerR[2] = e * 0.85;
          t.soleTargetL[0] -= h * 0.062;
          t.soleTargetR[0] -= h * 0.062;
          _x(_tm, h * 0.38 + 0.12, 0.25, 1);
          _x(_nm, h * 0.38 - 0.12, 0.25, 1);
          _x(_am, 0.51, 0.09 - 0.04 * oo, -0.17 * oo + 0.11);
          _x(_om, -0.51, 0.09 + 0.04 * oo, 0.17 * oo + 0.11);
          _x(_sm, 0.78, -0.28, -0.56);
          _x(_cm, -0.78, -0.28, -0.56);
          t.sparksActive = true;
          _x(t.sparksAnchorLocal, -h * 0.22, 0.08, 0);
        }
      case PoseMove.stumble:
        {
          final e = math.sin(math.min(1, x * 1.45) * math.pi);
          final nn = _vf(0.45, 1, x);
          final rr = math.sin(x * math.pi * 3) * (1 - nn);
          t.stumbleWeight = e;
          dY = _y(0.478 - 0.022 * e, 0.522, nn);
          k = _y(-0.24 * e + 0.04, 0.22, nn);
          aY = 0.28 * rr;
          jZ = -0.18 * rr + w * nn;
          mT = _y(-0.14 * e, 0.08, nn);
          nT = -0.14 * rr;
          eeT = 0.12 * rr;
          te = 0.16 * e - 0.14 * nn;
          ne = _j(-0.22 * rr + u * 0.5 * nn, -0.5, 0.5);
          re = 0.16 * rr;
          ie = _npGait(le, 1, 0.135, 0.13, t.soleTargetL, t.bootEulerL);
          ae = _npGait(ue, -1, 0.135, 0.13, t.soleTargetR, t.bootEulerR);
          _x(_am, _y(0.63, 0.52, nn), _y(0.36, 0.08, nn) + 0.05 * rr, _y(0.14, 0.08, nn));
          _x(_om, -_y(0.63, 0.52, nn), _y(0.3, 0.08, nn) - 0.05 * rr, _y(-0.12, 0.08, nn));
          _x(_sm, 0.8, -0.36, -0.46);
          _x(_cm, -0.8, -0.36, -0.46);
          t.sparksActive = x < 0.45;
          _x(t.sparksAnchorLocal, 0, 0.45, 0.14);
        }
      case PoseMove.pinBeacon:
        {
          final e = math.sin(i * 9);
          if (ce) {
            dY = 0.56;
            k = 0.3;
            aY = 0.08 * e;
            jZ = 0;
            mT = 0.16;
            nT = -0.06 * e;
            te = -0.16;
            ne = 0;
            re = 0;
            _x(t.soleTargetL, 0.132, 0.16, 0.13);
            _x(t.soleTargetR, -0.132, 0.13, -0.07);
            _x(t.bootEulerL, 0.36, 0.06, 0);
            _x(t.bootEulerR, 0.42, -0.06, 0);
            _x(_am, 0.54, 0.2, 0.2);
            _x(_om, -0.54, 0.2, 0.2);
            _x(_sm, 0.78, -0.32, -0.54);
            _x(_cm, -0.78, -0.32, -0.54);
          } else {
            dY = 0.57 + 0.02 * e;
            k = -0.12;
            aY = 0.14 * math.sin(i * 3);
            jZ = w * 0.35;
            mT = -0.12;
            nT = -0.1 * math.sin(i * 3);
            te = -0.1;
            ne = _j(u * 0.5, -0.45, 0.45);
            re = 0;
            _x(t.soleTargetL, 0.14, 0.12, 0.15);
            _x(t.soleTargetR, -0.14, 0.08, -0.14);
            _x(t.bootEulerL, 0.2, 0.1, 0);
            _x(t.bootEulerR, 0.34, -0.1, 0);
            _x(_am, 0.6, 0.5 + 0.04 * e, 0.14);
            _x(_om, -0.6, 0.5 - 0.04 * e, 0.14);
            _x(_sm, 0.74, -0.55, -0.38);
            _x(_cm, -0.74, -0.55, -0.38);
          }
          t.sparksActive = true;
          _x(t.sparksAnchorLocal, 0, 0.92, 0.08);
        }
      case PoseMove.finaleOrbit:
        {
          final e = i * 5.4, nn = i * 2.7;
          final rr = math.sin(e).abs();
          final aa = math.sin(nn);
          final oo = 0.5 + 0.5 * math.sin(e);
          final ss = 0.5 + 0.5 * math.sin(e - 0.52);
          t.dancePumpL = oo;
          t.dancePumpR = ss;
          eX = 0.036 * aa;
          dY = 0.478 + 0.056 * rr;
          k = 0.04 - 0.05 * rr;
          aY = 0.16 * aa;
          jZ = -0.075 * aa;
          mT = -0.05 - 0.05 * rr;
          nT = -0.09 * aa;
          eeT = 0.05 * aa;
          te = -0.05 - 0.11 * math.sin(e);
          ne = 0.18 * aa;
          re = 0.1 * aa;
          _x(t.soleTargetL, 0.136, 0, 0.042);
          _x(t.soleTargetR, -0.136, 0, -0.042);
          _x(t.bootEulerL, 0, 0.12, 0);
          _x(t.bootEulerR, 0, -0.12, 0);
          ie = true;
          ae = true;
          final cc = math.sin(oo * math.pi), ll = math.sin(ss * math.pi);
          _x(_am, _y(0.58, 0.44, oo) + 0.065 * cc, _y(0.24, 0.72, oo), _y(0.18, 0.12, oo) + 0.04 * cc);
          _x(_om, -(_y(0.58, 0.44, ss) + 0.065 * ll), _y(0.24, 0.72, ss), _y(0.18, 0.12, ss) + 0.04 * ll);
          _x(_sm, 0.74, -0.52, -0.42);
          _x(_cm, -0.74, -0.52, -0.42);
          t.sparksActive = rr > 0.82;
          _x(t.sparksAnchorLocal, 0, 0.04, 0);
        }
    }

    t.bankRad = w;
    t.forwardLeanRad = k + mT;
    t.torsoHeightM = r == PoseMove.slide ? PegmanRigSpec.slideTorsoHeightM : dY;
    t.filamentPulse = r == PoseMove.finaleOrbit
        ? 0.92 + 0.12 * math.sin(i * 4.4)
        : _j(0.35 + vKv / 15 * 0.85 + cOver * 0.35 + 0.08 * math.sin(i * 14), 0.25, 1.65);
    t.auraIntensity = r == PoseMove.finaleOrbit
        ? 1.25 + 0.18 * math.sin(i * 4.4)
        : _j(0.08 + vKv / 15 * 1.15 + cOver * 0.55 + (ce ? 0.25 : 0), 0.08, 1.8);
    t.stanceFootL = ie;
    t.stanceFootR = ae;
    _x(t.pelvisPos, eX, dY, oZ);
    _x(t.pelvisEuler, k, aY, jZ);
    _x(t.torsoEuler, mT, nT, eeT);
    _x(t.headEuler, te, ne, re);
    _ip(_pP, k, aY, jZ);
    _ip(_fP, mT, nT, eeT);
    _ep(_iP, _pP, _fP);
    _np(_iP, _iP);
    _ip(_lP, te, ne, re);
    t.collarGapM = 0;
    t.helmetGapM = 0;
    _rp(_dP, _pP, PegmanRigSpec.hipOffsetL);
    _gf(_jp, t.pelvisPos, _dP);
    _rp(_dP, _pP, PegmanRigSpec.hipOffsetR);
    _gf(_yP, t.pelvisPos, _dP);
    _rp(_dP, _pP, PegmanRigSpec.torsoLocal);
    _gf(_xP, t.pelvisPos, _dP);
    _rp(_dP, _iP, PegmanRigSpec.shoulderOffsetL);
    _gf(_zp, _xP, _dP);
    _rp(_dP, _iP, PegmanRigSpec.shoulderOffsetR);
    _gf(_qp, _xP, _dP);
    if (r == PoseMove.railGrind && b.abs() > 1e-6) {
      _ip(_lm, -b, 0, 0);
      _ip(_um, 0, oe, 0);
      _ep(_rP, _lm, _um);
      _np(_rP, _rP);
      _ip(_um, 0, se, 0);
      _ep(_zP, _lm, _um);
      _np(_zP, _zP);
    } else {
      _ip(_rP, t.bootEulerL[0], t.bootEulerL[1], t.bootEulerL[2]);
      _ip(_zP, t.bootEulerR[0], t.bootEulerR[1], t.bootEulerR[2]);
    }
    _rp(_dm, _rP, _oP);
    _rp(_fm, _zP, _oP);
    _kf(_$p, t.soleTargetL, _dm);
    _kf(_em, t.soleTargetR, _fm);
    final fe = PegmanRigSpec.legReach * PegmanRigSpec.legMaxReachRatio;
    var pe = _zfDist(_jp, _$p), me = _zfDist(_yP, _em);
    if (pe > fe || me > fe) {
      final e = math.max(pe - fe, me - fe);
      if (ie || ae) {
        final drop = math.min(0.18, e * 1.18 + 0.006);
        t.pelvisPos[1] -= drop;
        _jp[1] -= drop;
        _yP[1] -= drop;
        _xP[1] -= drop;
        _zp[1] -= drop;
        _qp[1] -= drop;
        if (r != PoseMove.slide) t.torsoHeightM = t.pelvisPos[1];
      }
      pe = _zfDist(_jp, _$p);
      me = _zfDist(_yP, _em);
      if (pe > fe) {
        _pm(_$p, _jp, PegmanRigSpec.legL1, PegmanRigSpec.legL2, PegmanRigSpec.legMaxReachRatio - 0.002);
        _gf(t.soleTargetL, _$p, _dm);
      }
      if (me > fe) {
        _pm(_em, _yP, PegmanRigSpec.legL1, PegmanRigSpec.legL2, PegmanRigSpec.legMaxReachRatio - 0.002);
        _gf(t.soleTargetR, _em, _fm);
      }
    }
    _rp(_dP, _iP, _am);
    _gf(t.handTargetL, _xP, _dP);
    _rp(_dP, _iP, _om);
    _gf(t.handTargetR, _xP, _dP);
    _rp(_rm, _iP, _sm);
    _rp(_im, _iP, _cm);
    _pm(t.handTargetL, _zp, PegmanRigSpec.armL1, PegmanRigSpec.armL2, PegmanRigSpec.armMaxReachRatio);
    _pm(t.handTargetR, _qp, PegmanRigSpec.armL1, PegmanRigSpec.armL2, PegmanRigSpec.armMaxReachRatio);
    _kp(_jp, _$p, PegmanRigSpec.legL1, PegmanRigSpec.legL2, _tm, t.legL, PegmanRigSpec.legMaxReachRatio);
    _kp(_yP, _em, PegmanRigSpec.legL1, PegmanRigSpec.legL2, _nm, t.legR, PegmanRigSpec.legMaxReachRatio);
    _kp(_zp, t.handTargetL, PegmanRigSpec.armL1, PegmanRigSpec.armL2, _rm, t.armL, PegmanRigSpec.armMaxReachRatio);
    _kp(_qp, t.handTargetR, PegmanRigSpec.armL1, PegmanRigSpec.armL2, _im, t.armR, PegmanRigSpec.armMaxReachRatio);
    _gf(t.soleActualL, t.legL.end, _dm);
    _gf(t.soleActualR, t.legR.end, _fm);
    t.ikSoleErrorL = _zfDist(t.soleActualL, t.soleTargetL);
    t.ikSoleErrorR = _zfDist(t.soleActualR, t.soleTargetR);
    t.ikSoleErrorM = math.max(t.ikSoleErrorL, t.ikSoleErrorR);
    t.maxReachRatio = [
      t.legL.reachRatio,
      t.legR.reachRatio,
      t.armL.reachRatio,
      t.armR.reachRatio,
    ].reduce(math.max);

    // Node writes.
    _wf(t.pelvisRoot.pos, t.pelvisPos);
    _copyQ(t.pelvisRoot.quat, _pP);
    _copyQ(t.torsoGlassShell.quat, _fP);
    _qIdentity(t.collarElectrode.quat);
    _copyQ(t.headHelmet.quat, _lP);
    _apBone(_bP, t.legL.upperDir, t.legL.bendAxis, -1);
    _apBone(_vP, t.legL.lowerDir, t.legL.bendAxis, -1);
    _apBone(_hP, t.legR.upperDir, t.legR.bendAxis, -1);
    _apBone(_uP, t.legR.lowerDir, t.legR.bendAxis, -1);
    _tp(_eP, _pP);
    _ep(t.thighL.quat, _eP, _bP);
    _np(t.thighL.quat, t.thighL.quat);
    _ep(t.thighR.quat, _eP, _hP);
    _np(t.thighR.quat, t.thighR.quat);
    _tp(_eP, _bP);
    _ep(t.shinL.quat, _eP, _vP);
    _np(t.shinL.quat, t.shinL.quat);
    _tp(_eP, _vP);
    _ep(t.bootL.quat, _eP, _rP);
    _np(t.bootL.quat, t.bootL.quat);
    _tp(_eP, _hP);
    _ep(t.shinR.quat, _eP, _uP);
    _np(t.shinR.quat, t.shinR.quat);
    _tp(_eP, _uP);
    _ep(t.bootR.quat, _eP, _zP);
    _np(t.bootR.quat, t.bootR.quat);
    _apBone(_wP, t.armL.upperDir, t.armL.bendAxis, 1, _sp);
    _apBone(_gP, t.armL.lowerDir, t.armL.bendAxis, 1, _lp);
    _apBone(_kP, t.armR.upperDir, t.armR.bendAxis, 1, _cp);
    _apBone(_qP, t.armR.lowerDir, t.armR.bendAxis, 1, _up);
    _tp(_eP, _iP);
    _ep(t.upperArmL.quat, _eP, _wP);
    _np(t.upperArmL.quat, t.upperArmL.quat);
    _ep(t.upperArmR.quat, _eP, _kP);
    _np(t.upperArmR.quat, t.upperArmR.quat);
    _tp(_eP, _wP);
    _ep(t.forearmL.quat, _eP, _gP);
    _np(t.forearmL.quat, t.forearmL.quat);
    _qIdentity(t.handL.quat);
    _tp(_eP, _kP);
    _ep(t.forearmR.quat, _eP, _qP);
    _np(t.forearmR.quat, t.forearmR.quat);
    _qIdentity(t.handR.quat);
    return t;
  }

  static void _copyQ(List<double> e, List<double> t) {
    e[0] = t[0];
    e[1] = t[1];
    e[2] = t[2];
    e[3] = t[3];
  }
}

/// Runs a handful of poses through the solver and asserts every node
/// quaternion is finite and unit length. Returns true on success.
bool debugSanityCheck() {
  final solver = PegmanPoseSolver();
  final p = PoseParams();
  for (final move in PoseMove.values) {
    for (final t in [0.0, 0.37, 1.9]) {
      p
        ..move = move
        ..time = t
        ..gaitPhase = t * 7
        ..speedMps = 12 + t * 15
        ..dropInProgress = (t / 2).clamp(0.0, 1.0)
        ..slideProgress = 0.4
        ..stumbleProgress = 0.3
        ..railSlope = 0.1
        ..flipPhase = move == PoseMove.vault ? 0.4 : 0
        ..flipStyle = move == PoseMove.vault ? 'front' : 'none';
      final r = solver.solve(p);
      for (final e in r.v2Nodes.entries) {
        final q = e.value.quat;
        final len = _hypot4(q[0], q[1], q[2], q[3]);
        assert(q.every((c) => c.isFinite), '${e.key} quat not finite ($move)');
        assert((len - 1).abs() < 1e-6, '${e.key} quat not unit ($move): $len');
        if (!q.every((c) => c.isFinite) || (len - 1).abs() > 1e-6) return false;
        if (!e.value.pos.every((c) => c.isFinite)) return false;
      }
      if (!r.rootFlipQuat.every((c) => c.isFinite)) return false;
    }
  }
  return true;
}
