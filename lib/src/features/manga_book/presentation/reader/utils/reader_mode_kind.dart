// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../constants/enum.dart';
import '../../../../settings/presentation/reader/widgets/reader_navigation_layout_tile/reader_navigation_layout_tile.dart';
import '../../../../settings/presentation/reader/widgets/reader_tap_invert/reader_tap_invert.dart';

/// Whether a reading mode is paged (page-flip) rather than continuous/webtoon
/// scroll. Single source of truth for the gesture routing and the bottom
/// controls, which must agree on what counts as "paged".
bool isPagedReaderMode(ReaderMode mode) => switch (mode) {
      ReaderMode.singleHorizontalLTR ||
      ReaderMode.singleHorizontalRTL ||
      ReaderMode.singleVertical =>
        true,
      ReaderMode.defaultReader ||
      ReaderMode.continuousVertical ||
      ReaderMode.webtoon ||
      ReaderMode.continuousHorizontalLTR ||
      ReaderMode.continuousHorizontalRTL =>
        false,
    };

/// Whether a mode reads right-to-left. Lives here so the page-transition
/// direction and the spatial tap zones can't drift apart.
bool isRTLReaderMode(ReaderMode mode) => switch (mode) {
      ReaderMode.singleHorizontalRTL ||
      ReaderMode.continuousHorizontalRTL =>
        true,
      ReaderMode.singleHorizontalLTR ||
      ReaderMode.continuousHorizontalLTR ||
      ReaderMode.singleVertical ||
      ReaderMode.continuousVertical ||
      ReaderMode.webtoon ||
      ReaderMode.defaultReader =>
        false,
    };

/// What the "Default" tap-zone setting resolves to for a given mode.
/// Komikku (`PagerConfig.defaultNavigation`): right-and-left for horizontal
/// paged, L-shaped for everything else.
ReaderNavigationLayout defaultNavigationFor(ReaderMode mode) => switch (mode) {
      ReaderMode.singleHorizontalLTR ||
      ReaderMode.singleHorizontalRTL ||
      ReaderMode.continuousHorizontalLTR ||
      ReaderMode.continuousHorizontalRTL =>
        ReaderNavigationLayout.rightAndLeft,
      ReaderMode.singleVertical ||
      ReaderMode.continuousVertical ||
      ReaderMode.webtoon ||
      ReaderMode.defaultReader =>
        ReaderNavigationLayout.lShaped,
    };

/// The tap-zone layout actually in force: the series' own choice if it made
/// one, else that viewer's setting, with Default resolved to a real layout.
/// Reader, settings sheet, and chapter separator all go through this so
/// they can't disagree about whether zones are on.
ReaderNavigationLayout effectiveNavigationLayout(
  WidgetRef ref, {
  required ReaderMode mode,
  ReaderNavigationLayout? seriesOverride,
}) {
  var layout = seriesOverride ?? ReaderNavigationLayout.defaultNavigation;
  if (layout == ReaderNavigationLayout.defaultNavigation) {
    layout = (isPagedReaderMode(mode)
            ? ref.watch(pagedNavigationLayoutKeyProvider)
            : ref.watch(longStripNavigationLayoutKeyProvider)) ??
        ReaderNavigationLayout.defaultNavigation;
  }
  return layout == ReaderNavigationLayout.defaultNavigation
      ? defaultNavigationFor(mode)
      : layout;
}

/// Tap inversion in force for [mode], including the right-to-left mirror that
/// only the spatial Right-and-Left layout needs.
TapInvert effectiveTapInvert(
  WidgetRef ref, {
  required ReaderMode mode,
  required ReaderNavigationLayout layout,
  TapInvert? seriesOverride,
}) {
  final invert = seriesOverride ??
      (isPagedReaderMode(mode)
          ? ref.watch(pagedTapInvertKeyProvider)
          : ref.watch(longStripTapInvertKeyProvider)) ??
      TapInvert.none;
  return layout == ReaderNavigationLayout.rightAndLeft && isRTLReaderMode(mode)
      ? invert.horizontallyFlipped
      : invert;
}
