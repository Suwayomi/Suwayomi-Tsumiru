// test/theme/app_theme_builder_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/constants/app_theme.dart';
import 'package:tsumiru/src/utils/theme/app_theme_builder.dart';

void main() {
  test('named dark theme carries brand surface', () {
    final theme = buildAppTheme(
      theme: AppTheme.indigoNight,
      brightness: Brightness.dark,
      customSeed: const Color(0xFF7C7BFF),
      amoled: false,
    );
    expect(theme.useMaterial3, isTrue);
    expect(theme.colorScheme.surface, const Color(0xFF0B0D1A));
    expect(theme.scaffoldBackgroundColor, const Color(0xFF0B0D1A));
  });

  test('amoled only applies in dark', () {
    final dark = buildAppTheme(
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
    expect(dark.colorScheme.surface, const Color(0xFF000000));
    expect(light.colorScheme.surface, isNot(const Color(0xFF000000)));
  });

  test('custom theme derives from seed', () {
    final theme = buildAppTheme(
      theme: AppTheme.custom,
      brightness: Brightness.dark,
      customSeed: const Color(0xFFFF0000),
      amoled: false,
    );
    // fromSeed maps a red seed to a reddish primary
    expect(theme.colorScheme.primary.r,
        greaterThan(theme.colorScheme.primary.b));
  });
}
