import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' as vm;

import 'game_state.dart';
import 'level_data.dart';
import 'route_spline.dart';

// Constants taken from the web demo's simulation core.
const double kGravity = 27.0; // Fm
const double kJumpV = 10.8; // Im
const double kDoubleJumpV = 9.4; // Lm
const double kRailVaultV = 18.5; // Rm
const double kSlideTime = 0.62; // zm
const double kDropTime = 3.5; // ym
const double kStumbleTime = 0.65; // Sm
const double kInvulnTime = 1.15; // wm
const double kLaneW = 3.6;
const double kNearMissMinSpeed = 22.0; // Km

double _clamp(double v, double a, double b) => v < a ? a : (v > b ? b : v);
double _lerp(double a, double b, double t) => a + (b - a) * t;
double smoothstep(double e0, double e1, double x) {
  final t = _clamp((x - e0) / (e1 - e0), 0, 1);
  return t * t * (3 - 2 * t);
}

double smootherstep(double x) {
  final t = _clamp(x, 0, 1);
  return t * t * t * (t * (6 * t - 15) + 10);
}

enum SimMove { skyDrop, sprint, vault, slide, railGrind, wallRun, stumble, pinBeacon, finaleOrbit }

class RailRt {
  RailRt(this.data)
      : id = data['id'] as String,
        startS = (data['startS'] as num).toDouble(),
        endS = (data['endS'] as num).toDouble(),
        lateral = (data['lateral'] as num).toDouble(),
        isHero = data['heroRailLaunch'] == true,
        isSky = data['kind'] == 'yamanote_sky_rail',
        line = Polyline3([
          for (final p in data['points'] as List<dynamic>)
            vm.Vector3((p[0] as num).toDouble(), (p[1] as num).toDouble(),
                (p[2] as num).toDouble()),
        ]);
  final Map<String, dynamic> data;
  final String id;
  final double startS, endS, lateral;
  final bool isHero, isSky;
  final Polyline3 line;
  double get tube => isHero ? 0.14 : 0.105;
  double u(double s) => _clamp((s - startS) / math.max(1, endS - startS), 0, 1);
}

class WallRt {
  WallRt(this.data)
      : id = data['id'] as String,
        startS = (data['startS'] as num).toDouble(),
        endS = (data['endS'] as num).toDouble(),
        side = (data['side'] as num).toDouble(),
        lateralOffset = (data['lateralOffset'] as num).toDouble(),
        y = ((data['points'] as List<dynamic>).first[1] as num).toDouble(),
        line = Polyline3([
          for (final p in data['points'] as List<dynamic>)
            vm.Vector3((p[0] as num).toDouble(), (p[1] as num).toDouble(), (p[2] as num).toDouble()),
        ]),
        transfersTo = data['transfersToRailId'] as String?;
  /// The wall's own spline (`wallSplines[i]`), sampled by run fraction.
  final Polyline3 line;
  final Map<String, dynamic> data;
  final String id;
  final double startS, endS, side, lateralOffset, y;
  final String? transfersTo;
}

class TransferRt {
  TransferRt(this.data, this.railIdx, this.wallIdx);
  final Map<String, dynamic> data;
  final int railIdx, wallIdx;
  vm.Vector3 v(String k) {
    final p = data[k] as List<dynamic>;
    return vm.Vector3((p[0] as num).toDouble(), (p[1] as num).toDouble(),
        (p[2] as num).toDouble());
  }
}

/// Per-type vehicle dimensions from the demo's `jm` table.
const Map<String, List<double>> kVehicleDims = {
  // width, height, length
  'CrownComfortTaxi': [1.879, 1.689, 4.7],
  'DriftWidebodyOrange': [2.075, 1.315, 4.708],
  'GtrMidnightBlue': [2.075, 1.358, 4.739],
  'PandaHatch86': [1.96, 1.314, 4.471],
  'TunerPearlSilver': [2.055, 1.27, 4.676],
};
const List<String> kFleetTypes = [
  'CrownComfortTaxi', 'DriftWidebodyOrange', 'GtrMidnightBlue', 'PandaHatch86', 'TunerPearlSilver',
];

/// Lane traffic vehicle (the demo's `taxis` pool entry).
class Vehicle {
  Vehicle(this.type, this.laneIndex) {
    final d = kVehicleDims[type] ?? kVehicleDims['CrownComfortTaxi']!;
    width = d[0];
    height = d[1];
    length = d[2];
  }
  final String type;
  final int laneIndex;
  late final double width, height, length;
  double startS = 0, endS = 100, laneLateral = 0, speed = 13.4, dir = 1;
  /// Current (barrier-weaving) lateral offset.
  double lateral = 0;
  double s = 0, x = 0, y = 0, z = 0, yaw = 0;
  bool active = true;
  double nearMissCd = 0, roofVaultCd = 0, hoodCd = 0;
}

class DriftCar {
  DriftCar(this.id, this.type, this.phase, this.underglow);
  final String id, type, underglow;
  double phase;
  double speed = 13.5, x = 0, z = 0, yaw = 0, nearMissCd = 0;
}

/// Gameplay simulation in the reference (three.js) frame. Mirrors the web
/// demo's `_stepSkyDrop`, `_stepActiveParkour`, traffic, scoring and
/// autopilot behaviour with the same constants (simplified collision).
class HeroSim {
  HeroSim(this.level, this.state) : spline = RouteSpline(level.waypoints) {
    final r = level.route;
    rails = [for (final d in r['grindRails'] as List<dynamic>) RailRt(d as Map<String, dynamic>)];
    walls = [for (final d in r['wallRuns'] as List<dynamic>) WallRt(d as Map<String, dynamic>)];
    transfers = [
      for (final d in r['wallToRailTransfers'] as List<dynamic>)
        TransferRt(
          d as Map<String, dynamic>,
          rails.indexWhere((x) => x.id == d['railId']),
          walls.indexWhere((x) => x.id == d['wallRunId']),
        ),
    ];
    rings = List<Map<String, dynamic>>.from(r['boostRings'] as List<dynamic>);
    barriers = List<Map<String, dynamic>>.from(r['streetBarriers'] as List<dynamic>);
    portals = List<Map<String, dynamic>>.from(r['slidePortals'] as List<dynamic>);
    gates = List<Map<String, dynamic>>.from(r['pinGates'] as List<dynamic>);
    segments = [
      for (final seg in r['streetSegments'] as List<dynamic>)
        StreetSegment(
          sStart: (seg['sStart'] as num).toDouble(),
          sEnd: (seg['sEnd'] as num).toDouble(),
          ja: _shortJa(seg['ja'] as String),
          miniEn: _miniEn(seg['en'] as String),
          shield: seg['shield'] as String?,
          shortEn: (seg['shortEn'] as String?) ?? '',
          isRail: seg['isRail'] == true,
        ),
    ];
    final loop = r['scrambleDriftLoop'] as Map<String, dynamic>;
    driftCenter = loop['center'] as List<dynamic>;
    driftAxes = loop['semiAxes'] as List<dynamic>;
    driftAngle = (loop['angleRad'] as num).toDouble();
    for (final c in loop['cars'] as List<dynamic>) {
      drift.add(DriftCar(c['id'] as String, c['vehicleType'] as String,
          (c['phase0'] as num).toDouble(), c['underglow'] as String));
    }
    final b = (level.meta['googleTower'] as Map<String, dynamic>)['rooftopBeacon'] as List<dynamic>;
    rooftop = vm.Vector3((b[0] as num).toDouble(), 22, (b[2] as num).toDouble());
    reset();
  }

  static String _shortJa(String ja) => ja
      .replaceAll('渋谷スクランブル交差点', '渋谷スクランブル')
      .replaceAll('山手線高架', '山手線');
  static String _miniEn(String en) => en
      .replaceAll(RegExp('Shibuya Scramble Crossing', caseSensitive: false), 'Scramble')
      .replaceAll(RegExp('Yamanote Line Viaduct', caseSensitive: false), 'Yamanote Line')
      .replaceAll(RegExp('Meiji-dori · R246 Crossing', caseSensitive: false), 'R246 Crossing')
      .replaceAll(RegExp('Meiji-dori Ave', caseSensitive: false), 'Meiji-dori')
      .replaceAll(RegExp('Shibuya River Promenade', caseSensitive: false), 'Shibuya River')
      .replaceAll(RegExp('Shibuya Stream · Google Tokyo', caseSensitive: false), 'Google Tokyo');

