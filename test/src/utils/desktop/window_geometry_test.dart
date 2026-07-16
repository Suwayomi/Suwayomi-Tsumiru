import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/utils/desktop/window_geometry.dart';

void main() {
  const fallback = Size(1280, 720);
  const min = Size(800, 600);

  test('falls back when nothing saved', () {
    expect(resolveRestoreSize(null, fallback: fallback, min: min), fallback);
  });

  test('restores a saved size', () {
    final g = WindowGeometry(size: const Size(1000, 700));
    expect(resolveRestoreSize(g, fallback: fallback, min: min),
        const Size(1000, 700));
  });

  test('clamps a too-small saved size up to the minimum', () {
    final g = WindowGeometry(size: const Size(300, 200));
    expect(resolveRestoreSize(g, fallback: fallback, min: min), min);
  });

  test('does not persist size while maximized', () {
    expect(shouldPersistSize(isMaximized: true), isFalse);
    expect(shouldPersistSize(isMaximized: false), isTrue);
  });

  test('clampToMin raises each axis independently', () {
    expect(clampToMin(const Size(300, 900), min), const Size(800, 900));
  });

  test('corrupt saved sizes fall back instead of reaching the window layer',
      () {
    for (final bad in [
      const Size(double.nan, 700),
      const Size(1000, double.infinity),
      const Size(-100, 700),
      const Size(0, 0),
      const Size(100000, 700),
    ]) {
      expect(
        resolveRestoreSize(WindowGeometry(size: bad),
            fallback: fallback, min: min),
        fallback,
        reason: 'expected fallback for $bad',
      );
    }
  });
}
