import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;

import 'osm_city.dart' show mulberry32;

/// Port of the demo's dynamic FX group (`_buildDynamicFX` /
/// `_syncDynamicFX` / `_updateRain` / `_syncDriftSmokeRibbons`):
///
/// * PegmanPlasmaSlipstream — 30-point camera-facing ribbon behind Pegman
/// * BallisticAnisotropicFootSparks — 220 velocity-stretched additive sparks
/// * PegmanGroundContactShadow — radial blob under the hero
/// * NeonElectricArcBolts — 4 jittered 12-segment bolts
/// * ShibuyaShockwaveRing — maps-extrude / finale / roof-vault ring
/// * ShibuyaRainStreaks — 340 streaks wrapped around the camera
/// * ScrambleDriftTireSmoke — 8 ribbons (two tyres x 4 drift cars)
///
/// three.js draws the ribbons and lines with custom shaders; here they are
/// built from billboard quads (velocity-stretched along each segment, which
/// is exactly the ribbon's camera-facing cross product) so they can use the
/// sprite material's additive blending. Everything lives in the reference
/// (three.js) frame under `ShibuyaWorld.refRoot`.
class NeonFx {
  NeonFx(this.root, {int seed = 14598366}) : _rng = mulberry32(seed + 509) {
    _build();
  }

  final fs.Node root;
  final double Function() _rng;
  final math.Random _fxRng = math.Random(99);

  static const int kTrail = 30; // Jh
  static const int kSparks = 220; // eg
  static const int kArcs = 4; // Yh
  static const int kArcSegs = 12;
  static const int kSmokeTrails = 8; // tg
  static const int kSmokePts = 18; // ng
  static const int kRain = 340;

  // ---- trail
  late final fs.BillboardGeometry _trailGeo;
  late final fs.Node _trailNode;
  final List<vm.Vector3> _trail =
      List.generate(kTrail, (_) => vm.Vector3(-48, 0.6, -5.2));
  bool _trailInit = false;

  // ---- sparks
  late final fs.BillboardGeometry _sparkGeo;
  late final fs.Node _sparkNode;
  final List<_Spark> _sparks = List.generate(kSparks, (_) => _Spark());
  int _sparkCursor = 0;
  double _sparkAccum = 0;

  // ---- contact shadow
  late final fs.Node _shadowNode;
  late final fs.UnlitMaterial _shadowMat;

  // ---- arcs
  late final fs.BillboardGeometry _arcGeo;
  late final fs.Node _arcNode;
  final List<_Arc> _arcBolts = List.generate(kArcs, (_) => _Arc());
  int _arcCursor = 0;

  // ---- shockwave
  late final fs.Node _ringNode;
  late final fs.UnlitMaterial _ringMat;
  double _mapsWaveTime = -1, _finaleShockTime = -1;

  // ---- rain
  late final fs.BillboardGeometry _rainGeo;
  late final fs.Node _rainNode;
  final Float32List _rainSeeds = Float32List(kRain * 4);

  // ---- drift smoke
  late final fs.BillboardGeometry _smokeGeo;
  late final fs.Node _smokeNode;
  final List<_SmokeTrail> _smoke = List.generate(kSmokeTrails, (_) => _SmokeTrail());

  final vm.Vector3 _a = vm.Vector3.zero(), _b = vm.Vector3.zero(), _c = vm.Vector3.zero();