  final ShibuyaLevel level;
  final GameState state;
  final RouteSpline spline;
  late final List<RailRt> rails;
  late final List<WallRt> walls;
  late final List<TransferRt> transfers;
  late final List<Map<String, dynamic>> rings, barriers, portals, gates;
  late final List<StreetSegment> segments;
  final List<Vehicle> taxis = [];
  final List<DriftCar> drift = [];
  late final List<dynamic> driftCenter, driftAxes;
  late final double driftAngle;
  late final vm.Vector3 rooftop;
  late final Polyline3 _driftLoop = () {
    final pts = [
      for (final p in (level.route['scrambleDriftLoop'] as Map<String, dynamic>)['points'] as List<dynamic>)
        vm.Vector3((p[0] as num).toDouble(), 0, (p[2] as num).toDouble()),
    ];
    pts.add(pts.first.clone());
    return Polyline3(pts);
  }();

  // Hero state
  double s = 0, prevS = 0, lateral = 0, lateralVel = 0, targetLateral = 0;
  int laneIndex = 0;
  double x = -48, y = 300, z = -5.2, vy = 0, groundY = 0;
  bool grounded = false;
  int jumpCount = 0;
  double slideTimer = 0, stumbleTimer = 0, invulnTimer = 0;
  bool fastFall = false;
  double speed = 0;
  SimMove move = SimMove.skyDrop;
  String flipStyle = 'none';
  double flipPhase = 0, bank = 0, yaw = 1.485;
  double gaitPhase = 0, timeSinceLand = 99, wallSide = 1, pitch = 0;
  int activeRail = -1, pendingRail = -1, activeWall = -1, activeTransfer = -1;
  double railCd = 0, wallCd = 0;
  bool canRoofVault = false;
  bool finaleFlip = false;
  double finaleStartS = 0, finaleStartY = 0;
  double transferStartS = 0, transferEndS = 0;
  vm.Vector3 tStart = vm.Vector3.zero(), tApex = vm.Vector3.zero(), tEnd = vm.Vector3.zero();

  // Game
  double voltage = 0, boostBonus = 0, trauma = 0, hitStop = 0;
  double dropClock = 0, elapsed = 0;
  bool routeComplete = false;
  bool googleStarted = false;
  double googleClock = 0;
  final Set<String> railsDone = {}, wallsDone = {};
  late List<bool> ringHit, gateLit, portalDone, barrierDone, transferDone;
  int nearMisses = 0, stumbles = 0;

  // Inputs
  bool _jump = false, _slide = false, inLeft = false, inRight = false;

  final RouteSample _now = RouteSample();
  final RouteSample _tmp = RouteSample();

  void reset() {
    _deflectUntil = -1;
    s = 0;
    prevS = 0;
    lateral = 0;
    lateralVel = 0;
    targetLateral = 0;
    laneIndex = 0;
    vy = 0;
    grounded = false;
    jumpCount = 0;
    slideTimer = 0;
    stumbleTimer = 0;
    invulnTimer = 0;
    fastFall = false;
    speed = 0;
    move = SimMove.skyDrop;
    flipStyle = 'none';
    flipPhase = 0;
    bank = 0;
    gaitPhase = 0;
    timeSinceLand = 99;
    activeRail = pendingRail = activeWall = activeTransfer = -1;
    railCd = wallCd = 0;
    finaleFlip = false;
    voltage = 1.8;
    boostBonus = 0;
    trauma = 0;
    hitStop = 0;
    dropClock = 0;
    routeComplete = false;
    googleStarted = false;
    googleClock = 0;
    railsDone.clear();
    wallsDone.clear();
    ringHit = List.filled(rings.length, false);
    gateLit = List.filled(gates.length, false);
    portalDone = List.filled(portals.length, false);
    barrierDone = List.filled(barriers.length, false);
    transferDone = List.filled(transfers.length, false);
    nearMisses = 0;
    stumbles = 0;
    ledger.clear();
    _bldgSignLit.clear();
    _corridorSigns = 0;
    _setupTraffic();
    spline.sample(0, _now);
    x = _now.x;
    z = _now.z;
    y = 312;
    yaw = _now.yaw;
  }

  // ------------------------------------------------- traffic (demo port)
  /// `_findGroundRoadSpans`: ground stretches ≥ 45 m with half-width ≥ 5.4.
  List<List<double>> _groundSpans() {
    final out = <List<double>>[];
    final t = spline.length;
    double n = -1;
    final smp = RouteSample();
    for (double r = 0; r <= t; r += 1) {
      spline.sample(r, smp);
      final ok = smp.y <= 0.35 && smp.halfWidth >= 5.4;
      if (ok && n < 0) {
        n = r;
      } else if (!ok && n >= 0) {
        final a = n < 20 ? 78.0 : n;
        final b = math.min(r - 1, n < 20 ? 278.0 : 914.0);
        if (b - a >= 45) out.add([a, b]);
        n = -1;
      }
    }
    if (n >= 0) {
      final b = math.min(t - 20, 914.0);
      if (b - n >= 45) out.add([n, b]);
    }
    return out;
  }

  late final List<Map<String, double>> _groundBarriers = [
    for (final e in barriers)
      if (((e['groundY'] as num?)?.toDouble() ?? 0) <= 0.35)
        () {
          final li = ((e['laneIndex'] as num?)?.round() ??
                  (((e['lateral'] as num?)?.toDouble() ?? 0) / kLaneW).round())
              .clamp(-1, 1);
          final bi = li == 0 ? 1 : 0;
          return {
            's': (e['s'] as num).toDouble(),
            'lane': li.toDouble(),
            'bypass': kLaneW * bi,
          };
        }(),
  ];

  /// `_computeBarrierWeave`: lane traffic swerves around street barriers.
  (double, double) _weave(int lane, double t) {
    final r = kLaneW * lane;
    for (final o in _groundBarriers) {
      if (o['lane']!.toInt() != lane) continue;
      final os = o['s']!;
      final s0 = os - 28, c = os - 6, l = os + 6, u = os + 24;
      if (t < s0 || t > u) continue;
      final d = o['bypass']! - r;
      if (t < c) {
        final e = _clamp((t - s0) / 22, 0, 1);
        return (r + d * smootherstep(e), d * 30 * e * e * (1 - e) * (1 - e) / 22);
      }
      if (t <= l) return (o['bypass']!, 0);
      final f = _clamp((t - l) / 18, 0, 1);
      return (r + d * (1 - smootherstep(f)), d * -30 * f * f * (1 - f) * (1 - f) / 18);
    }
    return (r, 0);
  }

  void _setupTraffic() {
    taxis.clear();
    final spans = _groundSpans();
    final buckets = <String, List<Vehicle>>{};
    List<Vehicle> bucket(int span, int lane) => buckets.putIfAbsent('$span:$lane', () => []);
    final smp = RouteSample();
    for (final o in level.route['hazards'] as List<dynamic>) {
      if (taxis.length >= 32) break;
      if (o['type'] != 'taxi_lane') continue;
      final os = (o['s'] as num).toDouble();
      final mid = _lerp(os, ((o['endS'] as num?)?.toDouble() ?? os + 60), 0.5);
      if (spline.sample(mid, smp).y > 0.35) continue;
      final lat = (o['lateral'] as num?)?.toDouble() ?? 0;
      final lane = ((o['laneIndex'] as num?)?.round() ?? (lat < -1.8 ? -1 : (lat > 1.8 ? 1 : 0))).clamp(-1, 1);
      var si = spans.indexWhere((e) => os >= e[0] - 25 && os <= e[1] + 25);
      if (si < 0) si = os < 500 ? 0 : math.max(0, spans.length - 1);
      final v = Vehicle((o['vehicleType'] as String?) ?? kFleetTypes[taxis.length % 5], lane);
      taxis.add(v);
      bucket(si, lane).add(v);
    }
    const caps = [[0, -1, 6], [0, 0, 6], [0, 1, 6], [1, -1, 5], [1, 0, 4], [1, 1, 5]];
    for (final c in caps) {
      if (spans.isEmpty) break;
      final b = bucket(math.min(c[0], spans.length - 1), c[1]);
      while (b.length < c[2] && taxis.length < 32) {
        final v = Vehicle(kFleetTypes[taxis.length % 5], c[1]);
        taxis.add(v);
        b.add(v);
      }
    }
    const slotCfg = [
      [7.0, 13.4, 0.0, {-1: [0.0, 1, 2, 3, 5, 6], 0: [0.5, 1.5, 2.5, 3.5, 5.5, 6.5], 1: [0.0, 1, 2, 4, 5, 6]}],
      [6.0, 14.4, 0.1, {-1: [0.0, 1, 2, 3, 5], 0: [0.5, 1.5, 3.5, 4.5], 1: [0.0, 1, 2, 4, 5]}],
    ];
    buckets.forEach((key, items) {
      final parts = key.split(':');
      final spanIdx = int.parse(parts[0]), lane = int.parse(parts[1]);
      final span = spans[spanIdx];
      final o = math.max(40.0, span[1] - span[0]);
      final cfg = slotCfg[spanIdx % 2];
      final l = o / (cfg[0] as double);
      final lanes = (cfg[3] as Map<int, List<num>>)[lane] ?? [0, 1, 2, 3, 4, 5];
      for (int e = 0; e < items.length; e++) {
        final v = items[e];
        v.startS = span[0];
        v.endS = span[1];
        v.laneLateral = kLaneW * lane;
        v.speed = cfg[1] as double;
        final slot = e < lanes.length ? lanes[e].toDouble() : e + (lane == 0 ? 0.5 : 0);
        v.s = span[0] + ((slot + (cfg[2] as double)) * l) % o;
        v.lateral = _weave(lane, v.s).$1;
      }
    });
  }

