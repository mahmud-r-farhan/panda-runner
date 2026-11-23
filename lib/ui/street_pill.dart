import 'dart:ui' show ImageFilter;

import 'package:flutter/widgets.dart';

import '../game/game_state.dart';
import 'ui_tokens.dart';

/// `.mlit-shield` route marker chip (LOOP pill, 305 hexagon, 246 shield).
class MlitShield extends StatelessWidget {
  const MlitShield(this.shield, {super.key});
  final String shield;

  @override
  Widget build(BuildContext context) {
    final loop = shield == 'LOOP';
    final hex = shield == '305';
    final text = Text(
      shield,
      style: (loop ? Ui.ui(11, weight: FontWeight.w700) : Ui.mono(11, weight: FontWeight.w700))
          .copyWith(
              color: hex ? Ui.bgAbyssal : const Color(0xFFFFFFFF),
              height: 1.15,
              letterSpacing: loop ? 0.55 : 0.22),
    );
    if (hex) {
      return ClipPath(
        clipper: _HexClipper(),
        child: Container(
          color: const Color(0xFFF59E0B),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: text,
        ),
      );
    }
    return Container(
      padding: loop
          ? const EdgeInsets.symmetric(horizontal: 7, vertical: 1)
          : (shield == '246'
              ? const EdgeInsets.fromLTRB(6, 1, 6, 2)
              : const EdgeInsets.symmetric(horizontal: 6, vertical: 1)),
      decoration: BoxDecoration(
        color: loop ? const Color(0xFF00662E) : const Color(0xFF0052A5),
        border: Border.all(
            color: loop
                ? const Color(0x73A7F3D0)
                : (shield == '246' ? const Color(0x7AFFFFFF) : const Color(0x61FFFFFF))),
        borderRadius: loop
            ? BorderRadius.circular(9999)
            : (shield == '246'
                ? const BorderRadius.vertical(top: Radius.circular(4), bottom: Radius.circular(10))
                : BorderRadius.circular(4)),
      ),
      child: text,
    );
  }
}

class _HexClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size s) => Path()
    ..moveTo(s.width * 0.16, 0)
    ..lineTo(s.width * 0.84, 0)
    ..lineTo(s.width, s.height / 2)
    ..lineTo(s.width * 0.84, s.height)
    ..lineTo(s.width * 0.16, s.height)
    ..lineTo(0, s.height / 2)
    ..close();

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// `.street-entry-pill`: MLIT-blue glass pill announcing the street the hero
/// just entered (shown for 1.8 s of sim time), above the minimap.
class StreetEntryPill extends StatelessWidget {
  const StreetEntryPill({super.key, required this.pill, this.compact = false});
  final StreetPill pill;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final rail = pill.isRail;
    return TweenAnimationBuilder<double>(
      key: ValueKey(pill.id),
      tween: Tween(begin: 5, end: 0),
      duration: const Duration(milliseconds: 200),
      curve: const Cubic(0.16, 1, 0.3, 1),
      builder: (context, dy, child) => Transform.translate(offset: Offset(0, dy), child: child),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9999),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
          child: Container(
            height: 24,
            constraints: BoxConstraints(maxWidth: compact ? 248 : 264),
            padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 9),
            decoration: BoxDecoration(
              color: const Color(0xE6091529),
              borderRadius: BorderRadius.circular(9999),
              border: Border.all(color: rail ? const Color(0xD9008C45) : const Color(0xE00066CC)),
              boxShadow: [
                const BoxShadow(color: Color(0x8F02050C), blurRadius: 18, offset: Offset(0, 6)),
                BoxShadow(color: rail ? const Color(0x5200662E) : const Color(0x570052A5), blurRadius: 14),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (pill.shield != null && pill.shield!.isNotEmpty) ...[
                  MlitShield(pill.shield!),
                  const SizedBox(width: 6),
                ],
                Text(pill.ja,
                    style: Ui.ui(11.5, weight: FontWeight.w700, height: 1)),
                if (pill.en.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Text('·',
                      style: Ui.ui(11, weight: FontWeight.w600, height: 1).copyWith(
                          color: (rail ? const Color(0xFF86EFAC) : const Color(0xFF93C5FD))
                              .withValues(alpha: 0.85))),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(pill.en,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Ui.ui(11, weight: FontWeight.w600, height: 1).copyWith(
                            letterSpacing: 0.44,
                            color: rail ? const Color(0xFFBBF7D0) : const Color(0xFFBFDBFE))),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