  void _build() {
    // Plasma slipstream: soft core across the ribbon (pow(across, 1.65)).
    _trailGeo = fs.BillboardGeometry(capacity: kTrail)
      ..facing = fs.BillboardFacing.velocityStretched;
    final trailMat = fs.SpriteMaterial(colorTexture: _profileTexture((u) {
      final across = 1 - (u * 2 - 1).abs();
      return math.pow(math.max(across, 1e-4), 1.65).toDouble();
    }))
      ..blendMode = fs.SpriteBlendMode.additive;
    _trailNode = fs.Node(name: 'PegmanPlasmaSlipstream', mesh: fs.Mesh(_trailGeo, trailMat));
    root.add(_trailNode);

    // Sparks: tipFade = sin(along * pi); the texture carries the white-hot
    // tip -> gold gradient (vAlong = 1 at the leading end, v = 0 here), the
    // per-instance colour the heat fade toward the #FF4F00 plasma tail.
    _sparkGeo = fs.BillboardGeometry(capacity: kSparks)
      ..facing = fs.BillboardFacing.velocityStretched;
    final sparkMat = fs.SpriteMaterial(colorTexture: _sparkTexture())
      ..blendMode = fs.SpriteBlendMode.additive;
    _sparkNode = fs.Node(name: 'BallisticAnisotropicFootSparks', mesh: fs.Mesh(_sparkGeo, sparkMat));
    root.add(_sparkNode);

    // Contact shadow (Fg): radial gradient rgba(2,5,12,.85 -> .52 -> 0).
    _shadowMat = fs.UnlitMaterial(colorTexture: contactShadowTexture())
      ..alphaMode = fs.AlphaMode.blend
      ..baseColorFactor = vm.Vector4(1, 1, 1, 0.58);
    _shadowNode = fs.Node(name: 'PegmanGroundContactShadow', mesh: fs.Mesh(quadXZ(1.55), _shadowMat));
    root.add(_shadowNode);

    // Arc bolts (LineBasicMaterial 0xFFE6B5, opacity .95, additive).
    _arcGeo = fs.BillboardGeometry(capacity: kArcs * kArcSegs)
      ..facing = fs.BillboardFacing.velocityStretched;
    final arcMat = fs.SpriteMaterial(colorTexture: _profileTexture((u) {
      final across = 1 - (u * 2 - 1).abs();
      return math.pow(across, 0.6).toDouble();
    }))
      ..blendMode = fs.SpriteBlendMode.additive;
    _arcNode = fs.Node(name: 'NeonElectricArcBolts', mesh: fs.Mesh(_arcGeo, arcMat));
    root.add(_arcNode);

    // Shockwave ring (RingGeometry(.82, 1, 48), additive).
    _ringMat = fs.UnlitMaterial()
      ..alphaMode = fs.AlphaMode.blend
      ..doubleSided = true
      ..baseColorFactor = vm.Vector4(0.26, 0.52, 0.96, 0);
    _ringNode = fs.Node(name: 'ShibuyaShockwaveRing', mesh: fs.Mesh(_ringGeometry(0.82, 1, 48), _ringMat))
      ..visible = false;
    root.add(_ringNode);

    // Rain streaks (Jm(seed + 509) seeds).
    for (int e = 0; e < kRain; e++) {
      _rainSeeds[e * 4] = (_rng() - 0.5) * 62;
      _rainSeeds[e * 4 + 1] = _rng() * 28;
      _rainSeeds[e * 4 + 2] = (_rng() - 0.5) * 62;
      _rainSeeds[e * 4 + 3] = 22 + _rng() * 14;
    }
    _rainGeo = fs.BillboardGeometry(capacity: kRain)
      ..facing = fs.BillboardFacing.velocityStretched;
    final rainMat = fs.SpriteMaterial(colorTexture: _profileTexture((u) {
      final across = 1 - (u * 2 - 1).abs();
      return math.min(1.0, across * 1.6);
    }))
      ..blendMode = fs.SpriteBlendMode.alpha;
    _rainNode = fs.Node(name: 'ShibuyaRainStreaks', mesh: fs.Mesh(_rainGeo, rainMat));
    root.add(_rainNode);

    // Drift tyre smoke.
    _smokeGeo = fs.BillboardGeometry(capacity: kSmokeTrails * (kSmokePts - 1))
      ..facing = fs.BillboardFacing.velocityStretched;
    final smokeMat = fs.SpriteMaterial(colorTexture: _smokeTexture())
      ..blendMode = fs.SpriteBlendMode.alpha;
    _smokeNode = fs.Node(name: 'ScrambleDriftTireSmoke', mesh: fs.Mesh(_smokeGeo, smokeMat));
    root.add(_smokeNode);
  }

  // ------------------------------------------------------------ triggers
  void reset() {
    for (final a in _arcBolts) {
      a.active = false;
      a.timer = 0;
    }
    _ringNode.visible = false;
    _mapsWaveTime = -1;
    _finaleShockTime = -1;
    for (final s in _sparks) {
      s.active = false;
    }
    for (final t in _smoke) {
      t.initialized = false;
    }
    _trailInit = false;
  }

  void resetTrail(double x, double y, double z) {
    for (final p in _trail) {
      p.setValues(x, y, z);
    }
    _trailInit = true;
  }

  /// `_spawnElectricArc(from, to, color, duration)`.
  void spawnArc(vm.Vector3 from, vm.Vector3 to, [double duration = 0.24]) {
    if (from.distanceToSquared(to) > 1296) return;
    final a = _arcBolts[_arcCursor % kArcs];
    _arcCursor++;
    a
      ..active = true
      ..timer = 0
      ..duration = duration;
    a.from.setFrom(from);
    a.to.setFrom(to);
  }

