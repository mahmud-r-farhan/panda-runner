import 'dart:math' as math;

import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;

import 'demo_grade.dart';
import 'fx.dart';
import 'game_state.dart';
import 'hero_sim.dart';
import 'level_data.dart';
import 'neon_environment.dart';
import 'glb_library.dart';
import 'ground_bounce.dart';
import 'map_location.dart';
import 'panda_rig.dart';
import 'pegman_builder.dart';
import 'pegman_glb.dart';
import 'pegman_pose.dart';
import 'route_spline.dart';
import 'sound_fx.dart';
import 'world_builder.dart';
import 'world_textures.dart';

double _lerp(double a, double b, double t) => a + (b - a) * t;
double _clamp(double v, double a, double b) => v < a ? a : (v > b ? b : v);

/// Owns the Flutter Scene world for Neon Scramble: builds the OSM Shibuya
/// level, runs [HeroSim] and drives Pegman, traffic and the camera rigs
/// ported from the web demo (`computeCameraState`).
class ShibuyaSceneController {
  ShibuyaSceneController({required this.state, required this.soundFx});

  final GameState state;
  final SoundFx soundFx;
  final fs.Scene scene = fs.Scene();

  bool initialized = false;
  late final ShibuyaLevel level;
  late final HeroSim sim;
  late final ShibuyaWorld world;
  late final GlbPegman pegman;
  late final PandaHero panda;
  final PegmanPoseSolver _poseSolver = PegmanPoseSolver();
  final PoseParams _poseParams = PoseParams();
  late final GlbLibrary glb;
  final List<fs.Node> _taxiNodes = [];
  final List<fs.Node> _driftNodes = [];
  final List<({fs.Node node, double x, double z, double yaw, String? underglow})> _parked = [];
  final List<fs.Node> _carShadows = [];
  final List<fs.Node> _underglows = [];
  late final NeonFx fx;
  fs.Node? _skyDome;
  // three.js PointLight(#4285F4, .4, 68, decay 1.5).
  final fs.PointLight _beacon = fs.PointLight(
      color: vm.Vector3(0.0545, 0.2346, 0.9047), intensity: 0.4, range: 68, falloffExponent: 1.5);
  final List<double> _letterFlash = List.filled(6, 0.0);
  double _hazardZap = 0;
  GroundBounce? _bounce;
  double _towerPower = 0;
  final FxFrame _fxf = FxFrame();
  PegmanPoseResult? _pose;
  double _mapsMorph = 0;

  /// Overcharge speed-line strength (`_computeEffectiveSpeedLinesFactor`).
  double speedLinesFactor = 0;
  double get time => _time;
  final List<_Train> _trains = [];

  // camera state (reference coordinates)
  final vm.Vector3 camPos = vm.Vector3(68, 435, 68);
  final vm.Vector3 camTarget = vm.Vector3(68, 0, 68);
  vm.Vector3 camUp = vm.Vector3(0, 0, -1);
  double camFov = 54;
  double camRoll = 0;
  final vm.Vector3 _springPos = vm.Vector3(68, 435, 68);
  final vm.Vector3 _springVel = vm.Vector3.zero();
  final vm.Vector3 _springTgt = vm.Vector3(68, 0, 68);
  final vm.Vector3 _springTgtVel = vm.Vector3.zero();
  bool _camInit = false;
  double _time = 0;
  int _lastCalloutId = -1;

  Future<void> initialize() async {
    state.setLoading(0.06, 'Loading Neon Scramble...');
    await fs.Scene.initializeStaticResources();
    state.setLoading(0.18, 'Loading Shibuya...');
    level = await ShibuyaLevel.load();
    sim = HeroSim(level, state);
    state.setLoading(0.32, 'Lighting Shibuya night sky...');
    _configureLighting();
    // cityRimLight: DirectionalLight(#FFB778, .24) from (-55, 28, 78) to
    // the origin (Flutter frame: z mirrored).
    scene.add(fs.Node(name: 'CityRimLight')
      ..addComponent(fs.DirectionalLightComponent.aimed(
          fs.DirectionalLight(color: vm.Vector3(1.0, 0.4678, 0.1845), intensity: 0.24),
          vm.Vector3(55, -28, 78).normalized())));
    try {
      scene.environment = await NeonEnvironment.build();
    } catch (_) {
      // keep the gradient fallback from _configureLighting
    }
    int loaded = 0;
    glb = await GlbLibrary.load(
        onProgress: (l) => state.setLoading(0.32 + 0.06 * ++loaded, l));
    state.setLoading(0.66, 'Preparing Shibuya Crossing...');
    final tex = await WorldTextures.create(level);
    state.setLoading(0.74, 'Building Shibuya streets...');
    world = ShibuyaWorld(level, sim.spline, tex, glb);
    await world.buildCity();
    world.build();
    await world.glbWorld.buildSigns();
    await world.glbWorld.buildSignFaces();
    await world.glbWorld.media?.update(0, 1.8, force: true);
    scene.add(world.root);
    state.setLoading(0.8, 'Preparing 3D Panda Runner & Pegman...');
    _skyDome = NeonEnvironment.buildSkyDome();
    world.refRoot.add(_skyDome!);
    pegman = GlbPegman(glb)..attach(world.refRoot);
    panda = PandaHero()..attach(world.refRoot);
    // googleBeaconLight: 6 m in front of the GLB sign's middle letter,
    // 1.5 m up — (245.5, 30, 256.4) as measured in the demo's scene (the
    // level meta signCenter predates the GLB tower).
    world.refRoot.add(fs.Node(name: 'GoogleBeaconLight')
      ..position = vm.Vector3(245.5, 30.0, 256.4)
      ..addComponent(fs.PointLightComponent(_beacon)));
    state.setLoading(0.86, 'Loading Tokyo street fleet...');
    _buildTraffic();
    _buildTrains();
    fx = NeonFx(world.refRoot);
    state.setLoading(0.95, 'Placing Shibuya Stream...');
    initialized = true;
    state.setLoading(1.0, 'Shibuya ready');
    await Future<void>.delayed(const Duration(milliseconds: 250));
    state.finishLoading();
  }