  // ------------------------------------------------------------- input
  /// Pending gameplay events (see [SimEvent]); the controller clears it.
  final List<SimEvent> events = [];
  void _emit(String kind, {double? px, double? py, double? pz, int index = 0, double value = 0}) {
    events.add(SimEvent(kind, px ?? x, py ?? y, pz ?? z, index: index, value: value));
  }

  /// Key release (`_onKeyUp` -> `_syncHoldKeysToEngine`): the held lane
  /// flags only stay set while A/D is down.
  void releaseLane(int dir) {
    if (dir < 0) {
      inLeft = false;
    } else {
      inRight = false;
    }
  }

  void pressJump() => _jump = true;
  void pressSlide() => _slide = true;
  void moveLane(int dir) {
    if (state.autoPilot) return;
    if (state.phase != AppPhase.playing) return;
    if (activeRail >= 0 && dir != 0) {
      // lane change off a rail dismounts
      final r = rails[activeRail];
      if (!r.isHero) {
        activeRail = -1;
        railCd = 0.35;
        grounded = false;
        jumpCount = 1;
        vy = 5.8;
        move = SimMove.vault;
      } else {
        return;
      }
    }
    if (dir < 0) {
      inLeft = true;
      inRight = false;
    } else {
      inRight = true;
      inLeft = false;
    }
    final prev = laneIndex;
    laneIndex = (laneIndex + dir).clamp(-1, 1);
    if (laneIndex != prev) {
      state.dismissOnboarding();
      _emit('laneChange', value: dir.toDouble());
    }
  }

  // -------------------------------------------------------------- step
  void step(double dtRaw) {
    final dt = _clamp(dtRaw, 0.001, 0.05);
    elapsed += dt;
    trauma = math.max(0, trauma - dt * 1.9);
    if (boostBonus > 0) {
      boostBonus = math.max(0, boostBonus * math.exp(-dt / (1.65 * 0.36)) - 0.65 * dt);
    }
    _updateTraffic(dt);
    if (state.phase == AppPhase.mapsTitle || state.phase == AppPhase.loading) {
      return;
    }
    if (hitStop > 0) {
      hitStop = math.max(0, hitStop - dt);
      return;
    }
    if (routeComplete || state.phase == AppPhase.finale) {
      move = SimMove.finaleOrbit;
      _syncState(dt);
      return;
    }
    if (state.phase == AppPhase.skyDrop) {
      _stepSkyDrop(dt);
      _syncState(dt);
      return;
    }
    final pY = y;
    final pGrounded = grounded;
    _stepParkour(dt);
    _resolveCollisions(dt, pY, pGrounded);
    _checkRings();
    _checkNearMiss();
    _checkGates();
    _checkBuildingSigns();
    _checkGoogle(dt);
    _syncState(dt);
  }

  double _dropVy = 0;
  double _deflectUntil = -1;

  void _stepSkyDrop(double dt) {
    if (dropClock <= 0) _emit('mapsExtrude');
    dropClock = math.min(kDropTime, dropClock + dt);
    final n = dropClock;
    move = SimMove.skyDrop;
    prevS = s;
    _jump = false;
    _slide = false;
    spline.sample(0, _now);
    if (n < 0.9) {
      y = _now.y + _lerp(312, 272, smootherstep(n / 0.9));
      _dropVy = -44 * (n / 0.9);
      speed = 0;
      grounded = false;
    } else if (n < 3.05) {
      final r = _clamp((n - 0.9) / 2.15, 0, 1);
      final o = y;
      y = _now.y + 272 * math.pow(1 - r, 1.75);
      _dropVy = (y - o) / math.max(1e-4, dt);
      speed = 0;
      grounded = false;
    } else if (n < 3.28) {
      if (!grounded) {
        grounded = true;
        timeSinceLand = 0;
        trauma = math.max(trauma, 0.32);
        voltage = math.max(voltage, 3.6);
        _emit('skyDropLand', value: 1);
      }
      timeSinceLand += dt;
      speed = _lerp(0, 9, smoothstep(0.2, 1, _clamp((n - 3.05) / 0.23, 0, 1)));
      s += speed * dt;
      spline.sample(s, _now);
      y = _now.y;
    } else {
      grounded = true;
      timeSinceLand += dt;
      speed = _lerp(9, 24, smoothstep(0, 1, _clamp((n - 3.28) / 0.22, 0, 1)));
      s += speed * dt;
      gaitPhase += speed / 2.2 * math.pi * 2 * dt;
      spline.sample(s, _now);
      y = _now.y;
    }
    groundY = _now.y;
    vy = grounded ? 0 : _dropVy;
    x = _now.x + _now.rx * lateral;
    z = _now.z + _now.rz * lateral;
    yaw = _now.yaw;
    if (dropClock >= kDropTime - 1e-6) {
      dropClock = kDropTime;
      move = SimMove.sprint;
      state.landFromSkyDrop();
    }
  }

