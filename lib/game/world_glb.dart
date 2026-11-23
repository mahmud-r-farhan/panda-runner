import 'dart:math' as math;

import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;

import 'aokanban.dart';
import 'glb_library.dart';
import 'level_data.dart';
import 'media_screen.dart';
import 'mesh_buf.dart';
import 'neon_arch.dart';
import 'world_builder.dart';
import 'world_textures.dart';

double _d(dynamic v, [double fb = 0]) => (v as num?)?.toDouble() ?? fb;

const _signTexts = ['NEON', 'NEON SCRAMBLE', 'ネオン', 'ネオンスクランブル', 'ネオン・スクランブル'];
const _signPalette = ['#FF4F00', '#4285F4', '#EA4335', '#FBBC05', '#34A853', '#38BDF8'];

/// A neon blade sign or wall billboard that ignites as Pegman approaches
/// (`routeS - heroS <= 38`, glow 1.46 flash → 1.08; dormant glow 0.08).
class NeonSign {
  NeonSign(this.routeS, this.material, this.neon, this.pos);
  final double routeS;
  /// Record position (`pos`), the ground-bounce light origin.
  final vm.Vector3 pos;
  final fs.PhysicallyBasedMaterial material;
  final vm.Vector4 neon;
  bool lit = false;
  double flash = 0;
  double glow = 0.08;

  void apply(double time, int index) {
    final litF = ((glow - 0.14) / 0.48).clamp(0.0, 1.0);
    final f = 0.95 + 0.05 * math.sin(time * 7 + index * 2.1);
    // lit glyph = mix(neon, white, 0.4) * (1.2 + 1.4 glow); dormant ≈ 0.06.
    final k = (1.2 + 1.4 * glow) * f * 0.6;
    final lr = (neon.x * 0.75 + 0.25 * neon.x.clamp(0.0, 1.0)) * k,
        lg = (neon.y * 0.75 + 0.25 * neon.y.clamp(0.0, 1.0)) * k,
        lb = (neon.z * 0.75 + 0.25 * neon.z.clamp(0.0, 1.0)) * k;
    const d = [0.055, 0.081, 0.133];
    material.emissiveFactor = vm.Vector4(d[0] + (lr - d[0]) * litF,
        d[1] + (lg - d[1]) * litF, d[2] + (lb - d[2]) * litF, 1);
  }
}

/// Places the demo's glTF models exactly like its `_attach*` / `_build*`
/// functions (positions, yaw offsets, scales), in the reference frame under
/// [ShibuyaWorld.refRoot].
class GlbWorld {
  GlbWorld(this.world, this.lib);

  final ShibuyaWorld world;
  final GlbLibrary lib;
  ShibuyaLevel get level => world.level;
  fs.Node get ref => world.refRoot;

  /// Rooftop target centre derived from `Podium_PinBeaconRing` (y ≥ 20).
  vm.Vector3 rooftop = vm.Vector3(242.89, 22, 257.3);
  MediaScreen? media;
  final List<NeonSign> signs = [];

  /// Photo colliders for the glTF landmarks (`_photoColliders` pushes in
  /// `_attachHeroArchitecture`): [minX,maxX,minY,maxY,minZ,maxZ].
  final List<List<double>> colliders = [];

  void _boxCollider(double x, double z, double yaw, double hx, double hz, double y0, double y1) {
    final c = math.cos(yaw).abs(), sn = math.sin(yaw).abs();
    final ex = c * hx + sn * hz, ez = sn * hx + c * hz;
    colliders.add([x - ex, x + ex, y0, y1, z - ez, z + ez]);
  }

  void build() {
    _googleTower();
    _heroArchitecture();
    _streetProps();
    _pinGates();
    _boostRings();
    _slideArches();
  }

  (List<dynamic>, List<vm.Matrix4>)? _signFaces;

