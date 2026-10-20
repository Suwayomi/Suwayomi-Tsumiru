// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/utils/wheel_scroll.dart';

double? _target({
  double pixels = 500,
  double rawDelta = 53,
  bool reverse = false,
  double speed = 1.7,
  double minExtent = 0,
  double maxExtent = 10000,
  double? pendingTarget,
}) =>
    wheelScrollTarget(
      pixels: pixels,
      rawDelta: rawDelta,
      reverse: reverse,
      speed: speed,
      minExtent: minExtent,
      maxExtent: maxExtent,
      pendingTarget: pendingTarget,
    );

void main() {
  test('notches during a glide stack onto the pending target', () {
    final first = _target(pixels: 500, speed: 1.7);
    final second = _target(pixels: 520, pendingTarget: first, speed: 1.7);
    expect(second, closeTo(500 + 53 * 1.7 * 2, 0.001));
    expect(
      _target(pixels: 9000, pendingTarget: 9950, speed: 4, maxExtent: 10000),
      10000,
    );
  });
}
