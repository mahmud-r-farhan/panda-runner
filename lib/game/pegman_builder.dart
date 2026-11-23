import 'dart:math' as math;

import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;

import 'world_builder.dart' show hexColor, pbr;

/// Pose inputs for [PegmanRig.update], mirroring the web demo's hero moves.
enum PegmanPose { skyDrop, run, jump, flip, slide, wallRun, grind, stumble, dance }

/// Procedural 1.72 m Street View Pegman (marigold body, terracotta collar,
/// orange chest V) with jointed arms/legs, following the proportions of the
/// demo's `Rf` rig spec.
class PegmanRig {
  PegmanRig() {
    final body = pbr(hexColor('#FDBF2D'),
        emissive: hexColor('#FDBF2D', 0.22), roughness: 0.45);
    final collar = pbr(hexColor('#CE592C'), emissive: hexColor('#CE592C', 0.15));
    final chest = pbr(hexColor('#E3812D'), emissive: hexColor('#E3812D', 0.2));

    root.add(flip);
    root.scale = vm.Vector3.all(1.12);
    flip.position = vm.Vector3(0, 0.7, 0);
    flip.add(pelvis);
    pelvis.position = vm.Vector3(0, -0.2, 0);

    final torso = fs.Node(
        mesh: fs.Mesh(fs.CapsuleGeometry(radius: 0.27, height: 0.3), body))
      ..position = vm.Vector3(0, 0.3, 0)
      ..scale = vm.Vector3(1.0, 1.0, 0.85);
    final collarN = fs.Node(
        mesh: fs.Mesh(fs.CylinderGeometry(topRadius: 0.16, bottomRadius: 0.22, height: 0.07), collar))
      ..position = vm.Vector3(0, 0.6, 0);
    final chestV = fs.Node(
        mesh: fs.Mesh(fs.CuboidGeometry(vm.Vector3(0.16, 0.16, 0.04)), chest))
      ..position = vm.Vector3(0, 0.38, 0.235)
      ..rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), math.pi / 4);
    final head = fs.Node(
        mesh: fs.Mesh(fs.SphereGeometry(radius: 0.24), body))
      ..position = vm.Vector3(0, 0.86, 0);
    pelvis.addAll([torso, collarN, chestV, head]);

    fs.Node limb(double len, double r) => fs.Node(
        mesh: fs.Mesh(fs.CapsuleGeometry(radius: r, height: len), body))
      ..position = vm.Vector3(0, -len / 2, 0);

    for (final side in [-1.0, 1.0]) {
      final hip = fs.Node()..position = vm.Vector3(0.14 * side, 0.08, 0);
      final knee = fs.Node()..position = vm.Vector3(0, -0.27, 0);
      hip.add(limb(0.2, 0.11));
      knee.add(limb(0.18, 0.1));
      hip.add(knee);
      pelvis.add(hip);
      final shoulder = fs.Node()..position = vm.Vector3(0.3 * side, 0.48, 0);
      final elbow = fs.Node()..position = vm.Vector3(0.0, -0.24, 0);
      shoulder.add(limb(0.16, 0.09));
      elbow.add(limb(0.14, 0.085));
      shoulder.add(elbow);
      pelvis.add(shoulder);
      if (side < 0) {
        hipL = hip;
        kneeL = knee;
        shoulderL = shoulder;
        elbowL = elbow;
      } else {
        hipR = hip;
        kneeR = knee;
        shoulderR = shoulder;
        elbowR = elbow;
      }
    }

    // Magenta plasma trail ribbon segments (sky drop / high speed).
    final trailMat = pbr(hexColor('#FF2A9D', 0.5, 0.45),
        emissive: hexColor('#FF2A9D', 2.6))
      ..alphaMode = fs.AlphaMode.blend;
    for (int i = 0; i < 14; i++) {
      final n = fs.Node(
          mesh: fs.Mesh(fs.CuboidGeometry(vm.Vector3(0.07, 0.07, 1.0)), trailMat))
        ..visible = false;
      trail.add(n);
    }
  }

  final fs.Node root = fs.Node(name: 'pegman');
  final fs.Node flip = fs.Node(name: 'pegman_flip');
  final fs.Node pelvis = fs.Node(name: 'pegman_pelvis');
  late final fs.Node hipL, hipR, kneeL, kneeR, shoulderL, shoulderR, elbowL, elbowR;
  final List<fs.Node> trail = [];
  final List<vm.Vector3> _history = [];
  double _gait = 0;

  void attach(fs.Node parent) {
    parent.add(root);
    for (final t in trail) {
      parent.add(t);
    }
  }

  static vm.Quaternion _rx(double a) =>
      vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), a);
  static vm.Quaternion _rz(double a) =>
      vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), a);

  /// [position] in Flutter Scene world space; [yaw] already mirrored.
  void update({
    required double dt,
    required vm.Vector3 position,
    required double yaw,
    required PegmanPose pose,
    double speed = 0,
    double flipPhase = 0,
    double bank = 0,
    double time = 0,
    bool showTrail = false,
  }) {
    root.position = position;
    root.rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), yaw);
    _gait += dt * math.max(speed, 4) / 2.2 * math.pi * 2;
    final g = math.sin(_gait);
    double lean = 0, legSwing = 0, armSwing = 0, kneeBend = 0, flipA = 0;
    double armSpread = 0.12, pelvisY = -0.2, roll = bank;
    switch (pose) {
      case PegmanPose.run:
      case PegmanPose.stumble:
        lean = pose == PegmanPose.stumble ? 0.55 : 0.32;
        legSwing = 0.9 * g;
        armSwing = -0.8 * g;
        kneeBend = 0.6 + 0.5 * math.max(0, -g);
        pelvisY = -0.2 + 0.04 * math.sin(_gait * 2).abs();
      case PegmanPose.jump:
        lean = 0.15;
        legSwing = 0.5;
        kneeBend = 1.1;
        armSwing = -0.6;
        armSpread = 0.5;
      case PegmanPose.flip:
        flipA = flipPhase * math.pi * 2;
        legSwing = 1.2;
        kneeBend = 1.6;
        armSwing = 1.2;
      case PegmanPose.slide:
        lean = -0.9;
        legSwing = 1.35;
        kneeBend = 0.2;
        armSwing = -0.4;
        armSpread = 0.7;
        pelvisY = -0.52;
      case PegmanPose.wallRun:
        lean = 0.3;
        legSwing = 1.0 * g;
        armSwing = -0.9 * g;
        kneeBend = 0.7;
      case PegmanPose.grind:
        lean = 0.12;
        legSwing = 0.25;
        kneeBend = 0.5;
        armSpread = 1.2;
        armSwing = 0.1;
      case PegmanPose.skyDrop:
        lean = 1.1 + 0.08 * math.sin(time * 6);
        legSwing = -0.2;
        kneeBend = 0.4;
        armSpread = 1.25;
        armSwing = 0.3;
      case PegmanPose.dance:
        final b = math.sin(time * 7);
        pelvisY = -0.2 + 0.06 * b.abs();
        legSwing = 0.1 * b;
        kneeBend = 0.2 + 0.2 * b.abs();
        armSpread = 0.2;
        armSwing = 0;
    }
    flip.rotation = _rx(flipA + lean * 0.5) * _rz(roll);
    pelvis.position = vm.Vector3(0, pelvisY, 0);
    pelvis.rotation = _rx(lean * 0.5);
    hipL.rotation = _rx(-legSwing);
    hipR.rotation = _rx(pose == PegmanPose.slide || pose == PegmanPose.jump || pose == PegmanPose.flip || pose == PegmanPose.grind
        ? -legSwing * 0.6
        : legSwing);
    kneeL.rotation = _rx(kneeBend * (pose == PegmanPose.run ? (g > 0 ? 0.4 : 1.0) : 1.0));
    kneeR.rotation = _rx(kneeBend * (pose == PegmanPose.run ? (g < 0 ? 0.4 : 1.0) : 1.0));
    if (pose == PegmanPose.dance) {
      // alternating fist pumps
      final pump = math.sin(time * 7) > 0;
      shoulderL.rotation = _rz(-0.3) * _rx(pump ? -2.9 : -1.6);
      shoulderR.rotation = _rz(0.3) * _rx(pump ? -1.6 : -2.9);
      elbowL.rotation = _rx(pump ? -0.2 : -1.4);
      elbowR.rotation = _rx(pump ? -1.4 : -0.2);
    } else {
      shoulderL.rotation = _rz(-armSpread) * _rx(armSwing);
      shoulderR.rotation = _rz(armSpread) * _rx(-armSwing);
      elbowL.rotation = _rx(-0.9);
      elbowR.rotation = _rx(-0.9);
    }

    // trail
    _history.insert(0, position.clone()..y += 0.9);
    if (_history.length > trail.length + 1) _history.removeLast();
    for (int i = 0; i < trail.length; i++) {
      final n = trail[i];
      if (!showTrail || i + 1 >= _history.length) {
        n.visible = false;
        continue;
      }
      final a = _history[i], b = _history[i + 1];
      final d = b - a;
      final len = d.length;
      if (len < 0.01) {
        n.visible = false;
        continue;
      }
      n.visible = true;
      n.position = (a + b) * 0.5;
      final dir = d / len;
      final yawT = math.atan2(dir.x, dir.z);
      final pitch = -math.asin(dir.y.clamp(-1.0, 1.0));
      final taper = 1.0 - i / trail.length;
      n.rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), yawT) *
          vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), pitch);
      n.scale = vm.Vector3(taper, taper, len);
    }
  }

  void resetTrail() => _history.clear();
}
