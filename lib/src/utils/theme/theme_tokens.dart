import 'package:flutter/material.dart';

import '../../constants/app_theme.dart';

/// Color tokens for a named theme at one brightness.
///
/// DARK values are copied VERBATIM from `~/Projects/theme-kit/themes/<id>.css` —
/// never invented, never derived by Material. LIGHT values use light surfaces
/// (Indigo from the docs-site light palette) and keep each theme's exact brand
/// accent.
class ThemeTokens {
  const ThemeTokens({
    required this.bg,
    required this.bg2,
    required this.ink,
    required this.muted,
    required this.faint,
    required this.accent,
    required this.accent2,
    required this.danger,
    required this.border,
  });

  final Color bg; // scaffold / base surface  (--bg)
  final Color bg2; // elevated panels, cards, app bars, sheets  (--bg2)
  final Color ink; // primary text  (--ink → onSurface)
  final Color muted; // secondary text  (--muted → onSurfaceVariant)
  final Color faint; // outline  (--faint)
  final Color accent; // primary  (--accent)
  final Color accent2; // secondary / tertiary  (--accent2)
  final Color danger; // error  (--danger)
  final Color border; // panel border overlay  (--panel-brd → outlineVariant)
}

// --- DARK token sets: VERBATIM from theme-kit/themes/<id>.css ---
const _indigoDark = ThemeTokens(
  bg: Color(0xFF0B0D1A),
  bg2: Color(0xFF11142A),
  ink: Color(0xFFEEF0FB),
  muted: Color(0xFF9AA0C4),
  faint: Color(0xFF6B7099),
  accent: Color(0xFF7C7BFF),
  accent2: Color(0xFF33D6FF),
  danger: Color(0xFFFF6B6B),
  border: Color(0x14FFFFFF), // --panel-brd: white @ 0.08
);
const _carbonDark = ThemeTokens(
  bg: Color(0xFF08100E),
  bg2: Color(0xFF0C1714),
  ink: Color(0xFFEAFCF6),
  muted: Color(0xFF8FB6AC),
  faint: Color(0xFF5D7E76),
  accent: Color(0xFF19E6B0),
  accent2: Color(0xFF22D3EE),
  danger: Color(0xFFFF6F6F),
  border: Color(0x12FFFFFF), // white @ 0.07
);
const _plumDark = ThemeTokens(
  bg: Color(0xFF120A16),
  bg2: Color(0xFF1B0F22),
  ink: Color(0xFFFBEEFB),
  muted: Color(0xFFCAA0C9),
  faint: Color(0xFF946B93),
  accent: Color(0xFFFF5DB1),
  accent2: Color(0xFFFF9F5C),
  danger: Color(0xFFFF7A6B),
  border: Color(0x17FFFFFF), // white @ 0.09
);

// --- LIGHT token sets: light surfaces (Indigo from docs base.styl :root);
//     each theme keeps its EXACT brand accent. ---
const _indigoLight = ThemeTokens(
  bg: Color(0xFFFBFBFF), // --vp-c-bg
  bg2: Color(0xFFEEF0FB), // --vp-c-bg-alt
  ink: Color(0xFF11142A),
  muted: Color(0xFF5B6080),
  faint: Color(0xFF9AA0C4),
  accent: Color(0xFF7C7BFF), // brand accent, same as dark
  accent2: Color(0xFF33D6FF),
  danger: Color(0xFFD92D2D),
  border: Color(0x14000000), // black @ 0.08
);
const _carbonLight = ThemeTokens(
  bg: Color(0xFFF6FFFB),
  bg2: Color(0xFFE8F3EF),
  ink: Color(0xFF0C1714),
  muted: Color(0xFF4E6B63),
  faint: Color(0xFF8FB6AC),
  accent: Color(0xFF19E6B0),
  accent2: Color(0xFF22D3EE),
  danger: Color(0xFFD92D2D),
  border: Color(0x12000000),
);
const _plumLight = ThemeTokens(
  bg: Color(0xFFFFF7FD),
  bg2: Color(0xFFF7E9F4),
  ink: Color(0xFF1B0F22),
  muted: Color(0xFF7A5479),
  faint: Color(0xFF946B93),
  accent: Color(0xFFFF5DB1),
  accent2: Color(0xFFFF9F5C),
  danger: Color(0xFFD92D2D),
  border: Color(0x17000000),
);

ThemeTokens tokensFor(AppTheme theme, Brightness brightness) {
  assert(theme != AppTheme.custom, 'custom theme has no fixed tokens');
  final isDark = brightness == Brightness.dark;
  return switch (theme) {
    AppTheme.indigoNight => isDark ? _indigoDark : _indigoLight,
    AppTheme.carbon => isDark ? _carbonDark : _carbonLight,
    AppTheme.plum => isDark ? _plumDark : _plumLight,
    AppTheme.custom => throw StateError('unreachable'),
  };
}