  void _configureLighting() {
    // Port of the demo's renderer/shadow-rig setup: moonlit sky dome
    // (#0F1D3A → #233C6B → #375789), hemisphere light #7AA4E6/#384B6B @0.42,
    // moon from (0.7427, 0.48, -0.4737) colour #DBEAFF @0.56, warm city rim
    // light, haze #1E345D @3.2e-4, AgX at exposure 1.18 with light bloom,
    // vignette 0.14 and film grain.
    final sky = fs.GradientSkySource(
      zenithColor: vm.Vector3(0.0085, 0.0220, 0.0680),
      horizonColor: vm.Vector3(0.0520, 0.1220, 0.2960),
      groundColor: vm.Vector3(0.0055, 0.0095, 0.0220),
      sunColor: vm.Vector3.zero(),
    );
    scene.skybox = fs.Skybox(sky);
    // Hemisphere-like IBL: bake a sky/ground gradient in the hemi colours.
    scene.environment = fs.EnvironmentMap.fromSky(fs.GradientSkySource(
      zenithColor: vm.Vector3(0.195, 0.371, 0.791) * 0.42,
      horizonColor: vm.Vector3(0.11, 0.2, 0.42) * 0.42,
      groundColor: vm.Vector3(0.040, 0.069, 0.147) * 0.42,
      sunColor: vm.Vector3.zero(),
    ));
    scene.environmentIntensity = 1.0;
    // The demo's composer grade (applyAgXGolden) via an exact LUT over an
    // invertible Reinhard curve; see DemoGrade.
    scene.toneMapping = fs.ToneMappingMode.reinhard;
    scene.exposure = 1.18;
    scene.postProcess.colorGrading.lut = DemoGrade.lut();
    final moon = vm.Vector3(0.7427, 0.48, -0.4737).normalized();
    scene.directionalLight = fs.DirectionalLight(
      direction: w3(-moon.x, -moon.y, -moon.z),
      color: vm.Vector3(0.716, 0.823, 1.0),
      // staticSun 0.56 + heroSun 0.68: both light everything (E_ rig).
      intensity: 0.56 + 0.68,
    );
    // The demo has no scene fog: each world material blends toward its haze
    // colour (default (.095,.17,.31)) by 1 - exp(-3.2e-4 * max(0, d - 12)),
    // capped at 0.62 (the Mh/Ih "aerial perspective" chunk).
    scene.fog
      ..enabled = true
      ..mode = fs.FogMode.exponential
      ..color = vm.Vector3(0.095, 0.17, 0.31)
      ..density = 3.2e-4
      ..start = 12
      ..maxOpacity = 0.62
      // the sky dome (1100 m, camera-centred) is drawn unfogged like the
      // demo's ShaderMaterial dome; all real geometry is nearer than this.
      ..cutoffDistance = 1050;
    // The demo's bloom is a 3 px, 13-tap soft-knee blur (strength 0.18):
    // practically no halo, so the engine's wide bloom stays off.
    scene.postProcess.bloom.enabled = false;
    scene.screenSpaceReflections
      // The demo has no SSR (its wet sheen is the moon's GGX lobe, matched
      // via the asphalt roughness); off by default for fidelity and mobile
      // performance, `?ssr=1` to experiment.
      ..enabled = Uri.base.queryParameters['ssr'] == '1'
      ..intensity = 0.7
      ..maxDistance = 60
      ..resolutionScale = 0.5
      ..blur = 0.35;
    // Vignette is applied in display space after the grade (game_screen).
    scene.postProcess.vignette.enabled = false;
    scene.postProcess.filmGrain
      ..enabled = true
      ..intensity = 0.006;
  }

  fs.Node _car(String type) {
    final t = GlbLibrary.template(glb.fleet, type) ??
        GlbLibrary.template(glb.fleet, 'CrownComfortTaxi')!;
    world.refRoot.add(t);
    return t;
  }

  void _buildTraffic() {
    for (final t in sim.taxis) {
      _taxiNodes.add(_car(t.type));
    }
    for (final c in sim.drift) {
      _driftNodes.add(_car(c.type));
    }
    _buildParkedCarMeet();
    // InstFleet_ContactShadows (2.65 x 5.45, opacity .72) and
    // InstFleet_DriftUnderglow (2.75 x 5.25, additive, opacity .58).
    final shadowGeo = NeonFx.rectXZ(2.65, 5.45);
    final shadowMat = fs.UnlitMaterial(colorTexture: NeonFx.contactShadowTexture())
      ..alphaMode = fs.AlphaMode.blend
      ..baseColorFactor = vm.Vector4(1, 1, 1, 0.72);
    final glowGeo = NeonFx.rectXZ(2.75, 5.25);
    final glowTex = NeonFx.underglowTexture();
    final n = _taxiNodes.length + _driftNodes.length + _parked.length;
    for (int i = 0; i < n; i++) {
      final sh = fs.Node(name: 'CarContactShadow_$i', mesh: fs.Mesh(shadowGeo, shadowMat));
      world.refRoot.add(sh);
      _carShadows.add(sh);
    }
    final glowCars = [
      for (final c in sim.drift) c.underglow,
      for (final p in _parked)
        if (p.underglow != null) p.underglow!,
    ];
    for (final hex in glowCars) {
      final m = fs.UnlitMaterial(colorTexture: glowTex)
        ..alphaMode = fs.AlphaMode.blend
        ..baseColorFactor = hexColor(hex, 1.6, 0.58);
      final g = fs.Node(name: 'CarUnderglow', mesh: fs.Mesh(glowGeo, m));
      world.refRoot.add(g);
      _underglows.add(g);
    }
    _bounce = GroundBounce(world.refRoot);
  }

  /// `_buildParkedCarMeetSlots`: up to 10 tuner cars parked 8.4 m off the
  /// route every 7 waypoints (alternating sides, nose angled .22 rad).
  void _buildParkedCarMeet() {
    const kinds = [
      ('DriftWidebodyOrange', '#FF4F00'),
      ('GtrMidnightBlue', '#38BDF8'),
      ('PandaHatch86', '#34A853'),
      ('TunerPearlSilver', '#4285F4'),
      ('CrownComfortTaxi', null),
    ];
    final e = level.waypoints;
    for (int n = 6; n < e.length - 8 && _parked.length < 10; n += 7) {
      final r = e[n];
      if (r.s < 75 || r.y > 0.25 || world.inScramblePlaza(r.x, r.z)) continue;
      final i = e[math.min(e.length - 1, n + 1)];
      final a = i.x - r.x, o = i.z - r.z, sl = math.sqrt(a * a + o * o);
      if (sl < 0.2) continue;
      final c = a / sl, l = o / sl, u = o / sl, d = -a / sl;
      final f = _parked.length % 2 == 0 ? 1.0 : -1.0;
      final m = r.x + u * f * 8.4, h = r.z + d * f * 8.4;
      if (world.inScramblePlaza(m, h) || world.insideBuilding(m, h, 2.4)) continue;
      final k = kinds[_parked.length % kinds.length];
      final node = _car(k.$1);
      final yaw = math.atan2(c, l) + f * 0.22;
      node.localTransform = GlbLibrary.slot(m, 0.18, h, yaw);
      _parked.add((node: node, x: m, z: h, yaw: yaw, underglow: k.$2));
    }
  }

  void _syncCarDecals() {
    final visible = _mapsMorph > 0.03;
    final glowOn = visible && math.sqrt(math.pow(camPos.x - 4.5, 2) + math.pow(camPos.z + 1, 2)) <= 190;
    int si = 0, gi = 0;
    void place(double x, double y, double z, double yaw, bool show, String? glow) {
      final sh = _carShadows[si++];
      sh.visible = visible && show;
      sh.localTransform = GlbLibrary.slot(x, y + 0.024, z, yaw);
      if (glow != null && gi < _underglows.length) {
        final g = _underglows[gi++];
        g.visible = glowOn && show;
        g.localTransform = GlbLibrary.slot(x, y + 0.036, z, yaw);
      }
    }

    for (final t in sim.taxis) {
      place(t.x, t.y, t.z, t.yaw, t.active, null);
    }
    for (final c in sim.drift) {
      place(c.x, 0, c.z, c.yaw, true, c.underglow);
    }
    for (final p in _parked) {
      place(p.x, 0.18, p.z, p.yaw, true, p.underglow);
    }
  }

  void _buildTrains() {
    final tracks = level.meta['yamanoteTracks'] as Map<String, dynamic>;
    for (int e = 0; e < 2; e++) {
      final pts = [
        for (final p in tracks[e == 0 ? 'outer' : 'inner'] as List<dynamic>)
          vm.Vector3((p[0] as num).toDouble(), (p[1] as num).toDouble(),
              (p[2] as num).toDouble()),
      ];
      final cars = <fs.Node>[];
      for (int c = 0; c < 4; c++) {
        final t = GlbLibrary.template(glb.props, 'YamanoteTrain');
        if (t == null) return;
        GlbLibrary.forEachMaterial(t, (name, p) {
          String? hex;
          double k = 0;
          if (name == 'Yamanote_Lights') {
            hex = '#FFFBEB';
            k = 3.6;
          } else if (name == 'Yamanote_Windows') {
            hex = '#D4E9FF';
            k = 1.45;
          } else if (name == 'Yamanote_Stripe') {
            hex = '#34A853';
            k = 0.45;
          }
          if (hex != null) {
            p.material = GlbLibrary.clonePbr(p.material)
              ..emissiveFactor = hexColor(hex, k)
              ..emissiveStrength = 1;
          }
        });
        world.refRoot.add(t);
        cars.add(t);
      }
      _trains.add(_Train(Polyline3(pts), cars, e == 0 ? 360 : 625, e == 0 ? 1 : -1));
    }
  }