  /// Per-sign aokanban faces with their own text texture (`Ag` atlas).
  Future<void> buildSignFaces() async {
    final sf = _signFaces;
    final t = GlbLibrary.template(lib.props, 'AoKanbanSign');
    if (sf == null || t == null) return;
    final face = GlbLibrary.meshNodes(t).where((e) => e.$1.name == 'AoKanban_SignFace').toList();
    if (face.isEmpty) return;
    final (node, rel) = face.first;
    for (int i = 0; i < sf.$1.length && i < sf.$2.length; i++) {
      final tex = await AoKanbanFace.create(sf.$1[i] as Map<String, dynamic>);
      final m = fs.PhysicallyBasedMaterial(baseColorTexture: tex, emissiveTexture: tex)
        ..baseColorFactor = vm.Vector4(1, 1, 1, 1)
        ..emissiveFactor = vm.Vector4(0.78, 0.78, 0.78, 1)
        ..roughnessFactor = 0.36
        ..metallicFactor = 0.08
        ..doubleSided = true;
      for (final prim in node.mesh!.primitives) {
        ref.add(fs.Node(name: 'AoKanbanFace_$i', mesh: fs.Mesh(prim.geometry, m))
          ..localTransform = sf.$2[i] * rel);
      }
    }
  }

  /// Kanji blade signs + NeonBillboardTall/Wide wall billboards
  /// (`_attachKanjiBladeSigns` / `_attachWallBillboards`).
  Future<void> buildSigns() async {
    final props = level.route['streetProps'] as Map<String, dynamic>;
    final hosts = <String, Map<String, dynamic>>{
      for (final b in ((level.meta['heroArchSlots'] as Map<String, dynamic>)['shopfrontBlocks']
              as List<dynamic>? ??
          const []))
        b['id'] as String: b as Map<String, dynamic>,
    };
    String textFor(dynamic t, int i) =>
        _signTexts.contains(t) ? t as String : _signTexts[i % _signTexts.length];
    fs.PhysicallyBasedMaterial signMat(fs.Texture2D tex) => fs.PhysicallyBasedMaterial(
          emissiveTexture: tex,
        )
          ..baseColorFactor = vm.Vector4(0.032, 0.048, 0.088, 1)
          ..roughnessFactor = 0.3
          ..metallicFactor = 0.1
          ..doubleSided = true;

    // Unit blade box (0.24 x 1 x 1) with the glyph on the ±X faces.
    final blade = MeshBuf();
    vm.Vector3 v(double x, double y, double z) => vm.Vector3(x, y, z);
    blade.quad(v(0.12, -0.5, 0.5), v(0.12, -0.5, -0.5), v(0.12, 0.5, -0.5), v(0.12, 0.5, 0.5),
        v(1, 0, 0), u0: 0, u1: 1, v0: 1, v1: 0);
    blade.quad(v(-0.12, -0.5, -0.5), v(-0.12, -0.5, 0.5), v(-0.12, 0.5, 0.5), v(-0.12, 0.5, -0.5),
        v(-1, 0, 0), u0: 0, u1: 1, v0: 1, v1: 0);
    for (final sz in [-0.5, 0.5]) {
      blade.quad(v(-0.12, -0.5, sz), v(0.12, -0.5, sz), v(0.12, 0.5, sz), v(-0.12, 0.5, sz),
          v(0, 0, sz * 2), u0: 0.01, u1: 0.02, v0: 0.01, v1: 0.02);
    }
    blade.quad(v(-0.12, 0.5, -0.5), v(0.12, 0.5, -0.5), v(0.12, 0.5, 0.5), v(-0.12, 0.5, 0.5),
        v(0, 1, 0), u0: 0.01, u1: 0.02, v0: 0.01, v1: 0.02);
    final bladeGeo = blade.build();
    final bracketBuf = MeshBuf();

    final blades = props['bladeSigns'] as List<dynamic>;
    for (int r = 0; r < blades.length; r++) {
      final t = blades[r] as Map<String, dynamic>;
      final a = _d(t['height'], 6.4).clamp(4.0, 9.6);
      final u = _d(t['width'], 1.4).clamp(1.0, 1.8);
      final d = (t['wallPoint'] ?? t['pos']) as List<dynamic>;
      final f = t['wallNormal'] as List<dynamic>? ??
          [math.sin(_d(t['yaw'])), 0, math.cos(_d(t['yaw']))];
      final nx = _d(f[0]), nz = _d(f[2]);
      final p = math.atan2(nx, nz);
      var m = 0.16;
      final h = hosts[t['hostId']];
      if (h != null) {
        if (h['nodeName'] == 'ShibuyaShopfrontBlockA') {
          final hp = h['pos'] as List<dynamic>;
          final e = _d(d[0]) - _d(hp[0]), z = _d(d[2]) - _d(hp[2]);
          m = e * math.cos(_d(h['yaw'])) - z * math.sin(_d(h['yaw'])) < 0 ? 1.24 : 0.16;
        } else {
          m = 0.8;
        }
      }
      final g = switch (t['id']) {
        'blade_46' => 24.4,
        'blade_47' => 22.8,
        'blade_74' => 43.3,
        _ => _d(d[1]),
      };
      final y = m + u * 0.5;
      final text = textFor(t['text'], r);
      final color = hexColor((t['accent'] as String?) ?? _signPalette[r % _signPalette.length]);
      final mat = signMat(await WorldTextures.bladeSign(text));
      ref.add(fs.Node(name: t['id'] as String? ?? 'blade', mesh: fs.Mesh(bladeGeo, mat))
        ..localTransform = GlbLibrary.slot(_d(d[0]) + nx * y, g, _d(d[2]) + nz * y, p,
            vm.Vector3(1, a, u)));
      // wall brackets
      final cy = math.cos(p), sy = math.sin(p);
      for (final e in [-1.0, 1.0]) {
        final len = m + 0.354;
        final off = -0.35 + len * 0.5;
        final lx = 0.0, lz = off;
        bracketBuf.box(vm.Vector3(_d(d[0]) + lx * cy + lz * sy, g + e * a * 0.34, _d(d[2]) - lx * sy + lz * cy),
            vm.Vector3(0.12, 0.14, len), p);
      }
      final s = NeonSign(_d(t['routeS'], _d(t['s'])), mat, color,
          vm.Vector3(_d(d[0]) + nx * y, g, _d(d[2]) + nz * y));
      s.apply(0, r);
      signs.add(s);
    }

    final bills = props['wallBillboards'] as List<dynamic>;
    int wideIdx = 0, tallIdx = 0;
    for (final t0 in bills) {
      final t = t0 as Map<String, dynamic>;
      final tall = t['nodeName'] == 'NeonBillboardTall';
      final e = tall ? tallIdx++ : wideIdx++;
      final tpl = GlbLibrary.template(lib.arch, tall ? 'NeonBillboardTall' : 'NeonBillboardWide');
      if (tpl == null) continue;
      final aW = tall ? 4.34 : 12.08, oH = tall ? 11.5 : 5.2;
      final r = (t['wallPoint'] ?? t['pos']) as List<dynamic>;
      final c = t['wallNormal'] as List<dynamic>? ??
          [math.sin(_d(t['yaw'])), 0, math.cos(_d(t['yaw']))];
      final l = math.atan2(_d(c[0]), _d(c[2]));
      final u = _d(t['width'], aW).clamp(2.5, 16.0);
      final d = _d(t['height'], oH).clamp(3.0, 14.0);
      final h = hosts[t['hostId']];
      final b = h == null ? 0.0 : (h['nodeName'] == 'ShibuyaShopfrontBlockA' ? 0.72 : 1.12);
      final sY = t['id'] == 'billboard_29' ? 22.6 : _d(r[1]);
      final x = t['id'] == 'billboard_40' ? 0.32 : 1.0;
      tpl.localTransform = GlbLibrary.slot(_d(r[0]) + _d(c[0]) * b, sY - d * 0.5,
          _d(r[2]) + _d(c[2]) * b, l, vm.Vector3(u / aW, d / oH, x));
      final text = textFor(t['text'], e);
      final tex = tall
          ? await WorldTextures.tallBillboard(text)
          : await WorldTextures.wideBillboard(text, e);
      final mat = signMat(tex);
      final screen = tpl.getChildByName(tall ? 'NeonBillboardTall_ScreenSurface' : 'NeonBillboardWide_ScreenSurface');
      if (screen?.mesh != null) {
        for (final p in screen!.mesh!.primitives) {
          p.material = mat;
        }
      }
      ref.add(tpl);
      final color = hexColor((t['accent'] as String?) ??
          _signPalette[(e + (tall ? 2 : 0)) % _signPalette.length]);
      final tt = b + (tall ? 0.73 : 0.76) * x;
      final s = NeonSign(_d(t['routeS'], _d(t['s'])), mat, color,
          vm.Vector3(_d(r[0]) + _d(c[0]) * tt, sY, _d(r[2]) + _d(c[2]) * tt));
      s.apply(0, e);
      signs.add(s);
    }
    if (!bracketBuf.isEmpty) {
      ref.add(fs.Node(
          name: 'KanjiBladeBrackets',
          mesh: fs.Mesh(bracketBuf.build(), pbr(hexColor('#1B2434'), roughness: 0.48, metallic: 0.74))));
    }
  }

