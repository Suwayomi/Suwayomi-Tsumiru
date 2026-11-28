// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'chrome_extents.g.dart';

/// Measured chrome extents include system insets; do not add them again at call sites.
@immutable
class ChromeExtents {
  const ChromeExtents({
    required this.topInset,
    required this.bottomInset,
  });

  /// Fallback offsets before the first chrome measurement.
  static const ChromeExtents initial = ChromeExtents(
    topInset: 80,
    bottomInset: 100,
  );

  /// System status-bar inset + measured top-bar height (dp).
  final double topInset;

  /// System nav-bar inset + measured bottom-bar height (dp, mode-specific).
  final double bottomInset;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChromeExtents &&
          runtimeType == other.runtimeType &&
          topInset == other.topInset &&
          bottomInset == other.bottomInset;

  @override
  int get hashCode => Object.hash(topInset, bottomInset);

  @override
  String toString() =>
      'ChromeExtents(topInset: $topInset, bottomInset: $bottomInset)';
}

/// Side insets the reader chrome keeps its controls out of.
///
/// With "Ignore safe area" on, the page draws under the side insets (iPhone
/// Duo's cover-screen status column, a notch in landscape) and nothing above
/// the chrome applies them, so the bars inset their contents by this while
/// their backgrounds still run to the edge. With it off, the reader's
/// SafeArea has already taken the insets and this is zero.
EdgeInsets readerChromeSideInsets(BuildContext context) {
  final padding = MediaQuery.viewPaddingOf(context);
  return EdgeInsets.only(left: padding.left, right: padding.right);
}

/// Measure fully shown bars and update after layout to avoid build writes and animation feedback.
@Riverpod(keepAlive: false)
class ChromeExtentsNotifier extends _$ChromeExtentsNotifier {
  @override
  ChromeExtents build() => ChromeExtents.initial;

  /// Call after the frame with system insets already included; equal measurements are no-ops.
  void update(ChromeExtents extents) {
    if (state == extents) return; // equality guard — no feedback loop
    state = extents;
  }
}
