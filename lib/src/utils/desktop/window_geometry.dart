// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:ui';

/// Persisted desktop window state. Size is in logical pixels.
class WindowGeometry {
  final Size? size;
  final bool maximized;
  const WindowGeometry({this.size, this.maximized = false});
}

/// Raise each axis of [size] to at least [min].
Size clampToMin(Size size, Size min) => Size(
      size.width < min.width ? min.width : size.width,
      size.height < min.height ? min.height : size.height,
    );

/// Sanity cap against corrupted prefs.
const double _kMaxDimension = 8192;

/// The size to open at: the saved size (clamped to [min]), else [fallback].
/// Corrupt saved values (NaN/infinite/non-positive/absurd) fall back.
Size resolveRestoreSize(
  WindowGeometry? saved, {
  required Size fallback,
  required Size min,
}) {
  final s = saved?.size;
  if (s == null ||
      !s.isFinite ||
      s.width <= 0 ||
      s.height <= 0 ||
      s.width > _kMaxDimension ||
      s.height > _kMaxDimension) {
    return fallback;
  }
  return clampToMin(s, min);
}

/// Never persist the window size while maximized — it would save the
/// screen-filling size as the restore size.
bool shouldPersistSize({required bool isMaximized}) => !isMaximized;
