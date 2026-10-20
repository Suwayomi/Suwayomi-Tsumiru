// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/utils/wheel_scroll.dart';

double? _target({double speed = 1.7}) => wheelScrollTarget(
  pixels: 500,
  rawDelta: 53,
  reverse: false,
  speed: speed,
  minExtent: 0,
  maxExtent: 10000,
);

void main() {
  test('a notch moves the multiple of what the platform would', () {
    // Measured against the running app: 53px notch at 1.7x moves 90.1px.
    expect(_target(), closeTo(500 + 90.1, 0.001));
    expect(_target(speed: 4), closeTo(500 + 212, 0.001));
  });
}