  void _stepParkour(double dt) {
    prevS = s;
    timeSinceLand += dt;
    if (invulnTimer > 0) invulnTimer = math.max(0, invulnTimer - dt);
    if (stumbleTimer > 0) stumbleTimer = math.max(0, stumbleTimer - dt);
    if (railCd > 0) railCd = math.max(0, railCd - dt);
    if (wallCd > 0) wallCd = math.max(0, wallCd - dt);
    var jump = _jump, slide = _slide;
    const bool dismount = false;
    final auto = state.autoPilot;
    _BotOut? bot;
    if (auto) {
      bot = _bot();
      if (bot.jump) jump = true;
      if (bot.slide) slide = true;
    }
    _jump = false;
    _slide = false;
    if (jump) state.dismissOnboarding();

    final o = _clamp(voltage / 15, 0, 1);
    final cm = _clamp((state.combo - 1) / 11, 0, 1);
    double c = 22.6 + o * 5.6 + cm * 4.2;
    if (activeRail >= 0) {
      final r = rails[activeRail];
      final n = r.u(s);
      c = r.isHero
          ? _lerp(36, 45.2, smoothstep(0, 0.85, n))
          : _lerp(32, 42, smoothstep(0, 1, n * n));
    } else if (activeWall >= 0) {
      final w = walls[activeWall];
      c = _lerp(30, 39, smoothstep(0, 1, _clamp((s - w.startS) / math.max(1, w.endS - w.startS), 0, 1)));
    } else if (activeTransfer >= 0) {
      c = 33.5;
    } else if (finaleFlip) {
      c = 18;
    } else if (stumbleTimer > 0) {
      c = math.max(16.5, c * 0.72);
    } else if (move == SimMove.slide) {
      c = math.max(25, c + 0.8);
    }
    final l = _clamp(c + boostBonus, 15.5, 45.8);
    final k = stumbleTimer > 0 ? 2.6 : (l > speed ? 4.4 : 3.4);
    speed += (l - speed) * math.min(1, dt * k);
    s = math.min(spline.length, s + speed * dt);
    spline.sample(s, _now);
    final d = _now;
    final f = math.max(3.6, d.halfWidth - 1.05);
    groundY = d.y;

    // Wall-to-rail transfer arc
    if (activeTransfer >= 0) {
      final t = transfers[activeTransfer];
      final r = _clamp((s - transferStartS) / math.max(1, transferEndS - transferStartS), 0, 1);
      final i = tStart, a = tApex, e = tEnd;
      final q = 1 - r;
      final ctrl = a * 2 - (i + e) * 0.5;
      final p = i * (q * q) + ctrl * (2 * q * r) + e * (r * r);
      final hy = y;
      x = p.x;
      y = math.max(d.y + 0.4, p.y);
      z = p.z;
      vy = (y - hy) / math.max(1e-4, dt);
      lateral = _lerp((t.data['lateralFrom'] as num).toDouble(),
          (t.data['lateralTo'] as num).toDouble(), smoothstep(0, 1, r));
      targetLateral = lateral;
      yaw = d.yaw;
      bank = -(t.data['side'] as num).toDouble() * (1 - r) * 0.35;
      move = SimMove.vault;
      flipStyle = 'corkscrew';
      flipPhase = r;
      if (r >= 0.995) _snapRail(t.railIdx);
      _checkComplete();
      return;
    }
    // Final front flip onto the rooftop
    if (finaleFlip) {
      final r = _clamp((s - finaleStartS) / math.max(1, spline.length - finaleStartS), 0, 1);
      x = _lerp(d.x, rooftop.x, smoothstep(0, 1, r));
      z = _lerp(d.z, rooftop.z, smoothstep(0, 1, r));
      y = _lerp(finaleStartY, rooftop.y, r) + math.sin(r * math.pi) * 3.8;
      lateral = _lerp(lateral, 0, math.min(1, dt * 8));
      yaw = d.yaw;
      bank = 0;
      move = SimMove.pinBeacon;
      flipStyle = 'front';
      flipPhase = r;
      _checkComplete();
      return;
    }
    // Rail grinding
    if (activeRail >= 0) {
      final r = rails[activeRail];
      if (s >= r.endS || dismount || (jump && !r.isHero)) {
        activeRail = -1;
        railCd = 0.35;
        if (r.isHero) {
          finaleFlip = true;
          finaleStartS = s;
          finaleStartY = y;
          grounded = false;
          jumpCount = 1;
          vy = 10.5;
          move = SimMove.pinBeacon;
          flipStyle = 'front';
          flipPhase = 0;
          trauma = math.max(trauma, 0.3);
        } else {
          grounded = false;
          jumpCount = 1;
          canRoofVault = true;
          vy = jump ? 8.8 : 5.8;
          move = SimMove.vault;
          flipStyle = 'none';
          _emit('jump');
        }
      } else {
        final tan = vm.Vector3.zero();
        final p = r.line.at(r.u(s), tan);
        x = p.x;
        y = p.y + r.tube;
        z = p.z;
        vy = 0;
        lateral = r.lateral;
        targetLateral = r.lateral;
        laneIndex = (r.lateral / kLaneW).round().clamp(-1, 1);
        lateralVel = 0;
        yaw = math.atan2(tan.x, tan.z);
        bank = 0;
        grounded = true;
        jumpCount = 0;
        move = SimMove.railGrind;
        flipStyle = 'none';
        voltage = math.min(15, voltage + 2.4 * dt);
        return;
      }
    }
    // Snap onto rails we are lined up with
    if (activeRail < 0 && railCd <= 0) {
      for (int ri = 0; ri < rails.length; ri++) {
        final r = rails[ri];
        final big = r.isHero || r.isSky;
        if (!(s >= r.startS - 2.6 && s <= r.endS - 4)) continue;
        if ((lateral - r.lateral).abs() > (big ? 3.4 : 2.35)) continue;
        final ry = r.line.at(r.u(s)).y;
        final top = ry + r.tube;
        if (ry - groundY > 2.2 && !big) {
          if (!grounded && y >= top - 1.25 && y <= top + 1.65) {
            _snapRail(ri);
            return;
          }
          if (jump && grounded) {
            vy = kRailVaultV;
            grounded = false;
            jumpCount = 1;
            slideTimer = 0;
            pendingRail = ri;
            move = SimMove.vault;
            jump = false;
            _emit('jump');
            break;
          }
        } else if ((y - top).abs() <= 2.8 || big || jump) {
          _snapRail(ri);
          return;
        }
      }
    }
    if (jump && grounded && activeRail < 0 && railCd <= 0) {
      for (int ri = 0; ri < rails.length; ri++) {
        final r = rails[ri];
        final a = r.startS - s;
        if (a > 2.6 &&
            a <= 6.5 &&
            (lateral - r.lateral).abs() <= 2.35 &&
            r.line.at(0).y - groundY > 2.2) {
          vy = kRailVaultV;
          grounded = false;
          jumpCount = 1;
          slideTimer = 0;
          pendingRail = ri;
          move = SimMove.vault;
          jump = false;
          _emit('jump');
          break;
        }
      }
    }

    // Lateral target
    double p;
    if (auto && bot != null) {
      p = _clamp(bot.targetLateral, -f, f);
      final li = (p / kLaneW).round().clamp(-1, 1);
      if (li != laneIndex) _emit('laneChange', value: (li - laneIndex).sign.toDouble());
      laneIndex = li;
    } else {
      p = _clamp(kLaneW * laneIndex, -f, f);
      for (final w in walls) {
        if (((laneIndex == -1 && inLeft && w.side < 0) || (laneIndex == 1 && inRight && w.side > 0)) &&
            s >= w.startS - 6 &&
            s <= w.endS - 4) {
          p = w.side * math.min(w.lateralOffset - 0.85, f);
          break;
        }
      }
    }
    targetLateral = p;
    // critically damped spring (implicit) like the demo
    final m = 1 + 2 * dt * 0.96 * 30, h = dt * 900, g = dt * h, inv = 1 / (m + g);
    final v = (m * lateral + dt * lateralVel + g * p) * inv;
    final yv = (lateralVel + h * (p - v)) / m;
    lateral = _clamp(v, -f, f);
    lateralVel = _clamp(yv, -34, 34);

    // Wall running
    if (activeWall >= 0) {
      final w = walls[activeWall];
      final leave = (!auto && ((w.side > 0 && inLeft) || (w.side < 0 && inRight))) || dismount;
      final atEnd = s >= w.endS - 0.8;
      final ti = transfers.indexWhere((t) => t.wallIdx == activeWall);
      if (ti >= 0 && s >= w.endS - 9 && s <= w.endS + 2.5 && (jump || atEnd)) {
        if (_startTransfer(ti)) return;
      }
      if (atEnd || leave || jump) {
        activeWall = -1;
        wallCd = 0.45;
        grounded = false;
        jumpCount = 1;
        vy = jump ? 9.2 : 5.8;
        lateralVel = -w.side * 5.8;
        laneIndex = w.side > 0 ? 1 : -1;
        inLeft = inRight = false;
        move = SimMove.vault;
        _emit('wallRun', value: 0);
        _emit('jump');
      } else {
        final n = _clamp((s - w.startS) / math.max(1, w.endS - w.startS), 0, 1);
        final a = w.side * math.min(w.lateralOffset - 0.85, f);
        lateral += (a - lateral) * math.min(1, dt * 12);
        lateralVel = 0;
        // i = nh(wallSpline, n): the wall descends along Miyamasuzaka etc.
        final wy = math.max(0.0, w.line.at(n).y);
        final targetY = math.max(d.y + 1.85, wy + 1.15) + math.sin(n * math.pi) * 0.55;
        y += (targetY - y) * math.min(1, dt * 12);
        vy = 0;
        x = d.x + d.rx * lateral;
        z = d.z + d.rz * lateral;
        yaw = d.yaw;
        bank = -w.side * 42 * math.pi / 180;
        wallSide = w.side;
        gaitPhase += speed / 1.95 * math.pi * 2 * dt;
        move = SimMove.wallRun;
        voltage = math.min(15, voltage + 1.8 * dt);
        _checkComplete();
        return;
      }
    }
    if (activeWall < 0 && wallCd <= 0 && slideTimer <= 0) {
      for (int wi = 0; wi < walls.length; wi++) {
        final w = walls[wi];
        if (s < w.startS - 1.5 || s > w.endS - 6) continue;
        final o2 = math.min(w.lateralOffset - 2.35, f - 1.35);
        final engage = !auto && laneIndex == w.side && (jump || !grounded);
        if (lateral * w.side >= o2 || engage) {
          activeWall = wi;
          move = SimMove.wallRun;
          grounded = false;
          jumpCount = 0;
          fastFall = false;
          speed = math.max(speed, 30);
          voltage = math.min(15, voltage + 1.2);
          if (wallsDone.add(w.id)) {
            _popup('WALL RUN 2x');
          }
          _emit('wallRun', index: wi, value: 1);
          break;
        }
      }
    }
    // Jumps (with double-jump front flip)
    if (jump && activeWall < 0 && jumpCount < 2) {
      final dbl = jumpCount == 1;
      vy = dbl ? kDoubleJumpV : kJumpV;
      grounded = false;
      canRoofVault = true;
      jumpCount++;
      slideTimer = 0;
      fastFall = false;
      move = SimMove.vault;
      flipStyle = dbl ? 'front' : 'none';
      flipPhase = 0;
      _emit('jump', value: dbl ? 1 : 0);
    }
    if (slide && activeWall < 0) {
      stumbleTimer = 0;
      final ff = auto ? -26.0 : -38.0;
      if (grounded) {
        fastFall = false;
      } else {
        fastFall = true;
        vy = math.min(vy, ff);
        pendingRail = -1;
        canRoofVault = false;
      }
      if (slideTimer <= 0) _emit('slide', value: 1);
      slideTimer = kSlideTime;
    }
    if (!grounded && fastFall) {
      vy = math.min(vy, auto ? -26 : -38);
      slideTimer = kSlideTime;
    }
    if (grounded) {
      y = groundY;
      vy = 0;
      pendingRail = -1;
      flipPhase = 0;
      flipStyle = 'none';
      fastFall = false;
    } else {
      vy -= kGravity * dt;
      y += vy * dt;
      if (flipStyle == 'front') flipPhase = _clamp(flipPhase + dt * 1.85, 0, 1);
      if (pendingRail >= 0 && activeRail < 0) {
        final r = rails[pendingRail];
        if (s >= r.startS - 1.5 && s <= r.endS - 3) {
          final ty = r.line.at(r.u(s)).y + r.tube;
          if ((lateral - r.lateral).abs() <= 2.4 && (y >= ty - 0.55 || vy <= 1.2)) {
            _snapRail(pendingRail);
            return;
          }
        } else if (s > r.endS) {
          pendingRail = -1;
        }
      }
      if (y <= groundY) {
        final impact = _clamp(vy.abs() / 15, 0.2, 1);
        y = groundY;
        vy = 0;
        grounded = true;
        timeSinceLand = 0;
        canRoofVault = false;
        jumpCount = 0;
        pendingRail = -1;
        flipPhase = 0;
        flipStyle = 'none';
        if (fastFall) slideTimer = math.max(slideTimer, kSlideTime);
        fastFall = false;
        trauma = math.max(trauma, 0.14 * impact);
        _emit('land', value: impact);
      }
    }
    if (slideTimer > 0 && (grounded || !fastFall)) {
      slideTimer = math.max(0, slideTimer - dt);
    }
    if (activeWall < 0) {
      move = s >= spline.length - 16
          ? SimMove.pinBeacon
          : grounded
              ? (slideTimer > 0
                  ? SimMove.slide
                  : (stumbleTimer > 0 ? SimMove.stumble : SimMove.sprint))
              : SimMove.vault;
    }
    x = d.x + d.rx * lateral;
    z = d.z + d.rz * lateral;
    final lean = _clamp(math.atan2(lateralVel, math.max(8, speed)) * 0.45, -0.32, 0.32);
    yaw = d.yaw - lean;
    pitch = d.pitch;
    // Hf(): banking into the curve, atan(v^2 kappa / g) clamped to 0.44
    bank = _clamp(math.atan(math.min(200.0, speed) * math.min(200.0, speed) * d.kappa / 9.81), -0.44, 0.44);
    if ((move == SimMove.sprint || move == SimMove.stumble) && grounded) {
      final n = _clamp(2.15 + speed * 0.055, 2.2, 4.1);
      gaitPhase += speed / n * math.pi * 2 * dt;
    }
    if (voltage > 2) voltage = math.max(2, voltage - 0.07 * dt);
    _checkComplete();
  }

