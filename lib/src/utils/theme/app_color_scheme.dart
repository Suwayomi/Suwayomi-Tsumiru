import 'package:flutter/material.dart';

import 'theme_tokens.dart';

/// Builds a complete Material 3 [ColorScheme] EXPLICITLY from brand
/// [ThemeTokens]. Every role is set from the theme's own hexes — there is NO
/// `ColorScheme.fromSeed` and Material derives no colors. Elevated surfaces are
/// the theme's `bg2` (the theme maps every elevated surface to bg2); the few M3
/// container roles the theme doesn't name are simple lerps of the theme's own
/// accent over its background (deterministic, never Material's tonal palette).
ColorScheme schemeFromTokens(ThemeTokens t, Brightness brightness) {
  Color mix(Color a, Color b, double amt) => Color.lerp(a, b, amt)!;

  return ColorScheme(
    brightness: brightness,
    // Brand accents (verbatim)
    primary: t.accent,
    // Contrast against the accent, not always white: a light accent (e.g. the
    // Monochrome theme's near-white grey) needs dark text so the unread-count
    // badge and other primary-filled elements stay legible.
    onPrimary: ThemeData.estimateBrightnessForColor(t.accent) == Brightness.light
        ? Colors.black
        : Colors.white,
    primaryContainer: mix(t.accent, t.bg, 0.72),
    onPrimaryContainer: t.accent,
    secondary: t.accent2,
    onSecondary: t.bg,
    secondaryContainer: mix(t.accent2, t.bg, 0.72),
    onSecondaryContainer: t.accent2,
    tertiary: t.accent2,
    onTertiary: t.bg,
    tertiaryContainer: mix(t.accent2, t.bg, 0.72),
    onTertiaryContainer: t.accent2,
    error: t.danger,
    onError: Colors.white,
    errorContainer: mix(t.danger, t.bg, 0.72),
    onErrorContainer: t.danger,
    // Surfaces (verbatim): base = bg, every elevated surface = bg2
    surface: t.bg,
    onSurface: t.ink,
    onSurfaceVariant: t.muted,
    surfaceDim: t.bg,
    surfaceBright: t.bg2,
    surfaceContainerLowest: t.bg,
    surfaceContainerLow: t.bg2,
    surfaceContainer: t.bg2,
    surfaceContainerHigh: t.bg2,
    surfaceContainerHighest: t.bg2,
    // Lines
    outline: t.faint,
    outlineVariant: t.border,
    // Misc roles (from the theme's own colors)
    inverseSurface: t.ink,
    onInverseSurface: t.bg,
    inversePrimary: t.accent,
    scrim: Colors.black,
    shadow: Colors.black,
    // No elevation tinting — keep surfaces exactly as specified above.
    surfaceTint: Colors.transparent,
  );
}

/// Layers AMOLED pure-black on a DARK [ColorScheme]: backgrounds → black,
/// elevated containers → stepped near-black. Accents and on-colors unchanged.
ColorScheme applyAmoled(ColorScheme dark) {
  return dark.copyWith(
    surface: const Color(0xFF000000),
    surfaceDim: const Color(0xFF000000),
    surfaceContainerLowest: const Color(0xFF000000),
    surfaceContainerLow: const Color(0xFF0A0A0A),
    surfaceContainer: const Color(0xFF101010),
    surfaceContainerHigh: const Color(0xFF161616),
    surfaceContainerHighest: const Color(0xFF1C1C1C),
  );
}
