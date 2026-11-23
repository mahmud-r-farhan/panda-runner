import 'package:flutter/material.dart';

import '../game/game_state.dart';
import '../game/level_data.dart';
import 'hud_icons.dart';
import 'maps_title_card.dart';
import 'minimap.dart';
import 'street_pill.dart';
import 'ui_tokens.dart';

/// In-game HUD layer matching the web demo's `.hud-layer` pills:
/// telemetry (top-left), actions (top-right), minimap (bottom-right),
/// onboarding hint / action callout (bottom-center), finale banner and the
/// photo-mode bar.
class HudOverlay extends StatelessWidget {
  const HudOverlay({
    super.key,
    required this.state,
    required this.level,
    required this.onToggleAutoPilot,
    required this.onToggleMute,
    required this.onTogglePhoto,
    required this.onTogglePause,
    required this.onPlayAgain,
    required this.onPhotoPreset,
  });

  final GameState state;
  final ShibuyaLevel level;
  final VoidCallback onToggleAutoPilot;
  final VoidCallback onToggleMute;
  final VoidCallback onTogglePhoto;
  final VoidCallback onTogglePause;
  final VoidCallback onPlayAgain;
  final ValueChanged<PhotoPreset> onPhotoPreset;

  @override
  Widget build(BuildContext context) {
    if (!state.isGameplay) return const SizedBox.shrink();
    final width = MediaQuery.sizeOf(context).width;
    final compact = width <= 1360;
    final narrow = width <= 1180;
    final photo = state.photoMode;
    final finale = state.phase == AppPhase.finale;
    final callout = state.callout;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Gameplay HUD pills (fade/slide out in photo mode).
        _PhotoFade(
          hidden: photo,
          offsetY: -8,
          child: Stack(
            children: [
              Positioned(
                top: 20,
                left: 20,
                child: _TelemetryPill(state: state, compact: compact),
              ),
              Positioned(
                top: 20,
                right: 20,
                child: _ActionsPill(
                  state: state,
                  compact: compact,
                  onToggleAutoPilot: onToggleAutoPilot,
                  onToggleMute: onToggleMute,
                  onTogglePhoto: onTogglePhoto,
                  onTogglePause: onTogglePause,
                ),
              ),
            ],
          ),
        ),
        _PhotoFade(
          hidden: photo,
          offsetY: 10,
          child: Stack(
            children: [
              Positioned(
                right: 20,
                bottom: 20,
                child: MinimapPill(state: state, level: level),
              ),
            ],
          ),
        ),

        if (!photo && !finale && state.streetPill != null)
          Positioned(
            right: 20,
            bottom: narrow ? 190 : 208,
            child: IgnorePointer(
                child: StreetEntryPill(pill: state.streetPill!, compact: narrow)),
          ),

        if (!photo && state.onboardingVisible && !finale)
          const Positioned(
            left: 0,
            right: 0,
            bottom: 28,
            child: IgnorePointer(child: Center(child: _OnboardingHint())),
          ),

        if (!photo && !finale)
          Positioned(
            top: 80,
            left: 20,
            child: IgnorePointer(child: _ShieldPips(state: state)),
          ),

        if (!photo && callout != null && !finale)
          Positioned(
            left: 0,
            right: 0,
            bottom: 34,
            child: IgnorePointer(
              child: Center(
                child: _CalloutPill(key: ValueKey(callout.id), callout: callout),
              ),
            ),
          ),

        if (!photo && finale)
          Positioned(
            left: narrow ? 20 : 0,
            right: narrow ? null : 0,
            bottom: 22,
            child: _CardReveal(
              child: Center(
                child: _FinaleBanner(
                  state: state,
                  narrow: narrow,
                  onPlayAgain: onPlayAgain,
                  onPhoto: onTogglePhoto,
                ),
              ),
            ),
          ),

        if (photo) ...[
          Positioned(
            left: 0,
            right: 0,
            bottom: 24,
            child: _CardReveal(
              child: Center(
                child: _PhotoModeBar(
                  preset: state.photoPreset,
                  compact: compact,
                  onPreset: onPhotoPreset,
                  onResume: onTogglePhoto,
                ),
              ),
            ),
          ),
          Positioned(
            left: 20,
            bottom: narrow ? null : 20,
            top: narrow ? 16 : null,
            child: const OsmAttributionBadge(),
          ),
        ],
      ],
    );
  }
}