  /// Per-frame sign ignition (port of the demo's glow update loop).
  ///
  /// Returns the signs that ignited this frame within 18 m behind .. 38 m
  /// ahead (the demo's `_pushSignLight(e.pos, e.color)` condition).
  List<NeonSign> updateSigns(double heroS, double dt, double time,
      {bool finale = false, bool reset = false}) {
    final ignited = <NeonSign>[];
    for (int i = 0; i < signs.length; i++) {
      final e = signs[i];
      final n = e.routeS - heroS;
      if (finale) {
        e.lit = true;
        e.flash = 0;
        e.glow = 1.15;
      } else if (reset && n > 38) {
        e.lit = false;
        e.flash = 0;
        e.glow = 0.08;
      } else if (n <= 38) {
        if (e.lit) {
          if (e.flash > 0) {
            e.flash = math.max(0, e.flash - dt * 3.8);
            e.glow = 1.08 + (1.46 - 1.08) * e.flash;
          } else if (e.glow < 1.05) {
            e.glow = 1.08;
          }
        } else {
          e.lit = true;
          e.flash = 1;
          e.glow = 1.46;
          if (n > -18) ignited.add(e);
        }
      }
      e.apply(time, i);
    }
    return ignited;
  }

  bool _inScramblePlaza(double x, double z) => world.inScramblePlaza(x, z);