  bool _startTransfer(int ti) {
    final t = transfers[ti];
    if (t.railIdx < 0) return false;
    activeWall = -1;
    wallCd = 0.45;
    activeTransfer = ti;
    transferStartS = s;
    transferEndS = math.max(s + 6, (t.data['landS'] as num).toDouble());
    tStart = vm.Vector3(x, y, z);
    tApex = t.v('apexPos');
    tEnd = t.v('landPos')..y += rails[t.railIdx].tube;
    grounded = false;
    jumpCount = 1;
    move = SimMove.vault;
    flipStyle = 'corkscrew';
    flipPhase = 0;
    if (!transferDone[ti]) {
      transferDone[ti] = true;
      voltage = math.min(15, voltage + 3.5);
      state.combo = math.min(12, state.combo + 1);
      boostBonus = math.min(5.2, boostBonus + 5.5 * 0.65);
      speed = math.min(44.8, math.max(speed + 5.5 * 0.3, 32.5));
      trauma = math.max(trauma, 0.26);
      hitStop = math.max(hitStop, 0.028);
      _emit('transfer', py: y + 0.4);
      final pts = _award('transfer', t.data['label'] as String? ?? 'TRANSFER',
          ((t.data['bonusPts'] as num?) ?? 1200).toInt());
      _popup('WALL TO RAIL TRANSFER', bonus: pts);
    }
    return true;
  }

  void _snapRail(int ri) {
    final r = rails[ri];
    activeWall = -1;
    final p = r.line.at(r.u(s));
    activeRail = ri;
    pendingRail = -1;
    activeTransfer = -1;
    slideTimer = 0;
    fastFall = false;
    stumbleTimer = 0;
    flipPhase = 0;
    flipStyle = 'none';
    move = SimMove.railGrind;
    x = p.x;
    y = p.y + r.tube;
    z = p.z;
    lateral = r.lateral;
    targetLateral = r.lateral;
    laneIndex = (r.lateral / kLaneW).round().clamp(-1, 1);
    lateralVel = 0;
    vy = 0;
    grounded = true;
    jumpCount = 0;
    speed = math.max(speed, r.isHero ? 36 : 32);
    trauma = math.max(trauma, 0.18);
    voltage = math.min(15, voltage + 1.4);
    _emit('railGrind', index: ri, value: 1);
    if (railsDone.add(r.id)) {
      _popup(r.isHero ? 'GOOGLE LAUNCH RAIL 2x' : 'RAIL GRIND 2x');
    }
  }

  void _stumble({bool keepAirborne = false}) {
    stumbles++;
    _emit('stumble', py: y + 0.5);
    final a = speed;
    speed = math.max(15.5, a * 0.7);
    final loss = math.max(0, ((a - speed) * 3.6).round());
    voltage = math.max(1.2, voltage - 2.5);
    state.combo = math.max(1, (state.combo * 0.5).floor());
    boostBonus = 0;
    trauma = math.max(trauma, 0.42);
    hitStop = math.max(hitStop, 0.035);
    stumbleTimer = kStumbleTime;
    invulnTimer = kInvulnTime;
    if (!keepAirborne) {
      slideTimer = 0;
      if (grounded) move = SimMove.stumble;
    }
    state.showCallout('STUMBLE!',
        bonus: loss > 0 ? '-$loss km/h' : '', accent: CalloutAccent.danger);
  }