  void _syncTrains(double dt) {
    const minD = 345.0, maxD = 640.0, base = 8.2, spacing = 15.4;
    for (final n in _trains) {
      final total = n.path.length;
      final a = math.min(maxD, total - 10);
      if (dt > 1e-6) {
        final rem = n.dir > 0 ? a - n.distance : n.distance - minD;
        if (rem <= 0.35 && n.vel.abs() <= 0.85) n.dir = -n.dir;
        final r2 = n.dir > 0 ? a - n.distance : n.distance - minD;
        var target = base;
        if (r2 < 24) target = base * math.sqrt((r2 / 24).clamp(0.0, 1.0));
        final o = n.dir * target, s = 4.2 * dt;
        n.vel = (n.vel + (o - n.vel).clamp(-s, s)).clamp(-base, base);
        final c = n.distance + n.vel * dt;
        if (c >= a) {
          n.distance = a;
          n.vel = 0;
          n.dir = -1;
        } else if (c <= minD) {
          n.distance = minD;
          n.vel = 0;
          n.dir = 1;
        } else {
          n.distance = c;
        }
      }
      for (int e = 0; e < n.cars.length; e++) {
        final d = (n.distance - e * spacing).clamp(0.0, total);
        final tan = vm.Vector3.zero();
        final p = n.path.at(d / total, tan);
        n.cars[e].localTransform = GlbLibrary.slot(
            p.x, (level.meta['yamanoteTracks']['deckY'] as num).toDouble(), p.z,
            math.atan2(tan.x, tan.z));
      }
    }
  }

  // ----------------------------------------------------------- run flow
  void startNewRun() {
    if (!initialized) return;
    sim.reset();
    state.beginRun();
    pegman.resetTrail();
    panda.resetTrail();
    fx.reset();
    sim.events.clear();
    _beacon
      ..color = vm.Vector3(0.0545, 0.2346, 0.9047)
      ..intensity = 0.4;
    _bounce?.reset();
    _towerPower = 0;
    _firstPill = true;
    _camInit = false;
    _poPreset = null;
    for (final g in world.pinGates) {
      g.setLit(false);
      g.flash = 0;
    }
    for (final r in world.rings) {
      r.glow.flash = 0;
    }
    for (final a in world.archRigs) {
      a.reset();
    }
    for (int i = 0; i < 6; i++) {
      _letterFlash[i] = 0;
    }
  }

  /// Dynamically updates the environment skybox and lighting to match [loc].
  void updateLocation(MapLocation loc) {
    scene.skybox = fs.Skybox(fs.GradientSkySource(
      zenithColor: loc.skyZenith,
      horizonColor: loc.skyHorizon,
      groundColor: loc.skyGround,
      sunColor: vm.Vector3.zero(),
    ));
    scene.environment = fs.EnvironmentMap.fromSky(fs.GradientSkySource(
      zenithColor: loc.skyZenith * 0.42,
      horizonColor: loc.skyHorizon * 0.42,
      groundColor: loc.skyGround * 0.42,
      sunColor: vm.Vector3.zero(),
    ));
  }

  void moveLane(int dir) => sim.moveLane(dir);
  void releaseLane(int dir) => sim.releaseLane(dir);

  void jump() {
    if (state.phase == AppPhase.playing && !state.autoPilot) sim.pressJump();
  }

  void slide() {
    if (state.phase == AppPhase.playing && !state.autoPilot) sim.pressSlide();
  }

  // Photo orbit (port of the demo's _photoOrbit): goals + smoothed state.
  double _poYaw = 0, _poPitch = 0.3, _poRadius = 10, _poFov = 50;
  double _goYaw = 0, _goPitch = 0.3, _goRadius = 10, _goFov = 50;
  final vm.Vector3 _poTarget = vm.Vector3.zero(), _goTarget = vm.Vector3.zero();
  PhotoPreset? _poPreset;

  static const _photoLimits = {
    PhotoPreset.hero: [2.8, 18.0, 0.06, 1.15],
    PhotoPreset.scramble: [14.0, 58.0, 0.14, 1.22],
    PhotoPreset.skyline: [28.0, 82.0, 0.1, 1.18],
  };

  void orbitPhotoCamera(double dx, [double dy = 0]) {
    final l = _photoLimits[state.photoPreset]!;
    _goYaw -= dx * 0.0075;
    _goPitch = _clamp(_goPitch + dy * 0.006, l[2], l[3]);
  }

  void zoomPhotoCamera(double delta) {
    final l = _photoLimits[state.photoPreset]!;
    _goRadius = _clamp(_goRadius * math.exp(_clamp(delta, -180, 180) * 0.0014), l[0], l[1]);
  }

  /// `_setPhotoPresetGoal(preset, snap)`.
  void resetPhotoCamera() => _poPreset = null;

  void _setPhotoGoal(PhotoPreset p, bool snap) {
    final (pos, tgt, fov) = _presetCamera(p);
    final l = _photoLimits[p]!;
    final c = pos - tgt;
    final d = c.length;
    _goTarget.setFrom(tgt);
    _goRadius = _clamp(d, l[0], l[1]);
    _goYaw = math.atan2(c.x, c.z);
    _goPitch = _clamp(math.asin(_clamp(c.y / math.max(d, 0.01), -0.95, 0.95)), l[2], l[3]);
    _goFov = fov;
    if (snap) {
      _poTarget.setFrom(_goTarget);
      _poRadius = _goRadius;
      _poYaw = _goYaw;
      _poPitch = _goPitch;
      _poFov = _goFov;
    }
  }

  // --------------------------------------------------------------- tick
  void tick(double dt) {
    if (!initialized) return;
    _time += dt;
    if (!state.photoMode) sim.step(dt);
    _handleEvents();
    final c = state.callout;
    if (c != null && c.id != _lastCalloutId) {
      _lastCalloutId = c.id;
      if (c.accent == CalloutAccent.danger) {
        soundFx.playCrash();
      } else {
        soundFx.playBoostRing();
      }
    }
    _syncAudio();
    _syncProps();
    _syncTrains(dt);
    _syncHero(dt);
    _computeCamera(dt);
    _skyDome?.position = vm.Vector3(camPos.x, camPos.y, camPos.z);
    _syncBounce();
    _syncFx(state.photoMode ? 0 : dt);
    state.tick(state.photoMode ? 0 : dt);
  }

  void _syncMapsMorph() {
    // mapsMorph = smootherstep(dropClock / 0.9); overlay a = 1 - smoothstep(.18, .92, morph)
    double morph;
    if (state.phase == AppPhase.loading || state.phase == AppPhase.mapsTitle) {
      morph = 0;
    } else if (state.phase == AppPhase.skyDrop) {
      morph = _qs(sim.dropClock / 0.9);
    } else {
      morph = 1;
    }
    _mapsMorph = morph;
    final a = 1 - _sStep(0.18, 0.92, morph);
    world.mapsOverlay.visible = a > 0.01;
    world.mapsOverlayMat.baseColorFactor = vm.Vector4(0, 0, 0, a);
    world.mapsOverlayMat.emissiveFactor = vm.Vector4(a, a, a, 1);
    final pulse = (_time * 0.85) % 1;
    for (int i = 0; i < world.dropPin.length; i++) {
      final n = world.dropPin[i];
      n.visible = a > 0.01;
      if (i == 2) {
        final k = 1 + pulse * 0.45;
        final p = n.position;
        n.localTransform = vm.Matrix4.compose(p, vm.Quaternion.identity(), vm.Vector3(k, 1, k));
      }
    }
  }

