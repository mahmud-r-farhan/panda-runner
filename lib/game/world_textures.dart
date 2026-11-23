import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/painting.dart';
import 'package:flutter_scene/scene.dart' as fs;

import 'level_data.dart';

/// Procedurally painted textures for the Shibuya night city (window facades,
/// the dark-mode Google-Maps style ground, and neon sign faces).
class WorldTextures {
  late final fs.Texture2D facadeBase;
  late final fs.Texture2D facadeGlow;
  late final fs.Texture2D glassBase;
  late final fs.Texture2D glassGlow;
  late final fs.Texture2D brickBase;
  late final fs.Texture2D brickGlow;
  late final fs.Texture2D shopBase;
  late final fs.Texture2D shopGlow;
  late final fs.Texture2D ground;
  late final fs.Texture2D wallRun;
  late final fs.Texture2D hazardStripe;
  late final fs.Texture2D sidewalk;
  late final fs.Texture2D asphaltNormal;
  late final fs.Texture2D sidewalkRough;
  late final fs.Texture2D wetAsphalt;
  final List<fs.Texture2D> googleGlyphs = [];

  static Future<WorldTextures> create(ShibuyaLevel level) async {
    final t = WorldTextures();
    final f = await _facade(seed: 7, glass: false);
    t.facadeBase = await fs.Texture2D.fromImage(f.$1);
    t.facadeGlow = await fs.Texture2D.fromImage(f.$2);
    final g = await _facade(seed: 19, glass: true);
    t.glassBase = await fs.Texture2D.fromImage(g.$1);
    t.glassGlow = await fs.Texture2D.fromImage(g.$2);
    final br = await _facade(seed: 31, glass: false, brick: true);
    t.brickBase = await fs.Texture2D.fromImage(br.$1);
    t.brickGlow = await fs.Texture2D.fromImage(br.$2);
    final sh = await _storefront();
    t.shopBase = await fs.Texture2D.fromImage(sh.$1);
    t.shopGlow = await fs.Texture2D.fromImage(sh.$2);
    t.ground = await fs.Texture2D.fromImage(await _ground(level));
    t.wallRun = await fs.Texture2D.fromImage(await _wallRunTex());
    t.hazardStripe = await fs.Texture2D.fromImage(await _hazardTex());
    t.asphaltNormal = fs.Texture2D.fromPixels(_asphaltNormal(), 512, 512,
        content: fs.TextureContent.data, sampling: const fs.TextureSampling(maxAnisotropy: 4));
    final sw = _sidewalkTex();
    t.sidewalk = fs.Texture2D.fromPixels(sw.$1, 512, 512, sampling: const fs.TextureSampling(maxAnisotropy: 4));
    t.sidewalkRough = fs.Texture2D.fromPixels(sw.$2, 512, 512,
        content: fs.TextureContent.data, sampling: const fs.TextureSampling(maxAnisotropy: 4));
    t.wetAsphalt = await _wetRoughness();
    for (final ch in ['G', 'o', 'o', 'g', 'l', 'e']) {
      t.googleGlyphs.add(await fs.Texture2D.fromImage(await _glyph(ch)));
    }
    return t;
  }

