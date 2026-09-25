import 'package:flutter/material.dart';

import '../../constants/app_theme.dart';

/// Color tokens for a named theme at one brightness.
///
/// Every value is copied VERBATIM from `~/Projects/theme-kit/themes/<id>.css` —
/// never invented, never derived by Material. The DARK sets come from the
/// theme's `[data-mode='dark']` block, the LIGHT sets from its
/// `[data-mode='light']` block.
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
    this.onAccent,
    this.accentBg,
    this.grad,
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

  // The three below exist only on the LIGHT sets; the dark blocks name none of
  // them, and a null here keeps the dark scheme byte-identical to before.
  final Color? onAccent; // text on a filled accent  (--on-accent)
  final Color? accentBg; // tinted accent container  (--accent-bg)
  final LinearGradient? grad; // brand gradient  (--grad)
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

// --- LIGHT token sets: VERBATIM from theme-kit/themes/<id>.css ---
const _indigoLight = ThemeTokens(
  bg: Color(0xFFEEECF9),
  bg2: Color(0xFFFFFBFD),
  ink: Color(0xFF191B28),
  muted: Color(0xFF5C5D6F),
  faint: Color(0xFF7F8090),
  accent: Color(0xFF5351D4),
  accent2: Color(0xFF00758D),
  danger: Color(0xFFAE2F34),
  border: Color(0xFFD7D6E4), // --panel-brd
  onAccent: Color(0xFFFFFFFF),
  accentBg: Color(0xFFE2DFFF),
  grad: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF5550EC), Color(0xFF0677B3)],
  ),
);
const _carbonLight = ThemeTokens(
  bg: Color(0xFFE4F1EC),
  bg2: Color(0xFFFDFCFA),
  ink: Color(0xFF141D1B),
  muted: Color(0xFF4E635D),
  faint: Color(0xFF738580),
  accent: Color(0xFF007155),
  accent2: Color(0xFF007586),
  danger: Color(0xFFAC3236),
  border: Color(0xFFCCDAD5),
  onAccent: Color(0xFFFFFFFF),
  accentBg: Color(0xFFAFF0D4),
  grad: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF007759), Color(0xFF007889)],
  ),
);
const _plumLight = ThemeTokens(
  bg: Color(0xFFF7EAF7),
  bg2: Color(0xFFFFFBFF),
  ink: Color(0xFF211825),
  muted: Color(0xFF675A6B),
  faint: Color(0xFF897D8C),
  accent: Color(0xFFB81F78),
  accent2: Color(0xFFA35618),
  danger: Color(0xFFA7392F),
  border: Color(0xFFE0D3E1),
  onAccent: Color(0xFFFFFFFF),
  accentBg: Color(0xFFFFD8E6),
  grad: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFBE267D), Color(0xFFA85817)],
  ),
);