  void _syncProps() {
    _syncMapsMorph();
    // Animated Scramble media screen while it can be seen.
    final dm = math.sqrt(math.pow(camPos.x + 2.5, 2) + math.pow(camPos.z + 41.5, 2));
    if (dm < 260 && state.phase != AppPhase.mapsTitle) {
      world.glbWorld.media?.update(_time, sim.voltage);
    }
    for (int i = 0; i < world.railMats.length && i < sim.rails.length; i++) {
      final hero = sim.rails[i].isHero;
      final active = sim.activeRail == i;
      // #FF4F00 x4.8 desaturates to pale peach under the demo's AgX grade.
      world.railMats[i].emissiveFactor = active
          ? hexColor('#FF4F00', 4.8)
          : (hero ? hexColor('#38BDF8', 1.55) : hexColor('#FF4F00', 0.72));
    }
    for (int i = 0; i < world.wallRunMats.length; i++) {
      world.wallRunMats[i].emissiveFactor = hexColor('#38BDF8', sim.activeWall == i ? 2.6 : 0.95);
    }
    _syncPlasma(1 / 60);
    final cars = [
      for (final t in sim.taxis)
        if (t.active) (x: t.x, z: t.z),
      for (final c in sim.drift) (x: c.x, z: c.z),
    ];
    for (int i = 0; i < world.archRigs.length; i++) {
      world.archRigs[i].sync(state.photoMode ? 0 : 1 / 60, _time, sim.s,
          state.phase == AppPhase.finale, i < sim.portalDone.length && sim.portalDone[i], _mapsMorph, cars);
    }
    // igniteGoogleLetter / flash decay (3.2/s): core 3.3 -> 2.15, shell
    // .72 -> .46; dormant core #1C273B x.14, shell x.08 @ .32 opacity.
    for (int i = 0; i < 6; i++) {
      if (_letterFlash[i] > 0) _letterFlash[i] = math.max(0, _letterFlash[i] - (1 / 60) * 3.2);
    }
    for (final l in world.googleLetters) {
      final i = l.letterIndex;
      if (i < 0) continue;
      final c = l.baseEmissive;
      final lit = state.googleLettersLit[i];
      final f = _letterFlash[i];
      final k = !lit ? (l.core ? 0.14 : 0.08) : (l.core ? _lerp(2.15, 3.3, f) : _lerp(0.46, 0.72, f));
      l.material.emissiveFactor = vm.Vector4(c.x * k, c.y * k, c.z * k, 1);
      if (l.core) {
        l.material.baseColorFactor = lit ? vm.Vector4(c.x, c.y, c.z, 1) : hexColor('#1C273B');
      } else {
        l.material.baseColorFactor = vm.Vector4(c.x, c.y, c.z, lit ? 0.34 : 0.32);
      }
    }
    final lit = world.glbWorld.updateSigns(sim.s, 1 / 60, _time,
        finale: state.phase == AppPhase.finale,
        reset: state.phase == AppPhase.skyDrop || state.phase == AppPhase.mapsTitle);
    if (_mapsMorph > 0.35) {
      for (final sg in lit) {
        _bounce?.push(sg.pos.x, sg.pos.z, sg.neon);
      }
    }
    for (int i = 0; i < sim.taxis.length; i++) {
      final t = sim.taxis[i];
      final n = _taxiNodes[i];
      n.visible = t.active;
      n.localTransform = GlbLibrary.slot(t.x, t.y, t.z, t.yaw);
    }
    for (int i = 0; i < sim.drift.length; i++) {
      final c = sim.drift[i];
      final n = _driftNodes[i];
      n.localTransform = GlbLibrary.slot(c.x, 0, c.z, c.yaw);
    }
    _syncCarDecals();
  }

  void _syncHero(double dt) {
    PegmanPose pose;
    switch (sim.move) {
      case SimMove.skyDrop:
        pose = sim.grounded ? PegmanPose.run : PegmanPose.skyDrop;
      case SimMove.sprint:
        pose = PegmanPose.run;
      case SimMove.stumble:
        pose = PegmanPose.stumble;
      case SimMove.vault:
      case SimMove.pinBeacon:
        pose = sim.flipStyle != 'none' ? PegmanPose.flip : PegmanPose.jump;
        if (sim.move == SimMove.pinBeacon && sim.grounded) pose = PegmanPose.run;
      case SimMove.slide:
        pose = PegmanPose.slide;
      case SimMove.railGrind:
        pose = PegmanPose.grind;
      case SimMove.wallRun:
        pose = PegmanPose.wallRun;
      case SimMove.finaleOrbit:
        pose = PegmanPose.dance;
    }
    final visible =
        state.phase != AppPhase.mapsTitle && state.phase != AppPhase.loading;
    final isPanda = state.selectedHero == HeroCharacterType.panda;
    pegman.root.visible = visible && !isPanda;
    panda.root.visible = visible && isPanda;
    if (isPanda) {
      panda.placeRoot(sim.x, sim.y, sim.z, sim.yaw);
    } else {
      pegman.placeRoot(sim.x, sim.y, sim.z, sim.yaw);
    }
    // _updateHeroPose(): feed the demo's IK pose solver.
    final p = _poseParams;
    final now = sim.spline.sample(sim.s);
    final ahead = sim.spline.sample(sim.s + math.max(4.5, sim.speed * 0.25));
    var fyd = ahead.yaw - now.yaw;
    while (fyd > math.pi) {
      fyd -= 2 * math.pi;
    }
    while (fyd < -math.pi) {
      fyd += 2 * math.pi;
    }
    p
      ..move = switch (sim.move) {
        SimMove.skyDrop => PoseMove.skyDrop,
        SimMove.sprint => PoseMove.sprint,
        SimMove.vault => PoseMove.vault,
        SimMove.slide => PoseMove.slide,
        SimMove.railGrind => PoseMove.railGrind,
        SimMove.wallRun => PoseMove.wallRun,
        SimMove.stumble => PoseMove.stumble,
        SimMove.pinBeacon => PoseMove.pinBeacon,
        SimMove.finaleOrbit => PoseMove.finaleOrbit,
      }
      ..time = sim.elapsed
      ..gaitPhase = sim.gaitPhase
      ..speedMps = sim.speed
      ..curvature = now.kappa
      ..steerRate = _clamp(sim.lateralVel / 12, -1, 1)
      ..futureYawDelta = fyd
      ..verticalVel = sim.vy
      ..dropInProgress = _clamp(sim.dropClock / 3.5, 0, 1)
      ..timeSinceLand = sim.timeSinceLand
      ..slideProgress = _slideProgress()
      ..stumbleProgress = sim.stumbleTimer > 0 ? 1 - sim.stumbleTimer / 0.65 : 1
      ..wallSide = sim.wallSide
      ..railSide = sim.activeRail % 2 == 0 ? 1 : -1
      ..railSlope = sim.activeRail >= 0 ? sim.pitch : 0
      ..voltageKv = sim.voltage
      ..flipPhase = sim.flipPhase
      ..flipStyle = sim.flipStyle
      ..overchargeRatio = state.overchargeRatio;
    if (pose == PegmanPose.dance) p.time = _time;
    // Hero point light: intensity/colour from voltage, overcharge, hazards.
    _hazardZap = math.max(0, _hazardZap - dt);
    final oc = state.overchargeRatio;
    final res = _poseSolver.solve(p);

    if (isPanda) {
      panda.applyPose(res);
      panda.light.intensity = _clamp(0.28 + sim.voltage / 15 * 0.12 + oc * 0.05, 0.28, 0.42);
      if (_hazardZap / 0.42 > 0.05) {
        panda.light.color = vm.Vector3(0.3916, 0.0908, 0.9301); // #A855F7
      } else {
        final k = oc > 0.35 ? _clamp((oc - 0.35) * 0.75, 0, 0.45) : 0.0;
        // Emerald green (#10B981) shifting to radiant gold under overcharge
        panda.light.color = vm.Vector3(
          _lerp(0.063, 0.984, k),
          _lerp(0.725, 0.749, k),
          _lerp(0.506, 0.141, k),
        );
      }
    } else {
      pegman.applyPose(res);
      pegman.light.intensity = _clamp(0.24 + sim.voltage / 15 * 0.1 + oc * 0.04, 0.24, 0.38);
      if (_hazardZap / 0.42 > 0.05) {
        pegman.light.color = vm.Vector3(0.3916, 0.0908, 0.9301); // #A855F7
      } else {
        final k = oc > 0.35 ? _clamp((oc - 0.35) * 0.75, 0, 0.45) : 0.0;
        pegman.light.color = vm.Vector3(_lerp(1.0, 0.2051, k), _lerp(0.7913, 0.6584, k), _lerp(0.2232, 0.9734, k));
      }
    }
    _pose = res;
  }