  /// `_emitSparkBurst(pos, count, speedScale, upVel, floorY)`.
  void sparkBurst(vm.Vector3 e, int count, [double n = 1, double r = 2.8, double floor = 0]) {
    for (int k = 0; k < count; k++) {
      final t = _rnd() * math.pi * 2;
      final a = (2.8 + _rnd() * 6.8) * n;
      _spawnSpark(e.x + (_rnd() - 0.5) * 0.35, e.y + 0.15 + _rnd() * 0.4, e.z + (_rnd() - 0.5) * 0.35,
          math.cos(t) * a, r + _rnd() * 4.5, math.sin(t) * a, 0.26 + _rnd() * 0.32, floor);
    }
  }

  /// `triggerMapsExtrudeWave(pos)`.
  void mapsExtrudeWave(double x, double z) {
    _mapsWaveTime = 0;
    _ringNode.position = vm.Vector3(x, 0.25, z);
    _setRingColor(0x4285F4);
    _ringNode.visible = true;
  }

  /// `triggerSkylineFinale()` shock ring at the rooftop.
  void finaleShock(double x, double z) {
    _finaleShockTime = 0;
    _ringNode.position = vm.Vector3(x, 22.18, z);
    _setRingColor(0xFF4F00);
    _ringNode.visible = true;
  }

  /// `triggerRoofVaultFX(pos)`.
  void roofVault(vm.Vector3 t) {
    sparkBurst(t, 26, 1.55, 4.4, math.max(0, t.y - 1.65));
    if (_mapsWaveTime < 0 && _finaleShockTime < 0) {
      _ringNode.position = vm.Vector3(t.x, math.max(0.08, t.y - 1.55), t.z);
      _setRingColor(0x38BDF8);
      _ringNode.scale = vm.Vector3.all(2.2);
      _ringMat.baseColorFactor.w = 0.48;
      _ringNode.visible = true;
      _mapsWaveTime = 0.85;
    }
    spawnArc(t, vm.Vector3(t.x, t.y + 1.1, t.z), 0.2);
  }

  void _setRingColor(int hex) {
    final c = srgbToLinear(hex);
    _ringMat.baseColorFactor
      ..x = c.x
      ..y = c.y
      ..z = c.z;
  }

  double _rnd() => _fxRng.nextDouble();

  void _spawnSpark(double x, double y, double z, double vx, double vy, double vz,
      [double life = 0.32, double floorY = 0]) {
    final u = _sparks[_sparkCursor];
    _sparkCursor = (_sparkCursor + 1) % kSparks;
    u
      ..active = true
      ..x = x
      ..y = y
      ..z = z
      ..vx = vx
      ..vy = vy
      ..vz = vz
      ..floorY = floorY
      ..age = 0
      ..life = math.max(0.08, life);
  }