  // ------------------------------------------------ Google Stream tower
  void _googleTower() {
    final slot = (level.meta['heroArchSlots'] as Map<String, dynamic>)['googleStreamTower']
        as Map<String, dynamic>;
    final t = GlbLibrary.template(lib.googleTower, 'GoogleStreamTower');
    if (t == null) return;
    final r = _d(slot['yaw'], 2.68);
    final pos = slot['pos'] as List<dynamic>;
    final x = _d(pos[0]) - math.sin(r) * 29, z = _d(pos[2]) - math.cos(r) * 29;
    t.localTransform = GlbLibrary.slot(x, 0, z, r);
    // Rooftop centre from the pin beacon ring (local bbox centre (0, 22, 10.8)).
    rooftop = vm.Vector3(x + 10.8 * math.sin(r), 22, z + 10.8 * math.cos(r));

    // Per-letter materials so each of the six letters ignites on its own.
    const order = ['G', 'o1', 'o2', 'g', 'l', 'e'];
    // igniteGoogleLetter colours (more saturated than the brand palette).
    const colors = ['#1064FF', '#EE1F19', '#FFB300', '#1064FF', '#16A34A', '#EE1F19'];
    for (int i = 0; i < 6; i++) {
      for (final prefix in ['NeonLetter_', 'Core_']) {
        final n = t.getChildByName('$prefix${order[i]}');
        if (n == null) continue;
        for (final (mn, _) in GlbLibrary.meshNodes(n)) {
          for (final p in mn.mesh!.primitives) {
            final m = GlbLibrary.clonePbr(p.material);
            final core = prefix == 'Core_';
            m.baseColorFactor = core ? hexColor('#1C273B') : hexColor(colors[i], 1, 0.32);
            if (!core) m.alphaMode = fs.AlphaMode.blend;
            m.emissiveStrength = 1;
            m.emissiveFactor = hexColor(colors[i], core ? 0.14 : 0.08);
            p.material = m;
            world.googleLetters.add(GlowProp(m, hexColor(colors[i]), litScale: 1.0, letterIndex: i, core: core));
          }
        }
      }
    }
    final ring = t.getChildByName('Podium_PinBeaconRing');
    if (ring != null && ring.mesh != null) {
      final m = GlbLibrary.clonePbr(ring.mesh!.primitives.first.material);
      for (final p in ring.mesh!.primitives) {
        p.material = m;
      }
      world.beaconMat = m;
    }
    ref.add(t);
  }