  double _slideProgress() {
    var a = sim.slideTimer > 0 ? 1 - sim.slideTimer / 0.62 : 0.5;
    if (sim.move == SimMove.slide) {
      var duck = sim.fastFall;
      for (final pt in sim.portals) {
        if ((sim.s - (pt['s'] as num).toDouble()).abs() <= 2.4) duck = true;
      }
      if (duck) a = _clamp(a, 0.14, 0.86);
    }
    return a;
  }

  /// Drains [HeroSim.events] like the demo's engine callbacks
  /// (`onBoostRing` -> `igniteBoostRing`, `onNearMissTaxi` ->
  /// `triggerNearMissArc`, ...).
  /// Ground uniforms: uHeroPos (hero + .9), uHeroPower, uHeroColor,
  /// uTowerPower, uFinalePower -> the wet-asphalt bounce decals.
  void _syncBounce() {
    final b = _bounce;
    if (b == null) return;
    final oc = state.overchargeRatio;
    vm.Vector4 col;
    if (_hazardZap > 0) {
      col = hexColor('#A855F7');
    } else if (oc > 0.35) {
      final a = hexColor('#FF5A1A'), c = hexColor('#38BDF8');
      col = a + (c - a) * (oc * 0.45);
    } else {
      col = hexColor('#FF7A1A');
    }
    b.sync(
      visible: _mapsMorph > 0.03,
      cam: camPos,
      hero: vm.Vector3(sim.x, sim.y + 0.9, sim.z),
      heroColor: col,
      heroPower: 1.2 + sim.speed / 15 * 2.2 + oc * 1.4,
      towerPower: _towerPower,
      finalePower: state.phase == AppPhase.finale ? 1 : 0,
      time: _time,
    );
  }

  void _handleEvents() {
    final hero = vm.Vector3(sim.x, sim.y, sim.z);
    for (final e in sim.events) {
      _playEventSound(e);
      final p = vm.Vector3(e.x, e.y, e.z);
      switch (e.kind) {
        case 'mapsExtrude':
          fx.mapsExtrudeWave(e.x, e.z);
        case 'routeComplete':
          fx.finaleShock(sim.rooftop.x, sim.rooftop.z);
          _towerPower = 1.95;
        case 'googleLetter':
          if (e.index >= 0 && e.index < 6) _letterFlash[e.index] = 1;
          const lc = ['#1064FF', '#EE1F19', '#FFB300', '#1064FF', '#16A34A', '#EE1F19'];
          final c = hexColor(lc[e.index.clamp(0, 5)]);
          _beacon
            ..color = vm.Vector3(c.x, c.y, c.z)
            ..intensity = 2.5 + (e.index + 1);
          _bounce?.push(p.x, p.z, c);
          _towerPower = math.min(2, _towerPower + 0.32);
        case 'roofVault':
          fx.roofVault(p);
          _bounce?.pushHex(p.x, p.z, '#38BDF8');
        case 'carDeflect':
          _hazardZap = math.max(_hazardZap, 0.36);
          _bounce?.pushHex(p.x, p.z, '#FF6B1A');
          fx.sparkBurst(p, 24, 1.35, 3.8, math.max(0, p.y - 0.85));
        case 'stumble':
          _hazardZap = 0.42;
          fx.sparkBurst(p, 20, 1.25, 3.2, math.max(0, p.y - 0.5));
        case 'nearMiss':
        case 'driftNearMiss':
          fx.spawnArc(hero, p, 0.25);
          fx.sparkBurst(p, 18, 1.45, 2.8, math.max(0, sim.groundY));
        case 'transfer':
          fx.sparkBurst(p, 22, 1.55, 4, math.max(0, p.y - 0.4));
        case 'boostRing':
          if (e.index < world.rings.length) {
            final g = world.rings[e.index].glow..flash = 1;
            _bounce?.push(p.x, p.z, vm.Vector4(g.color.x, g.color.y, g.color.z, 1));
          }
          fx.spawnArc(hero, p, 0.22);
          fx.sparkBurst(p, 24, 1.6, 3.4, math.max(0, p.y - 2.3));
        case 'pinGate':
          if (e.index < world.pinGates.length) {
            final g = world.pinGates[e.index]..flash = 1;
            _bounce?.push(p.x, p.z, vm.Vector4(g.color.x, g.color.y, g.color.z, 1));
          }
          fx.spawnArc(hero, p, 0.26);
          fx.sparkBurst(p, 16, 1.3, 3.2, math.max(0, p.y - 3.2));
        case 'neonSlide':
          if (e.index < world.archRigs.length) world.archRigs[e.index].igniteNow();
          final pt = sim.portals[e.index];
          final pp = pt['pos'] as List<dynamic>;
          final px = (pp[0] as num).toDouble(), pz = (pp[2] as num).toDouble();
          final gy = (pt['groundY'] as num?)?.toDouble() ?? 0;
          final yaw = sim.spline.sample((pt['s'] as num).toDouble()).yaw;
          final rx = math.cos(yaw), rz = -math.sin(yaw);
          final crown = vm.Vector3(px, gy + 5.25, pz);
          if (e.index < world.archRigs.length) {
            final rig = world.archRigs[e.index];
            final o = rig.orangeColor, c = rig.cyanColor;
            _bounce?.push(px, pz, vm.Vector4(o.x, o.y, o.z, 1));
            _bounce?.push(px, pz, vm.Vector4(c.x, c.y, c.z, 1));
          }
          fx.spawnArc(hero, crown, 0.3);
          fx.spawnArc(vm.Vector3(px - rx * 5.6, gy + 4.4, pz - rz * 5.6), crown, 0.28);
          fx.spawnArc(vm.Vector3(px + rx * 5.6, gy + 4.4, pz + rz * 5.6), crown, 0.28);
          fx.sparkBurst(crown, 24, 1.45, 2.4, gy);
      }
    }
    sim.events.clear();
  }