/// `cardReveal`: slide up 8px with ease-out-expo.
class _CardReveal extends StatelessWidget {
  const _CardReveal({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 8, end: 0),
      duration: const Duration(milliseconds: 280),
      curve: const Cubic(0.16, 1, 0.3, 1),
      builder: (context, v, child) =>
          Transform.translate(offset: Offset(0, v), child: child),
      child: child,
    );
  }
}

class _PhotoFade extends StatelessWidget {
  const _PhotoFade({
    required this.hidden,
    required this.offsetY,
    required this.child,
  });
  final bool hidden;
  final double offsetY;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: hidden,
      child: AnimatedOpacity(
        opacity: hidden ? 0 : 1,
        duration: const Duration(milliseconds: 220),
        child: AnimatedSlide(
          offset: Offset(0, hidden ? offsetY / 720 : 0),
          duration: const Duration(milliseconds: 220),
          child: child,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Telemetry pill
// ---------------------------------------------------------------------------

class _VDivider extends StatelessWidget {
  const _VDivider();

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 24, color: Ui.borderSubtle);
}

class _TelemetryPill extends StatelessWidget {
  const _TelemetryPill({required this.state, required this.compact});
  final GameState state;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final gap = compact ? 6.0 : 8.0;
    final cellPad = compact ? 9.0 : 12.0;
    final overcharge = state.speedOvercharge;
    final highChain = state.highChain;
    const ch = 16.5 * 0.6; // JetBrains Mono advance ≈ 0.6em
    final speedKmh = state.speedKmh.round();
    // Finale: the demo swaps SPEED for PEAK (max speed reached).
    final peak = state.phase == AppPhase.finale;
    final peakKmh = state.maxSpeedKmh.round();

    Widget cell(String label, String value, double minCh,
        {bool last = false, Color? color, List<Shadow>? glow}) {
      return Stack(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(cellPad, 8, last ? 8 : cellPad, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    style: Ui.ui(11,
                        weight: FontWeight.w600,
                        color: Ui.textSecondary,
                        letterSpacingEm: .07,
                        height: 1)),
                const SizedBox(height: 3),
                ConstrainedBox(
                  constraints: BoxConstraints(minWidth: minCh * ch),
                  child: SizedBox(
                    height: 18,
                    child: Text(
                      value,
                      style: Ui.mono(16.5,
                              weight: FontWeight.w700,
                              color: color ?? Ui.textPrimary,
                              height: 1.05)
                          .copyWith(shadows: glow),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (!last)
            const Positioned(
              right: 0,
              top: 14,
              child: _VDivider(),
            ),
        ],
      );
    }

    return GlassDock(
      height: 52,
      padding: EdgeInsets.only(left: compact ? 14 : 16, right: compact ? 10 : 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Brand chip.
          Padding(
            padding: EdgeInsets.only(right: compact ? 10 : 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (state.selectedHero == HeroCharacterType.panda)
                  const Text('🐼', style: TextStyle(fontSize: 15))
                else
                  const PlasmaDot(),
                const SizedBox(width: 8),
                Text(
                  'PANDA RUNNER',
                  style: Ui.ui(17,
                      weight: FontWeight.w700,
                      letterSpacingEm: .05,
                      height: 1),
                ),
              ],
            ),
          ),
          const _VDivider(),
          SizedBox(width: gap - 1),
          SizedBox(
            height: 50,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                cell('SCORE', GameState.formatInt(state.score), 6.4),
                cell(peak ? 'PEAK' : 'SPEED',
                    peak ? (peakKmh > 0 ? '$peakKmh km/h' : '--') : '$speedKmh km/h', 7.4,
                    color: peak
                        ? Ui.textStrongSub
                        : (overcharge ? Ui.semanticNeonBright : null),
                    glow: overcharge
                        ? const [
                            Shadow(color: Color(0xCCFF4F00), blurRadius: 12),
                            Shadow(color: Color(0x8CFFF3EC), blurRadius: 3),
                          ]
                        : null),
                cell('COMBO', '${state.combo}x', 3.4,
                    last: true,
                    color: highChain ? Ui.semanticGold : null,
                    glow: highChain
                        ? const [
                            Shadow(color: Color(0x61FDE68A), blurRadius: 10),
                          ]
                        : null),
              ],
            ),
          ),
          SizedBox(width: gap),
          _MoveBadge(move: state.displayMove),
        ],
      ),
    );
  }
}

