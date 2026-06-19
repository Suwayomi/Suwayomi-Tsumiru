import 'package:flutter/material.dart';

import '../utils/extensions/custom_extensions.dart';

/// App-level curated themes. Replaces direct use of the third-party
/// `FlexScheme` enum. Dark hexes mirror ~/Projects/theme-kit/themes/*.css.
enum AppTheme {
  indigoNight,
  carbon,
  plum,
  custom;

  /// (accent, accent2) used for the picker swatch preview.
  (Color, Color) get swatch => switch (this) {
        AppTheme.indigoNight =>
          (const Color(0xFF7C7BFF), const Color(0xFF33D6FF)),
        AppTheme.carbon => (const Color(0xFF19E6B0), const Color(0xFF22D3EE)),
        AppTheme.plum => (const Color(0xFFFF5DB1), const Color(0xFFFF9F5C)),
        AppTheme.custom =>
          (const Color(0xFF7C7BFF), const Color(0xFF33D6FF)),
      };
}

extension AppThemeLabel on AppTheme {
  String label(BuildContext context) => switch (this) {
        AppTheme.indigoNight => context.l10n.appThemeIndigoNight,
        AppTheme.carbon => context.l10n.appThemeCarbon,
        AppTheme.plum => context.l10n.appThemePlum,
        AppTheme.custom => context.l10n.appThemeCustom,
      };
}