  // ---------------------------------------------------------------- sync
  /// One frame of `_syncDynamicFX` + `_updateRain` + contact shadow +
  /// `_syncDriftSmokeRibbons`.
  void update(double dt, FxFrame f) {
    final camX = f.camX, camY = f.camY, camZ = f.camZ;
    final visible = f.mapsMorph > 0.03;
    // --- plasma slipstream history
    final sx = f.heroX, sy = f.heroY + 0.92, sz = f.heroZ;
    final u = _trail[0].distanceToSquared(_a..setValues(sx, sy, sz));
    if (!_trailInit || u > 16) {
      resetTrail(sx, sy, sz);
    } else if (dt > 0 && u >= 0.0064) {
      for (int e = kTrail - 1; e > 0; e--) {
        _trail[e].setFrom(_trail[e - 1]);
      }
      _trail[0].setValues(sx, sy, sz);
    }
    final drop = f.skyDrop;
    final intensity = f.mapsMorph <= 0.03 || f.finale || (!drop && f.speed < 3)
        ? 0.0
        : drop
            ? 0.55
            : (0.24 + f.speed / 42).clamp(0.16, 0.92);
    _trailNode.visible = intensity > 0.02;
    if (_trailNode.visible) {
      final oc = f.overcharge;
      final width = drop ? 0.28 : 0.21 + oc * 0.14;
      final ca = srgbToLinear(0xFF6B1A), cb = srgbToLinear(0x38BDF8);
      final d = _trailGeo.instanceData;
      int n = 0;
      for (int r = 0; r < kTrail - 1; r++) {
        final p0 = _trail[r], p1 = _trail[r + 1];
        _b
          ..setFrom(p0)
          ..sub(p1);
        final len = _b.length;
        if (len < 1e-4) continue;
        final l0 = r / 29, l1 = (r + 1) / 29;
        final lm = (l0 + l1) * 0.5;
        final hw = math.pow(math.max(0.0, 1 - lm), 1.35) * width;
        final along = _smoothstep(0, 0.14, lm) * (1 - _smoothstep(0.55, 1.0, lm));
        final alpha = along * intensity.clamp(0.0, 1.0) * 0.44;
        final mixT = (lm * 0.6 + oc * 0.55).clamp(0.0, 1.0);
        final gain = 1.30 + 0.65 * oc;
        final o = n * fs.BillboardGeometry.floatsPerInstance;
        d[o] = (p0.x + p1.x) * 0.5;
        d[o + 1] = (p0.y + p1.y) * 0.5;
        d[o + 2] = (p0.z + p1.z) * 0.5;
        d[o + 3] = hw * 2;
        d[o + 4] = len * 1.04;
        d[o + 5] = 0;
        d[o + 6] = _lerp(ca.x, cb.x, mixT) * gain;
        d[o + 7] = _lerp(ca.y, cb.y, mixT) * gain;
        d[o + 8] = _lerp(ca.z, cb.z, mixT) * gain;
        d[o + 9] = alpha;
        d[o + 10] = 0;
        d[o + 11] = _b.x / len;
        d[o + 12] = _b.y / len;
        d[o + 13] = _b.z / len;
        n++;
      }
      _trailGeo.commit(n);
      _trailNode.visible = n > 0;
    }

    // --- sparks spawn
    final rate = (f.sparksActive || f.railGrind || f.wallRun
            ? 92.0
            : f.overcharge > 0.45
                ? 34.0
                : 0.0);
    if (rate > 0 && dt > 0 && f.mapsMorph > 0.3) {
      _sparkAccum += rate * dt;
      final t = math.min(8, _sparkAccum.floor());
      _sparkAccum -= t;
      final rail = f.railGrind;
      final ax = rail ? f.heroX : f.sparkX, ay = rail ? f.heroY : f.sparkY, az = rail ? f.heroZ : f.sparkZ;
      final cx = -math.sin(f.heroYaw), cz = -math.cos(f.heroYaw);
      for (int e = 0; e < t; e++) {
        _spawnSpark(
            ax + (_rnd() - 0.5) * (rail ? 0.12 : 0.24),
            ay + (rail ? 0.03 : 0.05),
            az + (_rnd() - 0.5) * (rail ? 0.12 : 0.24),
            cx * (5.5 + _rnd() * 7.5) + (_rnd() - 0.5) * 3.8,
            1.8 + _rnd() * 3.8,
            cz * (5.5 + _rnd() * 7.5) + (_rnd() - 0.5) * 3.8,
            0.26 + _rnd() * 0.34,
            f.groundY);
      }
    }
    _updateSparks(dt);

    // --- arcs
    {
      final d = _arcGeo.instanceData;
      int n = 0;
      final col = srgbToLinear(0xFFE6B5);
      for (final t in _arcBolts) {
        if (t.active) {
          t.timer += dt;
          if (t.timer >= t.duration) t.active = false;
        }
        if (!t.active) continue;
        _a.setFrom(t.from);
        for (int e = 0; e < kArcSegs; e++) {
          final k = (e + 1) / kArcSegs;
          _b
            ..setFrom(t.from)
            ..scale(1 - k)
            ..addScaled(t.to, k);
          if (e < kArcSegs - 1) {
            final j = 0.65 * math.sin(k * math.pi);
            _b.x += (_rnd() - 0.5) * j;
            _b.y += (_rnd() - 0.5) * j;
            _b.z += (_rnd() - 0.5) * j;
          }
          _c
            ..setFrom(_b)
            ..sub(_a);
          final len = _c.length;
          if (len > 1e-4) {
            final o = n * fs.BillboardGeometry.floatsPerInstance;
            final dist = math.sqrt(math.pow(_a.x - camX, 2) + math.pow(_a.y - camY, 2) + math.pow(_a.z - camZ, 2));
            d[o] = (_a.x + _b.x) * 0.5;
            d[o + 1] = (_a.y + _b.y) * 0.5;
            d[o + 2] = (_a.z + _b.z) * 0.5;
            // LineSegments: ~1.5 device pixels wide at any distance.
            d[o + 3] = math.max(0.004, dist * f.pixelSize * 1.6);
            d[o + 4] = len;
            d[o + 5] = 0;
            d[o + 6] = col.x * 1.6;
            d[o + 7] = col.y * 1.6;
            d[o + 8] = col.z * 1.6;
            d[o + 9] = 0.95;
            d[o + 10] = 0;
            d[o + 11] = _c.x / len;
            d[o + 12] = _c.y / len;
            d[o + 13] = _c.z / len;
            n++;
          }
          _a.setFrom(_b);
        }
      }
      _arcGeo.commit(n);
      _arcNode.visible = n > 0;
    }

    // --- shockwave ring
    if (_mapsWaveTime >= 0) {
      _mapsWaveTime += dt;
      final e = _mapsWaveTime / 1.15;
      if (e >= 1) {
        _mapsWaveTime = -1;
        _ringNode.visible = false;
      } else {
        _ringNode.scale = vm.Vector3.all(4 + e * 165);
        _ringMat.baseColorFactor.w = (1 - e) * 0.72;
      }
    } else if (_finaleShockTime >= 0) {
      _finaleShockTime += dt;
      final e = _finaleShockTime / 1.8;
      if (e >= 1) {
        _finaleShockTime = -1;
        _ringNode.visible = false;
      } else {
        _ringNode.scale = vm.Vector3.all(3 + e * 220);
        _ringMat.baseColorFactor.w = (1 - e) * 0.85;
      }
    }

    // --- contact shadow
    _shadowNode.visible = visible && f.heroVisible;
    if (_shadowNode.visible) {
      final h = math.max(0.0, f.heroY - f.groundY);
      _shadowNode.position = vm.Vector3(f.heroX, f.groundY + 0.028, f.heroZ);
      final r = 1 + math.min(0.65, h * 0.14).toDouble();
      _shadowNode.scale = vm.Vector3(r, 1, r);
      _shadowMat.baseColorFactor.w = (0.64 * math.exp(-0.95 * h)).clamp(0.0, 0.64);
    }

    // --- rain (_updateRain): wraps over 28 m around the camera
    {
      final alpha = 0.04 + 0.19 * f.mapsMorph.clamp(0.0, 1.0);
      final col = srgbToLinear(0x9EC5FE);
      final d = _rainGeo.instanceData;
      const lx = -0.12, ly = -1.15, lz = -0.08;
      final len = math.sqrt(lx * lx + ly * ly + lz * lz);
      for (int e = 0; e < kRain; e++) {
        final a = _rainSeeds[e * 4], o0 = _rainSeeds[e * 4 + 1], s0 = _rainSeeds[e * 4 + 2], c0 = _rainSeeds[e * 4 + 3];
        final l = ((o0 - f.time * c0) % 28 + 28) % 28;
        final px = camX + a, py = math.max(0.2, camY - 10 + l), pz = camZ + s0;
        final dist = math.sqrt(a * a + (py - camY) * (py - camY) + s0 * s0);
        final o = e * fs.BillboardGeometry.floatsPerInstance;
        d[o] = px + lx * 0.5;
        d[o + 1] = py + ly * 0.5;
        d[o + 2] = pz + lz * 0.5;
        // three.js lines are always one device pixel wide.
        d[o + 3] = math.max(0.012, dist * f.pixelSize * 1.4);
        d[o + 4] = len;
        d[o + 5] = 0;
        d[o + 6] = col.x;
        d[o + 7] = col.y;
        d[o + 8] = col.z;
        d[o + 9] = alpha;
        d[o + 10] = 0;
        d[o + 11] = lx / len;
        d[o + 12] = ly / len;
        d[o + 13] = lz / len;
      }
      _rainGeo.commit(kRain);
      _rainNode.visible = f.rainVisible;
    }

    // --- drift smoke
    _smokeNode.visible = visible;
    if (visible) _syncSmoke(dt, f);
  }

