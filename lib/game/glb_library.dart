import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;

/// The five glTF models shipped by the Neon Scramble web demo
/// (`pegman_rig`, `google_shibuya_tower`, `shibuya_arch`, `shibuya_props`,
/// `tokyo_fleet`), loaded with Flutter Scene's runtime glTF importer.
///
/// All placement helpers work in the demo's right-handed three.js frame;
/// add their output under [ShibuyaWorld.refRoot], which mirrors Z so the
/// result renders exactly like the original in Flutter Scene's view frame.
class GlbLibrary {
  late final fs.Node pegman;
  late final fs.Node googleTower;
  late final fs.Node arch;
  late final fs.Node props;
  late final fs.Node fleet;

  static Future<GlbLibrary> load({void Function(String label)? onProgress}) async {
    final lib = GlbLibrary();
    Future<fs.Node> one(String name, String label) async {
      final n = await fs.Node.fromGlbAsset('assets/models/$name.glb');
      onProgress?.call(label);
      return n;
    }

    final r = await Future.wait([
      one('pegman_rig', 'Loading Pegman...'),
      one('google_shibuya_tower', 'Loading Google Tokyo...'),
      one('shibuya_props', 'Loading Shibuya transit...'),
      one('shibuya_arch', 'Loading Shibuya skyline...'),
      one('tokyo_fleet', 'Loading Tokyo street fleet...'),
    ]);
    lib.pegman = r[0];
    lib.googleTower = r[1];
    lib.props = r[2];
    lib.arch = r[3];
    lib.fleet = r[4];
    return lib;
  }

  /// Port of the demo's `hg()`: a deep clone of the named node with its own
  /// transform reset to identity.
  static fs.Node? template(fs.Node scene, String name) {
    final n = scene.getChildByName(name);
    if (n == null) return null;
    final c = n.clone();
    c.localTransform = vm.Matrix4.identity();
    return c;
  }

  /// Every mesh-carrying node under [root] paired with its transform relative
  /// to [root] (the demo's `yg()` flattening).
  static List<(fs.Node, vm.Matrix4)> meshNodes(fs.Node root) {
    final out = <(fs.Node, vm.Matrix4)>[];
    void walk(fs.Node n, vm.Matrix4 acc) {
      for (final c in n.children) {
        final m = acc * c.localTransform;
        if (c.mesh != null) out.add((c, m));
        walk(c, m);
      }
    }

    if (root.mesh != null) out.add((root, vm.Matrix4.identity()));
    walk(root, vm.Matrix4.identity());
    return out;
  }

  /// Slot transform: translate · rotateY(yaw) · scale, in the demo's frame.
  static vm.Matrix4 slot(double x, double y, double z, double yaw,
      [vm.Vector3? scale]) {
    return vm.Matrix4.compose(vm.Vector3(x, y, z),
        vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), yaw), scale ?? vm.Vector3.all(1));
  }

  /// Port of the demo's `bg()`: draws every primitive of [template] once per
  /// slot via GPU instancing. [filter] selects which mesh nodes to include;
  /// [materialFor] may substitute a material per mesh node name.
  static fs.Node instance(
    fs.Node template,
    List<vm.Matrix4> slots, {
    String name = '',
    bool Function(String meshNodeName)? filter,
    fs.Material Function(String meshNodeName, fs.Material original)? materialFor,
  }) {
    final group = fs.Node(name: 'Inst_$name');
    if (slots.isEmpty) return group;
    for (final (node, rel) in meshNodes(template)) {
      if (filter != null && !filter(node.name)) continue;
      for (final prim in node.mesh!.primitives) {
        final mat = materialFor?.call(node.name, prim.material) ?? prim.material;
        final im = fs.InstancedMesh(
            geometry: prim.geometry, material: mat, cullInstances: slots.length > 8);
        for (final s in slots) {
          im.addInstance(s * rel);
        }
        group.add(fs.Node(name: '${name}_${node.name}')
          ..addComponent(fs.InstancedMeshComponent(im)));
      }
    }
    return group;
  }

  /// Applies [fn] to every primitive material under [root].
  static void forEachMaterial(
      fs.Node root, void Function(String meshNodeName, fs.MeshPrimitive prim) fn) {
    for (final (node, _) in meshNodes(root)) {
      for (final p in node.mesh!.primitives) {
        fn(node.name, p);
      }
    }
  }

  /// Shallow copy of a physically based material (so one instance can be
  /// lit independently of the shared glTF material).
  static fs.PhysicallyBasedMaterial clonePbr(fs.Material m) {
    if (m is! fs.PhysicallyBasedMaterial) {
      return fs.PhysicallyBasedMaterial()..baseColorFactor = vm.Vector4(1, 1, 1, 1);
    }
    return fs.PhysicallyBasedMaterial(
      baseColorTexture: m.baseColorTexture,
      metallicRoughnessTexture: m.metallicRoughnessTexture,
      normalTexture: m.normalTexture,
      emissiveTexture: m.emissiveTexture,
      occlusionTexture: m.occlusionTexture,
    )
      ..baseColorFactor = m.baseColorFactor.clone()
      ..metallicFactor = m.metallicFactor
      ..roughnessFactor = m.roughnessFactor
      ..emissiveFactor = m.emissiveFactor.clone()
      ..emissiveStrength = m.emissiveStrength
      ..alphaMode = m.alphaMode
      ..doubleSided = m.doubleSided;
  }
}
