import 'dart:math' as math;

import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;

import 'glb_library.dart';
import 'pegman_builder.dart' show PegmanPose;
import 'pegman_pose.dart';
import 'world_builder.dart' show hexColor, pbr;

/// The demo's authentic `pegman_rig.glb`, wrapped like `_attachPegmanRig`
/// (PegmanWorldRoot → FlipPivot @ 0.86 m → FlipOffset → glTF scene).
/// Lives under the reference-frame root, so positions/yaw are three.js
/// values.
class GlbPegman {
  GlbPegman(GlbLibrary lib) {
    root.add(flipPivot);
    root.add(fs.Node(name: 'PegmanPointLight')
      ..position = vm.Vector3(0, 0.22, -0.32)
      ..addComponent(fs.PointLightComponent(light)));
    flipPivot.position = vm.Vector3(0, 0.86, 0);
    flipPivot.add(flipOffset);
    flipOffset.position = vm.Vector3(0, -0.86, 0);
    // The importer wraps the glTF in a z-mirroring root; the demo attaches
    // the raw glTF scene, and this rig already lives under the mirrored
    // reference-frame root, so drop the importer's mirror (otherwise every
    // pitch - lean, dive, front flip - rotates the wrong way).
    final scene = lib.pegman.clone()..localTransform = vm.Matrix4.identity();
    flipOffset.add(scene);
    void collect(fs.Node n) {
      if (n.name.isNotEmpty) nodes[n.name] = n;
      for (final c in n.children) {
        collect(c);
      }
    }

    collect(scene);
    for (final n in nodes.values) {
      _rest[n.name] = n.localTransform.clone();
    }
    // Material tweak from the demo: roughness .39, metalness 0, emissive =
    // base colour map at 0.36.
    final seen = <fs.Material>{};
    GlbLibrary.forEachMaterial(scene, (name, p) {
      if (seen.contains(p.material)) return;
      final m = GlbLibrary.clonePbr(p.material)
        ..roughnessFactor = 0.39
        ..metallicFactor = 0
        ..emissiveStrength = 1;
      m.emissiveTexture = m.baseColorTexture;
      m.emissiveFactor = m.baseColorTexture != null
          ? vm.Vector4(0.36, 0.36, 0.36, 1)
          : hexColor('#FDBF2D', 0.36);
      seen.add(m);
      p.material = m;
    });
    final trailMat = pbr(hexColor('#FF2A9D', 0.5, 0.45), emissive: hexColor('#FF2A9D', 2.6))
      ..alphaMode = fs.AlphaMode.blend;
    for (int i = 0; i < 14; i++) {
      trail.add(fs.Node(
          mesh: fs.Mesh(fs.CuboidGeometry(vm.Vector3(0.07, 0.07, 1.0)), trailMat))
        ..visible = false);
    }
  }

  final fs.Node root = fs.Node(name: 'PegmanWorldRoot');

  /// The demo's PointLight(#FFE680, .3, 10.5, 2) at (0, .22, -.32).
  final fs.PointLight light = fs.PointLight(
      color: vm.Vector3(1.0, 0.7913, 0.2232), intensity: 0.3, range: 10.5, falloffExponent: 2);
  final fs.Node flipPivot = fs.Node(name: 'PegmanFlipPivot');
  final fs.Node flipOffset = fs.Node(name: 'PegmanFlipOffset');
  final Map<String, fs.Node> nodes = {};
  final Map<String, vm.Matrix4> _rest = {};
  final List<fs.Node> trail = [];
  final List<vm.Vector3> _history = [];
  double _gait = 0;

  void attach(fs.Node refRoot) {
    refRoot.add(root);
    for (final t in trail) {
      refRoot.add(t);
    }
  }

  /// Sets a joint's local rotation on top of its rest translation.
  void setJoint(String name, vm.Quaternion q, [vm.Vector3? pos]) {
    final n = nodes[name];
    final rest = _rest[name];
    if (n == null || rest == null) return;
    n.localTransform = vm.Matrix4.compose(
        pos ?? rest.getTranslation(), q, vm.Vector3.all(1));
  }

