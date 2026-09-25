import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/constants/app_theme.dart';
import 'package:tsumiru/src/utils/theme/app_color_scheme.dart';
import 'package:tsumiru/src/utils/theme/theme_tokens.dart';

/// WCAG 2.x relative luminance for one sRGB channel (0..1).
double _channel(double c) =>
    c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color c) =>
    0.2126 * _channel(c.r) + 0.7152 * _channel(c.g) + 0.0722 * _channel(c.b);

double contrastRatio(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
}

void _expectRatio(Color a, Color b, double minimum, String what) {
  final ratio = contrastRatio(a, b);
  expect(
    ratio,
    greaterThanOrEqualTo(minimum),
    reason: '$what: ${ratio.toStringAsFixed(2)}:1, needs $minimum:1',
  );
}

void main() {
  for (final theme in AppTheme.values.where((t) => t != AppTheme.custom)) {
    test('${theme.name} light scheme meets WCAG contrast', () {
      final tokens = tokensFor(theme, Brightness.light);
      final s = schemeFromTokens(tokens, Brightness.light);

      _expectRatio(s.onSurface, s.surface, 7.0, 'onSurface/surface');
      _expectRatio(
        s.onSurfaceVariant,
        s.surface,
        4.5,
        'onSurfaceVariant/surface',
      );
      _expectRatio(
        s.onSurfaceVariant,
        s.surfaceContainer,
        4.5,
        'onSurfaceVariant/surfaceContainer',
      );
      _expectRatio(s.primary, s.surface, 4.5, 'primary/surface');
      _expectRatio(
        s.primary,
        s.surfaceContainer,
        4.5,
        'primary/surfaceContainer',
      );
      _expectRatio(s.onPrimary, s.primary, 4.5, 'onPrimary/primary');
      _expectRatio(
        s.onSecondaryContainer,
        s.secondaryContainer,
        4.5,
        'onSecondaryContainer/secondaryContainer',
      );
      _expectRatio(s.error, s.surface, 4.5, 'error/surface');
      _expectRatio(s.outline, s.surface, 3.0, 'outline/surface');

      final onAccent = tokens.onAccent!;
      for (final stop in tokens.grad!.colors) {
        _expectRatio(onAccent, stop, 4.5, 'onAccent/$stop (grad stop)');
      }
    });
  }
}