  void _updateSparks(double dt) {
    final d = _sparkGeo.instanceData;
    int a = 0;
    final drag = math.exp(-1.8 * dt);
    for (final l in _sparks) {
      if (!l.active) continue;
      l.age += dt;
      if (l.age >= l.life) {
        l.active = false;
        continue;
      }
      l.vy -= 9.81 * dt;
      l.vx *= drag;
      l.vz *= drag;
      l.x += l.vx * dt;
      l.y += l.vy * dt;
      l.z += l.vz * dt;
      if (l.y < l.floorY + 0.02) {
        l.y = l.floorY + 0.02;
        if (l.vy < -0.6) {
          l.vy = -l.vy * 0.42;
          l.vx *= 0.82;
          l.vz *= 0.82;
        } else {
          l.vy = 0;
        }
      }
      final sp = math.sqrt(l.vx * l.vx + l.vy * l.vy + l.vz * l.vz);
      final heat = (1 - l.age / l.life).clamp(0.0, 1.0);
      final len = (0.18 + sp * 0.072).clamp(0.16, 1.35);
      final w = 0.036 * (0.75 + heat * 0.55);
      final r = 1.0, g = _lerp(0.40, 1.0, heat), b = _lerp(0.22, 1.0, heat);
      final gain = 1.8 + 1.4 * heat;
      final o = a * fs.BillboardGeometry.floatsPerInstance;
      d[o] = l.x;
      d[o + 1] = l.y;
      d[o + 2] = l.z;
      d[o + 3] = w;
      d[o + 4] = len;
      d[o + 5] = 0;
      d[o + 6] = r * gain;
      d[o + 7] = g * gain;
      d[o + 8] = b * gain;
      d[o + 9] = (heat * 1.15).clamp(0.0, 1.0);
      d[o + 10] = 0;
      if (sp > 1e-4) {
        d[o + 11] = l.vx / sp;
        d[o + 12] = l.vy / sp;
        d[o + 13] = l.vz / sp;
      } else {
        d[o + 11] = 0;
        d[o + 12] = 1;
        d[o + 13] = 0;
      }
      a++;
    }
    _sparkGeo.commit(a);
    _sparkNode.visible = a > 0;
  }