  /// Boost-ring and pin-gate plasma tubes (the demo's unlit `aGlow`
  /// ShaderMaterials): dormant 0.72 / 0.16, flash to 2.2 / 1.85 on a hit,
  /// decaying at 3.5 / 3.8 per second to the lit 1.25 / 1.15.
  void _syncPlasma(double dt) {
    for (int i = 0; i < world.rings.length; i++) {
      final g = world.rings[i].glow;
      if (g.flash > 0) {
        g.flash = math.max(0, g.flash - dt * 3.5);
        g.glow = _lerp(1.25, 2.2, g.flash);
      } else {
        g.glow = sim.ringHit[i] ? 1.25 : 0.72;
      }
      final pulse = 0.88 + 0.12 * math.sin(_time * 5.2);
      final w = _clamp((g.glow - 1.1) * 0.65, 0, 0.85);
      final k = (1.25 + 2.4 * g.glow) * pulse;
      g.material.emissiveFactor = vm.Vector4(
          _lerp(g.color.x, 1.0, w) * k, _lerp(g.color.y, 0.99, w) * k, _lerp(g.color.z, 0.95, w) * k, 1);
    }
    for (int i = 0; i < world.pinGates.length; i++) {
      final g = world.pinGates[i];
      if (g.flash > 0) {
        g.flash = math.max(0, g.flash - dt * 3.8);
        g.glow = _lerp(1.15, 1.85, g.flash);
      } else {
        g.glow = sim.gateLit[i] ? 1.15 : 0.16;
      }
      g.lit = sim.gateLit[i];
      const fresnel = 0.3; // view-dependent rim term, averaged
      final t = _clamp((g.glow - 0.22) / 0.5, 0, 1);
      final litF = t * t * (3 - 2 * t);
      final dk = (0.28 + fresnel * 0.55) * g.glow;
      final pulse = 0.94 + 0.06 * math.sin(_time * 5.0);
      final w = _clamp((g.glow - 1.0) * 0.55 + (1 - fresnel) * 0.3, 0, 0.85);
      final k = (1.85 + 2.25 * g.glow) * pulse;
      g.material.emissiveFactor = vm.Vector4(
          _lerp(0.08 + g.color.x * dk, _lerp(g.color.x, 1.0, w) * k, litF),
          _lerp(0.12 + g.color.y * dk, _lerp(g.color.y, 0.98, w) * k, litF),
          _lerp(0.20 + g.color.z * dk, _lerp(g.color.z, 0.92, w) * k, litF),
          1);
    }
  }

  /// The demo's callback -> `ShibuyaAudioEngine` wiring.
  void _playEventSound(SimEvent e) {
    final a = soundFx;
    switch (e.kind) {
      case 'jump':
        a.play('jump');
      case 'land':
        a.play(e.value > 0.6 ? 'land_heavy' : 'land_light');
      case 'slide':
        a.play('slide');
      case 'laneChange':
        a.play(e.value < 0 ? 'lane_left' : 'lane_right');
      case 'stumble':
        a.play('stumble');
      case 'driftNearMiss':
        a.play('drift_whoosh');
      case 'nearMiss':
        a.play('near_miss');
      case 'mapsExtrude':
        a.play('maps_swell');
      case 'boostRing':
        a.play('boost_ring');
      case 'transfer':
        a.play('transfer');
      case 'pinGate':
        a.play('pin_ignition');
      case 'signIgnite':
        a.play('electric_arc');
      case 'googleLetter':
        a.play('letter_${e.index.clamp(0, 5)}');
      case 'roofVault':
        a.play('roof_vault');
      case 'carDeflect':
        a.play('car_horn');
      case 'neonSlide':
        a.play('neon_arch');
      case 'skyDropLand':
        a.play('touchdown');
      case 'routeComplete':
        a.play('finale');
    }
  }

  int _lastPillId = -1;
  bool _firstPill = true;

  void _syncAudio() {
    final a = soundFx;
    final playing = state.phase == AppPhase.playing && !state.photoMode;
    if (playing && sim.move == SimMove.railGrind) {
      a.setRailGrind(true, _clamp(sim.speed / 38, 0.25, 1));
    } else {
      a.setRailGrind(false);
    }
    a.updateOverchargeWind(playing && sim.move != SimMove.finaleOrbit ? sim.speed : 0);
    a.skyDropWind(state.phase == AppPhase.skyDrop && !state.photoMode
        ? _clamp(sim.dropClock / 3.5, 0, 1)
        : -1);
    final pill = state.streetPill;
    if (pill != null && pill.id != _lastPillId) {
      _lastPillId = pill.id;
      if (!_firstPill) a.play('street_chime');
      _firstPill = false;
    }
  }

  void _syncFx(double dt) {
    final f = _fxf;
    final playing = state.phase == AppPhase.playing;
    f
      ..time = _time
      ..mapsMorph = _mapsMorph
      ..heroX = sim.x
      ..heroY = sim.y
      ..heroZ = sim.z
      ..heroYaw = sim.yaw
      ..groundY = sim.groundY
      ..speed = sim.speed
      ..overcharge = state.overchargeRatio
      ..skyDrop = sim.move == SimMove.skyDrop
      ..finale = sim.move == SimMove.finaleOrbit
      ..railGrind = sim.move == SimMove.railGrind
      ..wallRun = sim.move == SimMove.wallRun
      ..heroVisible = pegman.root.visible || panda.root.visible
      ..rainVisible = state.phase != AppPhase.mapsTitle && state.phase != AppPhase.loading
      ..camX = camPos.x
      ..camY = camPos.y
      ..camZ = camPos.z
      ..pixelSize = 2 * math.tan(camFov * vm.degrees2Radians / 2) / 720
      ..driftCars = [for (final c in sim.drift) (x: c.x, y: 0.0, z: c.z, yaw: c.yaw)];
    final pose = _pose;
    f.sparksActive = pose?.sparksActive ?? false;
    final co = math.cos(sim.yaw), si = math.sin(sim.yaw);
    final an = pose?.sparksAnchorLocal ?? const [0.0, 0.08, 0.0];
    f
      ..sparkX = sim.x + an[0] * co + an[2] * si
      ..sparkY = sim.y + an[1]
      ..sparkZ = sim.z - an[0] * si + an[2] * co;
    fx.update(dt, f);
    // _computeEffectiveSpeedLinesFactor
    double sl = 0;
    if (!state.photoMode && playing && f.speed >= 34.72 &&
        sim.move != SimMove.finaleOrbit && sim.move != SimMove.skyDrop) {
      final i = _clamp((f.speed - 34.72) / 10.5, 0, 1);
      final r = f.overcharge;
      final a = r > 0.15 ? _clamp((r - 0.15) / 0.85, 0, 1) : 0.0;
      sl = _clamp(math.max(i * 0.42, a), 0, 1);
    }
    speedLinesFactor = sl;
  }

  // ------------------------------------------------------------- camera
  void _spring(vm.Vector3 pos, vm.Vector3 vel, vm.Vector3 target, double dt) {
    const w = 13.5, zeta = 0.94;
    final n = 1 + 2 * zeta * w * dt;
    final r = w * w * dt;
    final i = dt * r;
    final inv = 1 / (n + i);
    for (int k = 0; k < 3; k++) {
      final x = (n * pos[k] + dt * vel[k] + i * target[k]) * inv;
      vel[k] = (vel[k] + r * (target[k] - x)) / n;
      pos[k] = x;
    }
  }

  static double _qs(double x) {
    final q = _clamp(x, 0, 1);
    return q * q * q * (q * (6 * q - 15) + 10);
  }

  static double _sStep(double e0, double e1, double x) {
    final q = _clamp((x - e0) / (e1 - e0), 0, 1);
    return q * q * (3 - 2 * q);
  }

