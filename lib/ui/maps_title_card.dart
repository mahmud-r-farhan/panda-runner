import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/game_state.dart';
import '../game/map_location.dart';
import 'hud_icons.dart';
import 'ui_tokens.dart';

/// Interactive start card: runner selection (3D panda vs Pegman), sky-mood
/// selector, best-run summary and the play button.
class MapsTitleCard extends StatelessWidget {
  const MapsTitleCard({
    super.key,
    required this.state,
    required this.onPlay,
    required this.onSelectLocation,
    required this.onSelectHero,
  });

  final GameState state;
  final VoidCallback onPlay;
  final ValueChanged<MapLocation> onSelectLocation;
  final ValueChanged<HeroCharacterType> onSelectHero;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width <= 1180;
    final currentLoc = state.location;
    final currentHero = state.selectedHero;

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          left: 0,
          right: 0,
          bottom: compact ? 20 : 32,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: math.min(560, size.width - 32),
                maxWidth: math.min(640, size.width - 32),
              ),
              child: GlassDock(
                radius: 24,
                color: Ui.surfaceGlassStrong,
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header Row: Title + Play Button
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: currentLoc.accentColor.withValues(
                                        alpha: 0.18,
                                      ),
                                      border: Border.all(
                                        color: currentLoc.accentColor.withValues(
                                          alpha: 0.55,
                                        ),
                                      ),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      currentLoc.emoji,
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Flexible(
                                    child: Text(
                                      'PANDA RUNNER',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Ui.ui(
                                        compact ? 22 : 26,
                                        weight: FontWeight.w800,
                                        letterSpacingEm: 0.04,
                                        height: 1,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 5),
                              Text(
                                '${currentLoc.nameJa} · ${currentLoc.subtitle}',
                                style: Ui.ui(
                                  13,
                                  weight: FontWeight.w500,
                                  color: Ui.textStrongSub,
                                  height: 1.2,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                state.bestScore > 0
                                    ? 'BEST ${GameState.formatInt(state.bestScore)} · ${state.runsPlayed} RUNS · ${state.bestCombo}x MAX COMBO'
                                    : 'FIRST RUN · NO SCORE YET',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Ui.mono(
                                  11,
                                  weight: FontWeight.w600,
                                  color: state.bestScore > 0
                                      ? Ui.semanticGold
                                      : Ui.textSecondary,
                                  letterSpacingEm: 0.06,
                                  height: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 18),
                        _PlayButton(
                          onTap: onPlay,
                          accent: currentLoc.accentColor,
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Selector Section: Character & Map Location
                    Row(
                      children: [
                        // Character Switcher
                        Expanded(
                          flex: 5,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'RUNNER HERO',
                                style: Ui.ui(
                                  10.5,
                                  weight: FontWeight.w700,
                                  color: Ui.textSecondary,
                                  letterSpacingEm: 0.08,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  for (final h in HeroCharacterType.values)
                                    Expanded(
                                      child: _HeroChoicePill(
                                        hero: h,
                                        selected: currentHero == h,
                                        accent: currentLoc.accentColor,
                                        onTap: () => onSelectHero(h),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(width: 12),

                        // Map Location Switcher
                        Expanded(
                          flex: 7,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'SKY MOOD',
                                style: Ui.ui(
                                  10.5,
                                  weight: FontWeight.w700,
                                  color: Ui.textSecondary,
                                  letterSpacingEm: 0.08,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  for (final loc in MapLocation.all)
                                    Expanded(
                                      child: _LocationChoicePill(
                                        location: loc,
                                        selected: currentLoc.id == loc.id,
                                        onTap: () => onSelectLocation(loc),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Environment Briefing Pill
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0x3D0B0F19),
                        border: Border.all(color: Ui.borderSubtle),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.explore_rounded,
                            size: 13,
                            color: currentLoc.accentColor,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              currentLoc.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Ui.ui(
                                11.5,
                                weight: FontWeight.w500,
                                color: Ui.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Keyboard / Swipe Controls Legend
                    Container(
                      padding: const EdgeInsets.only(top: 10),
                      decoration: const BoxDecoration(
                        border: Border(
                          top: BorderSide(color: Ui.borderSubtle),
                        ),
                      ),
                      child: const ControlsStrip(
                        items: [
                          (['A', 'D'], 'Lanes', true),
                          (['Space', 'W'], 'Jump / Vault', false),
                          (['S'], 'Slide', false),
                          (['Esc'], 'Pause', false),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        Positioned(
          left: 20,
          bottom: compact ? null : 20,
          top: compact ? 16 : null,
          child: const OsmAttributionBadge(),
        ),
      ],
    );
  }
}

class _HeroChoicePill extends StatelessWidget {
  const _HeroChoicePill({
    required this.hero,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final HeroCharacterType hero;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: HoverPress(
        onTap: onTap,
        lift: 1.0,
        builder: (context, hover) => Container(
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.18)
                : hover
                    ? const Color(0x2E1E293B)
                    : const Color(0x1A0F172A),
            border: Border.all(
              color: selected
                  ? accent
                  : hover
                      ? const Color(0x4794A3B8)
                      : Ui.borderSubtle,
              width: selected ? 1.5 : 1.0,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(hero.emoji, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  hero == HeroCharacterType.panda ? '3D Panda' : 'Pegman',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Ui.ui(
                    11.5,
                    weight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? Ui.textPrimary : Ui.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocationChoicePill extends StatelessWidget {
  const _LocationChoicePill({
    required this.location,
    required this.selected,
    required this.onTap,
  });

  final MapLocation location;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: HoverPress(
        onTap: onTap,
        lift: 1.0,
        builder: (context, hover) => Container(
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
          decoration: BoxDecoration(
            color: selected
                ? location.accentColor.withValues(alpha: 0.18)
                : hover
                    ? const Color(0x2E1E293B)
                    : const Color(0x1A0F172A),
            border: Border.all(
              color: selected
                  ? location.accentColor
                  : hover
                      ? const Color(0x4794A3B8)
                      : Ui.borderSubtle,
              width: selected ? 1.5 : 1.0,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(location.emoji, style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  location.shortName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Ui.ui(
                    11.5,
                    weight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? Ui.textPrimary : Ui.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Row of `<kbd>` groups separated by `·` (title strip and onboarding hint).
class ControlsStrip extends StatelessWidget {
  const ControlsStrip({
    super.key,
    required this.items,
    this.slashed = true,
    this.color = Ui.textSecondary,
  });

  final Color color;

  /// (keys, label, use "/" between keys)
  final List<(List<String>, String, bool)> items;
  final bool slashed;

  @override
  Widget build(BuildContext context) {
    final style = Ui.ui(12, weight: FontWeight.w500, color: color);
    final sepStyle = Ui.ui(12, weight: FontWeight.w500, color: Ui.textSecondary);
    final children = <Widget>[];
    for (int i = 0; i < items.length; i++) {
      final (keys, label, slash) = items[i];
      if (i > 0) {
        children.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Opacity(opacity: 0.65, child: Text('·', style: sepStyle)),
        ));
      }
      final group = <Widget>[];
      for (int k = 0; k < keys.length; k++) {
        if (k > 0) {
          group.add(const SizedBox(width: 4));
          if (slash && slashed) {
            group.add(Opacity(
              opacity: 0.72,
              child: Text(
                '/',
                style: Ui.ui(11,
                    weight: FontWeight.w500, color: Ui.textSecondary),
              ),
            ));
            group.add(const SizedBox(width: 4));
          }
        }
        group.add(Kbd(keys[k]));
      }
      group.add(const SizedBox(width: 4));
      group.add(Text(label, style: style));
      children.add(Row(mainAxisSize: MainAxisSize.min, children: group));
    }
    return DefaultTextStyle(
      style: style,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: children,
        ),
      ),
    );
  }
}

class OsmAttributionBadge extends StatelessWidget {
  const OsmAttributionBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: GlassDock(
        color: const Color(0xD10B0F19),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Text(
          'Map data © OpenStreetMap contributors',
          style: Ui.ui(11,
              weight: FontWeight.w500, color: Ui.textStrongSub, height: 1.2),
        ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.onTap, required this.accent});
  final VoidCallback onTap;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return HoverPress(
      onTap: onTap,
      lift: 1.5,
      builder: (context, hover) => Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 26),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [accent, const Color(0xFFFBBF24)],
            begin: const Alignment(-1, -1),
            end: const Alignment(1, 1),
          ),
          borderRadius: BorderRadius.circular(9999),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: hover ? 0.65 : 0.45),
              blurRadius: hover ? 28 : 22,
              offset: Offset(0, hover ? 10 : 6),
            ),
          ],
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9999),
          border: Border(
            top: BorderSide(
              color: hover ? const Color(0x6BFFFFFF) : const Color(0x52FFFFFF),
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const PlayTriangleIcon(size: 15, color: Ui.bgAbyssal),
            const SizedBox(width: 8),
            Text(
              'RUN',
              style: Ui.ui(
                16,
                weight: FontWeight.w800,
                color: Ui.bgAbyssal,
                letterSpacingEm: 0.08,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