  void _syncSmoke(double dt, FxFrame f) {
    final d = _smokeGeo.instanceData;
    int n = 0;
    final cars = f.driftCars;
    final s = math.min(4, cars.length);
    for (int ci = 0; ci < s; ci++) {
      final c = cars[ci];
      final yaw = c.yaw;
      final u = math.sin(yaw), dd = math.cos(yaw), fx = dd, pz = -u;
      for (int e = 0; e < 2; e++) {
        final l = _smoke[ci * 2 + e];
        final h = e == 0 ? -0.78 : 0.78;
        final g = c.x - u * 1.38 + fx * h, y0 = c.y + 0.16, v = c.z - dd * 1.38 + pz * h;
        final p0 = l.points[0];
        final b = (g - p0.x) * (g - p0.x) + (v - p0.z) * (v - p0.z);
        if (!l.initialized || b > 25) {
          for (int k = 0; k < kSmokePts; k++) {
            l.points[k].setValues(g, y0 + k * 0.04, v);
          }
          l.initialized = true;
        } else if (dt > 0 && b > 0.12) {
          for (int k = kSmokePts - 1; k > 0; k--) {
            l.points[k].setFrom(l.points[k - 1]);
            l.points[k].y += 0.045;
          }
          l.points[0].setValues(g, y0, v);
        }
        for (int k = 0; k < kSmokePts - 1; k++) {
          final a0 = l.points[k], a1 = l.points[k + 1];
          _b
            ..setFrom(a0)
            ..sub(a1);
          final len = _b.length;
          if (len < 1e-4) continue;
          final um = (k + 0.5) / 17;
          final hw = 0.22 + um * 0.68;
          final along = _smoothstep(0, 0.16, um) * (1 - _smoothstep(0.32, 1.0, um));
          // billow ~ FBM noise; animate it from time + position
          final billow = 0.5 + 0.35 * math.sin(f.time * 2.2 + k * 0.9 + ci * 1.7 + e);
          final alpha = along * (0.38 + 0.62 * billow) * 0.32 * 0.6;
          final o = n * fs.BillboardGeometry.floatsPerInstance;
          d[o] = (a0.x + a1.x) * 0.5;
          d[o + 1] = (a0.y + a1.y) * 0.5;
          d[o + 2] = (a0.z + a1.z) * 0.5;
          d[o + 3] = hw * 2;
          d[o + 4] = len * 1.05;
          d[o + 5] = 0;
          final tint = billow;
          d[o + 6] = _lerp(0.58, 0.84, tint);
          d[o + 7] = _lerp(0.68, 0.89, tint);
          d[o + 8] = _lerp(0.82, 0.96, tint);
          d[o + 9] = alpha;
          d[o + 10] = 0;
          d[o + 11] = _b.x / len;
          d[o + 12] = _b.y / len;
          d[o + 13] = _b.z / len;
          n++;
        }
      }
    }
    _smokeGeo.commit(n);
    _smokeNode.visible = n > 0;
  }

