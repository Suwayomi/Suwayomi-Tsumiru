import 'package:flutter/material.dart';

import 'theme_tokens.dart';

/// Maps brand tokens to Material roles; unnamed containers interpolate accent over background.
ColorScheme schemeFromTokens(ThemeTokens t, Brightness brightness) {
  Color mix(Color a, Color b, double amt) => Color.lerp(a, b, amt)!;

  // Light themes supply accent background/on-accent tokens; dark themes derive them.
  final accentBg = t.accentBg;

  return ColorScheme(
    brightness: brightness,
    primary: t.accent,
    // Light accents need dark content for contrast.
    onPrimary: accentBg != null
        ? t.onAccent!
        : ThemeData.estimateBrightnessForColor(t.accent) == Brightness.light
            ? Colors.black
            : Colors.white,
    primaryContainer: accentBg ?? mix(t.accent, t.bg, 0.72),
    onPrimaryContainer: t.accent,
    secondary: t.accent2,
    onSecondary: accentBg != null ? t.onAccent! : t.bg,
    secondaryContainer: accentBg ?? mix(t.accent2, t.bg, 0.72),
    onSecondaryContainer: accentBg != null ? t.accent : t.accent2,
    tertiary: t.accent2,
    onTertiary: accentBg != null ? t.onAccent! : t.bg,
    tertiaryContainer: mix(t.accent2, t.bg, 0.72),
    onTertiaryContainer: t.accent2,
    error: t.danger,
    onError: Colors.white,
    errorContainer: mix(t.danger, t.bg, 0.72),
    onErrorContainer: t.danger,
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
    outline: t.faint,
    outlineVariant: t.border,
    inverseSurface: t.ink,
    onInverseSurface: t.bg,
    inversePrimary: t.accent,
    scrim: Colors.black,
    shadow: Colors.black,
    // Preserve token surface colors without elevation tinting.
    surfaceTint: Colors.transparent,
  );
}

/// AMOLED changes dark surfaces only; accents and content colors stay unchanged.
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
