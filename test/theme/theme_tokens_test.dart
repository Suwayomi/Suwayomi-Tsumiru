import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/constants/app_theme.dart';
import 'package:tsumiru/src/utils/theme/theme_tokens.dart';

void main() {
  test('indigoNight dark tokens mirror theme-kit indigo.css', () {
    final t = tokensFor(AppTheme.indigoNight, Brightness.dark);
    expect(t.bg, const Color(0xFF0B0D1A));
    expect(t.ink, const Color(0xFFEEF0FB));
    expect(t.accent, const Color(0xFF7C7BFF));
    expect(t.accent2, const Color(0xFF33D6FF));
  });

  test('every named theme resolves tokens for both brightnesses', () {
    for (final theme in AppTheme.values.where((t) => t != AppTheme.custom)) {
      expect(tokensFor(theme, Brightness.dark), isA<ThemeTokens>());
      expect(tokensFor(theme, Brightness.light), isA<ThemeTokens>());
    }
  });

  test('AppTheme.swatch returns brand accents', () {
    expect(AppTheme.indigoNight.swatch.$1, const Color(0xFF7C7BFF));
    expect(AppTheme.carbon.swatch.$1, const Color(0xFF19E6B0));
    expect(AppTheme.plum.swatch.$1, const Color(0xFFFF5DB1));
  });
}
