import 'dart:math';

import 'package:flutter/material.dart';

/// WCAG 2.x contrast ratio between two colors.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
}

/// Steps [base] along OKLCH lightness, keeping hue and chroma, until it reaches [target] against [against].
Color solveContrast(
  Color base,
  Color against,
  double target, {
  required bool lighten,
}) {
  if (contrastRatio(base, against) >= target) return base;
  final dir = lighten ? 1.0 : -1.0;
  final (l0, c, h) = _toOklch(base);
  var l = l0;
  var color = base;
  for (var i = 0; i < 200 && contrastRatio(color, against) < target; i++) {
    l = min(1.0, max(0.0, l + dir * 0.005));
    color = _eightBit(l, c, h);
  }
  return color;
}

double _linear(double v) =>
    v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4).toDouble();

double _encode(double v) =>
    255 *
    (v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4).toDouble() - 0.055);

(double, double, double) _toOklch(Color color) {
  final r = _linear(color.r);
  final g = _linear(color.g);
  final b = _linear(color.b);
  final l = pow(
    0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b,
    1 / 3,
  ).toDouble();
  final m = pow(
    0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b,
    1 / 3,
  ).toDouble();
  final s = pow(
    0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b,
    1 / 3,
  ).toDouble();
  final lightness = 0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s;
  final a = 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s;
  final bb = 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s;
  return (lightness, sqrt(a * a + bb * bb), atan2(bb, a));
}

List<double> _oklchToLinear(double l, double c, double h) {
  final a = c * cos(h);
  final b = c * sin(h);
  final l1 = l + 0.3963377774 * a + 0.2158037573 * b;
  final m1 = l - 0.1055613458 * a - 0.0638541728 * b;
  final s1 = l - 0.0894841775 * a - 1.291485548 * b;
  final l3 = l1 * l1 * l1;
  final m3 = m1 * m1 * m1;
  final s3 = s1 * s1 * s1;
  return [
    4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3,
    -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3,
    -0.0041960863 * l3 - 0.7034186147 * m3 + 1.707614701 * s3,
  ];
}

Color _eightBit(double l, double chroma, double h) {
  var c = chroma;
  for (var i = 0; i < 40; i++) {
    if (_oklchToLinear(l, c, h).every((v) => v >= -0.0005 && v <= 1.0005)) {
      break;
    }
    c *= 0.95;
  }
  int channel(double v) =>
      min(255.0, max(0.0, _encode(min(1.0, max(0.0, v))))).round();
  final rgb = _oklchToLinear(l, c, h);
  return Color.fromARGB(255, channel(rgb[0]), channel(rgb[1]), channel(rgb[2]));
}