  // --------------------------------------------- hero architecture (arch)
  void _heroArchitecture() {
    final slots = level.meta['heroArchSlots'] as Map<String, dynamic>;
    void place(String node, Map<String, dynamic>? s) {
      if (s == null) return;
      final t = GlbLibrary.template(lib.arch, node);
      if (t == null) return;
      final p = s['pos'] as List<dynamic>;
      final sc = s['scale'] as List<dynamic>?;
      t.localTransform = GlbLibrary.slot(_d(p[0]), _d(p[1]), _d(p[2]), _d(s['yaw']),
          sc == null ? null : vm.Vector3(_d(sc[0], 1), _d(sc[1], 1), _d(sc[2], 1)));
      if (node == 'ScrambleMediaFacade') {
        final ms = t.getChildByName('MediaScreenSurface');
        if (ms?.mesh != null) {
          // MeshStandardMaterial(map = emissiveMap = media canvas, emissive 1.55)
          final m = fs.PhysicallyBasedMaterial()
            ..baseColorFactor = vm.Vector4(1, 1, 1, 1)
            ..emissiveFactor = vm.Vector4(1.55, 1.55, 1.55, 1)
            ..roughnessFactor = 0.16
            ..metallicFactor = 0.08
            ..doubleSided = true;
          for (final pr in ms!.mesh!.primitives) {
            pr.material = m;
          }
          media = MediaScreen(m);
        }
      }
      ref.add(t);
      // model bounding boxes (structure meshes) → photo colliders
      const bb = {
        'ScrambleCornerLandmark': [13.32, 11.3, 34.0],
        'Shibuya109Landmark': [12.5, 12.5, 34.0],
        'ScrambleMediaFacade': [15.62, 10.5, 42.06],
      };
      final b = bb[node]!;
      final sx = sc == null ? 1.0 : _d(sc[0], 1), sz = sc == null ? 1.0 : _d(sc[2], 1);
      _boxCollider(_d(p[0]), _d(p[2]), _d(s['yaw']), b[0] * sx, b[1] * sz, 0, b[2]);
    }

    place('ScrambleCornerLandmark', slots['scrambleCorner'] as Map<String, dynamic>?);
    place('Shibuya109Landmark', slots['shibuya109'] as Map<String, dynamic>?);
    place('ScrambleMediaFacade', slots['scrambleMediaFacade'] as Map<String, dynamic>?);

    List<vm.Matrix4> mats(List<dynamic> list, {double yawOffset = 0}) => [
          for (final s in list)
            GlbLibrary.slot(
                _d((s['pos'] as List)[0]),
                _d((s['pos'] as List)[1]),
                _d((s['pos'] as List)[2]),
                _d(s['yaw']) + yawOffset,
                s['scale'] is List
                    ? vm.Vector3(_d(s['scale'][0], 1), _d(s['scale'][1], 1), _d(s['scale'][2], 1))
                    : null),
        ];
    final bays = slots['yamanoteViaductBays'] as List<dynamic>? ?? const [];
    for (final t in bays) {
      final r = _d(t['yaw']);
      final sc = t['scale'] as List<dynamic>?;
      final o = 6.5 * (sc == null ? 1 : _d(sc[0], 1)), sl = 12.2 * (sc == null ? 1 : _d(sc[2], 1));
      final cx = math.cos(r).abs() * o + math.sin(r).abs() * sl;
      final lz = math.sin(r).abs() * o + math.cos(r).abs() * sl;
      final p = t['pos'] as List<dynamic>;
      colliders.add([_d(p[0]) - cx, _d(p[0]) + cx, 5.5, 8.6, _d(p[2]) - lz, _d(p[2]) + lz]);
    }
    for (final b in slots['shopfrontBlocks'] as List<dynamic>? ?? const []) {
      final a = b['nodeName'] == 'ShibuyaShopfrontBlockA';
      final hx = a ? (8.1 + 7.16) * 0.5 : (7.39 + 7.12) * 0.5;
      final hz = a ? (7.39 + 6.08) * 0.5 : (7.39 + 6.28) * 0.5;
      final h = a ? 25.98 : 32.04;
      final sc = b['scale'] as List<dynamic>?;
      final p = b['pos'] as List<dynamic>;
      _boxCollider(_d(p[0]), _d(p[2]), _d(b['yaw']),
          hx * (sc == null ? 1 : _d(sc[0], 1)), hz * (sc == null ? 1 : _d(sc[2], 1)), 0,
          math.max(12, h) * (sc == null ? 1 : _d(sc[1], 1)));
    }
    final bay = GlbLibrary.template(lib.arch, 'YamanoteViaductBay');
    if (bay != null) ref.add(GlbLibrary.instance(bay, mats(bays), name: 'YamanoteViaductBay'));
    final blocks = slots['shopfrontBlocks'] as List<dynamic>? ?? const [];
    for (final kind in ['ShibuyaShopfrontBlockA', 'ShibuyaShopfrontBlockB']) {
      final t = GlbLibrary.template(lib.arch, kind);
      if (t == null) continue;
      ref.add(GlbLibrary.instance(t, mats(blocks.where((b) => b['nodeName'] == kind).toList()),
          name: kind));
    }
  }

