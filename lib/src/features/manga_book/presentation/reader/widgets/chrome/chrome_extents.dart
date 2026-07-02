// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'chrome_extents.g.dart';

/// Immutable snapshot of the reader chrome's inset extents, used to position
/// the side seek bar so it never overlaps the top or bottom bars.
///
/// [topInset]    = measured [ReaderTopBar] Material height.
///                 The Material wraps `Padding(top: systemTopInset)`, so
///                 `size.height` from [MeasureSize] already includes the
///                 status-bar inset — do NOT add it again at the call site.
///
/// [bottomInset] = system nav-bar inset (`View.viewPadding.bottom / dpr`)
///                 + measured bottom-controls height.
///                 The bottom bar is **shorter in webtoon mode** (no horizontal
///                 seek row), so the extent is mode-specific and must be
///                 measured — a constant can't capture it.
///
/// Both fields default to sensible fallback values (80 dp top, 100 dp bottom)
/// that match the old hardcoded [Positioned] offsets, so callers are safe even
/// before the first measurement fires.
@immutable
class ChromeExtents {
  const ChromeExtents({
    required this.topInset,
    required this.bottomInset,
  });

  /// Fallback that reproduces the hardcoded literals from the old
  /// [ReaderSideSeekBar]. Used as the initial provider state so the seekbar
  /// never jumps on the first frame before measurement fires.
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

/// Holds the current, measured [ChromeExtents] for the reader chrome.
///
/// Notifier design (manual, no riverpod_annotation codegen) so the update
/// method can be called directly by the chrome widgets without a generated
/// file or a codegen run for this purely UI-layer piece of state.
///
/// Guards:
/// - Writes are issued from **post-frame callbacks** inside [MeasureSize] so
///   they never fire during a build.
/// - The notifier only writes when the new value differs from the current one
///   (equality-guarded) — no relayout feedback loop.
/// - Measurement is at resting (fully-shown) bar height; the animation drives
///   fade only on the side seekbar so the extent never chases a slide.
@Riverpod(keepAlive: false)
class ChromeExtentsNotifier extends _$ChromeExtentsNotifier {
  @override
  ChromeExtents build() => ChromeExtents.initial;

  /// Update [ChromeExtents] with newly measured bar heights and system insets.
  ///
  /// The caller is responsible for composing `systemInset + measuredBarHeight`
  /// and calling this only from a post-frame callback (deferred write).
  /// The notifier provides the equality guard so duplicate writes are no-ops.
  void update(ChromeExtents extents) {
    if (state == extents) return; // equality guard — no feedback loop
    state = extents;
  }
}