class _MoveBadge extends StatelessWidget {
  const _MoveBadge({required this.move});
  final ParkourMove move;

  static String labelFor(ParkourMove m) => switch (m) {
        ParkourMove.pinBeacon => 'BOOST',
        ParkourMove.hoodBounce => 'BOUNCE',
        ParkourMove.carDeflect || ParkourMove.sideDeflect => 'DEFLECT',
        _ => m.label,
      };

  @override
  Widget build(BuildContext context) {
    Color fg = const Color(0xFFE2E8F0);
    Color bg = const Color(0x2694A3B8);
    List<BoxShadow> glow = const [];
    switch (move) {
      case ParkourMove.railGrind:
      case ParkourMove.wallRun:
      case ParkourMove.pinBeacon:
        fg = const Color(0xFFFFB480);
        bg = const Color(0x38FF4F00);
      case ParkourMove.overcharge:
        fg = Ui.semanticNeonCore;
        bg = const Color(0x4DFF4F00);
        glow = const [BoxShadow(color: Color(0x6BFF4F00), blurRadius: 12)];
      case ParkourMove.roofVault:
        fg = Ui.semanticCyanText;
        bg = const Color(0x3838BDF8);
        glow = const [BoxShadow(color: Color(0x4738BDF8), blurRadius: 10)];
      case ParkourMove.stumble:
      case ParkourMove.carDeflect:
      case ParkourMove.hoodBounce:
      case ParkourMove.sideDeflect:
        fg = Ui.semanticDangerText;
        bg = const Color(0x3DEF4444);
      case ParkourMove.finaleOrbit:
        fg = Ui.semanticGold;
        bg = const Color(0x33FBBC05);
      default:
        break;
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      constraints: const BoxConstraints(minWidth: 92),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(9999),
        boxShadow: glow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(labelFor(move),
              style: Ui.mono(12,
                  weight: FontWeight.w600,
                  color: fg,
                  letterSpacingEm: .04,
                  height: 1)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Actions pill
// ---------------------------------------------------------------------------

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.onTap,
    required this.builder,
    this.active = false,
    this.hPad = 12,
    this.height = 34,
    this.minWidth = 0,
    this.background,
    this.hoverBackground = const Color(0x17FFFFFF),
    this.gradient,
    this.hoverGradient,
  });

  final VoidCallback onTap;
  final Widget Function(Color fg, bool hover) builder;
  final bool active;
  final double hPad;
  final double height;
  final double minWidth;
  final Color? background;
  final Color hoverBackground;
  final Gradient? gradient;
  final Gradient? hoverGradient;

  @override
  Widget build(BuildContext context) {
    return HoverPress(
      onTap: onTap,
      builder: (context, hover) {
        Color? bg = background;
        if (active) bg = hover ? const Color(0x4DFF6B1A) : Ui.accentPrimarySoft;
        if (!active && hover) bg = hoverBackground;
        final fg = active
            ? (hover ? const Color(0xFFFFD1B0) : Ui.accentPrimaryText)
            : (hover ? Ui.textPrimary : Ui.textStrongSub);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: height,
          constraints: BoxConstraints(minWidth: minWidth),
          padding: EdgeInsets.symmetric(horizontal: hPad),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: gradient == null ? bg : null,
            gradient: gradient == null
                ? null
                : (hover ? (hoverGradient ?? gradient) : gradient),
            borderRadius: BorderRadius.circular(9999),
          ),
          child: builder(fg, hover),
        );
      },
    );
  }
}

