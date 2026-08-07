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
}) => wheelScrollTarget(
  pixels: pixels,
  rawDelta: rawDelta,
  reverse: reverse,
  speed: speed,
  minExtent: minExtent,
  maxExtent: maxExtent,
);

void main() {
  test('a notch moves the multiple of what the platform would', () {
    // Measured against the running app: 53px notch at 1.7x moves 90.1px.
    expect(_target(), closeTo(500 + 90.1, 0.001));
    expect(_target(speed: 4), closeTo(500 + 212, 0.001));
  });

  test('a reversed axis moves the other way, not less far', () {
    // Scrollable negates the delta on a reversed axis. Matching that sign is
    // what makes the two compound; getting it wrong cancels them out.
    expect(_target(reverse: true), closeTo(500 - 90.1, 0.001));
    expect(_target(reverse: true, rawDelta: -53), closeTo(500 + 90.1, 0.001));
  });

  test('slower than the platform still moves the short distance', () {
    expect(_target(speed: 0.5), closeTo(500 + 26.5, 0.001));
  });

  test('near an edge it lands on the edge rather than past it', () {
    expect(_target(pixels: 9950, speed: 4, maxExtent: 10000), 10000);
    expect(_target(pixels: 30, rawDelta: -53, speed: 4, minExtent: 0), 0);
    // Sitting on the edge and pushing further is not a move.
    expect(_target(pixels: 10000, maxExtent: 10000), isNull);
    expect(_target(pixels: 0, rawDelta: -53, minExtent: 0), isNull);
  });

  test('at 1x the platform is left to it', () {
    expect(_target(speed: 1), isNull);
  });

  test('an empty notch is not a move', () {
    expect(_target(rawDelta: 0), isNull);
  });
}
