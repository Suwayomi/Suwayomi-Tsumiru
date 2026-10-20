import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/constants/app_theme.dart';
import 'package:tsumiru/src/utils/theme/app_theme_builder.dart';
import 'package:tsumiru/src/utils/theme/theme_tokens.dart';

void main() {
  test('indigoNight dark tokens mirror theme-kit indigo.css and carry into '
      'the built theme', () {
    final t = tokensFor(AppTheme.indigoNight, Brightness.dark);
    expect(t.bg, const Color(0xFF0B0D1A));
    expect(t.ink, const Color(0xFFEEF0FB));
    expect(t.accent, const Color(0xFF7C7BFF));
    expect(t.accent2, const Color(0xFF33D6FF));
    expect(t.danger, const Color(0xFFFF6B6B));

    final theme = buildAppTheme(
      theme: AppTheme.indigoNight,
      brightness: Brightness.dark,
      customSeed: const Color(0xFF7C7BFF),
      amoled: false,
    );
    expect(theme.useMaterial3, isTrue);
    expect(theme.colorScheme.surface, const Color(0xFF0B0D1A));
    expect(theme.scaffoldBackgroundColor, const Color(0xFF0B0D1A));

    // Amoled applies in dark only, preserving the named accents.
    final amoled = buildAppTheme(
      theme: AppTheme.indigoNight,
      brightness: Brightness.dark,
      customSeed: const Color(0xFF7C7BFF),
      amoled: true,
    );
    final light = buildAppTheme(
      theme: AppTheme.indigoNight,
      brightness: Brightness.light,
      customSeed: const Color(0xFF7C7BFF),
      amoled: true,
    );
    expect(amoled.colorScheme.surface, const Color(0xFF000000));
    expect(light.colorScheme.surface, isNot(const Color(0xFF000000)));
    expect(amoled.colorScheme.primary, theme.colorScheme.primary);
    expect(amoled.colorScheme.onSurface, theme.colorScheme.onSurface);

    // A custom theme derives its accent from the seed.
    final custom = buildAppTheme(
      theme: AppTheme.custom,
      brightness: Brightness.dark,
      customSeed: const Color(0xFFFF0000),
      amoled: false,
    );
    expect(
      custom.colorScheme.primary.r,
      greaterThan(custom.colorScheme.primary.b),
    );
  });
}