class _ActionsPill extends StatelessWidget {
  const _ActionsPill({
    required this.state,
    required this.compact,
    required this.onToggleAutoPilot,
    required this.onToggleMute,
    required this.onTogglePhoto,
    required this.onTogglePause,
  });

  final GameState state;
  final bool compact;
  final VoidCallback onToggleAutoPilot;
  final VoidCallback onToggleMute;
  final VoidCallback onTogglePhoto;
  final VoidCallback onTogglePause;

  @override
  Widget build(BuildContext context) {
    final pad = compact ? 10.0 : 12.0;
    final auto = state.autoPilot;
    // Phones / narrow windows: icon-only pause so the two top pills fit.
    final condensed = MediaQuery.sizeOf(context).width < 900;
    return GlassDock(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ActionButton(
            onTap: onToggleAutoPilot,
            active: auto,
            hPad: pad,
            minWidth: 84,
            builder: (fg, _) => Text('Auto-Pilot',
                style: Ui.ui(13,
                    weight: auto ? FontWeight.w600 : FontWeight.w500,
                    color: fg,
                    height: 1)),
          ),
          const SizedBox(width: 4),
          Container(
            width: 1,
            height: 20,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            color: Ui.borderSubtle,
          ),
          const SizedBox(width: 4),
          _ActionButton(
            onTap: onTogglePhoto,
            active: state.photoMode,
            hPad: pad,
            builder: (fg, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Opacity(opacity: .92, child: CameraIcon(color: fg)),
                const SizedBox(width: 6),
                Text('Photo',
                    style: Ui.ui(13,
                        weight: FontWeight.w500, color: fg, height: 1)),
                const SizedBox(width: 6),
                const Kbd.pill('P'),
              ],
            ),
          ),
          const SizedBox(width: 4),
          _ActionButton(
            onTap: onTogglePause,
            hPad: condensed ? 9 : pad,
            builder: (fg, _) => condensed
                ? Opacity(opacity: .92, child: PauseIcon(color: fg))
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Opacity(opacity: .92, child: PauseIcon(color: fg)),
                      const SizedBox(width: 6),
                      Text('Pause',
                          style: Ui.ui(13,
                              weight: FontWeight.w500, color: fg, height: 1)),
                    ],
                  ),
          ),
          const SizedBox(width: 4),
          HoverPress(
            onTap: onToggleMute,
            builder: (context, hover) {
              final muted = state.muted;
              final fg = muted
                  ? (hover ? Ui.textStrongSub : Ui.textSecondary)
                  : (hover ? Ui.textPrimary : const Color(0xFFE2E8F0));
              return AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: hover && !muted ? const Color(0x17FFFFFF) : null,
                  borderRadius: BorderRadius.circular(9999),
                ),
                child: Opacity(
                  opacity: .92,
                  child: SpeakerIcon(color: fg, muted: muted),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Onboarding hint & action callout
// ---------------------------------------------------------------------------

/// Three-shield run health, bottom-left (clear of the minimap and callouts).
class _ShieldPips extends StatelessWidget {
  const _ShieldPips({required this.state});

  final GameState state;

  @override
  Widget build(BuildContext context) {
    return GlassDock(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('SHIELDS',
              style: Ui.ui(9.5,
                  weight: FontWeight.w700,
                  color: Ui.textSecondary,
                  letterSpacingEm: .12,
                  height: 1)),
          const SizedBox(width: 8),
          for (int i = 0; i < GameState.maxShields; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            AnimatedScale(
              scale: i < state.shields ? 1 : .8,
              duration: const Duration(milliseconds: 180),
              child: AnimatedOpacity(
                opacity: i < state.shields ? 1 : .26,
                duration: const Duration(milliseconds: 180),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < state.shields
                        ? Ui.semanticCyan
                        : Ui.textSecondary,
                    boxShadow: i < state.shields
                        ? const [
                            BoxShadow(
                                color: Color(0x8C38BDF8), blurRadius: 8),
                          ]
                        : null,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OnboardingHint extends StatelessWidget {
  const _OnboardingHint();

  @override
  Widget build(BuildContext context) {
    // Narrow/touch layouts get swipe hints, desktop keeps the key strip.
    final touch = MediaQuery.sizeOf(context).width < 900;
    return _CardReveal(
      child: GlassDock(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        child: ControlsStrip(
          color: Ui.textStrongSub,
          items: touch
              ? const [
                  (['←', '→'], 'Swipe lanes', true),
                  (['↑'], 'Jump / Vault', false),
                  (['↓'], 'Slide', false),
                ]
              : const [
                  (['A', 'D'], 'Lanes', true),
                  (['Space'], 'Jump / Vault', false),
                  (['S'], 'Slide', false),
                  (['Esc'], 'Pause', false),
                ],
        ),
      ),
    );
  }
}

class _CalloutPill extends StatelessWidget {
  const _CalloutPill({super.key, required this.callout});
  final ActionCallout callout;

  @override
  Widget build(BuildContext context) {
    Color border = const Color(0x70FF6B1A);
    List<BoxShadow> shadows = const [
      BoxShadow(color: Color(0x9E02050C), blurRadius: 28, offset: Offset(0, 10)),
      BoxShadow(color: Color(0x38FF4F00), blurRadius: 22),
    ];
    Color bonus = Ui.accentPrimaryText;
    Gradient dot = const LinearGradient(colors: [Ui.semanticNeon, Ui.semanticNeon]);
    List<BoxShadow> dotGlow = const [BoxShadow(color: Color(0xE6FF4F00), blurRadius: 10)];
    switch (callout.accent) {
      case CalloutAccent.neon:
        break;
      case CalloutAccent.gold:
        border = const Color(0x85FBBC05);
        shadows = const [
          BoxShadow(color: Color(0x9E02050C), blurRadius: 28, offset: Offset(0, 10)),
          BoxShadow(color: Color(0x38FBBC05), blurRadius: 22),
        ];
        bonus = Ui.semanticGold;
        dot = const LinearGradient(colors: [Ui.gYellow, Ui.gYellow]);
        dotGlow = const [BoxShadow(color: Color(0xE6FBBC05), blurRadius: 10)];
      case CalloutAccent.danger:
        border = const Color(0x8FEF4444);
        shadows = const [
          BoxShadow(color: Color(0x9E02050C), blurRadius: 28, offset: Offset(0, 10)),
          BoxShadow(color: Color(0x3DEF4444), blurRadius: 22),
        ];
        bonus = Ui.semanticDangerText;
        dot = const LinearGradient(colors: [Ui.semanticDanger, Ui.semanticDanger]);
        dotGlow = const [BoxShadow(color: Color(0xE6EF4444), blurRadius: 10)];
      case CalloutAccent.google:
        border = const Color(0x8F4285F4);
        shadows = const [
          BoxShadow(color: Color(0x9E02050C), blurRadius: 28, offset: Offset(0, 10)),
          BoxShadow(color: Color(0x424285F4), blurRadius: 24),
        ];
        bonus = const Color(0xFF93C5FD);
        dot = const LinearGradient(colors: [Ui.gBlue, Ui.gBlue]);
        dotGlow = const [BoxShadow(color: Color(0xE64285F4), blurRadius: 10)];
      case CalloutAccent.vault:
        border = const Color(0x9E38BDF8);
        shadows = const [
          BoxShadow(color: Color(0x9E02050C), blurRadius: 28, offset: Offset(0, 10)),
          BoxShadow(color: Color(0x4238BDF8), blurRadius: 24),
        ];
        bonus = Ui.semanticGold;
        dot = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Ui.semanticCyan, Ui.gYellow]);
        dotGlow = const [
          BoxShadow(color: Color(0xEB38BDF8), blurRadius: 10),
          BoxShadow(color: Color(0xBFFBBC05), blurRadius: 4),
        ];
      case CalloutAccent.neonSlide:
        border = const Color(0xA6FF4F00);
        shadows = const [
          BoxShadow(color: Color(0xA302050C), blurRadius: 28, offset: Offset(0, 10)),
          BoxShadow(color: Color(0x42FF4F00), blurRadius: 24),
          BoxShadow(color: Color(0x3D38BDF8), blurRadius: 18),
        ];
        bonus = Ui.semanticCyanText;
        dot = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Ui.semanticNeon, Ui.semanticCyan]);
        dotGlow = const [
          BoxShadow(color: Color(0xEBFF4F00), blurRadius: 10),
          BoxShadow(color: Color(0xCC38BDF8), blurRadius: 8),
        ];
    }
    final hasBonus = callout.bonus.isNotEmpty;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 200),
      curve: const Cubic(0.16, 1, 0.3, 1),
      builder: (context, t, child) => Transform.translate(
        offset: Offset(0, 6 * (1 - t)),
        child: Transform.scale(scale: .95 + .05 * t, child: child),
      ),
      child: GlassDock(
        color: Ui.surfaceGlassStrong,
        borderColor: border,
        extraShadows: shadows,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                  shape: BoxShape.circle, gradient: dot, boxShadow: dotGlow),
            ),
            const SizedBox(width: 9),
            Text(callout.label,
                style: Ui.ui(14,
                    weight: FontWeight.w700, letterSpacingEm: .05, height: 1)),
            if (hasBonus) ...[
              const SizedBox(width: 9),
              Opacity(
                opacity: .75,
                child: Text('·',
                    style: Ui.ui(14,
                        weight: FontWeight.w600,
                        color: Ui.textSecondary,
                        height: 1)),
              ),
              const SizedBox(width: 9),
              Text(callout.bonus,
                  style: Ui.mono(13.5,
                      weight: FontWeight.w700, color: bonus, height: 1)),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Finale banner & photo-mode bar
// ---------------------------------------------------------------------------

class _FinaleBanner extends StatelessWidget {
  const _FinaleBanner({
    required this.state,
    required this.narrow,
    required this.onPlayAgain,
    required this.onPhoto,
  });

  final GameState state;
  final bool narrow;
  final VoidCallback onPlayAgain;
  final VoidCallback onPhoto;

  static const _dotColors = [
    Ui.gBlue,
    Ui.gRed,
    Ui.gYellow,
    Ui.gBlue,
    Ui.gGreen,
    Ui.gRed,
  ];

  @override
  Widget build(BuildContext context) {
    final btnPad = narrow ? 12.0 : 15.0;
    final btnFont = narrow ? 13.0 : 13.5;
    final meta =
        '${state.maxSpeedKmh.round()} km/h · ${GameState.formatRunTime(state.runTimeSec)}';
    return GlassDock(
      color: Ui.surfaceGlassStrong,
      padding: narrow
          ? const EdgeInsets.fromLTRB(18, 10, 14, 10)
          : const EdgeInsets.fromLTRB(22, 12, 16, 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('SHIBUYA IGNITED',
                      style: Ui.ui(11.5,
                          weight: FontWeight.w600,
                          color: Ui.textSecondary,
                          letterSpacingEm: .08,
                          height: 1.1)),
                  const SizedBox(width: 10),
                  for (int i = 0; i < 6; i++) ...[
                    if (i > 0) const SizedBox(width: 5),
                    AnimatedScale(
                      scale: state.googleLettersLit[i] ? 1.12 : 1,
                      duration: const Duration(milliseconds: 200),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 7.5,
                        height: 7.5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: state.googleLettersLit[i]
                              ? _dotColors[i]
                              : const Color(0x4794A3B8),
                          boxShadow: state.googleLettersLit[i]
                              ? [
                                  BoxShadow(
                                    color: _dotColors[i].withValues(alpha: .9),
                                    blurRadius: 8,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 3),
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('${GameState.formatInt(state.score)} PTS',
                      style: Ui.mono(narrow ? 18 : 19,
                          weight: FontWeight.w700,
                          letterSpacingEm: -.01,
                          height: 1.1)),
                  const SizedBox(width: 8),
                  Opacity(
                    opacity: .72,
                    child: Text('·',
                        style: Ui.mono(14,
                            color: Ui.textSecondary, height: 1.1)),
                  ),
                  const SizedBox(width: 8),
                  Text(meta,
                      style: Ui.mono(13,
                          weight: FontWeight.w500,
                          color: Ui.textStrongSub,
                          letterSpacingEm: .01,
                          height: 1.1)),
                ],
              ),
            ],
          ),
          SizedBox(width: narrow ? 14 : 20),
          _ActionButton(
            onTap: onPlayAgain,
            height: 36,
            hPad: btnPad,
            gradient: Ui.primaryGradient,
            hoverGradient: const LinearGradient(
              begin: Alignment(-1, -1),
              end: Alignment(1, 1),
              colors: [Ui.accentPrimaryHover, Color(0xFFFCD34D)],
            ),
            builder: (_, _) => Text('Play Again',
                style: Ui.ui(btnFont,
                    weight: FontWeight.w700, color: Ui.bgAbyssal, height: 1)),
          ),
          const SizedBox(width: 8),
          _ActionButton(
            onTap: onPhoto,
            height: 36,
            hPad: btnPad,
            background: const Color(0x14FFFFFF),
            hoverBackground: const Color(0x26FFFFFF),
            builder: (_, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Opacity(
                    opacity: .92, child: CameraIcon(color: Ui.textPrimary)),
                const SizedBox(width: 6),
                Text('Photo Mode',
                    style: Ui.ui(btnFont,
                        weight: FontWeight.w500,
                        color: Ui.textPrimary,
                        height: 1)),
                const SizedBox(width: 6),
                const Kbd.pill('P'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoModeBar extends StatelessWidget {
  const _PhotoModeBar({
    required this.preset,
    required this.compact,
    required this.onPreset,
    required this.onResume,
  });

  final PhotoPreset preset;
  final bool compact;
  final ValueChanged<PhotoPreset> onPreset;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    Widget presetBtn(PhotoPreset p, String key, String label) {
      final active = p == preset;
      return _ActionButton(
        onTap: () => onPreset(p),
        active: active,
        hPad: 11,
        builder: (fg, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Kbd.pill(
              key,
              color: active ? const Color(0xFFFFD1B0) : Ui.textPrimary,
              border: active ? const Color(0x8CFF6B1A) : const Color(0x4294A3B8),
            ),
            const SizedBox(width: 6),
            Text(label,
                style: Ui.ui(13,
                    weight: active ? FontWeight.w600 : FontWeight.w500,
                    color: fg,
                    height: 1)),
          ],
        ),
      );
    }

    return GlassDock(
      height: 48,
      color: Ui.surfaceGlassStrong,
      padding: const EdgeInsets.only(left: 18, right: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Ui.accentPrimary,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Color(0xE6FF6B1A), blurRadius: 10)],
            ),
          ),
          const SizedBox(width: 8),
          Text('PHOTO MODE',
              style: Ui.ui(17.5,
                  weight: FontWeight.w700, letterSpacingEm: .04, height: 1)),
          const SizedBox(width: 10),
          presetBtn(PhotoPreset.hero, '1', 'Hero'),
          const SizedBox(width: 4),
          presetBtn(PhotoPreset.scramble, '2', 'Scramble'),
          const SizedBox(width: 4),
          presetBtn(PhotoPreset.skyline, '3', 'Skyline'),
          if (!compact) ...[
            const SizedBox(width: 10),
            Container(
              width: 1,
              height: 20,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              color: Ui.borderSubtle,
            ),
            const SizedBox(width: 10),
            Text('Drag to Orbit · Scroll to Zoom',
                style: Ui.ui(12.5,
                    weight: FontWeight.w500, color: Ui.textSecondary)),
          ],
          const SizedBox(width: 10),
          _ActionButton(
            onTap: onResume,
            hPad: 14,
            gradient: Ui.primaryGradient,
            hoverGradient: const LinearGradient(
              begin: Alignment(-1, -1),
              end: Alignment(1, 1),
              colors: [Ui.accentPrimaryHover, Color(0xFFFCD34D)],
            ),
            builder: (_, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Resume',
                    style: Ui.ui(13,
                        weight: FontWeight.w700,
                        color: Ui.bgAbyssal,
                        height: 1)),
                const SizedBox(width: 6),
                const Kbd.pill(
                  'P',
                  color: Ui.bgAbyssal,
                  background: Color(0x2907090E),
                  border: Color(0x5707090E),
                  weight: FontWeight.w700,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
