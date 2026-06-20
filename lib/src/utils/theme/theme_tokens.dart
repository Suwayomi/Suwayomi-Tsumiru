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

const _regressionDark = ThemeTokens(
  bg: Color(0xFF06080F),
  bg2: Color(0xFF0A0E1C),
  ink: Color(0xFFDBE6FF),
  muted: Color(0xFF8FA2CC),
  faint: Color(0xFF5A6890),
  accent: Color(0xFF3D8BFF),
  accent2: Color(0xFF6FD2FF),
  danger: Color(0xFFFF5D6C),
  border: Color(0x38508CFF),
);
const _emberDark = ThemeTokens(
  bg: Color(0xFF140A0C),
  bg2: Color(0xFF1F0E11),
  ink: Color(0xFFFBE9EA),
  muted: Color(0xFFC99A9E),
  faint: Color(0xFF8F6468),
  accent: Color(0xFFFF3B4E),
  accent2: Color(0xFFFFB338),
  danger: Color(0xFFFF5B5B),
  border: Color(0x14FFFFFF),
);
const _synthwaveDark = ThemeTokens(
  bg: Color(0xFF150B2E),
  bg2: Color(0xFF1F1140),
  ink: Color(0xFFF3E9FF),
  muted: Color(0xFFB9A4E0),
  faint: Color(0xFF7E6AA8),
  accent: Color(0xFFFF2E97),
  accent2: Color(0xFF2DE2FF),
  danger: Color(0xFFFF5D73),
  border: Color(0x17FFFFFF),
);
const _terminalDark = ThemeTokens(
  bg: Color(0xFF060A06),
  bg2: Color(0xFF0B130B),
  ink: Color(0xFFD6FFD9),
  muted: Color(0xFF76A878),
  faint: Color(0xFF4F6E50),
  accent: Color(0xFF36FF7A),
  accent2: Color(0xFFFFD84D),
  danger: Color(0xFFFF5B5B),
  border: Color(0x1A78FF96),
);
const _catppuccinDark = ThemeTokens(
  bg: Color(0xFF1E1E2E),
  bg2: Color(0xFF181825),
  ink: Color(0xFFCDD6F4),
  muted: Color(0xFFA6ADC8),
  faint: Color(0xFF6C7086),
  accent: Color(0xFFCBA6F7),
  accent2: Color(0xFF89B4FA),
  danger: Color(0xFFF38BA8),
  border: Color(0x14FFFFFF),
);
const _nordDark = ThemeTokens(
  bg: Color(0xFF2E3440),
  bg2: Color(0xFF3B4252),
  ink: Color(0xFFECEFF4),
  muted: Color(0xFFABB6C9),
  faint: Color(0xFF6B7689),
  accent: Color(0xFF88C0D0),
  accent2: Color(0xFF81A1C1),
  danger: Color(0xFFBF616A),
  border: Color(0x1AFFFFFF),
);
const _gruvboxDark = ThemeTokens(
  bg: Color(0xFF1D2021),
  bg2: Color(0xFF282828),
  ink: Color(0xFFEBDBB2),
  muted: Color(0xFFA89984),
  faint: Color(0xFF7C6F64),
  accent: Color(0xFFFE8019),
  accent2: Color(0xFF8EC07C),
  danger: Color(0xFFFB4934),
  border: Color(0x14FFFFFF),
);
const _draculaDark = ThemeTokens(
  bg: Color(0xFF282A36),
  bg2: Color(0xFF343746),
  ink: Color(0xFFF8F8F2),
  muted: Color(0xFFB9BCD0),
  faint: Color(0xFF6272A4),
  accent: Color(0xFFBD93F9),
  accent2: Color(0xFFFF79C6),
  danger: Color(0xFFFF5555),
  border: Color(0x17FFFFFF),
);
const _monoDark = ThemeTokens(
  bg: Color(0xFF0A0A0B),
  bg2: Color(0xFF141417),
  ink: Color(0xFFF4F4F6),
  muted: Color(0xFF9A9AA2),
  faint: Color(0xFF62626B),
  accent: Color(0xFFE8E8EE),
  accent2: Color(0xFFA8A8B2),
  danger: Color(0xFFFF6B6B),
  border: Color(0x1AFFFFFF),
);
const _royalDark = ThemeTokens(
  bg: Color(0xFF0D0B16),
  bg2: Color(0xFF16122A),
  ink: Color(0xFFF3EEFB),
  muted: Color(0xFFB6ABD0),
  faint: Color(0xFF7C719C),
  accent: Color(0xFFE8C468),
  accent2: Color(0xFF9B7BFF),
  danger: Color(0xFFFF6B6B),
  border: Color(0x17FFFFFF),
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

const _regressionLight = ThemeTokens(
  bg: Color(0xFFF7F9FF),
  bg2: Color(0xFFE8EEFC),
  ink: Color(0xFF0A0E1C),
  muted: Color(0xFF5A6890),
  faint: Color(0xFF9AA6C4),
  accent: Color(0xFF2F6FE0),
  accent2: Color(0xFF2BB6E6),
  danger: Color(0xFFD92D2D),
  border: Color(0x14000000),
);
const _emberLight = ThemeTokens(
  bg: Color(0xFFFFF6F6),
  bg2: Color(0xFFFBE7E8),
  ink: Color(0xFF2A1012),
  muted: Color(0xFF8F6468),
  faint: Color(0xFFC0989C),
  accent: Color(0xFFE11D2E),
  accent2: Color(0xFFE08A10),
  danger: Color(0xFFD92D2D),
  border: Color(0x14000000),
);
const _synthwaveLight = ThemeTokens(
  bg: Color(0xFFFBF5FF),
  bg2: Color(0xFFF3E9FB),
  ink: Color(0xFF1F1140),
  muted: Color(0xFF6A5A90),
  faint: Color(0xFFA99CC4),
  accent: Color(0xFFE0117F),
  accent2: Color(0xFF0BB6D6),
  danger: Color(0xFFD92D2D),
  border: Color(0x14000000),
);
const _terminalLight = ThemeTokens(
  bg: Color(0xFFF4FFF5),
  bg2: Color(0xFFE6F5E8),
  ink: Color(0xFF0B130B),
  muted: Color(0xFF4F6E50),
  faint: Color(0xFF8FB892),
  accent: Color(0xFF18A34A),
  accent2: Color(0xFFC79100),
  danger: Color(0xFFD92D2D),
  border: Color(0x14000000),
);
const _catppuccinLight = ThemeTokens(
  bg: Color(0xFFEFF1F5),
  bg2: Color(0xFFE6E9EF),
  ink: Color(0xFF4C4F69),
  muted: Color(0xFF6C6F85),
  faint: Color(0xFF9CA0B0),
  accent: Color(0xFF8839EF),
  accent2: Color(0xFF1E66F5),
  danger: Color(0xFFD20F39),
  border: Color(0x14000000),
);
const _nordLight = ThemeTokens(
  bg: Color(0xFFECEFF4),
  bg2: Color(0xFFE5E9F0),
  ink: Color(0xFF2E3440),
  muted: Color(0xFF4C566A),
  faint: Color(0xFF9AA3B4),
  accent: Color(0xFF5E81AC),
  accent2: Color(0xFF81A1C1),
  danger: Color(0xFFBF616A),
  border: Color(0x14000000),
);
const _gruvboxLight = ThemeTokens(
  bg: Color(0xFFFBF1C7),
  bg2: Color(0xFFF2E5BC),
  ink: Color(0xFF3C3836),
  muted: Color(0xFF7C6F64),
  faint: Color(0xFFA89984),
  accent: Color(0xFFAF3A03),
  accent2: Color(0xFF427B58),
  danger: Color(0xFF9D0006),
  border: Color(0x14000000),
);
const _draculaLight = ThemeTokens(
  bg: Color(0xFFF5F5FB),
  bg2: Color(0xFFEAEAF4),
  ink: Color(0xFF282A36),
  muted: Color(0xFF6272A4),
  faint: Color(0xFFA3A8C4),
  accent: Color(0xFF7D4FD6),
  accent2: Color(0xFFD6248F),
  danger: Color(0xFFCB3A2A),
  border: Color(0x14000000),
);
const _monoLight = ThemeTokens(
  bg: Color(0xFFFBFBFC),
  bg2: Color(0xFFF0F0F2),
  ink: Color(0xFF121215),
  muted: Color(0xFF62626B),
  faint: Color(0xFFA8A8B0),
  accent: Color(0xFF2A2A30),
  accent2: Color(0xFF6A6A74),
  danger: Color(0xFFFF6B6B),
  border: Color(0x14000000),
);
const _royalLight = ThemeTokens(
  bg: Color(0xFFFBF8FF),
  bg2: Color(0xFFF1ECFB),
  ink: Color(0xFF16122A),
  muted: Color(0xFF6A5F8C),
  faint: Color(0xFFA89CC0),
  accent: Color(0xFFB8902A),
  accent2: Color(0xFF7B5FE0),
  danger: Color(0xFFD92D2D),
  border: Color(0x14000000),
);

ThemeTokens tokensFor(AppTheme theme, Brightness brightness) {
  assert(theme != AppTheme.custom, 'custom theme has no fixed tokens');
  final isDark = brightness == Brightness.dark;
  return switch (theme) {
    AppTheme.indigoNight => isDark ? _indigoDark : _indigoLight,
    AppTheme.carbon => isDark ? _carbonDark : _carbonLight,
    AppTheme.plum => isDark ? _plumDark : _plumLight,
    AppTheme.custom => throw StateError('unreachable'),
    AppTheme.regression => isDark ? _regressionDark : _regressionLight,
    AppTheme.ember => isDark ? _emberDark : _emberLight,
    AppTheme.synthwave => isDark ? _synthwaveDark : _synthwaveLight,
    AppTheme.terminal => isDark ? _terminalDark : _terminalLight,
    AppTheme.catppuccin => isDark ? _catppuccinDark : _catppuccinLight,
    AppTheme.nord => isDark ? _nordDark : _nordLight,
    AppTheme.gruvbox => isDark ? _gruvboxDark : _gruvboxLight,
    AppTheme.dracula => isDark ? _draculaDark : _draculaLight,
    AppTheme.mono => isDark ? _monoDark : _monoLight,
    AppTheme.royal => isDark ? _royalDark : _royalLight,
  };
}