  void _computeCamera(double dt) {
    final h = sim;
    final t = _time;
    final shake = sim.trauma * sim.trauma;
    final sx = math.sin(t * 37.1) * 0.42 * shake;
    final sy = math.sin(t * 41.7 + 1.3) * 0.34 * shake;
    final shakeRoll = math.sin(t * 29.3 + 0.7) * 0.048 * shake;

    if (state.photoMode) {
      _photoCamera();
      return;
    }
    if (state.phase == AppPhase.loading || state.phase == AppPhase.mapsTitle) {
      camPos.setValues(68, 435, 68);
      camTarget.setValues(68, 0, 68);
      camUp = vm.Vector3(0, 0, -1);
      camFov = 54;
      camRoll = 0;
      _springPos.setFrom(camPos);
      _springTgt.setFrom(camTarget);
      _camInit = true;
      return;
    }
    if (state.phase == AppPhase.finale) {
      final r = sim.rooftop;
      final face = ((level.meta['googleTower'] as Map<String, dynamic>)['facingYaw'] as num)
          .toDouble();
      final a = face + math.sin(t * 0.28) * 0.34;
      final o = 15.5 + math.cos(t * 0.28) * 1.4;
      final yy = r.y + 2.8 + math.sin(t * 0.42) * 0.45;
      sim.yaw = face + math.sin(t * 0.28) * 0.16;
      camPos.setValues(r.x + math.sin(a) * o + sx, yy + sy, r.z + math.cos(a) * o);
      camTarget.setValues(
          r.x - math.sin(face) * 1.2, r.y + 2.15, r.z - math.cos(face) * 1.2);
      camFov = 52;
      camRoll = shakeRoll;
      camUp = vm.Vector3(0, 1, 0);
      return;
    }
    final now = sim.spline.sample(h.s);
    final c = _clamp((h.speed - 22) / 22, 0, 1);
    final l = _lerp(4.5, 5.4, c);
    final u = h.move == SimMove.slide
        ? 1.56
        : (h.activeTransfer >= 0 ? 2.28 : _lerp(2.05, 2.38, c));
    final d = _lerp(13, 20, c);
    final f = sim.spline.sample(h.s + d);
    var px = h.x - now.tx * l + now.rx * (h.lateral * -0.18);
    var py = h.y + u;
    var pz = h.z - now.tz * l + now.rz * (h.lateral * -0.18);
    var gx = f.x + f.rx * (h.lateral * 0.42);
    var gy = h.y + _clamp((f.y - h.y) * 0.35, -1.4, 1.1) + 1.92;
    var gz = f.z + f.rz * (h.lateral * 0.42);
    var fov = 58 + c * 18;
    if (h.activeRail >= 0 || h.activeWall >= 0 || h.activeTransfer >= 0) {
      fov = math.max(fov, 70 + state.overchargeRatio * 8);
    }
    if (state.overchargeRatio > 0.05) {
      fov = math.max(fov, _lerp(68, 78, state.overchargeRatio));
    }
    fov = _clamp(fov, 56, 78);
    final launch = level.route['heroGoogleLaunch'] as Map<String, dynamic>;
    final trig = (launch['triggerS'] as num).toDouble();
    final fly = _sStep(trig - 8, trig + 14, h.s) *
        (1 - _sStep(sim.spline.length - 12, sim.spline.length + 2, h.s));
    if (fly > 0.001) {
      final sc = (level.meta['googleTower'] as Map<String, dynamic>)['signCenter']
          as List<dynamic>;
      px += now.rx * (-3.4 * fly) - now.tx * (1.8 * fly);
      py += -0.35 * fly;
      pz += now.rz * (-3.4 * fly) - now.tz * (1.8 * fly);
      gx = _lerp(gx, (sc[0] as num).toDouble(), 0.5 * fly);
      gy = _lerp(gy, (sc[1] as num).toDouble() + 3.2, 0.5 * fly);
      gz = _lerp(gz, (sc[2] as num).toDouble(), 0.5 * fly);
      fov = _lerp(fov, 68, fly * 0.65);
    }

    final w = sim.dropClock;
    if (state.phase == AppPhase.skyDrop || w < 3.5) {
      double nx, ny, nz, ox, oy, oz, upY = 1, upZ = 0, fv = 60;
      if (w < 0.9) {
        final e = _qs(w / 0.9);
        nx = _lerp(68, h.x - now.tx * 9.5, e);
        ny = _lerp(435, 285, e);
        nz = _lerp(68, h.z - now.tz * 9.5, e);
        ox = _lerp(68, h.x + now.tx * 12, e);
        oy = _lerp(0, math.max(0, h.y - 45), e);
        oz = _lerp(68, h.z + now.tz * 12, e);
        final p = e, m = e - 1;
        final hh = math.max(1e-4, math.sqrt(p * p + m * m));
        upY = p / hh;
        upZ = m / hh;
        fv = _lerp(54, 66, e);
      } else if (w < 3.05) {
        final e = _clamp((w - 0.9) / 2.15, 0, 1);
        final dd = _qs(e);
        final back = _lerp(9.5, l + 1.1, dd);
        final up = _lerp(13, u + 1.6, dd);
        nx = h.x - now.tx * back;
        ny = h.y + up;
        nz = h.z - now.tz * back;
        final m = _qs(_clamp((e - 0.65) / 0.35, 0, 1));
        final hx = h.x + now.tx * _lerp(12, 10, dd);
        final hy = math.max(0.5, h.y - _lerp(45, 1.5, dd));
        final hz = h.z + now.tz * _lerp(12, 10, dd);
        ox = _lerp(hx, gx, m);
        oy = _lerp(hy, gy, m);
        oz = _lerp(hz, gz, m);
        fv = _lerp(66, 74, math.sin(e * math.pi));
      } else {
        final e = _qs(_clamp((w - 3.05) / 0.45, 0, 1));
        nx = _lerp(h.x - now.tx * (l + 1.1), px, e);
        ny = _lerp(h.y + u + 1.6, py, e);
        nz = _lerp(h.z - now.tz * (l + 1.1), pz, e);
        ox = _lerp(h.x + now.tx * 10, gx, e);
        oy = _lerp(h.y + 1.1, gy, e);
        oz = _lerp(h.z + now.tz * 10, gz, e);
        fv = _lerp(66, fov, e);
      }
      final inv = 1 / math.max(dt, 1e-4);
      if (_camInit) {
        _springVel.setValues((nx - _springPos.x) * inv,
            (ny - _springPos.y) * inv, (nz - _springPos.z) * inv);
        _springTgtVel.setValues((ox - _springTgt.x) * inv,
            (oy - _springTgt.y) * inv, (oz - _springTgt.z) * inv);
      }
      _springPos.setValues(nx, ny, nz);
      _springTgt.setValues(ox, oy, oz);
      // _applyCameraFromSnapshot: ease out of the title camera
      // (50, 515, 114) over the first 30% of the drop.
      final tt = 1 - _sStep(0, 0.3, _clamp(w / 3.5, 0, 1));
      if (tt > 1e-4) {
        nx += (50 - 68) * tt;
        ny += (515 - 435) * tt;
        nz += 46 * tt;
        ox += (50 - 68) * tt;
        oz += 46 * tt;
      }
      camPos.setValues(nx + sx, ny + sy, nz);
      camTarget.setValues(ox, oy, oz);
      camFov = fv;
      camRoll = shakeRoll;
      camUp = vm.Vector3(0, upY, upZ);
      _camInit = true;
      return;
    }
    if (!_camInit) {
      _springPos.setValues(px, py, pz);
      _springTgt.setValues(gx, gy, gz);
      _camInit = true;
    } else {
      _spring(_springPos, _springVel, vm.Vector3(px, py, pz), dt);
      _spring(_springTgt, _springTgtVel, vm.Vector3(gx, gy, gz), dt);
    }
    final bob = 0.022 * math.sin(t * 2.1);
    camPos.setValues(_springPos.x + sx, _springPos.y + bob + sy, _springPos.z);
    camTarget.setFrom(_springTgt);
    camFov = _lerp(camFov, fov, 0.14);
    camRoll = _lerp(camRoll, -sim.bank * 0.24 + shakeRoll, 0.18);
    camUp = vm.Vector3(0, 1, 0);
  }