  // ------------------------------------------------------------ helpers
  static double _lerp(double a, double b, double t) => a + (b - a) * t;
  static double _smoothstep(double e0, double e1, double x) {
    final t = ((x - e0) / (e1 - e0)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  static vm.Vector3 srgbToLinear(int hex) {
    double c(int v) {
      final s = v / 255.0;
      return s <= 0.04045 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
    }

    return vm.Vector3(c((hex >> 16) & 255), c((hex >> 8) & 255), c(hex & 255));
  }

  /// A white texture whose alpha follows [across] (u) and [along] (v).
  static fs.Texture2D _profileTexture(double Function(double u) across,
      {double Function(double v)? along}) {
    const w = 32, h = 32;
    final px = Uint8List(w * h * 4);
    for (int y = 0; y < h; y++) {
      final v = (y + 0.5) / h;
      final av = along == null ? 1.0 : along(v);
      for (int x = 0; x < w; x++) {
        final u = (x + 0.5) / w;
        final i = (y * w + x) * 4;
        px[i] = 255;
        px[i + 1] = 255;
        px[i + 2] = 255;
        px[i + 3] = (across(u) * av * 255).round().clamp(0, 255);
      }
    }
    return fs.Texture2D.fromPixels(px, w, h);
  }

  static fs.Texture2D _sparkTexture() {
    const w = 8, h = 64;
    final px = Uint8List(w * h * 4);
    int enc(double v) {
      final c = v <= 0.0031308 ? v * 12.92 : 1.055 * math.pow(v, 1 / 2.4) - 0.055;
      return (c * 255).round().clamp(0, 255);
    }

    for (int y = 0; y < h; y++) {
      final along = 1 - (y + 0.5) / h;
      final t = _smoothstep(0.45, 0.95, along);
      final r = 1.0, g = _lerp(0.76, 0.96, t), b = _lerp(0.18, 0.86, t);
      final a = math.sin(along * math.pi);
      for (int x = 0; x < w; x++) {
        final i = (y * w + x) * 4;
        px[i] = enc(r);
        px[i + 1] = enc(g);
        px[i + 2] = enc(b);
        px[i + 3] = (a * 255).round();
      }
    }
    return fs.Texture2D.fromPixels(px, w, h);
  }

  /// `Ig()`: elliptical radial glow (white .92 -> .48 -> 0), 128 x 256.
  static fs.Texture2D underglowTexture() {
    const w = 128, h = 256;
    final px = Uint8List(w * h * 4);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        // canvas scaled (.5, 1) around the centre: ellipse radius 59 x 118
        final dx = (x + 0.5 - 64) / 0.5, dy = y + 0.5 - 128;
        final r = math.sqrt(dx * dx + dy * dy);
        final t = ((r - 10) / (118 - 10)).clamp(0.0, 1.0);
        final a = r > 118
            ? 0.0
            : (t < 0.45 ? _lerp(0.92, 0.48, t / 0.45) : _lerp(0.48, 0.0, (t - 0.45) / 0.55));
        final i = (y * w + x) * 4;
        px[i] = 255;
        px[i + 1] = 255;
        px[i + 2] = 255;
        px[i + 3] = (a * 255).round();
      }
    }
    return fs.Texture2D.fromPixels(px, w, h);
  }

  /// Flat w x l rectangle on the XZ plane (both windings), for decals.
  static fs.MeshGeometry rectXZ(double w, double l) {
    final hw = w / 2, hl = l / 2;
    return fs.MeshGeometry.fromArrays(
      positions: Float32List.fromList([-hw, 0, -hl, hw, 0, -hl, hw, 0, hl, -hw, 0, hl]),
      normals: Float32List.fromList([0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0]),
      texCoords: Float32List.fromList([0, 0, 1, 0, 1, 1, 0, 1]),
      indices: [0, 2, 1, 0, 3, 2, 0, 1, 2, 0, 2, 3],
    );
  }

  static fs.Texture2D contactShadowTexture() {
    const n = 128;
    final px = Uint8List(n * n * 4);
    for (int y = 0; y < n; y++) {
      for (int x = 0; x < n; x++) {
        final r = math.sqrt(math.pow(x + 0.5 - 64, 2) + math.pow(y + 0.5 - 64, 2));
        final t = ((r - 4) / (61.44 - 4)).clamp(0.0, 1.0);
        final a = t < 0.55 ? _lerp(0.85, 0.52, t / 0.55) : _lerp(0.52, 0.0, (t - 0.55) / 0.45);
        final i = (y * n + x) * 4;
        px[i] = 2;
        px[i + 1] = 5;
        px[i + 2] = 12;
        px[i + 3] = (a * 255).round();
      }
    }
    return fs.Texture2D.fromPixels(px, n, n);
  }

