// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

class InfinityContinuousConfig {
  const InfinityContinuousConfig._();

  static const Duration chapterLoadCooldown = Duration(milliseconds: 500);

  /// Tolerance for detecting when scroll position is at min/max extent (in pixels)
  static const double scrollExtentTolerance = 1.0;

  static const double feedbackThreshold = 30.0;

  static const double minVisibleAreaThreshold = 0.4;

  static const Duration scrollAnimationDuration = Duration(milliseconds: 200);

  static const Duration feedbackCooldown = Duration(seconds: 3);

  static const Duration scrollRestorationDelay = Duration(milliseconds: 16);
  static const Duration scrollRestorationFallbackDelay =
      Duration(milliseconds: 50);
  static const Duration scrollRestorationTimeout = Duration(milliseconds: 200);

  static const double scrollAlignmentPrecision = 0.001;
  static const double scrollPositionTolerance = 0.1;

  static const double navigationTrailingThreshold = 0.8;
  static const double navigationLeadingThreshold = 0.2;

  static const Curve scrollAnimationCurve = Curves.easeOut;

  /// Viewport lengths cached on each side of the visible strip.
  static const double verticalCacheMultiplier = 2.0;
  static const double horizontalCacheMultiplier = 2.0;

  /// Ignore layout jitter when deciding whether scrolling should load a neighbouring chapter.
  static const double boundaryScrollDirectionEpsilonPx = 24.0;

  /// Boundary visibility floor is lower than the progress floor so short pages can trigger loading.
  static const double boundaryVisibleAreaThreshold = 0.12;

  static const double verticalPageHeightRatio = 0.7;
  static const double horizontalPageWidthRatio = 0.7;

  static const double maxZoomScale = 5.0;

  /// Space below the end-of-strip card, clear of the reader's bottom menu.
  static const double endOfStripSpace = 96.0;
}

/// Gap between pages in "Long strip with gaps".
const double kLongStripPageGap = 16;
