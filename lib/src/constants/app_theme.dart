import 'package:flutter/material.dart';

import '../utils/extensions/custom_extensions.dart';

/// App-level curated themes. Dark hexes mirror ~/Projects/theme-kit/themes/*.css.
enum AppTheme {
  indigoNight,
  carbon,
  plum,
  custom,
  regression,
  ember,
  synthwave,
  terminal,
  catppuccin,
  nord,
  gruvbox,
  dracula,
  mono,
  royal;

  /// (accent, accent2) used for the picker swatch preview.
  (Color, Color) get swatch => switch (this) {
        AppTheme.indigoNight =>
          (const Color(0xFF7C7BFF), const Color(0xFF33D6FF)),
        AppTheme.carbon => (const Color(0xFF19E6B0), const Color(0xFF22D3EE)),
        AppTheme.plum => (const Color(0xFFFF5DB1), const Color(0xFFFF9F5C)),
        // placeholder swatch for the user-seeded custom theme
        AppTheme.custom =>
          (const Color(0xFF7C7BFF), const Color(0xFF33D6FF)),
        AppTheme.regression =>
          (const Color(0xFF3D8BFF), const Color(0xFF6FD2FF)),
        AppTheme.ember =>
          (const Color(0xFFFF3B4E), const Color(0xFFFFB338)),
        AppTheme.synthwave =>
          (const Color(0xFFFF2E97), const Color(0xFF2DE2FF)),
        AppTheme.terminal =>
          (const Color(0xFF36FF7A), const Color(0xFFFFD84D)),
        AppTheme.catppuccin =>
          (const Color(0xFFCBA6F7), const Color(0xFF89B4FA)),
        AppTheme.nord =>
          (const Color(0xFF88C0D0), const Color(0xFF81A1C1)),
        AppTheme.gruvbox =>
          (const Color(0xFFFE8019), const Color(0xFF8EC07C)),
        AppTheme.dracula =>
          (const Color(0xFFBD93F9), const Color(0xFFFF79C6)),
        AppTheme.mono =>
          (const Color(0xFFE8E8EE), const Color(0xFFA8A8B2)),
        AppTheme.royal =>
          (const Color(0xFFE8C468), const Color(0xFF9B7BFF)),
      };
}

extension AppThemeLabel on AppTheme {
  String label(BuildContext context) => switch (this) {
        AppTheme.indigoNight => context.l10n.appThemeIndigoNight,
        AppTheme.carbon => context.l10n.appThemeCarbon,
        AppTheme.plum => context.l10n.appThemePlum,
        AppTheme.custom => context.l10n.appThemeCustom,
        AppTheme.regression => 'Regression',
        AppTheme.ember => 'Ember',
        AppTheme.synthwave => 'Synthwave',
        AppTheme.terminal => 'Terminal',
        AppTheme.catppuccin => 'Catppuccin Mocha',
        AppTheme.nord => 'Nord',
        AppTheme.gruvbox => 'Gruvbox',
        AppTheme.dracula => 'Dracula',
        AppTheme.mono => 'Monochrome',
        AppTheme.royal => 'Royal',
      };
}
