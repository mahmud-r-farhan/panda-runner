import 'dart:ui' as dui;

import 'package:flutter/material.dart';

import '../game/game_state.dart';
import 'ui_tokens.dart';

/// End-of-run card: final score, personal best, run stats and the two ways
/// back into the game (retry or map).
///
/// A run ends when all [GameState.maxShields] shields are spent. Completing
/// the route still goes through the finale banner instead.
class GameOverCard extends StatelessWidget {
  const GameOverCard({
    super.key,
    required this.state,
    required this.onRestart,
    required this.onQuit,
  });

  final GameState state;
  final VoidCallback onRestart;
  final VoidCallback onQuit;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 720 || size.height < 560;
    final meta =
        '${state.routeS.round()} m · ${GameState.formatRunTime(state.runTimeSec)} · ${state.maxSpeedKmh.round()} km/h';

    return Stack(
      fit: StackFit.expand,
      children: [
        BackdropFilter(
          filter: dui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(color: const Color(0xC207090E)),
        ),
        SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: compact ? 400 : 470),
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
                          Container(
                            width: 9,
                            height: 9,
                            decoration: const BoxDecoration(
                              color: Ui.semanticDanger,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                    color: Color(0xCCEF4444), blurRadius: 12),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text('RUN OVER',
                              style: Ui.ui(22,
                                  weight: FontWeight.w800,
                                  letterSpacingEm: .08,
                                  height: 1)),
                          const Spacer(),
                          if (state.newBest) const _NewBestChip(),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text('THE STREETS WON THIS ONE — GO AGAIN',
                          style: Ui.ui(10.5,
                              weight: FontWeight.w600,
                              color: Ui.textSecondary,
                              letterSpacingEm: .1,
                              height: 1.2)),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Text(GameState.formatInt(state.score),
                              style: Ui.mono(compact ? 34 : 40,
                                  weight: FontWeight.w700,
                                  letterSpacingEm: -.01,
                                  height: 1)),
                          const SizedBox(width: 8),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text('PTS',
                                style: Ui.mono(13,
                                    weight: FontWeight.w600,
                                    color: Ui.textSecondary,
                                    height: 1)),
                          ),
                          const Spacer(),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('BEST',
                                  style: Ui.ui(10,
                                      weight: FontWeight.w600,
                                      color: Ui.textSecondary,
                                      letterSpacingEm: .08,
                                      height: 1)),
                              const SizedBox(height: 4),
                              Text(GameState.formatInt(state.displayBest),
                                  style: Ui.mono(17,
                                      weight: FontWeight.w700,
                                      color: Ui.semanticGold,
                                      height: 1.05)),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(meta,
                          style: Ui.mono(12.5,
                              weight: FontWeight.w500,
                              color: Ui.textStrongSub,
                              height: 1.2)),
                      const SizedBox(height: 20),
                      _GameOverButton(
                        label: 'Run again',
                        shortcut: 'R',
                        primary: true,
                        onTap: onRestart,
                      ),
                      const SizedBox(height: 8),
                      _GameOverButton(
                        label: 'Back to the map',
                        shortcut: 'Q',
                        onTap: onQuit,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('BEST COMBO ',
                              style: Ui.ui(10.5,
                                  weight: FontWeight.w600,
                                  color: Ui.textSecondary,
                                  letterSpacingEm: .08,
                                  height: 1)),
                          Text('${state.bestCombo}x',
                              style: Ui.mono(11.5,
                                  weight: FontWeight.w700,
                                  color: Ui.textStrongSub,
                                  height: 1)),
                          const SizedBox(width: 10),
                          Text('RUNS ',
                              style: Ui.ui(10.5,
                                  weight: FontWeight.w600,
                                  color: Ui.textSecondary,
                                  letterSpacingEm: .08,
                                  height: 1)),
                          Text('${state.runsPlayed}',
                              style: Ui.mono(11.5,
                                  weight: FontWeight.w700,
                                  color: Ui.textStrongSub,
                                  height: 1)),
                        ],
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

class _NewBestChip extends StatelessWidget {
  const _NewBestChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0x29FBBC05),
        border: Border.all(color: const Color(0x85FBBC05)),
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [BoxShadow(color: Color(0x3DFBBC05), blurRadius: 14)],
      ),
      child: Text('NEW BEST',
          style: Ui.mono(10.5,
              weight: FontWeight.w700,
              color: Ui.semanticGold,
              letterSpacingEm: .06,
              height: 1)),
    );
  }
}

class _GameOverButton extends StatelessWidget {
  const _GameOverButton({
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