  // ----------------------------------------------------- street props
  List<vm.Matrix4> _groundSlots(List<dynamic> list, {double yawOffset = 0, bool roadSign = false}) {
    final out = <vm.Matrix4>[];
    for (final s in list) {
      final p = s['pos'] as List<dynamic>;
      var y = roadSign ? _d(s['groundY'], _d(p[1])) : _d(p[1]);
      final lift = roadSign
          ? (s['onViaduct'] != true && y < 0.3 && !_inScramblePlaza(_d(p[0]), _d(p[2])) && _d(s['lateral']) <= 11.4)
          : (y < 0.3 && !_inScramblePlaza(_d(p[0]), _d(p[2])));
      if (lift) y = 0.18;
      out.add(GlbLibrary.slot(_d(p[0]), y, _d(p[2]), _d(s['yaw']) + yawOffset));
    }
    return out;
  }

  void _streetProps() {
    final props = level.route['streetProps'] as Map<String, dynamic>;
    void inst(String node, List<vm.Matrix4> slots,
        {bool Function(String)? filter,
        fs.Material Function(String, fs.Material)? mat}) {
      final t = GlbLibrary.template(lib.props, node);
      if (t == null) return;
      ref.add(GlbLibrary.instance(t, slots, name: node, filter: filter, materialFor: mat));
    }

    fs.Material emissive(fs.Material m, String hex, double k) {
      final c = GlbLibrary.clonePbr(m)
        ..emissiveFactor = hexColor(hex, k)
        ..emissiveStrength = 1;
      return c;
    }

    inst('TrafficGantry', _groundSlots(props['trafficGantries'] as List, yawOffset: -math.pi / 2),
        mat: (n, m) => switch (n) {
              'Gantry_SignalGreen' => emissive(m, '#22C55E', 3.2),
              'Gantry_SignalAmber' => emissive(m, '#F59E0B', 0.35),
              'Gantry_SignalRed' => emissive(m, '#EF4444', 0.25),
              _ => m,
            });
    final signSlots = _groundSlots(props['roadSigns'] as List, roadSign: true);
    inst('AoKanbanSign', signSlots,
        filter: (n) => n != 'AoKanban_SignFace',
        mat: (n, m) => n == 'AoKanban_LampLens' ? emissive(m, '#FFF4DC', 3) : m);
    _signFaces = (props['roadSigns'] as List, signSlots);
    inst('PedestrianRail', _groundSlots(props['pedestrianRails'] as List, yawOffset: -math.pi / 2),
        filter: (n) => n == 'PedRail_PostsAndBars' || n == 'PedRail_TopHandrail');
    inst('StreetLampTokyo', _groundSlots(props['streetLamps'] as List, yawOffset: -math.pi / 2),
        mat: (n, m) => n == 'Lamp_LedLens' ? emissive(m, '#DCEEFF', 4.6) : m);

    // Vending alcoves / transformer poles along the kerbs (the demo's
    // waypoint-stepped placement, 9 m off the centreline).
    final wps = level.waypoints;
    final vend = <vm.Matrix4>[], poles = <vm.Matrix4>[];
    for (int e = 2; e < wps.length - 4; e += 4) {
      final t = wps[e];
      if (t.s < 46 || t.y > 0.3 || _inScramblePlaza(t.x, t.z)) continue;
      final n = wps[math.min(wps.length - 1, e + 1)];
      final rx = n.x - t.x, iz = n.z - t.z;
      final a = math.sqrt(rx * rx + iz * iz);
      if (a < 0.2) continue;
      final o = iz / a, s = -rx / a;
      final c = e % 8 == 2 ? 1.0 : -1.0;
      final f = t.x + o * c * 9, p = t.z + s * c * 9;
      if (_inScramblePlaza(f, p) || world.insideBuilding(f, p, 1.5)) continue;
      final yaw = math.atan2(-o * c, -s * c);
      if (vend.length < 14 && e % 8 == 2) {
        vend.add(GlbLibrary.slot(f, 0.18, p, yaw));
      } else if (poles.length < 14) {
        poles.add(GlbLibrary.slot(f, 0.18, p, yaw));
      }
    }
    inst('VendingAlcove', vend,
        mat: (n, m) => n == 'Vending_Display' ? emissive(m, '#E0F2FE', 2) : m);
    inst('TransformerPole', poles);
  }