  // Simplified version of `_resolveSolidCollisions`.
  void _resolveCollisions(double dt, double prevY, bool prevGrounded) {
    if (activeTransfer >= 0 || finaleFlip || routeComplete) return;
    final onRailOrWall = activeRail >= 0 || activeWall >= 0;
    // Slide portals
    for (int i = 0; i < portals.length; i++) {
      final p = portals[i];
      final ps = (p['s'] as num).toDouble();
      if (!((s - ps).abs() <= 1.85 || (math.min(prevS, s) <= ps + 0.6 && math.max(prevS, s) >= ps - 0.6))) {
        continue;
      }
      if (onRailOrWall || portalDone[i]) continue;
      final gy = (p['groundY'] as num?)?.toDouble() ?? 0;
      final top = gy + ((p['solidArchTopY'] as num?)?.toDouble() ?? 6.45);
      if ((move == SimMove.slide || slideTimer > 0) && y <= gy + 0.15) {
        portalDone[i] = true;
        voltage = math.min(15, voltage + 3);
        state.combo = math.min(12, state.combo + 1);
        boostBonus = math.min(5.5, boostBonus + 2.4);
        speed = _clamp(speed + 1.8, 25, 45.8);
        trauma = math.max(trauma, 0.18);
        _award('neon_slide', 'NEON SLIDE', 1500, scaled: false);
        _emit('neonSlide', index: i);
        state.showCallout('NEON SLIDE', bonus: '+1,500', accent: CalloutAccent.neonSlide);
      } else if (y < top + 0.15) {
        portalDone[i] = true;
        y = gy;
        vy = 0;
        grounded = true;
        canRoofVault = false;
        flipStyle = 'none';
        slideTimer = math.max(slideTimer, 0.48);
        move = SimMove.slide;
        if (invulnTimer <= 0) _stumble(keepAirborne: true);
      }
    }
    if (onRailOrWall) return;
    // Street barriers
    for (int i = 0; i < barriers.length; i++) {
      final b = barriers[i];
      final bs = (b['s'] as num).toDouble();
      if ((bs - s).abs() > 1.6) continue;
      final gy = (b['groundY'] as num?)?.toDouble() ?? 0;
      if ((groundY - gy).abs() > 2.5) continue;
      final half = ((b['width'] as num?)?.toDouble() ?? 2.8) * 0.5;
      final bl = (b['lateral'] as num).toDouble();
      if ((lateral - bl).abs() > half + 0.45) continue;
      final top = gy + ((b['height'] as num?)?.toDouble() ?? 1.15);
      if (y >= top + 0.11) continue;
      if (prevY < top - 0.1) {
        // clipped the barrier: vault over it with a stumble
        y = math.max(y, top + 0.11);
        grounded = false;
        move = SimMove.vault;
        slideTimer = 0;
        vy = math.max(vy, 6.8);
        jumpCount = 1;
        canRoofVault = false;
        if (invulnTimer <= 0 && !barrierDone[i]) {
          barrierDone[i] = true;
          _stumble(keepAirborne: true);
        }
      } else {
        y = math.max(y, top + 0.11);
        if (vy < 0) vy = 1.5;
      }
    }
    // Taxis: roof vault / hood bounce
    for (final t in taxis) {
      if (!t.active || (t.s - s).abs() > t.length * 0.5 + 0.6) continue;
      if ((t.lateral - lateral).abs() > t.width * 0.5 + 0.42) continue;
      final roof = t.y + t.height;
      if (y > roof + 0.27) continue;
      if (y >= roof - 0.36 && vy <= 1.2 && canRoofVault && t.roofVaultCd <= 0) {
        // landed on the roof: ROOF VAULT
        y = roof + 0.11;
        vy = math.max(vy, 10.2);
        grounded = false;
        jumpCount = 1;
        slideTimer = 0;
        move = SimMove.vault;
        t.roofVaultCd = 1.4;
        t.nearMissCd = 3.5;
        voltage = math.min(15, voltage + 2);
        state.combo = math.min(12, state.combo + 1);
        boostBonus = math.min(5.5, boostBonus + 1.8);
        speed = _clamp(speed + 2.2, 24, 45.8);
        canRoofVault = true;
        trauma = math.max(trauma, 0.2);
        _award('roof_vault', 'ROOF VAULT', 750, scaled: false);
        _emit('roofVault', py: y + 0.15);
        state.showCallout('ROOF VAULT', bonus: '+750', accent: CalloutAccent.vault);
      } else if (t.hoodCd <= 0) {
        // ran into the car: HOOD BOUNCE
        y = math.max(y, roof + 0.11);
        vy = math.max(vy, 8.4);
        grounded = false;
        canRoofVault = false;
        jumpCount = 1;
        slideTimer = 0;
        move = SimMove.vault;
        t.hoodCd = 1.05;
        t.nearMissCd = 3.2;
        state.combo = math.max(1, state.combo - 1);
        speed = math.max(18, speed * 0.85);
        trauma = math.max(trauma, 0.3);
        state.showCallout('HOOD BOUNCE', accent: CalloutAccent.danger);
        _emit('carDeflect', py: y + 0.45, value: 1);
        _deflectUntil = elapsed + math.max(hitStop, 0.036);
      }
    }
    // Boost rings: duck under / hop over the solid ring rim
    // (simplified: rings are fly-through; see _checkRings)
  }

  void _checkRings() {
    final lo = math.min(prevS, s) - 2.4, hi = math.max(prevS, s) + 2.4;
    final hy = y + 0.92;
    for (int i = 0; i < rings.length; i++) {
      if (ringHit[i]) continue;
      final r = rings[i];
      final rs = (r['s'] as num).toDouble();
      if (rs < lo || rs > hi) continue;
      final pos = r['pos'] as List<dynamic>;
      final dyy = hy - (pos[1] as num).toDouble();
      final dl = (lateral - (r['lateral'] as num).toDouble()).abs();
      final dist = math.sqrt(math.pow(x - (pos[0] as num).toDouble(), 2) +
          dyy * dyy +
          math.pow(z - (pos[2] as num).toDouble(), 2));
      final bottom = (r['bottomY'] as num?)?.toDouble() ?? 0;
      if (r['elevatedOverTraffic'] == true && hy < bottom + 0.35) continue;
      if ((dist <= 3.2 && dyy.abs() <= 1.95 && y + 1.72 > bottom + 0.35) ||
          (dl <= 2.15 && dyy.abs() <= 1.85)) {
        ringHit[i] = true;
        voltage = math.min(15, voltage + ((r['bonusKv'] as num?)?.toDouble() ?? 2.5));
        state.combo = math.min(12, state.combo + 1);
        boostBonus = math.min(5.5, boostBonus + 6.5 * 0.65);
        speed = _clamp(speed + 6.5 * 0.35, 27, 45.8);
        trauma = math.max(trauma, 0.22);
        hitStop = math.max(hitStop, 0.024);
        final pts = _award('boost_ring', r['label'] as String? ?? 'BOOST RING',
            ((r['bonusPts'] as num?) ?? 400).toInt());
        _popup('BOOST RING', bonus: pts, accent: CalloutAccent.vault);
        _emit('boostRing',
            px: (pos[0] as num).toDouble(),
            py: (pos[1] as num).toDouble(),
            pz: (pos[2] as num).toDouble(),
            index: i,
            value: bottom);
      }
    }
  }

  void _checkNearMiss() {
    if (speed < kNearMissMinSpeed) return;
    for (final t in taxis) {
      if (!t.active || t.nearMissCd > 0 || t.hoodCd > 0 || t.roofVaultCd > 0) continue;
      if ((y - t.y).abs() > t.height + 1.1) continue;
      if ((t.s - s).abs() > 3.9) continue;
      final a = (t.lateral - lateral).abs();
      final clear = math.max(0, a - t.width * 0.5 - 0.35);
      if (clear > 2.35) continue;
      if (a < t.width * 0.5 + 0.34 && y < t.y + t.height - 0.12) continue;
      t.nearMissCd = 3.2;
      nearMisses++;
      voltage = math.min(15, voltage + 2);
      state.combo = math.min(12, state.combo + 1);
      boostBonus = math.min(5.5, boostBonus + 3.5 * 0.65);
      speed = _clamp(speed + 3.5 * 0.3, 24, 45.8);
      trauma = math.max(trauma, 0.18);
      final drift = t.type != 'CrownComfortTaxi';
      final pts = _award('near_miss', drift ? 'TOKYO DRIFT NEAR MISS' : 'NEAR MISS TAXI', 500);
      _popup(drift ? 'TOKYO DRIFT NEAR MISS' : 'NEAR MISS',
          bonus: pts, accent: CalloutAccent.gold);
      _emit('nearMiss', py: y + 0.6, value: speed);
    }
    if (s >= 8 && s <= 95 && y < 3.5) {
      for (final c in drift) {
        if (c.nearMissCd > 0) continue;
        final dd = math.sqrt((c.x - x) * (c.x - x) + (c.z - z) * (c.z - z));
        if (dd > 11.5 || dd < 1.6) continue;
        c.nearMissCd = 4.5;
        nearMisses++;
        voltage = math.min(15, voltage + 2);
        state.combo = math.min(12, state.combo + 1);
        boostBonus = math.min(5.5, boostBonus + 1.92);
        speed = _clamp(speed + 1.2, 24, 45.8);
        final pts = _award('near_miss', 'TOKYO DRIFT NEAR MISS', 600);
        _popup('TOKYO DRIFT NEAR MISS', bonus: pts, accent: CalloutAccent.gold);
        _emit('driftNearMiss', py: 1.5, value: _clamp(1 - dd / 11.5, 0.35, 1));
      }
    }
  }

