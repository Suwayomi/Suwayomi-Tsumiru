// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

/// Where a wheel notch should land the reader, given [speed] as a multiple of
/// what the platform would do on its own.
///
/// Returns null when the position wouldn't move. [reverse] mirrors what
/// `Scrollable` does with a reversed axis (`scrollable.dart` negates the delta
/// there); getting it wrong makes the two cancel instead of compounding.
double? wheelScrollTarget({
  required double pixels,
  required double rawDelta,
  required bool reverse,
  required double speed,
  required double minExtent,
  required double maxExtent,
}) {
  final applied = reverse ? -rawDelta : rawDelta;
  if (applied == 0 || speed == 1) return null;
  final target =
      (pixels + applied * speed).clamp(minExtent, maxExtent).toDouble();
  return target == pixels ? null : target;
}