  /// Soft value-noise plume (static stand-in for the demo's FBM smoke).
  static fs.Texture2D _smokeTexture() {
    const w = 64, h = 64;
    final px = Uint8List(w * h * 4);
    final rnd = math.Random(5);
    final grid = List.generate(9 * 9, (_) => rnd.nextDouble());
    double noise(double x, double y) {
      final ix = x.floor(), iy = y.floor();
      final fx = x - ix, fy = y - iy;
      double g(int a, int b) => grid[((b % 8) * 9) + (a % 8)];
      final sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy);
      return _lerp(_lerp(g(ix, iy), g(ix + 1, iy), sx), _lerp(g(ix, iy + 1), g(ix + 1, iy + 1), sx), sy);
    }

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final u = (x + 0.5) / w, v = (y + 0.5) / h;
        final fbm = noise(u * 4, v * 8) * 0.62 + noise(u * 8 + 3.4, v * 16) * 0.38;
        final across = math.pow(math.max(1 - (u * 2 - 1).abs(), 1e-4), 1.55);
        final billow = _smoothstep(0.24, 0.84, fbm);
        final a = across * (0.38 + 0.62 * billow);
        final i = (y * w + x) * 4;
        px[i] = 255;
        px[i + 1] = 255;
        px[i + 2] = 255;
        px[i + 3] = (a * 255).round().clamp(0, 255);
      }
    }
    return fs.Texture2D.fromPixels(px, w, h);
  }

  static fs.MeshGeometry quadXZ(double size) {
    final h = size / 2;
    return fs.MeshGeometry.fromArrays(
      positions: Float32List.fromList([-h, 0, -h, h, 0, -h, h, 0, h, -h, 0, h]),
      normals: Float32List.fromList([0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0]),
      texCoords: Float32List.fromList([0, 0, 1, 0, 1, 1, 0, 1]),
      // Both windings: flutter_scene back-face culls translucent materials.
      indices: [0, 2, 1, 0, 3, 2, 0, 1, 2, 0, 2, 3],
    );
  }

  static fs.MeshGeometry _ringGeometry(double inner, double outer, int segs) {
    final pos = <double>[], nrm = <double>[], uv = <double>[];
    final idx = <int>[];
    for (int i = 0; i <= segs; i++) {
      final a = i / segs * math.pi * 2;
      final c = math.cos(a), s = math.sin(a);
      pos.addAll([c * inner, 0, s * inner, c * outer, 0, s * outer]);
      nrm.addAll([0, 1, 0, 0, 1, 0]);
      uv.addAll([i / segs, 0, i / segs, 1]);
      if (i < segs) {
        final b = i * 2;
        idx.addAll([b, b + 1, b + 2, b + 1, b + 3, b + 2, b, b + 2, b + 1, b + 1, b + 2, b + 3]);
      }
    }
    return fs.MeshGeometry.fromArrays(
      positions: Float32List.fromList(pos),
      normals: Float32List.fromList(nrm),
      texCoords: Float32List.fromList(uv),
      indices: idx,
    );
  }
}

/// Per-frame inputs to [NeonFx.update] (reference frame).
class FxFrame {
  double time = 0, mapsMorph = 1;
  double heroX = 0, heroY = 0, heroZ = 0, heroYaw = 0, groundY = 0, speed = 0;
  double overcharge = 0;
  bool skyDrop = false, finale = false, railGrind = false, wallRun = false;
  bool sparksActive = false, heroVisible = true, rainVisible = true;
  double sparkX = 0, sparkY = 0, sparkZ = 0;
  double camX = 0, camY = 6, camZ = 0;

  /// World size of one screen pixel at 1 m distance.
  double pixelSize = 0.0016;
  List<({double x, double y, double z, double yaw})> driftCars = const [];
}

class _Spark {
  bool active = false;
  double x = 0, y = 0, z = 0, vx = 0, vy = 0, vz = 0, floorY = 0, age = 0, life = 0.35;
}

class _Arc {
  bool active = false;
  double timer = 0, duration = 0.24;
  final vm.Vector3 from = vm.Vector3.zero(), to = vm.Vector3.zero();
}

class _SmokeTrail {
  bool initialized = false;
  final List<vm.Vector3> points = List.generate(NeonFx.kSmokePts, (_) => vm.Vector3(0, -99, 0));
}