  void _checkGates() {
    final lo = math.min(prevS, s) - 2, hi = math.max(prevS, s) + 2;
    for (int i = 0; i < gates.length; i++) {
      if (gateLit[i]) continue;
      final g = gates[i];
      final gs = (g['s'] as num).toDouble();
      if (gs < lo || gs > hi) continue;
      final half = math.max(4.4, ((g['clearWidth'] as num?)?.toDouble() ?? 10.4) * 0.5);
      final ch = math.max(4.8, ((g['clearHeight'] as num?)?.toDouble() ?? 7.2) + 0.6);
      final gy = ((g['pos'] as List<dynamic>)[1] as num).toDouble();
      if ((lateral - (g['lateral'] as num).toDouble()).abs() <= half && (y - gy).abs() <= ch) {
        gateLit[i] = true;
        voltage = math.min(15, voltage + 1.8);
        state.combo = math.min(12, state.combo + 1);
        trauma = math.max(trauma, 0.24);
        hitStop = math.max(hitStop, 0.035);
        _award('sign', g['label'] as String? ?? 'GATE', 250);
        final gp = g['pos'] as List<dynamic>;
        _emit('pinGate',
            px: (gp[0] as num).toDouble(),
            py: (gp[1] as num).toDouble(),
            pz: (gp[2] as num).toDouble(),
            index: i);
      }
    }
  }

  /// Debug ledger mirroring the demo's `ignitionLedger` (kind, label, pts, t).
  final List<String> ledger = [];
  int _award(String kind, String label, int base, {bool scaled = true}) {
    final pts = scaled ? state.award(base) : base;
    if (!scaled) state.score += base;
    ledger.add('$kind|$label|$pts|${state.runTimeSec.toStringAsFixed(2)}');
    return pts;
  }

  final Set<int> _bldgSignLit = {};
  int _corridorSigns = 0;

  /// Second half of `_checkPinGatesAndSigns`: up to 3 OSM building signs
  /// within 38 m ignite (150 pts × combo) once voltage ≥ 2.2 kV.
  void _checkBuildingSigns() {
    if (voltage < 2.2 || _corridorSigns >= 3) return;
    final b = level.buildings;
    for (int t = 0; t < b.length; t++) {
      if (_bldgSignLit.contains(t)) continue;
      final n = b[t];
      if (n['isGoogleHero'] == true) continue;
      final c = n['center'] as List<dynamic>;
      final dx = (c[0] as num).toDouble() - x, dz = (c[1] as num).toDouble() - z;
      if (dx * dx + dz * dz <= 1444) {
        _bldgSignLit.add(t);
        _corridorSigns++;
        _award('sign', n['sign'] as String? ?? 'SHIBUYA', 150);
        _emit('signIgnite');
        break;
      }
    }
  }

  void _checkGoogle(double dt) {
    final h = level.route['heroGoogleLaunch'] as Map<String, dynamic>;
    final n = (h['igniteStartS'] as num).toDouble();
    final r = (h['igniteEndS'] as num).toDouble();
    if (!googleStarted && s >= n) {
      googleStarted = true;
      googleClock = 0;
    }
    if (!googleStarted) return;
    googleClock += dt;
    final i = _clamp((s - n) / math.max(10, r - n), 0, 1);
    final a = math.min(6, math.max((i * 5.99).floor() + 1, (googleClock / 0.42).floor() + 1));
    for (int e = 0; e < a; e++) {
      if (!state.googleLettersLit[e]) _igniteLetter(e);
    }
  }

  void _igniteLetter(int e) {
    state.googleLettersLit[e] = true;
    _emit('googleLetter', index: e);
    voltage = math.min(15, voltage + 1.1);
    state.combo = math.min(12, state.combo + 1);
    trauma = math.max(trauma, 0.3);
    if (e == 5) {
      _award('google_tower', 'Google Shibuya Stream', 1500);
    }
    if (state.googleLettersLit.every((x) => x)) {
      // The HUD shows "GOOGLE IGNITED!" once all six letters are lit.
      state.showCallout('GOOGLE IGNITED!', accent: CalloutAccent.google);
    }
  }

  void _checkComplete() {
    final d = math.sqrt((x - rooftop.x) * (x - rooftop.x) + (z - rooftop.z) * (z - rooftop.z));
    if (s >= spline.length - 1.5 || (finaleFlip && d <= 5.5)) {
      for (int e = 0; e < 6; e++) {
        if (!state.googleLettersLit[e]) _igniteLetter(e);
      }
      routeComplete = true;
      s = spline.length;
      lateral = 0;
      x = rooftop.x;
      y = rooftop.y;
      z = rooftop.z;
      groundY = rooftop.y;
      vy = 0;
      speed = 0;
      grounded = true;
      activeRail = pendingRail = activeWall = activeTransfer = -1;
      finaleFlip = false;
      flipPhase = 0;
      flipStyle = 'none';
      move = SimMove.finaleOrbit;
      yaw = ((level.meta['googleTower'] as Map<String, dynamic>)['facingYaw'] as num).toDouble();
      voltage = 15;
      trauma = math.max(trauma, 0.36);
      _award('beacon', 'Rooftop Pin', 1000);
      _emit('routeComplete');
      state.enterFinale();
    }
  }

  void _popup(String label, {int bonus = 0, CalloutAccent accent = CalloutAccent.neon}) {
    state.showCallout(label,
        bonus: bonus > 0 ? '+${GameState.formatInt(bonus)}' : '', accent: accent);
  }

  void _updateTraffic(double dt) {
    for (final t in taxis) {
      if (!t.active) continue;
      if (t.nearMissCd > 0) t.nearMissCd = math.max(0, t.nearMissCd - dt);
      if (t.roofVaultCd > 0) t.roofVaultCd = math.max(0, t.roofVaultCd - dt);
      if (t.hoodCd > 0) t.hoodCd = math.max(0, t.hoodCd - dt);
      final span = math.max(20, t.endS - t.startS);
      t.s += t.dir * t.speed * dt;
      if (t.s < t.startS) t.s += span;
      if (t.s > t.endS) t.s -= span;
      spline.sample(t.s, _tmp);
      if (_tmp.y > 0.35) {
        t.active = false;
        continue;
      }
      final (lat, dLat) = _weave(t.laneIndex, t.s);
      t.lateral = _clamp(lat, -3.6, 3.6);
      t.x = _tmp.x + _tmp.rx * t.lateral;
      t.y = math.max(0, _tmp.y);
      t.z = _tmp.z + _tmp.rz * t.lateral;
      final la = math.atan(dLat);
      t.yaw = t.dir >= 0 ? _tmp.yaw - la : _tmp.yaw + math.pi + la;
    }
    // Drift cars lap the exported Scramble drift loop; like the demo they
    // brake (4.2 m/s) when Pegman is just ahead and surge (20 m/s) when he
    // is just behind, so the near-miss passes line up.
    final loop = _driftLoop;
    final total = loop.length;
    for (final c in drift) {
      if (c.nearMissCd > 0) c.nearMissCd = math.max(0, c.nearMissCd - dt);
      var target = 13.5;
      if (state.phase == AppPhase.playing && s >= 8 && s <= 92 && y < 2.2) {
        final tan = vm.Vector3.zero();
        final p = loop.at(c.phase, tan);
        final nx = x - p.x, nz = z - p.z;
        if (math.sqrt(nx * nx + nz * nz) < 22) {
          final along = nx * tan.x + nz * tan.z;
          if (along > -4.5 && along < 18) {
            target = 4.2;
          } else if (along <= -4.5 && along > -17) {
            target = 20;
          }
        }
      }
      if (dt > 1e-6) {
        final k = 12 * dt;
        c.speed = _clamp(c.speed + _clamp(target - c.speed, -k, k), 4, 20.5);
        c.phase = (c.phase + c.speed * dt / total) % 1;
      }
      final tan = vm.Vector3.zero();
      final p = loop.at(c.phase, tan);
      c.x = p.x;
      c.z = p.z;
      final wob = math.sin(elapsed * 3.4 + drift.indexOf(c) * 1.57) * 0.04;
      c.yaw = math.atan2(tan.x, tan.z) + (-0.42 - wob);
    }
  }

