import 'dart:math' as math;

import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;

import 'pegman_builder.dart' show PegmanPose;
import 'pegman_pose.dart';
import 'world_builder.dart' show hexColor, pbr;

/// Articulated 3D Panda Hero ("Panda Runner") with stylized fur materials,
/// anime eyes, ninja headband, and a glowing neon bamboo staff.
///
/// Shares the standard humanoid node hierarchy (Pelvis, Torso, Chest, Head,
/// Thigh/Shin/Foot, Arm/Forearm/Hand) so the demo's IK pose solver and forward
/// kinematics pose the Panda flawlessly during sky drop, sprint, rail grind,
/// wall run, vault, roll, and victory dance.
class PandaHero {
  PandaHero() {
    _buildPanda();
  }

  final fs.Node root = fs.Node(name: 'PandaWorldRoot');

  /// Emerald-green aura point light (#10B981) radiating from the Panda.
  final fs.PointLight light = fs.PointLight(
    color: vm.Vector3(0.063, 0.725, 0.506),
    intensity: 0.35,
    range: 12.0,
    falloffExponent: 2.0,
  );

  final fs.Node flipPivot = fs.Node(name: 'PandaFlipPivot');
  final fs.Node flipOffset = fs.Node(name: 'PandaFlipOffset');

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

