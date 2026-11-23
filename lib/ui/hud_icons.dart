import 'package:flutter/material.dart';

/// Icons hand-converted from the web demo's inline SVGs (18×18 viewBox).
class _SvgIcon extends StatelessWidget {
  const _SvgIcon(this.painter, this.size);
  final CustomPainter painter;
  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: painter);
}

abstract class _IconPainter extends CustomPainter {
  _IconPainter(this.color);
  final Color color;

  void draw(Canvas canvas);

  Paint get strokePaint => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.65
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 18, size.height / 18);
    draw(canvas);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _IconPainter old) => old.color != color;
}

class PlayTriangleIcon extends StatelessWidget {
  const PlayTriangleIcon({super.key, this.size = 15, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => _SvgIcon(_PlayPainter(color), size);
}

class _PlayPainter extends _IconPainter {
  _PlayPainter(super.color);

  @override
  void draw(Canvas canvas) {
    final p = Path()
      ..moveTo(5.2, 3.3)
      ..cubicTo(5.2, 2.5, 6.06, 2.0, 6.76, 2.4)
      ..lineTo(14.91, 7.1)
      ..arcToPoint(const Offset(14.91, 8.9),
          radius: const Radius.circular(1.04), clockwise: true)
      ..lineTo(6.76, 13.6)
      ..cubicTo(6.06, 14.0, 5.2, 13.5, 5.2, 12.7)
      ..close();
    canvas.drawPath(p, Paint()..color = color);
  }
}

class CameraIcon extends StatelessWidget {
  const CameraIcon({super.key, this.size = 14, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => _SvgIcon(_CameraPainter(color), size);
}

class _CameraPainter extends _IconPainter {
  _CameraPainter(super.color);

  @override
  void draw(Canvas canvas) {
    const r15 = Radius.circular(1.5), r1 = Radius.circular(1);
    final p = Path()
      ..moveTo(2.25, 6.25)
      ..arcToPoint(const Offset(3.75, 4.75), radius: r15)
      ..lineTo(5.3, 4.75)
      ..lineTo(6.35, 3.3)
      ..arcToPoint(const Offset(7.15, 2.9), radius: r1)
      ..lineTo(10.85, 2.9)
      ..arcToPoint(const Offset(11.65, 3.3), radius: r1)
      ..lineTo(12.7, 4.75)
      ..lineTo(14.25, 4.75)
      ..arcToPoint(const Offset(15.75, 6.25), radius: r15)
      ..lineTo(15.75, 13.25)
      ..arcToPoint(const Offset(14.25, 14.75), radius: r15)
      ..lineTo(3.75, 14.75)
      ..arcToPoint(const Offset(2.25, 13.25), radius: r15)
      ..close();
    canvas.drawPath(p, strokePaint);
    canvas.drawCircle(const Offset(9, 9.6), 2.65, strokePaint);
  }
}

class SpeakerIcon extends StatelessWidget {
  const SpeakerIcon({
    super.key,
    this.size = 15,
    required this.color,
    required this.muted,
  });
  final double size;
  final Color color;
  final bool muted;

  @override
  Widget build(BuildContext context) =>
      _SvgIcon(_SpeakerPainter(color, muted), size);
}

class _SpeakerPainter extends _IconPainter {
  _SpeakerPainter(super.color, this.muted);
  final bool muted;

  @override
  void draw(Canvas canvas) {
    const r = Radius.circular(.8);
    final body = Path()
      ..moveTo(3, 6.8)
      ..lineTo(5.8, 6.8)
      ..lineTo(9.6, 3.6)
      ..lineTo(9.6, 14.4)
      ..lineTo(5.8, 11.2)
      ..lineTo(3, 11.2)
      ..arcToPoint(const Offset(2.2, 10.4), radius: r)
      ..lineTo(2.2, 7.6)
      ..arcToPoint(const Offset(3, 6.8), radius: r)
      ..close();
    final s = strokePaint;
    canvas.drawPath(body, s);
    if (muted) {
      canvas.drawLine(const Offset(12.2, 6.8), const Offset(15.8, 11.2), s);
      canvas.drawLine(const Offset(15.8, 6.8), const Offset(12.2, 11.2), s);
    } else {
      canvas.drawPath(
          Path()
            ..moveTo(12.3, 6.3)
            ..arcToPoint(const Offset(12.3, 11.7),
                radius: const Radius.circular(3.7)),
          s);
      canvas.drawPath(
          Path()
            ..moveTo(14.3, 4.4)
            ..arcToPoint(const Offset(14.3, 13.6),
                radius: const Radius.circular(6.4)),
          s);
    }
  }

  @override
  bool shouldRepaint(covariant _SpeakerPainter old) =>
      old.color != color || old.muted != muted;
}
