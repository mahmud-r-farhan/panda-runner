import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_scene/scene.dart' as fs;

/// Blue MLIT road-sign face (port of the demo's `Ag()` atlas cell, drawn at
/// half resolution: 512 x 256): gradient board, lamp glows, white border,
/// main Japanese + English names, route shield and two direction rows.
class AoKanbanFace {
  static Future<fs.Texture2D> create(Map<String, dynamic> sign) async {
    const t = 1024.0, h = 512.0;
    final rec = ui.PictureRecorder();
    final r = Canvas(rec);
    r.scale(0.5);
    final green = sign['style'] == 'viaduct_green' || sign['onViaduct'] == true;
    r.drawRect(
        const Rect.fromLTWH(0, 0, t, h),
        Paint()
          ..shader = ui.Gradient.linear(const Offset(0, 0), const Offset(0, h),
              green
                  ? const [Color(0xFF0A7C45), Color(0xFF006837), Color(0xFF004D28)]
                  : const [Color(0xFF0B62BE), Color(0xFF0052A5), Color(0xFF003A7A)],
              const [0, 0.45, 1]));
    for (final e in [0.29, 0.71]) {
      final c = Offset(t * e, 26 + 85);
      r.drawRect(
          const Rect.fromLTWH(0, 0, t, h),
          Paint()
            ..shader = ui.Gradient.radial(c, 290, const [
              Color(0x3DFFFAE8),
              Color(0x14DCF0FF),
              Color(0x00DCF0FF),
            ], const [0, 0.45, 1]));
    }
    r.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(22, 22, 980, 468), const Radius.circular(28)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 12
          ..color = const Color(0xFFFFFFFF));
    r.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(36, 36, 952, 440), const Radius.circular(20)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = green ? const Color(0x66BBF7D0) : const Color(0x6BBAE0FF));
    final d = ((sign['mainJa'] as String?) ?? '渋谷').trim();
    final f = ((sign['mainEn'] as String?) ?? 'SHIBUYA').trim().toUpperCase();
    final p = (sign['routeShield'] as String?)?.trim();
    if (p != null && p.isNotEmpty) shield(r, p, 132, 132, 92);
    final m = p != null && p.isNotEmpty ? 216.0 : 64.0;
    final hw = t - m - 64;
    final g = p != null && p.isNotEmpty ? m + hw * 0.46 : t * 0.5;
    _text(r, d, g, 114, d.length >= 9 ? 66 : (d.length >= 6 ? 78 : 92), FontWeight.w900,
        const Color(0xFFFFFFFF), hw, align: 0.5);
    _text(r, f, g, 194, f.length >= 16 ? 34 : 40, FontWeight.w800,
        green ? const Color(0xFFDCFCE7) : const Color(0xFFDCEFFF), hw, align: 0.5);
    r.drawLine(const Offset(56, 244), const Offset(t - 56, 244),
        Paint()
          ..color = const Color(0x9EFFFFFF)
          ..strokeWidth = 4);
    final subs = ((sign['subDirections'] as List<dynamic>?) ?? const []).take(2).toList();
    for (int e = 0; e < subs.length; e++) {
      var n = (subs[e] as String? ?? '').trim();
      final y = subs.length == 1 ? 356.0 : 306.0 + e * 98;
      var dir = 'up';
      if (n.startsWith('←')) {
        dir = 'left';
        n = n.substring(1).trim();
      } else if (n.startsWith('→')) {
        dir = 'right';
        n = n.substring(1).trim();
      } else if (n.startsWith('↑')) {
        n = n.substring(1).trim();
      }
      String? u;
      if (n.contains('[305]')) {
        u = '305';
        n = n.replaceAll('[305]', '').trim();
      } else if (n.contains('[246]')) {
        u = '246';
        n = n.replaceAll('[246]', '').trim();
      } else if (n.contains('首都高3号') || n.contains('No. 3')) {
        u = '3';
      }
      final li = n.indexOf(RegExp('[A-Za-z]'));
      final ja = li > 0 ? n.substring(0, li).trim() : n;
      final en = li > 0 ? n.substring(li).trim() : '';
      r.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(58, y - 38, 908, 76), const Radius.circular(12)),
          Paint()..color = const Color(0x14FFFFFF));
      _arrow(r, dir, 108, y, 44);
      const mx = 156.0;
      final hx = t - (u != null ? 156 : 74);
      final gw = math.max(200.0, hx - mx);
      final jw = _text(r, ja, mx, y, 38, FontWeight.w800, const Color(0xFFFFFFFF), gw * 0.54);
      if (en.isNotEmpty) {
        _text(r, en, mx + math.min(gw * 0.52, jw) + 22, y + 2, 28, FontWeight.w700,
            green ? const Color(0xFFBBF7D0) : const Color(0xFFCFE7FF), math.max(120, gw - jw - 22));
      }
      if (u != null) shield(r, u, t - 108, y, 50);
    }
    final img = await rec.endRecording().toImage(512, 256);
    return fs.Texture2D.fromImage(img);
  }

  /// Draws text left-aligned (align 0) or centred (0.5), squeezed to maxW.
  static double _text(Canvas c, String s, double x, double y, double size, FontWeight w, Color col,
      double maxW, {double align = 0}) {
    final tp = TextPainter(
      text: TextSpan(
          text: s,
          style: TextStyle(
              fontFamily: 'NotoSansJP',
              fontFamilyFallback: const ['Inter'],
              fontSize: size,
              fontWeight: w,
              color: col,
              height: 1)),
      textDirection: TextDirection.ltr,
    )..layout();
    final k = tp.width > maxW ? maxW / tp.width : 1.0;
    c.save();
    c.translate(x, y);
    c.scale(k, 1);
    tp.paint(c, Offset(-tp.width * align, -tp.height / 2));
    c.restore();
    return tp.width * k;
  }

  static void _arrow(Canvas c, String dir, double x, double y, double i) {
    c.save();
    c.translate(x, y);
    if (dir == 'left') c.rotate(-math.pi / 2);
    if (dir == 'right') c.rotate(math.pi / 2);
    final a = i * 0.5;
    c.drawPath(
        Path()
          ..moveTo(0, -a)
          ..lineTo(a * 0.78, -a * 0.14)
          ..lineTo(a * 0.3, -a * 0.14)
          ..lineTo(a * 0.3, a)
          ..lineTo(-a * 0.3, a)
          ..lineTo(-a * 0.3, -a * 0.14)
          ..lineTo(-a * 0.78, -a * 0.14)
          ..close(),
        Paint()..color = const Color(0xFFFFFFFF));
    c.restore();
  }

  /// Port of `Dg()`: route shields (305 hexagon, 246 shield, LOOP, other).
  static void shield(Canvas c, String t0, double x, double y, double i) {
    final a = t0.trim().toUpperCase();
    c.save();
    c.translate(x, y);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..color = const Color(0xFFFFFFFF);
    Path path;
    Color fill, textCol = const Color(0xFFFFFFFF);
    double fs0;
    if (a == '305') {
      final t = i * 0.62, n = i * 0.5;
      path = Path()
        ..moveTo(-t * 0.56, -n)
        ..lineTo(t * 0.56, -n)
        ..lineTo(t, 0)
        ..lineTo(t * 0.56, n)
        ..lineTo(-t * 0.56, n)
        ..lineTo(-t, 0)
        ..close();
      fill = const Color(0xFFF59E0B);
      textCol = const Color(0xFF0B1220);
      stroke.strokeWidth = math.max(2.5, i * 0.08);
      fs0 = i * 0.44;
    } else if (a == '246') {
      final t = i * 0.54;
      path = Path()
        ..moveTo(-t * 0.88, -t * 0.58)
        ..quadraticBezierTo(0, -t * 0.96, t * 0.88, -t * 0.58)
        ..quadraticBezierTo(t * 1.02, t * 0.25, 0, t * 0.96)
        ..quadraticBezierTo(-t * 1.02, t * 0.25, -t * 0.88, -t * 0.58)
        ..close();
      fill = const Color(0xFF003C82);
      stroke.strokeWidth = math.max(2.5, i * 0.085);
      fs0 = i * 0.4;
    } else if (a == 'LOOP') {
      final t = i * 0.72, n = i * 0.44;
      path = Path()..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(-t, -n, t * 2, n * 2), Radius.circular(n)));
      fill = const Color(0xFF16A34A);
      stroke.strokeWidth = math.max(2.5, i * 0.075);
      fs0 = i * 0.36;
    } else {
      final t = i * 0.46;
      path = Path()
        ..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(-t, -t, t * 2, t * 2), Radius.circular(i * 0.14)));
      fill = const Color(0xFF047857);
      stroke.strokeWidth = math.max(2.5, i * 0.08);
      fs0 = i * 0.5;
    }
    c.drawPath(path, Paint()..color = fill);
    c.drawPath(path, stroke);
    final tp = TextPainter(
      text: TextSpan(
          text: a,
          style: TextStyle(
              fontFamily: 'Inter', fontSize: fs0, fontWeight: FontWeight.w900, color: textCol, height: 1)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, Offset(-tp.width / 2, -tp.height / 2 + (a == '246' ? -i * 0.04 : 0)));
    c.restore();
  }
}
