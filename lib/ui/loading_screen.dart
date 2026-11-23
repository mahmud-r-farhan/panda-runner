import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/game_state.dart';
import 'ui_tokens.dart';

/// `.loading-screen`: radial neon glow behind a glass card with the
/// NEON SCRAMBLE wordmark, gradient progress bar, label and percentage.
class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key, required this.state});

  final GameState state;

  @override
  Widget build(BuildContext context) {
    final p = state.loadingProgress.clamp(0.0, 1.0);
    final pct = (p * 100).round();
    final size = MediaQuery.sizeOf(context);
    // radial-gradient(circle at 50% 42%, #ff4f0024 0%, #0b0f19f0 55%,
    // #07090e 100%) — CSS circle radius = farthest-corner.
    final cx = size.width * 0.5, cy = size.height * 0.42;
    final farthest = math.sqrt(math.pow(math.max(cx, size.width - cx), 2) +
        math.pow(math.max(cy, size.height - cy), 2));
    final cardWidth = math.min(400.0, size.width - 40);

    return Container(
      color: Ui.bgAbyssal,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(
            painter: _RadialBgPainter(Offset(cx, cy), farthest),
          ),
          Center(
            child: Container(
              width: cardWidth,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                boxShadow: Ui.dockShadow,
              ),
              child: GlassDock(
                radius: 22,
                color: Ui.surfaceGlassStrong,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 28,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const PlasmaDot(large: true),
                        const SizedBox(width: 12),
                        Text(
                          'NEON SCRAMBLE',
                          style: Ui.ui(
                            32,
                            weight: FontWeight.w700,
                            letterSpacingEm: 0.06,
                            height: 1.05,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Shibuya Crossing → Google Tokyo',
                      style: Ui.ui(
                        14,
                        weight: FontWeight.w500,
                        color: Ui.textSecondary,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _ProgressBar(progress: p),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            state.loadingLabel,
                            overflow: TextOverflow.ellipsis,
                            style: Ui.ui(
                              12.5,
                              weight: FontWeight.w500,
                              color: Ui.textStrongSub,
                            ),
                          ),
                        ),
                        Text(
                          '$pct%',
                          style: Ui.mono(
                            13,
                            weight: FontWeight.w600,
                            color: Ui.accentPrimaryText,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RadialBgPainter extends CustomPainter {
  _RadialBgPainter(this.center, this.radius);
  final Offset center;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = const RadialGradient(
        // CSS interpolates premultiplied colours over the abyssal body
        // background; these are the composited stop colours.
        colors: [Color(0xFF2A130C), Color(0xFF0B0F18), Ui.bgAbyssal],
        stops: [0, 0.55, 1],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawRect(Offset.zero & size, Paint()..color = Ui.bgAbyssal);
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(_RadialBgPainter old) =>
      old.center != center || old.radius != radius;
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) {
    final scale = progress < 0.02 ? 0.02 : progress;
    return SizedBox(
      height: 6,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0x2E94A3B8),
                borderRadius: BorderRadius.circular(9999),
              ),
            ),
          ),
          Positioned.fill(
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: 1,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(end: scale),
                duration: const Duration(milliseconds: 180),
                curve: const Cubic(0.16, 1, 0.3, 1),
                builder: (context, v, _) => ClipRRect(
                  borderRadius: BorderRadius.circular(9999),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    widthFactor: 1,
                    child: FractionallySizedBox(
                      widthFactor: v,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(9999),
                          gradient: const LinearGradient(
                            colors: [Ui.semanticNeon, Ui.accentPrimaryHi],
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0xB8FF6B1A),
                              blurRadius: 14,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
