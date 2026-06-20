// test/theme/app_color_scheme_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/constants/app_theme.dart';
import 'package:tsumiru/src/utils/theme/app_color_scheme.dart';
import 'package:tsumiru/src/utils/theme/theme_tokens.dart';

void main() {
  test('dark scheme uses brand surface and accent verbatim', () {
    final scheme =
        schemeFromTokens(tokensFor(AppTheme.indigoNight, Brightness.dark), Brightness.dark);
    expect(scheme.brightness, Brightness.dark);
    expect(scheme.surface, const Color(0xFF0B0D1A));
    expect(scheme.primary, const Color(0xFF7C7BFF));
    expect(scheme.secondary, const Color(0xFF33D6FF));
    expect(scheme.onSurface, const Color(0xFFEEF0FB));
    expect(scheme.error, const Color(0xFFFF6B6B));
  });

  test('light scheme is light brightness with light surface', () {
    final scheme =
        schemeFromTokens(tokensFor(AppTheme.carbon, Brightness.light), Brightness.light);
    expect(scheme.brightness, Brightness.light);
    expect(scheme.surface, const Color(0xFFF6FFFB));
  });

  test('amoled forces surface to true black, preserves primary', () {
    final dark =
        schemeFromTokens(tokensFor(AppTheme.indigoNight, Brightness.dark), Brightness.dark);
    final amoled = applyAmoled(dark);
    expect(amoled.surface, const Color(0xFF000000));
    expect(amoled.surfaceContainerLowest, const Color(0xFF000000));
    expect(amoled.primary, dark.primary); // accent preserved
    expect(amoled.onSurface, dark.onSurface);
  });
}