  // ---------------------------------------------------------- pin gates
  void _pinGates() {
    for (final g in level.route['pinGates'] as List<dynamic>) {
      final t = GlbLibrary.template(lib.props, 'PinGateArch');
      if (t == null) return;
      final p = g['pos'] as List<dynamic>;
      final sx = (_d(g['postHalfSpan'], 5.6) / 2.65).clamp(1.0, 2.35).toDouble();
      final sy = math.min(math.max(_d(g['clearHeight'], 7.87) / 6.35, 0.95), 1.25);
      t.localTransform = GlbLibrary.slot(
          _d(p[0]), _d(g['groundY'], _d(p[1])), _d(p[2]), _d(g['yaw']), vm.Vector3(sx, sy, 1));
      final glow = _litMaterial(t, 'PinGate_PlasmaTube', (g['color'] as String?) ?? '#FF4F00');
      glow.glow = 0.16;
      world.pinGates.add(glow);
      ref.add(t);
    }
  }

  /// The demo swaps the GLB's glass sleeve for a faint #DCEEFF shell
  /// (opacity 0.2, roughness 0.08, env x1.45, emissive #60A5FA x0.06) so the
  /// plasma core reads through it.
  void _glassSleeve(fs.Node t, String meshName) {
    final n = t.getChildByName(meshName);
    if (n?.mesh == null) return;
    final m = fs.PhysicallyBasedMaterial()
      ..baseColorFactor = hexColor('#DCEEFF', 1, 0.2)
      ..alphaMode = fs.AlphaMode.blend
      ..roughnessFactor = 0.08
      ..metallicFactor = 0.1
      ..emissiveFactor = hexColor('#60A5FA', 0.06);
    for (final p in n!.mesh!.primitives) {
      p.material = m;
    }
  }

  GlowProp _litMaterial(fs.Node t, String meshName, String hex) {
    _glassSleeve(t, meshName.replaceAll('PlasmaTube', 'GlassTube'));
    final n = t.getChildByName(meshName);
    final base = hexColor(hex, 0.9);
    final m = n?.mesh != null
        ? GlbLibrary.clonePbr(n!.mesh!.primitives.first.material)
        : fs.PhysicallyBasedMaterial();
    // The demo shades the plasma tubes with an unlit ShaderMaterial.
    m
      ..baseColorFactor = vm.Vector4(0, 0, 0, 1)
      ..baseColorTexture = null
      ..metallicFactor = 0
      ..roughnessFactor = 1
      ..emissiveTexture = null
      ..emissiveFactor = base
      ..emissiveStrength = 1;
    if (n?.mesh != null) {
      for (final p in n!.mesh!.primitives) {
        p.material = m;
      }
    }
    final c = hexColor(hex);
    return GlowProp(m, base, litScale: 3.0)..color = vm.Vector3(c.x, c.y, c.z);
  }

  // -------------------------------------------------------- boost rings
  void _boostRings() {
    for (final r in level.route['boostRings'] as List<dynamic>) {
      final t = GlbLibrary.template(lib.props, 'NeonBoostRing');
      if (t == null) return;
      final m = r as Map<String, dynamic>;
      final p = m['pos'] as List<dynamic>;
      final y = m['bottomY'] != null
          ? _d(m['bottomY'])
          : (m['groundY'] != null ? _d(m['groundY']) : (_d(p[1]) > 7.8 ? 7.5 : 0.0));
      t.localTransform = GlbLibrary.slot(_d(p[0]), y, _d(p[2]), _d(m['yaw']));
      final glow = _litMaterial(t, 'BoostRing_PlasmaTube', (m['color'] as String?) ?? '#38BDF8');
      glow.glow = 0.72;
      ref.add(t);
      world.rings.add(RingProp(t, glow, m));
    }
  }

  // ------------------------------------------------ neon slide arches
  void _slideArches() {
    int k = 0;
    for (final r in level.route['slidePortals'] as List<dynamic>) {
      final rig = NeonArchRig.build(lib.props, ref, r as Map<String, dynamic>, k++);
      if (rig != null) world.archRigs.add(rig);
    }
  }

}
