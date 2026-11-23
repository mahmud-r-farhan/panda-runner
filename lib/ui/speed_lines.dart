import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// Overcharge speed lines: the demo's peripheral filament pass (`I_`),
/// drawn additively over the 3D view.
class SpeedLinesOverlay extends StatefulWidget {
  const SpeedLinesOverlay({super.key, required this.factor, required this.time});

  final double factor;
  final double time;

  @override
  State<SpeedLinesOverlay> createState() => _SpeedLinesOverlayState();
}

class _SpeedLinesOverlayState extends State<SpeedLinesOverlay> {
  static ui.FragmentProgram? _program;
  ui.FragmentShader? _shader;

  @override
  void initState() {
    super.initState();
    if (_program == null) {
      ui.FragmentProgram.fromAsset('shaders/speed_lines.frag').then((p) {
        _program = p;
        if (mounted) {
          setState(() {
            _shader?.dispose();
            _shader = p.fragmentShader();
          });
        }
      });
    } else {
      _shader = _program!.fragmentShader();
    }
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _shader;
    if (s == null || widget.factor <= 0.02) return const SizedBox.shrink();
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _SpeedLinesPainter(s, widget.factor, widget.time),
      ),
    );
  }
}

class _SpeedLinesPainter extends CustomPainter {
  _SpeedLinesPainter(this.shader, this.factor, this.time);

  final ui.FragmentShader shader;
  final double factor, time;

  @override
  void paint(Canvas canvas, Size size) {
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, time)
      ..setFloat(3, factor);
    canvas.drawRect(Offset.zero & size,
        Paint()
          ..shader = shader
          ..blendMode = BlendMode.plus);
  }

  @override
  bool shouldRepaint(covariant _SpeedLinesPainter old) => true;
}


/// The demo's display-space vignette (applied after its grade), multiplied
/// over the 3D view.
class VignetteOverlay extends StatefulWidget {
  const VignetteOverlay({super.key, this.strength = 0.14});

  final double strength;

  @override
  State<VignetteOverlay> createState() => _VignetteOverlayState();
}

class _VignetteOverlayState extends State<VignetteOverlay> {
  static ui.FragmentProgram? _program;
  ui.FragmentShader? _shader;

  @override
  void initState() {
    super.initState();
    if (_program == null) {
      ui.FragmentProgram.fromAsset('shaders/vignette.frag').then((p) {
        _program = p;
        if (mounted) {
          setState(() {
            _shader?.dispose();
            _shader = p.fragmentShader();
          });
        }
      });
    } else {
      _shader = _program!.fragmentShader();
    }
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _shader;
    if (s == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _VignettePainter(s, widget.strength),
        ),
      ),
    );
  }
}

class _VignettePainter extends CustomPainter {
  _VignettePainter(this.shader, this.strength);

  final ui.FragmentShader shader;
  final double strength;

  @override
  void paint(Canvas canvas, Size size) {
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, strength);
    canvas.drawRect(Offset.zero & size,
        Paint()
          ..shader = shader
          ..blendMode = BlendMode.multiply);
  }

  @override
  bool shouldRepaint(covariant _VignettePainter old) => old.strength != strength;
}