  (vm.Vector3, vm.Vector3, double) _presetCamera(PhotoPreset p) {
    switch (p) {
      case PhotoPreset.scramble:
        return (vm.Vector3(-72, 26, 22), vm.Vector3(-10, 4.5, -18), 54);
      case PhotoPreset.skyline:
        final gt = level.meta['googleTower'] as Map<String, dynamic>;
        final e = gt['signCenter'] as List<dynamic>;
        final yaw = (gt['facingYaw'] as num).toDouble();
        return (
          vm.Vector3((e[0] as num).toDouble() + math.sin(yaw - 0.12) * 38, 29,
              (e[2] as num).toDouble() + math.cos(yaw - 0.12) * 38),
          vm.Vector3(253, 24.5, 236),
          54
        );
      case PhotoPreset.hero:
        final n = sim.yaw + 0.62;
        return (
          vm.Vector3(sim.x - math.sin(n) * 4.4, sim.y + 1.85, sim.z - math.cos(n) * 4.4),
          vm.Vector3(sim.x, sim.y + 1.15, sim.z),
          50
        );
    }
  }

  void _photoCamera() {
    final p = state.photoPreset;
    if (_poPreset != p) {
      _setPhotoGoal(p, _poPreset == null);
      _poPreset = p;
    }
    const e = 0.16;
    final l = _photoLimits[p]!;
    var r = _goYaw - _poYaw;
    while (r > math.pi) {
      r -= 2 * math.pi;
    }
    while (r < -math.pi) {
      r += 2 * math.pi;
    }
    _poYaw += r * e;
    _poPitch = _clamp(_lerp(_poPitch, _goPitch, e), l[2], l[3]);
    _poRadius = _clamp(_lerp(_poRadius, _goRadius, e), l[0], l[1]);
    _poFov = _lerp(_poFov, _goFov, e);
    _poTarget.setFrom(_poTarget + (_goTarget - _poTarget) * e);
    final cp = math.cos(_poPitch);
    final a = _poTarget.x + _poRadius * cp * math.sin(_poYaw);
    final o = math.max(1.4, _poTarget.y + _poRadius * math.sin(_poPitch));
    final s = _poTarget.z + _poRadius * cp * math.cos(_poYaw);
    camPos.setFrom(_safePhotoPos(_poTarget, vm.Vector3(a, o, s)));
    camTarget.setFrom(_poTarget);
    camFov = _poFov;
    camUp = vm.Vector3(0, 1, 0);
    camRoll = 0;
  }

  /// `_resolveSafePhotoCameraPos`: pull the camera in front of buildings
  /// between it and the target, then push it out of any it sits inside.
  vm.Vector3 _safePhotoPos(vm.Vector3 t, vm.Vector3 want) {
    final cols = world.photoColliders;
    var o = want.x, sy = math.max(1.4, want.y), c = want.z;
    final dx = o - t.x, dy = sy - t.y, dz = c - t.z;
    final p = math.sqrt(dx * dx + dy * dy + dz * dz);
    if (p > 0.05) {
      final ix = dx / p, iy = dy / p, iz = dz / p;
      var h = p;
      const g = 1.45, gy = 0.65;
      for (final b in cols) {
        final hit = _rayBox(t.x, t.y, t.z, ix, iy, iz, h, b[0] - g, b[2] - gy, b[4] - g,
            b[1] + g, b[3] + gy, b[5] + g);
        if (hit != null) {
          if (hit.$1 > 0.12) {
            final e = math.max(2.6, hit.$1 - 0.55);
            if (e < h) h = e;
          } else if (hit.$2 > 0.12 && h <= hit.$2) {
            final e = math.max(2.6, math.min(h, 3.0));
            if (e < h) h = e;
          }
        }
      }
      if (h < p) {
        o = t.x + ix * h;
        sy = math.max(1.4, t.y + iy * h);
        c = t.z + iz * h;
      }
    }
    const m = 1.35, hh = 0.55;
    for (int it = 0; it < 3; it++) {
      var moved = false;
      for (final b in cols) {
        final r0 = b[0] - m, i0 = b[1] + m, a0 = b[2] - hh, u0 = b[3] + hh, d0 = b[4] - m, f0 = b[5] + m;
        if (o > r0 && o < i0 && sy > a0 && sy < u0 && c > d0 && c < f0) {
          final tl = o - r0, ar = i0 - o, lz = c - d0, pz = f0 - c, my = u0 - sy;
          if (b[3] <= 25 && my <= 4.8) {
            sy = u0 + 0.55;
          } else {
            final e = [tl, ar, lz, pz].reduce(math.min);
            if (my < e && b[3] <= 40) {
              sy = u0 + 0.55;
            } else if (e == tl) {
              o = r0 - 0.15;
            } else if (e == ar) {
              o = i0 + 0.15;
            } else if (e == lz) {
              c = d0 - 0.15;
            } else {
              c = f0 + 0.15;
            }
          }
          sy = math.max(1.4, sy);
          moved = true;
        }
      }
      if (!moved) break;
    }
    return vm.Vector3(o, sy, c);
  }

  (double, double)? _rayBox(double ox, double oy, double oz, double dx, double dy, double dz,
      double maxT, double x0, double y0, double z0, double x1, double y1, double z1) {
    var tmin = -double.infinity, tmax = double.infinity;
    for (final (o, d, lo, hi) in [(ox, dx, x0, x1), (oy, dy, y0, y1), (oz, dz, z0, z1)]) {
      if (d.abs() > 1e-7) {
        var a = (lo - o) / d, b = (hi - o) / d;
        if (a > b) {
          final t = a;
          a = b;
          b = t;
        }
        if (a > tmin) tmin = a;
        if (b < tmax) tmax = b;
      } else if (o < lo || o > hi) {
        return null;
      }
    }
    if (tmax < math.max(0, tmin) || tmin > maxT) return null;
    return (tmin, tmax);
  }

  fs.Camera buildCamera(Duration elapsed) {
    final pos = w3(camPos.x, camPos.y, camPos.z);
    final tgt = w3(camTarget.x, camTarget.y, camTarget.z);
    var up = vm.Vector3(camUp.x, camUp.y, -camUp.z);
    if (camRoll.abs() > 1e-4) {
      final fwd = (tgt - pos).normalized();
      up = vm.Quaternion.axisAngle(fwd, camRoll).rotated(up);
    }
    return fs.PerspectiveCamera(
      fovRadiansY: camFov * vm.degrees2Radians,
      position: pos,
      target: tgt,
      up: up,
      fovNear: 0.15,
      fovFar: 2500,
    );
  }

  void dispose() {
    _taxiNodes.clear();
    _driftNodes.clear();
    _parked.clear();
    _carShadows.clear();
    _underglows.clear();
    _trains.clear();
  }
}

class _Train {
  _Train(this.path, this.cars, this.distance, this.dir) : vel = 8.2 * dir;
  final Polyline3 path;
  final List<fs.Node> cars;
  double distance;
  double dir;
  double vel;
}
