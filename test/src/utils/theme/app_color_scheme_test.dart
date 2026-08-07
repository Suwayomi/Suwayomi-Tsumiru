// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/constants/app_theme.dart';
import 'package:tsumiru/src/utils/theme/app_color_scheme.dart';
import 'package:tsumiru/src/utils/theme/theme_tokens.dart';

void main() {
  ColorScheme darkScheme(AppTheme theme) =>
      schemeFromTokens(tokensFor(theme, Brightness.dark), Brightness.dark);

  test('Monochrome dark: onPrimary is dark against its light-grey accent', () {
    final scheme = darkScheme(AppTheme.mono);
    // The accent is a near-white grey, so white text was illegible (#105).
    expect(scheme.primary.computeLuminance(), greaterThan(0.5),
        reason: 'the Monochrome accent should be light');
    expect(scheme.onPrimary, Colors.black);
  });

  test('Indigo Night (the dark-accent brand) keeps white onPrimary', () {
    // No regression for a genuinely dark accent.
    expect(darkScheme(AppTheme.indigoNight).onPrimary, Colors.white);
  });

  test('every dark theme: onPrimary genuinely contrasts primary', () {
    for (final theme in AppTheme.values) {
      if (theme == AppTheme.custom) continue; // custom is ColorScheme.fromSeed
      final scheme = darkScheme(theme);
      final contrast = (scheme.primary.computeLuminance() -
              scheme.onPrimary.computeLuminance())
          .abs();
      expect(contrast, greaterThan(0.3),
          reason: '$theme: primary/onPrimary too close ($contrast)');
    }
  });
}
