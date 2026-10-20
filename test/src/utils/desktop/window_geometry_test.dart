import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/utils/desktop/desktop_window.dart';
import 'package:tsumiru/src/utils/desktop/window_geometry.dart';

void main() {
  const fallback = Size(1280, 720);
  const min = Size(800, 600);

  test('restores a saved size and falls back when nothing is saved', () {
    expect(resolveRestoreSize(null, fallback: fallback, min: min), fallback);
    expect(
      resolveRestoreSize(
        WindowGeometry(size: const Size(1000, 700)),
        fallback: fallback,
        min: min,
      ),
      const Size(1000, 700),
    );
  });

  test('clamps a too-small saved size up to the minimum', () {
    expect(
      resolveRestoreSize(
        WindowGeometry(size: const Size(300, 200)),
        fallback: fallback,
        min: min,
      ),
      min,
    );
    // Each axis is raised independently.
    expect(clampToMin(const Size(300, 900), min), const Size(800, 900));
  });

  test(
    'corrupt saved sizes fall back instead of reaching the window layer',
    () {
      for (final bad in [
        const Size(double.nan, 700),
        const Size(1000, double.infinity),
        const Size(-100, 700),
        const Size(0, 0),
        const Size(100000, 700),
      ]) {
        expect(
          resolveRestoreSize(
            WindowGeometry(size: bad),
            fallback: fallback,
            min: min,
          ),
          fallback,
          reason: 'expected fallback for $bad',
        );
      }
    },
  );

  test('minimum window fits the two-row desktop layout', () {
    // Pinned: the desktop layout needs width >= 600 with a shortestSide >=
    // 600, and linux/my_application.cc mirrors this floor natively.
    expect(kMinWindowSize, const Size(600, 600));
    expect(
      resolveRestoreSize(
        const WindowGeometry(size: Size(300, 400)),
        fallback: fallback,
        min: kMinWindowSize,
      ),
      kMinWindowSize,
    );
  });
}