  /// A tile of 8 x 16 windows. Returns (base colour, emissive) images.
  static Future<(ui.Image, ui.Image)> _facade(
      {required int seed, required bool glass, bool brick = false}) async {
    const w = 256, h = 512, cols = 8, rows = 16;
    final rng = math.Random(seed);
    final rb = ui.PictureRecorder();
    final re = ui.PictureRecorder();
    final cb = Canvas(rb);
    final ce = Canvas(re);
    final wall = brick
        ? const Color(0xFF3A2A2E)
        : (glass ? const Color(0xFF1B2D57) : const Color(0xFF17264A));
    cb.drawRect(const Rect.fromLTWH(0, 0, 256, 512), Paint()..color = wall);
    // faint facade self-illumination so towers read as deep sapphire blue
    ce.drawRect(const Rect.fromLTWH(0, 0, 256, 512),
        Paint()
          ..color = brick
              ? const Color(0xFF140F16)
              : (glass ? const Color(0xFF0E1A3A) : const Color(0xFF0B1531)));
    if (brick) {
      // brick coursing
      final mortar = Paint()..color = const Color(0xFF2C2024);
      for (double y = 0; y < 512; y += 8) {
        cb.drawRect(Rect.fromLTWH(0, y, 256, 1.5), mortar);
      }
    }
    final cw = w / cols, chh = h / rows;
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final rect = Rect.fromLTWH(c * cw + cw * 0.18, r * chh + chh * 0.22,
            cw * 0.64, chh * 0.5);
        final roll = rng.nextDouble();
        Color base;
        Color glow;
        if (roll < 0.22) {
          base = const Color(0xFFFFD08A);
          glow = Color.lerp(const Color(0xFFFFB45A), const Color(0xFFFFE2A8),
              rng.nextDouble())!;
        } else if (roll < 0.38) {
          base = const Color(0xFFA9D2FF);
          glow = Color.lerp(const Color(0xFF6FA8FF), const Color(0xFFCFE6FF),
              rng.nextDouble())!;
        } else {
          base = const Color(0xFF0E1830);
          glow = const Color(0xFF060C1C);
        }
        cb.drawRect(rect, Paint()..color = base);
        ce.drawRect(rect, Paint()..color = glow);
      }
    }
    // horizontal floor slab lines
    final slab = Paint()
      ..color = brick ? const Color(0xFF4A3638) : const Color(0xFF223766);
    for (int r = 0; r <= rows; r++) {
      cb.drawRect(Rect.fromLTWH(0, r * chh - 1.5, 256, 3), slab);
    }
    final a = await rb.endRecording().toImage(w, h);
    final b = await re.endRecording().toImage(w, h);
    return (a, b);
  }

  static final Map<String, fs.Texture2D> _signCache = {};

  static TextPainter _tp(String t, double size, FontWeight w, Color c) =>
      TextPainter(
        text: TextSpan(
          text: t,
          style: TextStyle(
              fontFamily: 'NotoSansJP',
              fontFamilyFallback: const ['Inter'],
              fontSize: size,
              fontWeight: w,
              color: c,
              height: 1.0),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

  static void _paintCentered(Canvas c, TextPainter tp, double cx, double cy,
      {bool rotate = false, double maxWidth = 1e9}) {
    c.save();
    c.translate(cx, cy);
    if (rotate) c.rotate(math.pi / 2);
    final k = tp.width > maxWidth ? maxWidth / tp.width : 1.0;
    c.scale(k, 1);
    tp.paint(c, Offset(-tp.width / 2, -tp.height / 2));
    c.restore();
  }

  /// Port of the demo's `Mg()` kanji blade-sign cell (192 x 768, vertical).
  static Future<fs.Texture2D> bladeSign(String text) async {
    final key = 'blade:$text';
    if (_signCache[key] != null) return _signCache[key]!;
    const w = 192.0, h = 768.0;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.drawRect(const Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0xFF070B15));
    c.drawRect(const Rect.fromLTWH(6, 8, 180, 752), Paint()..color = const Color(0xFF091020));
    c.drawRect(const Rect.fromLTWH(16, 18, 160, 732),
        Paint()..style = PaintingStyle.stroke..strokeWidth = 7..color = const Color(0xFFFFFFFF));
    c.drawRect(const Rect.fromLTWH(26, 28, 140, 712),
        Paint()..style = PaintingStyle.stroke..strokeWidth = 2.5..color = const Color(0x73FFFFFF));
    final chars = text.split('').where((e) => e != ' ').toList();
    final o = 652 / math.max(1, chars.length);
    final latin = RegExp(r'^[A-Z ]+$').hasMatch(text);
    final size = latin
        ? (o * 0.84).floorToDouble().clamp(40.0, 82.0)
        : (o * 0.82).floorToDouble().clamp(54.0, 108.0);
    for (int i = 0; i < chars.length; i++) {
      _paintCentered(c, _tp(chars[i], size, FontWeight.w900, const Color(0xFFFFFFFF)),
          96, 58 + o * (i + 0.5), rotate: chars[i] == 'ー');
    }
    final img = await rec.endRecording().toImage(w.toInt(), h.toInt());
    return _signCache[key] = await fs.Texture2D.fromImage(img);
  }

  /// Port of `Ng()` wide billboard cell (512 x 256).
  static Future<fs.Texture2D> wideBillboard(String text, int index) async {
    final sub = index.isEven ? 'NEON SCRAMBLE' : 'ネオンスクランブル';
    final key = 'wide:$text:$sub';
    if (_signCache[key] != null) return _signCache[key]!;
    const w = 512.0, h = 256.0;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.drawRect(const Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0xFF080D18));
    c.drawRect(const Rect.fromLTWH(8, 8, 496, 240), Paint()..color = const Color(0xFF0B1324));
    final line = Paint()..color = const Color(0x14FFFFFF)..strokeWidth = 2;
    for (double y = 22; y < 240; y += 16) {
      c.drawLine(Offset(18, y), Offset(w - 18, y), line);
    }
    c.drawRect(const Rect.fromLTWH(18, 18, 476, 220),
        Paint()..style = PaintingStyle.stroke..strokeWidth = 8..color = const Color(0xFFFFFFFF));
    final short = text.length <= 4;
    _paintCentered(c, _tp(text, short ? 104 : 54, FontWeight.w900, const Color(0xFFFFFFFF)),
        256, short ? 104 : 108, maxWidth: 448);
    _paintCentered(c, _tp(sub, 28, FontWeight.w700, const Color(0xD1FFFFFF)), 256, 192,
        maxWidth: 440);
    final img = await rec.endRecording().toImage(w.toInt(), h.toInt());
    return _signCache[key] = await fs.Texture2D.fromImage(img);
  }

  /// Port of `Pg()` tall billboard cell (256 x 640, vertical).
  static Future<fs.Texture2D> tallBillboard(String text) async {
    final key = 'tall:$text';
    if (_signCache[key] != null) return _signCache[key]!;
    const w = 256.0, h = 640.0;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.drawRect(const Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0xFF080D18));
    c.drawRect(const Rect.fromLTWH(8, 8, 240, 624), Paint()..color = const Color(0xFF0B1324));
    c.drawRect(const Rect.fromLTWH(18, 18, 220, 604),
        Paint()..style = PaintingStyle.stroke..strokeWidth = 8..color = const Color(0xFFFFFFFF));
    c.drawRect(const Rect.fromLTWH(30, 30, 196, 580),
        Paint()..style = PaintingStyle.stroke..strokeWidth = 3..color = const Color(0x6BFFFFFF));
    final chars = text.split('').where((e) => e != ' ').toList();
    final a = 536 / math.max(1, chars.length);
    final latin = RegExp(r'^[A-Z ]+$').hasMatch(text);
    final size = latin
        ? (a * 0.84).floorToDouble().clamp(38.0, 86.0)
        : (a * 0.82).floorToDouble().clamp(48.0, 96.0);
    for (int i = 0; i < chars.length; i++) {
      _paintCentered(c, _tp(chars[i], size, FontWeight.w900, const Color(0xFFFFFFFF)),
          128, 54 + a * (i + 0.5), rotate: chars[i] == 'ー');
    }
    final img = await rec.endRecording().toImage(w.toInt(), h.toInt());
    return _signCache[key] = await fs.Texture2D.fromImage(img);
  }

  /// White glyph on black for the emissive Google sign letters.
  static Future<ui.Image> _glyph(String ch) async {
    const w = 128, h = 160;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.drawRect(const Rect.fromLTWH(0, 0, 128, 160), Paint()..color = const Color(0xFF000000));
    final tp = TextPainter(
      text: TextSpan(
        text: ch,
        style: const TextStyle(
            fontFamily: 'Inter', fontSize: 132, fontWeight: FontWeight.w600,
            color: Color(0xFFFFFFFF), height: 1.0),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, Offset((w - tp.width) / 2, (h - tp.height) / 2 - 8));
    return rec.endRecording().toImage(w, h);
  }

  static double _h21(double x, double y) {
    var px = (x * 127.1) % 1.0, py = (y * 311.7) % 1.0;
    if (px < 0) px += 1;
    if (py < 0) py += 1;
    final d = px * (px + 34.12) + py * (py + 34.12);
    px += d;
    py += d;
    final v = (px * py) % 1.0;
    return v < 0 ? v + 1 : v;
  }

  static double _vn(double x, double y) {
    final ix = x.floorToDouble(), iy = y.floorToDouble();
    var fx = x - ix, fy = y - iy;
    fx = fx * fx * (3 - 2 * fx);
    fy = fy * fy * (3 - 2 * fy);
    final a = _h21(ix, iy), b = _h21(ix + 1, iy), c = _h21(ix, iy + 1), d = _h21(ix + 1, iy + 1);
    return (a + (b - a) * fx) + ((c + (d - c) * fx) - (a + (b - a) * fx)) * fy;
  }

  /// Puddle roughness map: the demo's `shibuyaWetSheen` FBM + micro breakup
  /// baked in world space over the whole 1180 m asphalt plane (G = roughness
  /// 0.34 wet .. 0.68 damp, B = metalness .06). Texel (i, j) is demo
  /// (x, z) = (-590 + 1180 (i + .5) / n, -590 + 1180 (j + .5) / n).
  static const int wetMapSize = 2048;
  static Future<fs.Texture2D> _wetRoughness() async {
    const n = wetMapSize;
    const metres = 1180.0;
    final px = Uint8List(n * n * 4);
    double smooth(double e0, double e1, double x) {
      final t = ((x - e0) / (e1 - e0)).clamp(0.0, 1.0);
      return t * t * (3 - 2 * t);
    }

    final sw = Stopwatch()..start();
    for (int j = 0; j < n; j++) {
      final wz = -590 + (j + 0.5) / n * metres;
      for (int i = 0; i < n; i++) {
        final wx = -590 + (i + 0.5) / n * metres;
        var qx = wx * 0.028, qz = wz * 0.028;
        var v = _vn(qx, qz) * 0.44;
        // GLSL mat2(.8, -.6, .6, .8) (column-major) * q.
        var rx = 0.8 * qx + 0.6 * qz, rz = -0.6 * qx + 0.8 * qz;
        qx = rx * 2.15 + 11.3;
        qz = rz * 2.15 + 7.1;
        v += _vn(qx, qz) * 0.30;
        rx = 0.8 * qx + 0.6 * qz;
        rz = -0.6 * qx + 0.8 * qz;
        qx = rx * 2.08 + 23.7;
        qz = rz * 2.08 + 17.9;
        v += _vn(qx, qz) * 0.17;
        rx = 0.8 * qx + 0.6 * qz;
        rz = -0.6 * qx + 0.8 * qz;
        qx = rx * 2.12 + 5.1;
        qz = rz * 2.12 + 13.4;
        v += _vn(qx, qz) * 0.09;
        final wet = smooth(0.28, 0.78, v);
        final micro = _vn(wx * 0.24 + 3.7, wz * 0.24 - 5.1);
        final fine = _vn(wx * 0.72 - 9.2, wz * 0.72 + 4.4);
        final breakup = (wet * (0.68 + 0.56 * micro) - 0.10 * (1 - fine)).clamp(0.0, 1.0);
        final rough = 0.68 + (0.34 - 0.68) * breakup;
        final o = (j * n + i) * 4;
        px[o] = 255;
        px[o + 1] = (rough * 255).round();
        px[o + 2] = 15;
        px[o + 3] = 255;
      }
    }
    debugPrint('wet asphalt map baked in ${sw.elapsedMilliseconds} ms');
    return fs.Texture2D.fromPixels(px, n, n,
        content: fs.TextureContent.data, sampling: const fs.TextureSampling(maxAnisotropy: 4));
  }

  static double _lgh(double e, double t) {
    final n = math.sin(e * 127.1 + t * 311.7) * 43758.5453123;
    return n - n.floorToDouble();
  }

  /// Normal map half of the demo's `wg()` asphalt: tileable value-noise
  /// FBM + per-pixel hash grain, central-difference normals (x1.45).
  static Uint8List _asphaltNormal() {
    const n = 512;
    double lerp(double a, double b, double t) => a + (b - a) * t;
    double c(double e, double t, int per) {
      final r = e.floor(), i = t.floor();
      final a = e - r, o = t - i;
      final s = a * a * (3 - 2 * a), cc = o * o * (3 - 2 * o);
      final l = ((r % per) + per) % per, u = (l + 1) % per;
      final d = ((i % per) + per) % per, f = (d + 1) % per;
      final p = _lgh(l * 17.0 + per * 3, d * 31.0 + 7), m = _lgh(u * 17.0 + per * 3, d * 31.0 + 7);
      final h = _lgh(l * 17.0 + per * 3, f * 31.0 + 7), g = _lgh(u * 17.0 + per * 3, f * 31.0 + 7);
      return lerp(lerp(p, m, s), lerp(h, g, s), cc);
    }

    final hgt = Float32List(n * n);
    for (int e = 0; e < n; e++) {
      for (int t = 0; t < n; t++) {
        final r = t / n, i = e / n;
        final o = c(r * 6, i * 6, 6), l = c(r * 12 + 3.1, i * 12 + 1.7, 12), u = c(r * 24 + 5.3, i * 24 + 4.9, 24);
        final d = o * 0.5 + l * 0.32 + u * 0.18;
        final f = _lgh(((t * 1.13).floor() & 511).toDouble(), ((e * 1.13).floor() & 511).toDouble()) - 0.5;
        final p = _lgh(((t * 2 + 17) & 511).toDouble(), ((e * 2 + 31) & 511).toDouble()) - 0.5;
        hgt[e * n + t] = (d - 0.5) * 0.1 + (f * 0.45 + p * 0.28) * 0.72;
      }
    }
    final out = Uint8List(n * n * 4);
    for (int e = 0; e < n; e++) {
      final t0 = (e - 1 + n) & 511, n1 = (e + 1) & 511;
      for (int r = 0; r < n; r++) {
        final i0 = (r - 1 + n) & 511, a1 = (r + 1) & 511;
        final cx = (hgt[e * n + a1] - hgt[e * n + i0]) * 1.45;
        final ly = (hgt[n1 * n + r] - hgt[t0 * n + r]) * 1.45;
        final u = math.sqrt(cx * cx + ly * ly + 1);
        final k = (e * n + r) * 4;
        out[k] = ((-cx / u * 0.5 + 0.5) * 255).round().clamp(0, 255);
        out[k + 1] = ((-ly / u * 0.5 + 0.5) * 255).round().clamp(0, 255);
        out[k + 2] = ((1 / u * 0.5 + 0.5) * 255).round().clamp(128, 255);
        out[k + 3] = 255;
      }
    }
    return out;
  }

  /// Port of the demo's `Eg()` granite paving: 8 x 8 slabs (60 px, 2 px
  /// joints #0F141E) of rgb(28..42, +6, +15) on #1B2230, and the matching
  /// roughness canvas (#767676 joints, 72..130 per slab). Returns (sRGB
  /// colour pixels, metallic-roughness pixels with G = roughness, B = 1).
  static (Uint8List, Uint8List) _sidewalkTex() {
    const n = 512;
    final col = Uint8List(n * n * 4), mr = Uint8List(n * n * 4);
    for (int k = 0; k < n * n; k++) {
      col[k * 4] = 0x1B;
      col[k * 4 + 1] = 0x22;
      col[k * 4 + 2] = 0x30;
      col[k * 4 + 3] = 255;
      mr[k * 4] = 255;
      mr[k * 4 + 1] = 0x76;
      mr[k * 4 + 2] = 255;
      mr[k * 4 + 3] = 255;
    }
    for (int e = 0; e < 8; e++) {
      for (int t = 0; t < 8; t++) {
        final r = _lgh(t * 19.0 + 5, e * 23.0 + 11);
        final a = (28 + r * 14).round();
        final o = (72 + (1 - r) * 58).round();
        for (int y = e * 64 + 2; y < e * 64 + 62; y++) {
          for (int x = t * 64 + 2; x < t * 64 + 62; x++) {
            final k = (y * n + x) * 4;
            col[k] = a;
            col[k + 1] = a + 6;
            col[k + 2] = a + 15;
            mr[k + 1] = o;
          }
        }
      }
    }
    // 3 px joint lines every 64 px (stroked on the grid lines)
    for (int g = 0; g <= n; g += 64) {
      for (int d = -1; d <= 1; d++) {
        final q = g + d;
        if (q < 0 || q >= n) continue;
        for (int z = 0; z < n; z++) {
          for (final k in [(z * n + q) * 4, (q * n + z) * 4]) {
            col[k] = 0x0F;
            col[k + 1] = 0x14;
            col[k + 2] = 0x1E;
          }
        }
      }
    }
    return (col, mr);
  }

  /// Port of the demo's `Tg()` hazard stripe texture (256 x 128).
  static Future<ui.Image> _hazardTex() async {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.drawRect(const Rect.fromLTWH(0, 0, 256, 128), Paint()..color = const Color(0xFF161E2E));
    c.save();
    c.clipRect(const Rect.fromLTWH(0, 22, 256, 84));
    c.drawRect(const Rect.fromLTWH(0, 22, 256, 84), Paint()..color = const Color(0xFF111722));
    final amber = Paint()..color = const Color(0xFFF59E0B);
    for (double e = -128; e < 384; e += 48) {
      c.drawPath(
          Path()
            ..moveTo(e, 128)
            ..lineTo(e + 24, 128)
            ..lineTo(e + 24 + 92.16, 0)
            ..lineTo(e + 92.16, 0)
            ..close(),
          amber);
    }
    c.restore();
    final band = Paint()..color = const Color(0xFF2A364D);
    c.drawRect(const Rect.fromLTWH(0, 18, 256, 5), band);
    c.drawRect(const Rect.fromLTWH(0, 105, 256, 5), band);
    c.drawRect(const Rect.fromLTWH(0, 23, 256, 2), Paint()..color = const Color.fromRGBO(255, 255, 255, 0.22));
    return rec.endRecording().toImage(256, 128);
  }

  /// Port of the demo's `Lg()` wall-run panel texture (chevrons).
  static Future<ui.Image> _wallRunTex() async {
    final rec = ui.PictureRecorder();
    final r = Canvas(rec);
    r.drawRect(const Rect.fromLTWH(0, 0, 512, 256), Paint()..color = const Color(0xFF09111E));
    final line = Paint()
      ..color = const Color(0x4038BDF8)
      ..strokeWidth = 3;
    for (double y = 24; y < 256; y += 32) {
      r.drawLine(Offset(0, y), Offset(512, y), line);
    }
    for (int e = 0; e < 4; e++) {
      final t = 74.0 + e * 124;
      r.drawPath(
          Path()
            ..moveTo(t - 28, 56)
            ..lineTo(t + 28, 128)
            ..lineTo(t - 28, 200),
          Paint()
            ..color = e.isEven ? const Color(0xFFFF4F00) : const Color(0xFF38BDF8)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 14
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round);
    }
    return rec.endRecording().toImage(512, 256);
  }

  /// Ground-floor shopfront band: big warm-lit panes between dark mullions.
  static Future<(ui.Image, ui.Image)> _storefront() async {
    const w = 256, h = 128;
    final rb = ui.PictureRecorder();
    final re = ui.PictureRecorder();
    final cb = Canvas(rb);
    final ce = Canvas(re);
    cb.drawRect(const Rect.fromLTWH(0, 0, 256, 128), Paint()..color = const Color(0xFF1A1418));
    ce.drawRect(const Rect.fromLTWH(0, 0, 256, 128), Paint()..color = const Color(0xFF000000));
    final rng = math.Random(5);
    for (int i = 0; i < 4; i++) {
      final x = i * 64.0;
      final lit = rng.nextDouble() < 0.8;
      final pane = Rect.fromLTWH(x + 5, 22, 54, 100);
      final warm = Color.lerp(const Color(0xFFFFB866), const Color(0xFFFFE0B0), rng.nextDouble())!;
      cb.drawRect(pane, Paint()..color = lit ? warm : const Color(0xFF2A2230));
      ce.drawRect(pane, Paint()..color = lit ? warm : const Color(0xFF0A0810));
      // mullions
      final mull = Paint()..color = const Color(0xFF15111A);
      cb.drawRect(Rect.fromLTWH(x + 31, 22, 3, 100), mull);
      ce.drawRect(Rect.fromLTWH(x + 31, 22, 3, 100), Paint()..color = const Color(0xFF000000));
      // fascia / awning strip
      cb.drawRect(Rect.fromLTWH(x, 6, 64, 12), Paint()..color = const Color(0xFF2B2230));
    }
    final a = await rb.endRecording().toImage(w, h);
    final b = await re.endRecording().toImage(w, h);
    return (a, b);
  }

  /// World-space ground texture over the overview bounds, adapted from the
  /// demo's `DarkModeGoogleMapsGround` canvas (roads, crosswalks, rails,
  /// parks, station platforms, river). 1 texel ≈ 0.46 m.
  static Future<ui.Image> _ground(ShibuyaLevel level) async {
    final ov = level.overview;
    final b = ov['bounds'] as Map<String, dynamic>;
    final minX = (b['minX'] as num).toDouble();
    final maxX = (b['maxX'] as num).toDouble();
    final minZ = (b['minZ'] as num).toDouble();
    final maxZ = (b['maxZ'] as num).toDouble();
    const c = 2048.0;
    final sx = c / (maxX - minX), sz = c / (maxZ - minZ);
    Offset p(XZ q) => Offset((q.x - minX) * sx, (q.z - minZ) * sz);
    // The demo paints at 4096 px; convert its pixel widths.
    double w(double px4096) => px4096 * 0.5;

    final rec = ui.PictureRecorder();
    final cv = Canvas(rec);
    cv.drawRect(const Rect.fromLTWH(0, 0, c, c),
        Paint()..color = const Color(0xFF171E29));

    void strokeLines(List<List<XZ>> lines, Color col, double width) {
      final paint = Paint()
        ..color = col
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final path = Path();
      for (final l in lines) {
        if (l.length < 2) continue;
        path.moveTo(p(l[0]).dx, p(l[0]).dy);
        for (int i = 1; i < l.length; i++) {
          path.lineTo(p(l[i]).dx, p(l[i]).dy);
        }
      }
      cv.drawPath(path, paint);
    }

    void fillPoly(List<XZ> pts, Color fill, Color stroke, double sw) {
      if (pts.length < 3) return;
      final path = Path()..moveTo(p(pts[0]).dx, p(pts[0]).dy);
      for (int i = 1; i < pts.length; i++) {
        path.lineTo(p(pts[i]).dx, p(pts[i]).dy);
      }
      path.close();
      cv.drawPath(path, Paint()..color = fill);
      cv.drawPath(
          path,
          Paint()
            ..color = stroke
            ..style = PaintingStyle.stroke
            ..strokeWidth = sw);
    }

    for (final park in ov['parks'] as List<dynamic>) {
      fillPoly(ShibuyaLevel.pts(park['points']), const Color(0xFF1B3B2B),
          const Color(0xFF2A5E44), w(4));
    }
    final river = ov['river'];
    if (river != null) {
      final rl = [ShibuyaLevel.pts(river['points'])];
      strokeLines(rl, const Color(0xFF1A3A63), w(52));
      strokeLines(rl, const Color(0xFF26538A), w(28));
    }
    for (final st in ov['stations'] as List<dynamic>) {
      fillPoly(ShibuyaLevel.pts(st['points']), const Color(0xFF222D3D),
          const Color(0xFF364963), w(3));
    }
    final roads = ov['roads'] as Map<String, dynamic>;
    List<List<XZ>> rl(String k) => ShibuyaLevel.lines(roads[k]);
    strokeLines(rl('pedestrian'), const Color(0xFF202A3A), w(7));
    strokeLines(rl('local'), const Color(0xFF1D2634), w(18));
    strokeLines(rl('local'), const Color(0xFF283447), w(12));
    strokeLines(rl('secondary'), const Color(0xFF263348), w(30));
    strokeLines(rl('secondary'), const Color(0xFF384862), w(21));
    strokeLines(rl('arterial'), const Color(0xFF2B364A), w(42));
    strokeLines(rl('arterial'), const Color(0xFF445572), w(31));

    final streets = level.streets;
    final poly = streets['scramblePolygon'];
    if (poly is List && poly.length >= 3) {
      final pts = ShibuyaLevel.pts(poly);
      final path = Path()..moveTo(p(pts[0]).dx, p(pts[0]).dy);
      for (final q in pts.skip(1)) {
        path.lineTo(p(q).dx, p(q).dy);
      }
      cv.drawPath(path..close(), Paint()..color = const Color(0xFF3E4E68));
    }
    // Zebra crosswalk stripes
    final cws = (ov['crosswalks'] ?? streets['crosswalks']) as List<dynamic>;
    for (final cw in cws) {
      final s = cw['start'] as List<dynamic>, e = cw['end'] as List<dynamic>;
      final a = p(XZ((s[0] as num).toDouble(), (s[1] as num).toDouble()));
      final bb = p(XZ((e[0] as num).toDouble(), (e[1] as num).toDouble()));
      final d = bb - a;
      final len = d.distance;
      if (len < 3) continue;
      final dir = d / len;
      final nrm = Offset(-dir.dy, dir.dx);
      final half = ((cw['width'] as num?)?.toDouble() ?? 9) * sx * 0.48;
      final count = ((cw['stripeCount'] as num?)?.toInt() ?? 12).clamp(8, 18);
      final paint = Paint()
        ..color = const Color(0xD9E2ECF8)
        ..strokeWidth = math.max(1.5, len / count * 0.45);
      for (int i = 0; i < count; i++) {
        final m = a + d * ((i + 0.5) / count);
        cv.drawLine(m - nrm * half, m + nrm * half, paint);
      }
    }
    strokeLines(rl('expressway'), const Color(0xFF4A3B1E), w(52));
    strokeLines(rl('expressway'), const Color(0xFF8E6E2B), w(34));

    final pic = rec.endRecording();
    return pic.toImage(c.toInt(), c.toInt());
  }
}
