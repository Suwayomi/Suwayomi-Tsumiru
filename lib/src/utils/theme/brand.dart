import 'package:flutter/material.dart';

/// Brand visual language — the indigo→cyan (per-theme accent→accent2) gradient
/// and glow used instead of flat Material fills. Colors come from the active
/// [ColorScheme] so every theme (Indigo Night, Carbon, Plum, Custom) gets its
/// own gradient automatically.

/// The signature 135° gradient: `accent → accent2`.
LinearGradient brandGradient(ColorScheme cs) => LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [cs.primary, cs.secondary],
    );

/// A soft brand-colored glow (drop shadow) for gradient surfaces.
List<BoxShadow> brandGlow(
  ColorScheme cs, {
  double opacity = 0.40,
  double blur = 18,
  double spread = -2,
}) =>
    [
      BoxShadow(
        color: cs.primary.withValues(alpha: opacity),
        blurRadius: blur,
        spreadRadius: spread,
        offset: const Offset(0, 4),
      ),
    ];

/// A translucent "glass" fill tinted by the accent — used for chips/secondary
/// surfaces instead of stock Material fills.
Color brandGlass(ColorScheme cs, {double opacity = 0.12}) =>
    cs.primary.withValues(alpha: opacity);
