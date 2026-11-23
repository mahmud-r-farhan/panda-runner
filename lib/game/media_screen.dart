import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_scene/scene.dart' as fs;

/// The Scramble media facade's animated screen — port of the demo's
/// `Rg()`/`zg()` canvas (gradient backdrop, scanlines, 16 equaliser bars,
/// NEON / NEON SCRAMBLE / ネオンスクランブル, Google dots), redrawn ~8×/s.
class MediaScreen {
  MediaScreen(this.material);
  final fs.PhysicallyBasedMaterial material;
  final Float32List _eq = Float32List(16);
  double _last = -1;
  bool _busy = false;

  static const _kh = [
    Color(0xFFFF4F00), Color(0xFF4285F4), Color(0xFFEA4335),
    Color(0xFFFBBC05), Color(0xFF34A853), Color(0xFF38BDF8),
  ];

  Future<void> update(double t, double voltage, {bool force = false}) async {
    if (_busy) return;
    if (!force && _last >= 0 && (t - _last).abs() < 0.12) return;
    _last = t;
    _busy = true;
    try {
      final img = await _draw(t, voltage);
      try {
        final tex = await fs.Texture2D.fromImage(img);
        material.baseColorTexture = tex;
        material.emissiveTexture = tex;
      } finally {
        img.dispose();
      }
    } finally {
      _busy = false;
    }
  }

  Future<ui.Image> _draw(double t, double v) async {
    const l = 512.0, u = 512.0;
    final rec = ui.PictureRecorder();
    final s = Canvas(rec);
    s.drawRect(
        const Rect.fromLTWH(0, 0, l, u),
        Paint()
          ..shader = ui.Gradient.linear(const Offset(0, 0), const Offset(l, u),
              const [Color(0xFF0A1836), Color(0xFF172A54), Color(0xFF221338)], const [0, 0.5, 1]));
    final scan = Paint()
      ..color = const Color(0x2938BDF8)
      ..strokeWidth = 2;
    for (double e = 24; e < u; e += 32) {
      s.drawLine(Offset(0, e), Offset(l, e), scan);
    }
    final f = 0.5 + 0.5 * math.sin(t * 3.8);
    final p = (l - 72) / 16;
    for (int e = 0; e < 16; e++) {
      final target = 0.14 + 0.64 * math.pow(math.sin(t * 3.8 + e * 0.62).abs(), 1.35);
      _eq[e] = _eq[e] + (target - _eq[e]) * 0.35;
      final o = (_eq[e] * 124).clamp(10.0, 126.0);
      final c = 36 + e * p + 4, top = u - 38 - o;
      s.drawRect(Rect.fromLTWH(c, top, p - 8, o), Paint()..color = _kh[e % _kh.length]);
    }
    s.drawRect(
        const Rect.fromLTWH(20, 22, l - 40, u - 44),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..color = f > 0.5 ? const Color(0xFF38BDF8) : const Color(0xFFFF4F00));
    s.drawRect(const Rect.fromLTWH(40, 44, l - 80, 6), Paint()..color = const Color(0xFFFF4F00));
    s.drawRect(Rect.fromLTWH(40, 56, (l - 80) * (0.4 + 0.6 * (v / 15).clamp(0.0, 1.0)), 4),
        Paint()..color = const Color(0xFF38BDF8));
    void text(String str, double size, Color col, double y, String family) {
      final tp = TextPainter(
        text: TextSpan(
            text: str,
            style: TextStyle(
                fontFamily: family,
                fontFamilyFallback: const ['NotoSansJP', 'Inter'],
                fontSize: size,
                fontWeight: FontWeight.w900,
                color: col,
                height: 1)),
        textDirection: TextDirection.ltr,
      )..layout();
      final k = tp.width > l - 76 ? (l - 76) / tp.width : 1.0;
      s.save();
      s.translate(l / 2, y);
      s.scale(k, 1);
      tp.paint(s, Offset(-tp.width / 2, -tp.height / 2));
      s.restore();
    }

    text('NEON', 76, const Color(0xFFFFFFFF), 168, 'Inter');
    text('NEON SCRAMBLE', 41, const Color(0xFF38BDF8), 226, 'Inter');
    text('ネオンスクランブル', 31, f > 0.5 ? const Color(0xFFFBBC05) : const Color(0xFFFF7A33), 272,
        'NotoSansJP');
    const h = [Color(0xFF4285F4), Color(0xFFEA4335), Color(0xFFFBBC05), Color(0xFF34A853)];
    for (int e = 0; e < 4; e++) {
      final n = 11.5 + 3 * math.sin(t * 5 + e * 1.4);
      s.drawCircle(Offset(l / 2 - 78 + e * 52, 320), n, Paint()..color = h[e]);
    }
    final pic = rec.endRecording();
    final img = await pic.toImage(l.toInt(), u.toInt());
    pic.dispose();
    return img;
  }
}
