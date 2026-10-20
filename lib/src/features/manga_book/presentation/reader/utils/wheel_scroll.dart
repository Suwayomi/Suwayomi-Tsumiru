// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.


/// Where a wheel notch should land the reader, given [speed] as a multiple of
/// what the platform would do on its own.
///
/// [pendingTarget] is where a glide already in flight is headed. Notches that
/// arrive mid-glide stack onto it rather than onto the pixel the animation has
/// reached, so a burst travels their combined distance instead of losing the
/// tail of each one.
///
/// Returns null when the reader wouldn't move. [reverse] mirrors what
/// `Scrollable` does with a reversed axis (`scrollable.dart` negates the delta
/// there); getting it wrong makes the two cancel instead of compounding.
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