  void placeRoot(double x, double y, double z, double yaw) {
    root.localTransform = vm.Matrix4.compose(
      vm.Vector3(x, y, z),
      vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), yaw),
      vm.Vector3.all(1),
    );
  }

  void _buildPanda() {
    root.add(flipPivot);
    root.add(fs.Node(name: 'PandaPointLight')
      ..position = vm.Vector3(0, 0.35, -0.32)
      ..addComponent(fs.PointLightComponent(light)));

    flipPivot.position = vm.Vector3(0, 0.86, 0);
    flipPivot.add(flipOffset);
    flipOffset.position = vm.Vector3(0, -0.86, 0);

    // ------------------------------------------------------------- Materials
    final whiteFur = pbr(
      hexColor('#F4F6F9'),
      emissive: hexColor('#F4F6F9', 0.12),
      roughness: 0.55,
      metallic: 0.0,
    );
    final blackFur = pbr(
      hexColor('#14171E'),
      emissive: hexColor('#14171E', 0.05),
      roughness: 0.65,
      metallic: 0.04,
    );
    final eyeGlow = pbr(
      hexColor('#38BDF8'),
      emissive: hexColor('#38BDF8', 2.8),
      roughness: 0.15,
      metallic: 0.1,
    );
    final eyePupil = pbr(hexColor('#07090E'), roughness: 0.1);
    final snoutMat = pbr(hexColor('#FFFBEB'), roughness: 0.45);
    final noseMat = pbr(
      hexColor('#0F172A'),
      emissive: hexColor('#0F172A', 0.1),
      roughness: 0.2,
      metallic: 0.2,
    );
    final headbandMat = pbr(
      hexColor('#EF4444'),
      emissive: hexColor('#EF4444', 2.4),
      roughness: 0.3,
    );
    final goldBuckleMat = pbr(
      hexColor('#F59E0B'),
      emissive: hexColor('#F59E0B', 1.2),
      roughness: 0.2,
      metallic: 0.85,
    );
    final bambooStalkMat = pbr(
      hexColor('#10B981'),
      emissive: hexColor('#10B981', 1.8),
      roughness: 0.25,
      metallic: 0.15,
    );
    final bambooRingMat = pbr(
      hexColor('#FBBF24'),
      emissive: hexColor('#FBBF24', 1.5),
      roughness: 0.2,
      metallic: 0.4,
    );

    // ---------------------------------------------------------------- Skeleton
    // Pelvis (root of character body)
    final pelvis = fs.Node(name: 'Pelvis')..position = vm.Vector3(0, 0.6, 0);
    flipOffset.add(pelvis);
    nodes['Pelvis'] = pelvis;

    // Chubby White Belly
    pelvis.add(
      fs.Node(
        name: 'PandaBelly',
        mesh: fs.Mesh(fs.CapsuleGeometry(radius: 0.30, height: 0.28), whiteFur),
      )
        ..position = vm.Vector3(0, 0.02, 0)
        ..scale = vm.Vector3(1.12, 1.0, 0.98),
    );

    // Crimson Ninja Sash Belt & Golden Buckle
    pelvis.add(
      fs.Node(
        name: 'PandaSash',
        mesh: fs.Mesh(fs.CuboidGeometry(vm.Vector3(0.66, 0.07, 0.58)), headbandMat),
      )..position = vm.Vector3(0, -0.06, 0),
    );
    pelvis.add(
      fs.Node(
        name: 'PandaBuckle',
        mesh: fs.Mesh(
          fs.CylinderGeometry(topRadius: 0.06, bottomRadius: 0.06, height: 0.04),
          goldBuckleMat,
        ),
      )
        ..position = vm.Vector3(0, -0.06, 0.30)
        ..rotation = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), math.pi / 2),
    );

    // Fluffy Tail
    pelvis.add(
      fs.Node(
        name: 'PandaTail',
        mesh: fs.Mesh(fs.SphereGeometry(radius: 0.08), blackFur),
      )..position = vm.Vector3(0, -0.04, -0.28),
    );

    // Torso / Upper Chest (Black shoulder vest band)
    final torso = fs.Node(name: 'Torso')..position = vm.Vector3(0, 0.22, 0);
    pelvis.add(torso);
    nodes['Torso'] = torso;

    torso.add(
      fs.Node(
        name: 'PandaChestBand',
        mesh: fs.Mesh(fs.CapsuleGeometry(radius: 0.31, height: 0.22), blackFur),
      )..scale = vm.Vector3(1.08, 0.95, 0.92),
    );

    // Chest Node
    final chest = fs.Node(name: 'Chest')..position = vm.Vector3(0, 0.16, 0);
    torso.add(chest);
    nodes['Chest'] = chest;

    // Head Node
    final head = fs.Node(name: 'Head')..position = vm.Vector3(0, 0.30, 0);
    chest.add(head);
    nodes['Head'] = head;

    // Head Base (White Sphere)
    head.add(
      fs.Node(
        name: 'PandaHeadBase',
        mesh: fs.Mesh(fs.SphereGeometry(radius: 0.29), whiteFur),
      )..scale = vm.Vector3(1.06, 1.0, 1.02),
    );

    // Panda Black Ears
    for (final side in [-1.0, 1.0]) {
      head.add(
        fs.Node(
          name: side < 0 ? 'PandaEarL' : 'PandaEarR',
          mesh: fs.Mesh(fs.SphereGeometry(radius: 0.095), blackFur),
        )
          ..position = vm.Vector3(0.20 * side, 0.24, -0.04)
          ..scale = vm.Vector3(1.0, 1.15, 0.7),
      );
    }

    // Snout & Nose
    final snout = fs.Node(
      name: 'PandaSnout',
      mesh: fs.Mesh(fs.CapsuleGeometry(radius: 0.11, height: 0.09), snoutMat),
    )
      ..position = vm.Vector3(0, -0.06, 0.23)
      ..scale = vm.Vector3(1.2, 0.9, 0.85);
    head.add(snout);

    head.add(
      fs.Node(
        name: 'PandaNose',
        mesh: fs.Mesh(fs.SphereGeometry(radius: 0.045), noseMat),
      )
        ..position = vm.Vector3(0, -0.03, 0.33)
        ..scale = vm.Vector3(1.3, 0.85, 1.0),
    );

    // Iconic Panda Eye Patches & Glowing Anime Eyes
    for (final side in [-1.0, 1.0]) {
      final patch = fs.Node(
        name: side < 0 ? 'PandaEyePatchL' : 'PandaEyePatchR',
        mesh: fs.Mesh(fs.SphereGeometry(radius: 0.095), blackFur),
      )
        ..position = vm.Vector3(0.12 * side, 0.04, 0.22)
        ..rotation = vm.Quaternion.axisAngle(
          vm.Vector3(0, 0, 1),
          side < 0 ? 0.35 : -0.35,
        )
        ..scale = vm.Vector3(1.1, 1.35, 0.45);
      head.add(patch);

      final eye = fs.Node(
        name: side < 0 ? 'PandaEyeL' : 'PandaEyeR',
        mesh: fs.Mesh(fs.SphereGeometry(radius: 0.036), eyeGlow),
      )
        ..position = vm.Vector3(0.12 * side, 0.045, 0.27)
        ..scale = vm.Vector3(0.85, 1.15, 0.4);
      head.add(eye);

      final pupil = fs.Node(
        name: side < 0 ? 'PandaPupilL' : 'PandaPupilR',
        mesh: fs.Mesh(fs.SphereGeometry(radius: 0.018), eyePupil),
      )..position = vm.Vector3(0.12 * side, 0.045, 0.285);
      head.add(pupil);
    }

    // Red Ninja Headband & Flowing Ribbon Tails
    head.add(
      fs.Node(
        name: 'PandaHeadbandBand',
        mesh: fs.Mesh(
          fs.CylinderGeometry(
            topRadius: 0.295,
            bottomRadius: 0.295,
            height: 0.055,
          ),
          headbandMat,
        ),
      )..position = vm.Vector3(0, 0.10, 0),
    );

    // Floating ribbon knot + tails trailing behind
    final knot = fs.Node(name: 'PandaHeadbandKnot')
      ..position = vm.Vector3(0, 0.10, -0.29);
    knot.add(
      fs.Node(
        name: 'RibbonKnotCenter',
        mesh: fs.Mesh(fs.SphereGeometry(radius: 0.04), headbandMat),
      ),
    );
    knot.add(
      fs.Node(
        name: 'RibbonTail1',
        mesh: fs.Mesh(fs.CuboidGeometry(vm.Vector3(0.04, 0.28, 0.01)), headbandMat),
      )
        ..position = vm.Vector3(-0.04, -0.12, -0.06)
        ..rotation = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), 0.35),
    );
    knot.add(
      fs.Node(
        name: 'RibbonTail2',
        mesh: fs.Mesh(fs.CuboidGeometry(vm.Vector3(0.04, 0.34, 0.01)), headbandMat),
      )
        ..position = vm.Vector3(0.04, -0.15, -0.08)
        ..rotation = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), 0.45),
    );
    head.add(knot);

    // ------------------------------------------------------------- Arms & Legs
    // Left & Right Arms
    for (final side in [-1.0, 1.0]) {
      final shoulderName = side < 0 ? 'ArmL' : 'ArmR';
      final elbowName = side < 0 ? 'ForearmL' : 'ForearmR';
      final handName = side < 0 ? 'HandL' : 'HandR';

      final shoulder = fs.Node(name: shoulderName)
        ..position = vm.Vector3(0.28 * side, 0.08, 0.0);
      torso.add(shoulder);
      nodes[shoulderName] = shoulder;

      shoulder.add(
        fs.Node(
          name: '${shoulderName}_Upper',
          mesh: fs.Mesh(fs.CapsuleGeometry(radius: 0.11, height: 0.18), blackFur),
        )..position = vm.Vector3(0, -0.10, 0),
      );

      final elbow = fs.Node(name: elbowName)..position = vm.Vector3(0, -0.22, 0);
      shoulder.add(elbow);
      nodes[elbowName] = elbow;

      elbow.add(
        fs.Node(
          name: '${elbowName}_Lower',
          mesh: fs.Mesh(fs.CapsuleGeometry(radius: 0.10, height: 0.16), blackFur),
        )..position = vm.Vector3(0, -0.09, 0),
      );

      final hand = fs.Node(name: handName)..position = vm.Vector3(0, -0.18, 0);
      elbow.add(hand);
      nodes[handName] = hand;

      hand.add(
        fs.Node(
          name: '${handName}_Paw',
          mesh: fs.Mesh(fs.SphereGeometry(radius: 0.095), blackFur),
        ),
      );

      // Attach the Glowing Neon Bamboo Staff to Right Hand (HandR)
      if (side > 0) {
        final bambooStaff = fs.Node(name: 'NeonBambooStaff')
          ..position = vm.Vector3(0.05, 0.02, 0.05)
          ..rotation = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), 0.2);

        // Bamboo pole
        bambooStaff.add(
          fs.Node(
            name: 'BambooPole',
            mesh: fs.Mesh(
              fs.CylinderGeometry(
                topRadius: 0.032,
                bottomRadius: 0.032,
                height: 1.55,
              ),
              bambooStalkMat,
            ),
          ),
        );

        // 4 Glowing Bamboo Ring Joints
        for (final yPos in [-0.48, -0.16, 0.16, 0.48]) {
          bambooStaff.add(
            fs.Node(
              name: 'BambooRing_$yPos',
              mesh: fs.Mesh(
                fs.CylinderGeometry(
                  topRadius: 0.039,
                  bottomRadius: 0.039,
                  height: 0.03,
                ),
                bambooRingMat,
              ),
            )..position = vm.Vector3(0, yPos, 0),
          );
        }

        // Bamboo Leaves at the top tip
        bambooStaff.add(
          fs.Node(
            name: 'BambooLeaf1',
            mesh: fs.Mesh(
              fs.CuboidGeometry(vm.Vector3(0.02, 0.18, 0.08)),
              bambooStalkMat,
            ),
          )
            ..position = vm.Vector3(0.04, 0.72, 0)
            ..rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), 0.45),
        );
        bambooStaff.add(
          fs.Node(
            name: 'BambooLeaf2',
            mesh: fs.Mesh(
              fs.CuboidGeometry(vm.Vector3(0.02, 0.16, 0.07)),
              bambooStalkMat,
            ),
          )
            ..position = vm.Vector3(-0.04, 0.68, 0)
            ..rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), -0.55),
        );

        hand.add(bambooStaff);
      }
    }

    // Left & Right Legs
    for (final side in [-1.0, 1.0]) {
      final hipName = side < 0 ? 'ThighL' : 'ThighR';
      final kneeName = side < 0 ? 'ShinL' : 'ShinR';
      final footName = side < 0 ? 'FootL' : 'FootR';

      final hip = fs.Node(name: hipName)
        ..position = vm.Vector3(0.16 * side, -0.10, 0);
      pelvis.add(hip);
      nodes[hipName] = hip;

      hip.add(
        fs.Node(
          name: '${hipName}_Thigh',
          mesh: fs.Mesh(fs.CapsuleGeometry(radius: 0.13, height: 0.22), blackFur),
        )..position = vm.Vector3(0, -0.12, 0),
      );

      final knee = fs.Node(name: kneeName)..position = vm.Vector3(0, -0.25, 0);
      hip.add(knee);
      nodes[kneeName] = knee;

      knee.add(
        fs.Node(
          name: '${kneeName}_Calf',
          mesh: fs.Mesh(fs.CapsuleGeometry(radius: 0.12, height: 0.20), blackFur),
        )..position = vm.Vector3(0, -0.10, 0),
      );

      final foot = fs.Node(name: footName)..position = vm.Vector3(0, -0.21, 0);
      knee.add(foot);
      nodes[footName] = foot;

      foot.add(
        fs.Node(
          name: '${footName}_Paw',
          mesh: fs.Mesh(fs.SphereGeometry(radius: 0.11), blackFur),
        )
          ..position = vm.Vector3(0, -0.02, 0.06)
          ..scale = vm.Vector3(1.1, 0.75, 1.4),
      );
    }

    // ------------------------------------------------------------- Cache Rest
    void collect(fs.Node n) {
      if (n.name.isNotEmpty) nodes[n.name] = n;
      for (final c in n.children) {
        collect(c);
      }
    }

    collect(pelvis);
    for (final n in nodes.values) {
      _rest[n.name] = n.localTransform.clone();
    }

    // Emerald Green & Gold Particle Trail Ribbons
    final trailMat = pbr(
      hexColor('#10B981', 0.6, 0.45),
      emissive: hexColor('#10B981', 3.2),
    )..alphaMode = fs.AlphaMode.blend;

    for (int i = 0; i < 14; i++) {
      trail.add(
        fs.Node(
          mesh: fs.Mesh(fs.CuboidGeometry(vm.Vector3(0.09, 0.09, 1.0)), trailMat),
        )..visible = false,
      );
    }
  }

  /// Sets a joint's local rotation on top of its rest translation.
  void setJoint(String name, vm.Quaternion q, [vm.Vector3? pos]) {
    final n = nodes[name];
    final rest = _rest[name];
    if (n == null || rest == null) return;
    n.localTransform = vm.Matrix4.compose(
      pos ?? rest.getTranslation(),
      q,
      vm.Vector3.all(1),
    );
  }

  static vm.Quaternion _e(double x, double y, double z) {
    final qx = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), x);
    final qy = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), y);
    final qz = vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), z);
    return qx * qy * qz;
  }

  /// Applies the IK solver output to the Panda rig.
  void applyPose(PegmanPoseResult r) {
    final pv = r.rootFlipPivotLocal;
    final q = r.rootFlipQuat;
    flipPivot.localTransform = vm.Matrix4.compose(
      vm.Vector3(pv[0], pv[1], pv[2]),
      vm.Quaternion(q[0], q[1], q[2], q[3]),
      vm.Vector3.all(1),
    );
    flipOffset.localTransform = vm.Matrix4.translation(
      vm.Vector3(-pv[0], -pv[1], -pv[2]),
    );
    r.v2Nodes.forEach((name, np) {
      final n = nodes[name];
      if (n == null) return;
      n.localTransform = vm.Matrix4.compose(
        vm.Vector3(np.pos[0], np.pos[1], np.pos[2]),
        vm.Quaternion(np.quat[0], np.quat[1], np.quat[2], np.quat[3]),
        vm.Vector3.all(1),
      );
    });
  }

  /// Procedural forward-kinematics fallback animation.
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
    double armL = 0.0, armR = 0.0, spread = 0.22, fore = -0.5, pelvisY = 0.60;
    switch (pose) {
      case PegmanPose.run:
      case PegmanPose.stumble:
      case PegmanPose.wallRun:
        lean = pose == PegmanPose.stumble ? 0.45 : 0.32;
        thighL = -0.92 * g;
        thighR = 0.92 * g;
        shinL = 0.35 + 0.85 * math.max(0, g);
        shinR = 0.35 + 0.85 * math.max(0, -g);
        armL = 0.82 * g;
        armR = -0.82 * g;
        fore = -1.1;
        pelvisY = 0.58 + 0.04 * math.cos(2 * _gait);
      case PegmanPose.jump:
      case PegmanPose.flip:
        lean = 0.2;
        thighL = -1.0;
        thighR = -0.35;
        shinL = 1.35;
        shinR = 0.95;
        armL = -0.55;
        armR = -0.55;
        spread = 0.55;
        fore = -0.85;
      case PegmanPose.slide:
        lean = -0.85;
        thighL = -1.4;
        thighR = -1.15;
        shinL = 0.2;
        shinR = 0.55;
        armL = -0.25;
        armR = 0.35;
        spread = 0.75;
        pelvisY = 0.34;
      case PegmanPose.grind:
        lean = 0.12;
        thighL = -0.28;
        thighR = 0.28;
        shinL = 0.45;
        shinR = 0.45;
        spread = 1.2;
        fore = -0.25;
        pelvisY = 0.54;
      case PegmanPose.skyDrop:
        lean = 0.16 + 0.06 * math.sin(time * 4.8);
        thighL = 0.16 * math.sin(time * 9.6);
        thighR = -0.16 * math.sin(time * 9.6);
        shinL = 0.3;
        shinR = 0.3;
        spread = 1.25;
        fore = -0.3;
      case PegmanPose.dance:
        final b = math.sin(time * 7);
        pelvisY = 0.58 + 0.04 * b.abs();
        thighL = 0.1 * b;
        thighR = -0.1 * b;
        shinL = 0.2;
        shinR = 0.2;
        armL = b > 0 ? -2.8 : -1.5;
        armR = b > 0 ? -1.5 : -2.8;
        spread = 0.3;
        fore = b > 0 ? -0.2 : -1.2;
    }

    double fx = 0, fy = 0, fz = 0;
    if (flipStyle != 'none' && flipPhase > 0.001 && flipPhase < 0.999) {
      final e = flipPhase * flipPhase * (3 - 2 * flipPhase);
      fx = e * math.pi * 2;
      if (flipStyle == 'corkscrew') fy = e * math.pi * 2;
    }
    flipPivot.localTransform = vm.Matrix4.compose(
      vm.Vector3(0, 0.86, 0),
      _e(fx, fy, fz + bank),
      vm.Vector3.all(1),
    );
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
      n.visible = false;
    }
  }

  void resetTrail() => _history.clear();
}