const _regressionLight = ThemeTokens(
  bg: Color(0xFFECEDF9),
  bg2: Color(0xFFFFFBFD),
  ink: Color(0xFF191B23),
  muted: Color(0xFF595E6F),
  faint: Color(0xFF7D818F),
  accent: Color(0xFF0060C6),
  accent2: Color(0xFF007397),
  danger: Color(0xFFB4243A),
  border: Color(0xFFD5D6E4),
  onAccent: Color(0xFFFFFFFF),
  accentBg: Color(0xFFD7E2FF),
  grad: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0065CF), Color(0xFF00769A)],
  ),
);
const _emberLight = ThemeTokens(
  bg: Color(0xFFFFE9EB),
  bg2: Color(0xFFFFFBFF),
  ink: Color(0xFF24191B),
  muted: Color(0xFF72575C),
  faint: Color(0xFF957B7F),
  accent: Color(0xFFC8022D),
  accent2: Color(0xFF926000),
  danger: Color(0xFFB5242C),
  border: Color(0xFFEBD1D4),
  onAccent: Color(0xFFFFFFFF),
  accentBg: Color(0xFFFFDAD8),
  grad: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFCF0E31), Color(0xFF956300)],
  ),
);
const _synthwaveLight = ThemeTokens(
  bg: Color(0xFFF2EBF8),
  bg2: Color(0xFFFFFBFF),
  ink: Color(0xFF1F1538),
  muted: Color(0xFF615C6E),
  faint: Color(0xFF847F8F),
  accent: Color(0xFFC1006E),
  accent2: Color(0xFF007586),
  danger: Color(0xFFB42440),
  border: Color(0xFFDBD4E3),
  onAccent: Color(0xFFFFFFFF),
  accentBg: Color(0xFFFFD9E3),
  // The one 3-stop, 90° grad in theme-kit: left → right, magenta → violet → teal.
  grad: LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFFC8007A), Color(0xFF6B2BD6), Color(0xFF0079A0)],
    stops: [0, 0.55, 1],
  ),
);
const _terminalLight = ThemeTokens(
  bg: Color(0xFFE8F0E3),
  bg2: Color(0xFFFEFCF9),
  ink: Color(0xFF171D16),
  muted: Color(0xFF536252),
  faint: Color(0xFF788576),
  accent: Color(0xFF007330),
  accent2: Color(0xFF806800),
  danger: Color(0xFFB5242C),
  border: Color(0xFFD0DACC),
  onAccent: Color(0xFFFFFFFF),
  accentBg: Color(0xFFBDEFBF),
  grad: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF15803D), Color(0xFF0F766E)],
  ),
);
const _catppuccinLight = ThemeTokens(
  bg: Color(0xFFEFF1F5),
  bg2: Color(0xFFFFFFFF),
  ink: Color(0xFF4C4F69),
  muted: Color(0xFF5C5F77),
  faint: Color(0xFF7C7F93),
  accent: Color(0xFF7A2FE0),
  accent2: Color(0xFF1E66F5),
  danger: Color(0xFFB80D32),
  border: Color(0xFFCCD0DA),
  onAccent: Color(0xFFFFFFFF),
  accentBg: Color(0xFFECE2FC),
  grad: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF7A2FE0), Color(0xFF1A5AE0)],
  ),
);
const _nordLight = ThemeTokens(
  bg: Color(0xFFEBEDF9),
  bg2: Color(0xFFFEFBFD),
  ink: Color(0xFF161C27),
  muted: Color(0xFF575E6E),
  faint: Color(0xFF7B818F),
  accent: Color(0xFF006D80),
  accent2: Color(0xFF316F9F),
  danger: Color(0xFF99434C),
  border: Color(0xFFD3D7E3),
  onAccent: Color(0xFFFFFFFF),
  accentBg: Color(0xFFACECFF),
  grad: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF007286), Color(0xFF0772B0)],
  ),
);
const _gruvboxLight = ThemeTokens(
  bg: Color(0xFFE7E5DF),
  bg2: Color(0xFFF7F6F2),
  ink: Color(0xFF282828),
  muted: Color(0xFF5A524C),
  faint: Color(0xFF857C74),
  accent: Color(0xFFAF3A03),
  accent2: Color(0xFF3F7552),
  danger: Color(0xFF9D0006),
  border: Color(0xFFCFCBC2),
  onAccent: Color(0xFFFFFFFF),
  accentBg: Color(0xFFF5DCC8),
  grad: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFC2530C), Color(0xFF9D3205)],
  ),
);
const _draculaLight = ThemeTokens(
  bg: Color(0xFFEEEDF9),
  bg2: Color(0xFFFFFBFD),
  ink: Color(0xFF191B26),
  muted: Color(0xFF5B5D6F),
  faint: Color(0xFF7F8090),
  accent: Color(0xFF764FAF),
  accent2: Color(0xFFB43B86),
  danger: Color(0xFFB71F29),
  border: Color(0xFFD6D6E4),
  onAccent: Color(0xFFFFFFFF),
  accentBg: Color(0xFFEDDCFF),
  grad: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF7C54B4), Color(0xFFB73E88)],
  ),
);
const _monoLight = ThemeTokens(
  bg: Color(0xFFF3F3F5),
  bg2: Color(0xFFFFFFFF),
  ink: Color(0xFF0A0A0B),
  muted: Color(0xFF4A4A52),
  faint: Color(0xFF76767E),
  accent: Color(0xFF111114),
  accent2: Color(0xFF55555C),
  danger: Color(0xFFAE2F34),
  border: Color(0xFFD9D9DE),
  onAccent: Color(0xFFFFFFFF),
  accentBg: Color(0xFFE3E3E8),
  grad: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1A1A1E), Color(0xFF55555C)],
  ),
);
const _royalLight = ThemeTokens(
  bg: Color(0xFFF1EBF9),
  bg2: Color(0xFFFFFBFF),
  ink: Color(0xFF1C1A26),
  muted: Color(0xFF605C6E),
  faint: Color(0xFF837F8F),
  accent: Color(0xFF5F45CC),
  accent2: Color(0xFF8A6400),
  danger: Color(0xFFAE2F34),
  border: Color(0xFFDAD5E3),
  onAccent: Color(0xFFFFFFFF),
  accentBg: Color(0xFFE7E0FF),
  grad: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF5F45CC), Color(0xFF8E3FB8)],
  ),
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
