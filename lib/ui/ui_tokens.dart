import 'dart:ui' as dui;

import 'package:flutter/material.dart';

/// Design tokens copied from the web demo's CSS custom properties
/// (`:root` in neon-scramble.ai.studio's stylesheet).
abstract final class Ui {
  static const String fontUi = 'Inter';
  static const String fontDisplay = 'Inter';
  static const String fontMono = 'JetBrainsMono';
  static const List<String> fontFallback = [
    'Inter',
    'NotoSansJP',
    'Hiragino Kaku Gothic ProN',
    'Hiragino Sans',
    'Noto Sans JP',
    'Noto Sans CJK JP',
  ];

  static const Color bgAbyssal = Color(0xFF07090E);
  static const Color surfaceGlass = Color(0xCC0B0F19);
  static const Color surfaceGlassStrong = Color(0xEB0B0F19);
  static const Color surfaceMaps = Color(0xFF1B222D);
  static const Color borderGlass = Color(0x2B94A3B8);
  static const Color borderSubtle = Color(0x1F94A3B8);

  static const Color textPrimary = Color(0xFFF1F5F9);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textStrongSub = Color(0xFFCBD5E1);

  static const Color accentPrimary = Color(0xFFFF6B1A);
  static const Color accentPrimaryHi = Color(0xFFFBBC04);
  static const Color accentPrimaryHover = Color(0xFFFF823A);
  static const Color accentPrimarySoft = Color(0x38FF6B1A);
  static const Color accentPrimaryText = Color(0xFFFFB480);

  static const Color semanticNeon = Color(0xFFFF4F00);
  static const Color semanticNeonBright = Color(0xFFFF8E53);
  static const Color semanticNeonCore = Color(0xFFFFF3EC);
  static const Color semanticCyan = Color(0xFF38BDF8);
  static const Color semanticCyanText = Color(0xFF7DD3FC);
  static const Color semanticDanger = Color(0xFFEF4444);
  static const Color semanticDangerText = Color(0xFFFCA5A5);
  static const Color semanticGold = Color(0xFFFDE68A);

  static const Color gBlue = Color(0xFF4285F4);
  static const Color gRed = Color(0xFFEA4335);
  static const Color gYellow = Color(0xFFFBBC05);
  static const Color gGreen = Color(0xFF34A853);

  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment(-1, -1),
    end: Alignment(1, 1),
    colors: [accentPrimary, accentPrimaryHi],
  );

  static TextStyle ui(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color color = textPrimary,
    double letterSpacingEm = 0,
    double? height,
  }) =>
      TextStyle(
        fontFamily: fontUi,
        fontFamilyFallback: fontFallback,
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacingEm * size,
        height: height,
        decoration: TextDecoration.none,
      );

  static TextStyle mono(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color color = textPrimary,
    double letterSpacingEm = 0,
    double? height,
  }) =>
      TextStyle(
        fontFamily: fontMono,
        fontFamilyFallback: fontFallback,
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacingEm * size,
        height: height,
        fontFeatures: const [dui.FontFeature.tabularFigures()],
        decoration: TextDecoration.none,
      );

  /// `box-shadow: 0 12px 32px #02050c8f, inset 0 1px #ffffff0f`.
  static const List<BoxShadow> dockShadow = [
    BoxShadow(color: Color(0x8F02050C), blurRadius: 32, offset: Offset(0, 12)),
  ];
}

/// `.glass-dock`: translucent navy, 16px backdrop blur, hairline border.
class GlassDock extends StatelessWidget {
  const GlassDock({
    super.key,
    required this.child,
    this.radius = 9999,
    this.color = Ui.surfaceGlass,
    this.padding = EdgeInsets.zero,
    this.width,
    this.height,
    this.borderColor = Ui.borderGlass,
    this.extraShadows = const [],
  });

  final Widget child;
  final double radius;
  final Color color;
  final EdgeInsetsGeometry padding;
  final double? width;
  final double? height;
  final Color borderColor;
  final List<BoxShadow> extraShadows;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: [...Ui.dockShadow, ...extraShadows],
      ),
      child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: dui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: color,
              borderRadius: r,
              border: Border.all(color: borderColor, width: 1),
            ),
            foregroundDecoration: BoxDecoration(
              borderRadius: r,
              border: const Border(
                top: BorderSide(color: Color(0x0FFFFFFF), width: 1),
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Orange `.ne-plasma-dot` with its neon glow.
class PlasmaDot extends StatelessWidget {
  const PlasmaDot({super.key, this.large = false});
  final bool large;

  @override
  Widget build(BuildContext context) {
    final size = large ? 11.0 : 8.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Ui.semanticNeon,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: const Color(0xF2FF4F00),
            blurRadius: large ? 16 : 10,
          ),
          BoxShadow(color: Ui.semanticNeonCore, blurRadius: large ? 4 : 3),
        ],
      ),
    );
  }
}

/// `<kbd>` key cap.
class Kbd extends StatelessWidget {
  const Kbd(
    this.label, {
    super.key,
    this.size = 20,
    this.radius = 5,
    this.hPad = 6,
    this.background = const Color(0x14FFFFFF),
    this.border = const Color(0x4294A3B8),
    this.color = Ui.textPrimary,
    this.weight = FontWeight.w600,
  });

  /// `.pill-kbd` style (18px, radius 4, padding 0 4px).
  const Kbd.pill(
    this.label, {
    super.key,
    this.color = Ui.textPrimary,
    this.border = const Color(0x4294A3B8),
    this.background = const Color(0x17FFFFFF),
    this.weight = FontWeight.w600,
  })  : size = 18,
        radius = 4,
        hPad = 4;

  final String label;
  final double size;
  final double radius;
  final double hPad;
  final Color background;
  final Color border;
  final Color color;
  final FontWeight weight;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minWidth: size),
      height: size,
      padding: EdgeInsets.symmetric(horizontal: hPad),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Text(
        label,
        style: Ui.mono(11, weight: weight, color: color, height: 1),
      ),
    );
  }
}

/// A button with the CSS hover lift (translateY(-1px)) and active scale.
class HoverPress extends StatefulWidget {
  const HoverPress({
    super.key,
    required this.onTap,
    required this.builder,
    this.lift = 1,
  });

  final VoidCallback? onTap;
  final double lift;
  final Widget Function(BuildContext context, bool hovered) builder;

  @override
  State<HoverPress> createState() => _HoverPressState();
}

class _HoverPressState extends State<HoverPress> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() {
        _hover = false;
        _down = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: const Cubic(0.16, 1, 0.3, 1),
          transform: Matrix4.translationValues(
            0,
            _down ? 0 : (_hover ? -widget.lift : 0),
            0,
          )..multiply(Matrix4.diagonal3Values(
              _down ? 0.97 : 1, _down ? 0.97 : 1, 1)),
          transformAlignment: Alignment.center,
          child: widget.builder(context, _hover),
        ),
      ),
    );
  }
}