  void _syncState(double dt) {
    state.speedKmh = speed * 3.6;
    // engine: decays by 0.12/step when not sprinting (sky drop, < 10 m/s).
    if (routeComplete || state.phase != AppPhase.playing) {
      state.overchargeRatio = 0;
    } else if (move == SimMove.finaleOrbit || move == SimMove.skyDrop || speed < 10) {
      state.overchargeRatio = math.max(0, state.overchargeRatio - 0.12);
    } else {
      state.overchargeRatio = _clamp((speed - 30) / 14, 0, 1);
    }
    state.routeS = s;
    state.routeLength = spline.length;
    state.heroX = x;
    state.heroZ = z;
    state.heroHeading = yaw;
    for (final seg in segments) {
      if (s >= seg.sStart && s < seg.sEnd + (seg == segments.last ? 1 : 0)) {
        if (!identical(state.street, seg)) {
          final first = state.street == null;
          state.street = seg;
          if (!first) state.showStreetPill(seg);
        }
        break;
      }
    }
    // _deflectBadgeMove: "BOUNCE" for max(hitStop, .036) s after a hood bounce.
    if (elapsed <= _deflectUntil &&
        (move == SimMove.stumble || move == SimMove.sprint || move == SimMove.vault)) {
      state.move = ParkourMove.hoodBounce;
      return;
    }
    state.move = switch (move) {
      SimMove.skyDrop => ParkourMove.skyDrop,
      SimMove.sprint => ParkourMove.sprint,
      // The demo labels hero.move directly: VAULT is always "JUMP" (also
      // mid-flip and mid-transfer).
      SimMove.vault => ParkourMove.jump,
      SimMove.slide => ParkourMove.slide,
      SimMove.railGrind => ParkourMove.railGrind,
      SimMove.wallRun => ParkourMove.wallRun,
      SimMove.stumble => ParkourMove.stumble,
      SimMove.pinBeacon => ParkourMove.pinBeacon,
      SimMove.finaleOrbit => ParkourMove.finaleOrbit,
    };
  }

  /// Seek helper for testing / photo presets: jump to a route fraction.
  void seek(double frac) {
    final target = _clamp(frac, 0, 1) * spline.length;
    if (state.phase == AppPhase.skyDrop) {
      dropClock = kDropTime;
      state.landFromSkyDrop();
    }
    s = target;
    prevS = target;
    activeRail = pendingRail = activeWall = activeTransfer = -1;
    finaleFlip = false;
    spline.sample(s, _now);
    groundY = _now.y;
    y = _now.y;
    grounded = true;
    vy = 0;
    speed = math.max(speed, 26);
    x = _now.x + _now.rx * lateral;
    z = _now.z + _now.rz * lateral;
  }

  // ------------------------------------------------------------- autopilot
  _BotOut _bot() {
    final out = _BotOut()..targetLateral = lateral;
    final n = s;
    spline.sample(n, _tmp);
    final i = math.max(3.6, _tmp.halfWidth - 1.1);
    if (activeRail >= 0) {
      out.targetLateral = rails[activeRail].lateral;
      return out;
    }
    if (activeWall >= 0) {
      final w = walls[activeWall];
      out.targetLateral = w.side * math.min(w.lateralOffset - 0.85, i);
      if (w.transfersTo != null && n >= w.endS - 2.4) out.jump = true;
      return out;
    }
    Map<String, dynamic>? portal;
    double portalD = double.infinity;
    for (final p in portals) {
      final r = (p['s'] as num).toDouble() - n;
      if (r >= -2.2 && r <= 20 && r < portalD) {
        portal = p;
        portalD = r;
      }
    }
    int ringIdx = -1;
    double ringD = double.infinity;
    for (int k = 0; k < rings.length; k++) {
      if (ringHit[k]) continue;
      final r = (rings[k]['s'] as num).toDouble() - n;
      if (r >= -1 && r <= 42 && r < ringD) {
        ringIdx = k;
        ringD = r;
      }
    }
    int gateIdx = -1;
    double gateD = double.infinity;
    for (int k = 0; k < gates.length; k++) {
      if (gateLit[k]) continue;
      final r = (gates[k]['s'] as num).toDouble() - n;
      if (r >= -1.2 && r <= 46 && r < gateD) {
        gateIdx = k;
        gateD = r;
      }
    }
    RailRt? rail;
    double railD = double.infinity;
    bool railBig = false;
    for (final r in rails) {
      if (railsDone.contains(r.id)) continue;
      final d = r.startS - n;
      final inside = n >= r.startS - 3 && n <= r.endS - 14;
      final big = r.isHero || r.isSky;
      if ((d >= -3 && d <= 34) || inside) {
        if (big && (!railBig || d < railD)) {
          rail = r;
          railD = d;
          railBig = true;
        } else if (!railBig && d < railD) {
          rail = r;
          railD = d;
        }
      }
    }
    WallRt? wall;
    for (final w in walls) {
      if (n >= w.startS - 14 && n <= w.endS - 10) {
        wall = w;
        break;
      }
    }
    double b = 0;
    if (ringIdx >= 0 && ringD <= 18 && (gateIdx < 0 || ringD <= gateD + 3)) {
      final ring = rings[ringIdx];
      b = (ring['lateral'] as num).toDouble();
      final rh = ((ring['pos'] as List<dynamic>)[1] as num).toDouble() - _tmp.y;
      final reach = speed * (kJumpV / kGravity);
      if (rh >= 1.75 && ringD >= 1.2 && ringD <= reach + 1.6 && grounded &&
          (portal == null || portalD > 12)) {
        out.jump = true;
      }
    } else if (railBig && rail != null && railD <= 28) {
      b = rail.lateral;
      if (railD >= -1 && railD <= 4.5 && grounded && (portal == null || portalD > 8)) {
        out.jump = true;
      }
    } else if (gateIdx >= 0 && gateD <= 14) {
      b = (gates[gateIdx]['lateral'] as num).toDouble();
    } else if (wall != null && (portal == null || portalD > 11)) {
      b = wall.side * math.min(wall.lateralOffset - 0.9, i);
    } else if (rail != null && railD <= 24 && (portal == null || portalD > 12)) {
      b = rail.lateral;
      final lined = n >= rail.startS - 6.2 && n <= rail.endS - 14 && (lateral - rail.lateral).abs() <= 2.3;
      if (n >= rail.startS - 8.5 && n <= rail.endS - 14 && lined && grounded) out.jump = true;
    } else if (ringIdx >= 0 && ringD <= 36) {
      b = (rings[ringIdx]['lateral'] as num).toDouble();
    } else if (gateIdx >= 0) {
      b = (gates[gateIdx]['lateral'] as num).toDouble();
    }
    if (portal != null && portalD >= -2 && portalD <= 19.5) {
      out.jump = false;
      out.slide = true;
    }
    if (!out.jump) {
      // dodge blocked lanes (barriers / taxis ahead)
      bool blocked(double lat, double range) {
        for (final br in barriers) {
          final d = (br['s'] as num).toDouble() - n;
          if (d > 0 && d < range && ((br['lateral'] as num).toDouble() - lat).abs() < 2.2) return true;
        }
        for (final t in taxis) {
          final d = t.s - n;
          if (t.active && d > -2 && d < range && (t.lateral - lat).abs() < 2.2) return true;
        }
        return false;
      }

      final wide = wall != null && b.abs() > 3.9;
      final r = (b / kLaneW).round().clamp(-1, 1);
      final lat = wide ? b : kLaneW * r;
      if (blocked(lat, wide ? 16 : 26)) {
        double best = -1e9;
        int pick = r;
        for (final cand in [-1, 0, 1]) {
          final o = kLaneW * cand;
          var score = -(o - b).abs() * 2.4;
          score += blocked(o, 26) ? 0 : 1000;
          if (score > best) {
            best = score;
            pick = cand;
          }
        }
        b = kLaneW * pick;
      }
      final look = _clamp(speed * 0.44, 11, 18);
      if (blocked(lateral, look) && y < groundY + 1.3 && (portal == null || portalD > 19.5)) {
        if (grounded) {
          out.jump = true;
        } else if (jumpCount == 1 && vy < 0) {
          out.jump = true;
        }
      }
    }
    out.targetLateral = _clamp(b, -i, i);
    return out;
  }
}

class _BotOut {
  bool jump = false, slide = false;
  double targetLateral = 0;
}


/// A gameplay event mirrored from the demo's engine callbacks (onJump,
/// onBoostRing, onNearMissTaxi, ...). Drained by the scene controller each
/// frame to drive FX and SFX.
class SimEvent {
  SimEvent(this.kind, this.x, this.y, this.z, {this.index = 0, this.value = 0});
  final String kind;
  final double x, y, z;
  final int index;
  final double value;
}
