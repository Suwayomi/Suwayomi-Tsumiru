// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.


/// Stacks wheel notches onto [pendingTarget]; returns null if unchanged and mirrors reversed axes.
double? wheelScrollTarget({
  required double pixels,
  required double rawDelta,
  required bool reverse,
  required double speed,
  required double minExtent,
  required double maxExtent,
  double? pendingTarget,
}) {
  final applied = reverse ? -rawDelta : rawDelta;
  if (applied == 0 || speed == 0) return null;
  final target = ((pendingTarget ?? pixels) + applied * speed)
      .clamp(minExtent, maxExtent)
      .toDouble();
  return target == pixels ? null : target;
}
