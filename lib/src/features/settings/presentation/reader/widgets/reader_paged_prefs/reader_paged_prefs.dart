// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../../constants/db_keys.dart';
import '../../../../../../constants/enum.dart';
import '../../../../../../utils/mixin/shared_preferences_client_mixin.dart';

part 'reader_paged_prefs.g.dart';

// Global paged-viewer prefs (Komikku parity — kept in ReaderPreferences, never
// per-series). Consumed by the paged viewer.

@riverpod
class ImageScaleTypeKey extends _$ImageScaleTypeKey
    with SharedPreferenceEnumClientMixin<ImageScaleType> {
  @override
  ImageScaleType? build() =>
      initialize(DBKeys.imageScaleType, enumList: ImageScaleType.values);
}

@riverpod
class ZoomStartKey extends _$ZoomStartKey
    with SharedPreferenceEnumClientMixin<ZoomStart> {
  @override
  ZoomStart? build() =>
      initialize(DBKeys.zoomStart, enumList: ZoomStart.values);
}

@riverpod
class PageLayoutKey extends _$PageLayoutKey
    with SharedPreferenceEnumClientMixin<PageLayout> {
  @override
  PageLayout? build() =>
      initialize(DBKeys.pageLayout, enumList: PageLayout.values);
}

@riverpod
class CenterMarginTypeKey extends _$CenterMarginTypeKey
    with SharedPreferenceEnumClientMixin<CenterMarginType> {
  @override
  CenterMarginType? build() =>
      initialize(DBKeys.centerMarginType, enumList: CenterMarginType.values);
}

@riverpod
class LandscapeZoom extends _$LandscapeZoom
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.landscapeZoom);
}

@riverpod
class NavigateToPan extends _$NavigateToPan
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.navigateToPan);
}

@riverpod
class InvertDoublePages extends _$InvertDoublePages
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.invertDoublePages);
}

@riverpod
class CropBorders extends _$CropBorders with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.cropBorders);
}

// Shared with the long-strip section (one key for both, like Komikku).

@riverpod
class SmallerTapZones extends _$SmallerTapZones
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.smallerTapZones);
}

@riverpod
class AnimatePageTransitions extends _$AnimatePageTransitions
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.animatePageTransitions);
}

// Wide-page handling — consumed by the paged viewer's spread mapping
// (double-page / split / true-dual-spread) and per-image rotate.

@riverpod
class DualPageSplitPaged extends _$DualPageSplitPaged
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.dualPageSplitPaged);
}

@riverpod
class DualPageInvertPaged extends _$DualPageInvertPaged
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.dualPageInvertPaged);
}

@riverpod
class RotateWidePages extends _$RotateWidePages
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.rotateWidePages);
}

@riverpod
class RotateWideInvert extends _$RotateWideInvert
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.rotateWideInvert);
}

@riverpod
class TrueDualPageSpread extends _$TrueDualPageSpread
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.trueDualPageSpread);
}
