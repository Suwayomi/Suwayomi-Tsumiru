import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/utils/desktop/window_geometry.dart';

void main() {
  const fallback = Size(1280, 720);
  const min = Size(800, 600);

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
}
