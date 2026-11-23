import 'dart:ui' as dui;

import 'package:flutter/material.dart';

import '../game/game_state.dart';
import 'ui_tokens.dart';

/// Full-screen pause sheet shown while an active run is frozen.
///
/// The simulation and gameplay clock stop in `ShibuyaSceneController.tick`;
/// this overlay is purely presentational and keeps the 3D frame visible
/// (dimmed + blurred) behind the card.
class PauseOverlay extends StatelessWidget {
  const PauseOverlay({
    super.key,
    required this.state,
    required this.onResume,
    required this.onRestart,
    required this.onQuit,
    required this.onToggleMute,
  });

  final GameState state;
  final VoidCallback onResume;
  final VoidCallback onRestart;
  final VoidCallback onQuit;
  final VoidCallback onToggleMute;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 720 || size.height < 560;

    return Stack(
      fit: StackFit.expand,
      children: [
        BackdropFilter(
          filter: dui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(color: const Color(0xB807090E)),
        ),
        SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: compact ? 380 : 440,
                ),
                child: GlassDock(
                  radius: 22,
                  color: Ui.surfaceGlassStrong,
                  padding: EdgeInsets.fromLTRB(
                      compact ? 20 : 26, 22, compact ? 20 : 26, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const PlasmaDot(large: true),
                          const SizedBox(width: 10),
                          Text('PAUSED',
                              style: Ui.ui(22,
                                  weight: FontWeight.w800,
                                  letterSpacingEm: .08,
                                  height: 1)),
                          const Spacer(),
                          Kbd.pill('Esc'),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text('PANDA RUNNER · SHIBUYA',
                          style: Ui.ui(10.5,
                              weight: FontWeight.w600,
                              color: Ui.textSecondary,
                              letterSpacingEm: .1,
                              height: 1.2)),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          _Stat(
                              label: 'SCORE',
                              value: GameState.formatInt(state.score)),
                          _Stat(
                              label: 'BEST',
                              value: GameState.formatInt(state.displayBest),
                              color: Ui.semanticGold),
                          _Stat(
                            label: 'SHIELDS',
                            value: '${state.shields}/${GameState.maxShields}',
                            color: state.shields > 1
                                ? Ui.semanticCyanText
                                : Ui.semanticDangerText,
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _PauseButton(
                        label: 'Resume run',
                        shortcut: 'Esc',
                        primary: true,
                        onTap: onResume,
                      ),
                      const SizedBox(height: 8),
                      _PauseButton(
                        label: 'Restart from the sky drop',
                        shortcut: 'R',
                        onTap: onRestart,
                      ),
                      const SizedBox(height: 8),
                      _PauseButton(
                        label: 'Back to the map',
                        shortcut: 'Q',
                        onTap: onQuit,
                      ),
                      const SizedBox(height: 10),
                      HoverPress(
                        onTap: onToggleMute,
                        builder: (context, hover) => Container(
                          height: 38,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: hover
                                ? const Color(0x17FFFFFF)
                                : Colors.transparent,
                          ),
                          child: Text(
                            state.muted ? 'Audio: OFF · tap to enable' : 'Audio: ON · tap to mute',
                            style: Ui.ui(12.5,
                                weight: FontWeight.w500,
                                color: Ui.textStrongSub,
                                height: 1),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: Ui.ui(10,
                  weight: FontWeight.w600,
                  color: Ui.textSecondary,
                  letterSpacingEm: .08,
                  height: 1)),
          const SizedBox(height: 4),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Ui.mono(18,
                  weight: FontWeight.w700,
                  color: color ?? Ui.textPrimary,
                  height: 1.05)),
        ],
      ),
    );
  }
}

class _PauseButton extends StatelessWidget {
  const _PauseButton({
    required this.label,
    required this.shortcut,
    required this.onTap,
    this.primary = false,
  });

  final String label;
  final String shortcut;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return HoverPress(
      onTap: onTap,
      builder: (context, hover) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: primary
              ? (hover
                  ? const LinearGradient(
                      colors: [Ui.accentPrimaryHover, Color(0xFFFCD34D)])
                  : Ui.primaryGradient)
              : null,
          color: primary
              ? null
              : (hover ? const Color(0x26FFFFFF) : const Color(0x14FFFFFF)),
          border: primary
              ? null
              : Border.all(
                  color: hover
                      ? const Color(0x4D94A3B8)
                      : const Color(0x2B94A3B8)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Ui.ui(13.5,
                      weight: FontWeight.w600,
                      color: primary ? Ui.bgAbyssal : Ui.textPrimary,
                      height: 1)),
            ),
            const SizedBox(width: 8),
            Kbd.pill(
              shortcut,
              color: primary ? Ui.bgAbyssal : Ui.textStrongSub,
              background:
                  primary ? const Color(0x2907090E) : const Color(0x17FFFFFF),
              border:
                  primary ? const Color(0x5707090E) : const Color(0x4294A3B8),
              weight: FontWeight.w700,
            ),
          ],
        ),
      ),
    );
  }
}
