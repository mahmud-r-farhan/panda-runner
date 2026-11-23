import 'dart:math' as math;

import 'package:flutter_scene/scene.dart' as fs;

/// The demo's final grade (`Nh` post pass, `applyAgXGolden`) as a 3D LUT.
///
/// Despite its name, the demo does not use three.js AgX: its composer pass
/// applies exposure, a 3x3 inset matrix, a rational sigmoid
/// `x(1.18x + .018) / (x(x + .62) + .052)`, saturation 1.06, a highlight
/// desaturation shoulder, `x1.12`, gamma 2.2 and contrast 1.04.
///
/// flutter_scene applies a LUT to the display-encoded, tone-mapped image, so
/// the scene renders with Reinhard (`c / (1 + c)`, exactly invertible) and
/// this table undoes the sRGB encoding and Reinhard before running the demo
/// curve on the exposed HDR colour.
class DemoGrade {
  static const double saturation = 1.06;
  static const double contrast = 1.04;

  static double _srgbToLinear(double s) =>
      s <= 0.04045 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();

  static double _ss(double a, double b, double x) {
    final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  /// `applyAgXGolden` on an already-exposed linear HDR colour; returns the
  /// display-encoded result.
  static List<double> grade(double r, double g, double b) {
    r = math.max(r, 0);
    g = math.max(g, 0);
    b = math.max(b, 0);
    // GLSL mat3 is column-major: columns are the listed triples.
    final ir = 0.842479062253094 * r + 0.0784335999999992 * g + 0.0792237451477643 * b;
    final ig = 0.0423282422610123 * r + 0.878468636469772 * g + 0.0791661274605434 * b;
    final ib = 0.0423756549057051 * r + 0.0784336 * g + 0.879142973793104 * b;
    double sig(double x) => (x * (x * 1.18 + 0.018)) / (x * (x + 0.62) + 0.052);
    var mr = sig(ir), mg = sig(ig), mb = sig(ib);
    final luma = 0.2126 * mr + 0.7152 * mg + 0.0722 * mb;
    mr = luma + (mr - luma) * saturation;
    mg = luma + (mg - luma) * saturation;
    mb = luma + (mb - luma) * saturation;
    final k = _ss(0.84, 1.02, luma) * 0.14;
    mr += (luma - mr) * k;
    mg += (luma - mg) * k;
    mb += (luma - mb) * k;
    double enc(double v) {
      final s = math.pow((v * 1.12).clamp(0.0, 0.992), 1 / 2.2).toDouble();
      return ((s - 0.5) * contrast + 0.5).clamp(0.0, 0.992);
    }

    return [enc(mr), enc(mg), enc(mb)];
  }

  /// `.cube` text (red fastest) mapping sRGB(Reinhard(c)) -> grade(c).
  static String cube({int size = 64}) {
    final sb = StringBuffer()
      ..writeln('TITLE "Panda Runner applyAgXGolden"')
      ..writeln('LUT_3D_SIZE $size');
    double inv(double s) {
      final r = _srgbToLinear(s).clamp(0.0, 0.9995);
      return r / (1 - r);
    }

    for (int bi = 0; bi < size; bi++) {
      final b = inv(bi / (size - 1));
      for (int gi = 0; gi < size; gi++) {
        final g = inv(gi / (size - 1));
        for (int ri = 0; ri < size; ri++) {
          final o = grade(inv(ri / (size - 1)), g, b);
          sb.writeln('${o[0].toStringAsFixed(5)} ${o[1].toStringAsFixed(5)} ${o[2].toStringAsFixed(5)}');
        }
      }
    }
    return sb.toString();
  }

  static fs.ColorLut lut() => fs.ColorLut.fromCubeString(cube());
}