  static vm.Quaternion _e(double x, double y, double z) {
    // three.js Euler 'XYZ' order.
    final qx = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), x);
    final qy = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), y);
    final qz = vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), z);
    return qx * qy * qz;
  }

  void placeRoot(double x, double y, double z, double yaw) {
    root.localTransform = vm.Matrix4.compose(vm.Vector3(x, y, z),
        vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), yaw), vm.Vector3.all(1));
  }

  /// Interim forward-kinematics pose (used until the IK solver is wired in).
  void updateFk({
    required double dt,
    required PegmanPose pose,
    double speed = 0,
    double flipPhase = 0,
    String flipStyle = 'none',
    double bank = 0,
    double time = 0,
  }) {
    _gait += dt * math.max(speed, 4) / 2.2 * math.pi * 2;
    final g = math.sin(_gait);
    double lean = 0.0, thighL = 0.0, thighR = 0.0, shinL = 0.0, shinR = 0.0;
    double armL = 0.0, armR = 0.0, spread = 0.18, fore = -0.5, pelvisY = 0.64;
    switch (pose) {
      case PegmanPose.run:
      case PegmanPose.stumble:
      case PegmanPose.wallRun:
        lean = pose == PegmanPose.stumble ? 0.5 : 0.36;
        thighL = -0.95 * g;
        thighR = 0.95 * g;
        shinL = 0.35 + 0.9 * math.max(0, g);
        shinR = 0.35 + 0.9 * math.max(0, -g);
        armL = 0.85 * g;
        armR = -0.85 * g;
        fore = -1.2;
        pelvisY = 0.6 + 0.04 * math.cos(2 * _gait);
      case PegmanPose.jump:
      case PegmanPose.flip:
        lean = 0.2;
        thighL = -1.1;
        thighR = -0.4;
        shinL = 1.4;
        shinR = 1.0;
        armL = -0.6;
        armR = -0.6;
        spread = 0.6;
        fore = -0.9;
      case PegmanPose.slide:
        lean = -0.9;
        thighL = -1.45;
        thighR = -1.2;
        shinL = 0.2;
        shinR = 0.6;
        armL = -0.3;
        armR = 0.4;
        spread = 0.8;
        pelvisY = 0.36;
      case PegmanPose.grind:
        lean = 0.1;
        thighL = -0.3;
        thighR = 0.3;
        shinL = 0.5;
        shinR = 0.5;
        spread = 1.25;
        fore = -0.2;
        pelvisY = 0.56;
      case PegmanPose.skyDrop:
        lean = 0.15 + 0.06 * math.sin(time * 4.8);
        thighL = 0.18 * math.sin(time * 9.6);
        thighR = -0.18 * math.sin(time * 9.6);
        shinL = 0.3;
        shinR = 0.3;
        spread = 1.3;
        fore = -0.3;
      case PegmanPose.dance:
        final b = math.sin(time * 7);
        pelvisY = 0.6 + 0.04 * b.abs();
        thighL = 0.1 * b;
        thighR = -0.1 * b;
        shinL = 0.2;
        shinR = 0.2;
        armL = b > 0 ? -2.9 : -1.6;
        armR = b > 0 ? -1.6 : -2.9;
        spread = 0.25;
        fore = b > 0 ? -0.2 : -1.3;
    }
    // Flip rotation about the 0.86 m pivot.
    double fx = 0, fy = 0, fz = 0;
    if (flipStyle != 'none' && flipPhase > 0.001 && flipPhase < 0.999) {
      final e = flipPhase * flipPhase * (3 - 2 * flipPhase);
      fx = e * math.pi * 2;
      if (flipStyle == 'corkscrew') fy = e * math.pi * 2;
    }
    flipPivot.localTransform = vm.Matrix4.compose(
        vm.Vector3(0, 0.86, 0), _e(fx, fy, fz + bank), vm.Vector3.all(1));
    setJoint('Pelvis', _e(lean * 0.4, 0, 0), vm.Vector3(0, pelvisY, 0));
    setJoint('Torso', _e(lean * 0.6, 0, 0));
    setJoint('ThighL', _e(thighL, 0, 0));
    setJoint('ThighR', _e(thighR, 0, 0));
    setJoint('ShinL', _e(shinL, 0, 0));
    setJoint('ShinR', _e(shinR, 0, 0));
    setJoint('FootL', _e(-0.2, 0, 0));
    setJoint('FootR', _e(-0.2, 0, 0));
    setJoint('ArmL', _e(armL, 0, spread));
    setJoint('ArmR', _e(armR, 0, -spread));
    setJoint('ForearmL', _e(fore, 0, 0));
    setJoint('ForearmR', _e(fore, 0, 0));
  }

  /// Applies the IK solver output exactly like the demo's world sync:
  /// FlipPivot at `rootFlipPivotLocal` rotated by `rootFlipQuat`,
  /// FlipOffset at minus the pivot, then each `v2Nodes` pos + quat.
  void applyPose(PegmanPoseResult r) {
    final pv = r.rootFlipPivotLocal;
    final q = r.rootFlipQuat;
    flipPivot.localTransform = vm.Matrix4.compose(vm.Vector3(pv[0], pv[1], pv[2]),
        vm.Quaternion(q[0], q[1], q[2], q[3]), vm.Vector3.all(1));
    flipOffset.localTransform = vm.Matrix4.translation(vm.Vector3(-pv[0], -pv[1], -pv[2]));
    r.v2Nodes.forEach((name, np) {
      final n = nodes[name];
      if (n == null) return;
      n.localTransform = vm.Matrix4.compose(vm.Vector3(np.pos[0], np.pos[1], np.pos[2]),
          vm.Quaternion(np.quat[0], np.quat[1], np.quat[2], np.quat[3]), vm.Vector3.all(1));
    });
  }

  void updateTrail(bool show) {
    final n0 = nodes['Pelvis'];
    final p = root.globalTransform.getTranslation();
    if (n0 == null) return;
    _history.insert(0, p..y += 0.0);
    if (_history.length > trail.length + 1) _history.removeLast();
    for (int i = 0; i < trail.length; i++) {
      final n = trail[i];
      if (!show || i + 1 >= _history.length) {
        n.visible = false;
        continue;
      }
      n.visible = false; // trail only shown on overcharge (set below)
    }
  }

  void resetTrail() => _history.clear();
}
