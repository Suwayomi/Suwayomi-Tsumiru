// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

/// Configuration constants for infinity continuous reader mode
class InfinityContinuousConfig {
  const InfinityContinuousConfig._();

  /// Cooldown period to prevent rapid chapter loading triggers
  static const Duration chapterLoadCooldown = Duration(milliseconds: 500);

  /// Tolerance for detecting when scroll position is at min/max extent (in pixels)
  static const double scrollExtentTolerance = 1.0;

  /// Higher threshold for user feedback to avoid spam
  static const double feedbackThreshold = 30.0;

  /// Minimum visibility threshold for position tracking
  static const double minVisibleAreaThreshold = 0.4;

  /// Scroll animation duration
  static const Duration scrollAnimationDuration = Duration(milliseconds: 200);

  /// Feedback cooldown to prevent spam
  static const Duration feedbackCooldown = Duration(seconds: 3);

  /// Scroll restoration timing controls
  static const Duration scrollRestorationDelay = Duration(milliseconds: 16);
  static const Duration scrollRestorationFallbackDelay =
      Duration(milliseconds: 50);
  static const Duration scrollRestorationTimeout = Duration(milliseconds: 200);

  /// Scroll position calculation precision
  static const double scrollAlignmentPrecision = 0.001;
  static const double scrollPositionTolerance = 0.1;

  /// Navigation threshold for determining when to move to next/previous item
  static const double navigationTrailingThreshold = 0.8;
  static const double navigationLeadingThreshold = 0.2;

  /// Default scroll animation curve
  static const Curve scrollAnimationCurve = Curves.easeOut;

  /// Cache extent multiplier in units of one viewport. Controls how
  /// far above and below the visible area Flutter keeps page widgets
  /// laid out. 2.0 = roughly two viewport heights of cache on each
  /// side, enough to keep adjacent pages alive for smooth scrolling
  /// without bloating memory.
  static const double verticalCacheMultiplier = 2.0;
  static const double horizontalCacheMultiplier = 2.0;

  /// Minimum net pixel movement of the top-most item's leading edge
  /// between two position-listener ticks before it counts as a
  /// deliberate scroll, for the purpose of the next/previous-chapter
  /// boundary trigger's direction check. Expressed in pixels rather
  /// than a viewport fraction: the previous fixed fraction (0.0015,
  /// ~1px on a typical phone) let ordinary sub-pixel layout jitter —
  /// e.g. a page-height correction landing while that page sits at the
  /// viewport top, see decodeAndCacheHeight — masquerade as a real
  /// scroll-up gesture and fire loadPreviousChapter unprompted.
  static const double boundaryScrollDirectionEpsilonPx = 24.0;

  /// Minimum visible-area fraction (see
  /// [InfinityContinuousUtils.calculateVisibleArea]) a page must clear
  /// to count toward the next/previous-chapter boundary trigger.
  /// Deliberately lower than [minVisibleAreaThreshold] (which decides
  /// the "current" page for progress tracking): a full 40% floor would
  /// delay the trigger past the point several short pages share the
  /// screen (see the #100 note on selectCurrentIndex), but the previous
  /// 0% floor let a single grazed pixel — routinely produced when a
  /// fast fling through a long chapter briefly lays out its tail pages —
  /// fire the load several pages before the reader actually gets there.
  static const double boundaryVisibleAreaThreshold = 0.12;

  /// Page height/width ratio for different orientations
  static const double verticalPageHeightRatio = 0.7;
  static const double horizontalPageWidthRatio = 0.7;

  /// Interactive viewer max scale for pinch to zoom
  static const double maxZoomScale = 5.0;
}

/// Gap between pages in "Long strip with gaps".
const double kLongStripPageGap = 16;
