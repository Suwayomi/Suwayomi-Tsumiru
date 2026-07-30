// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../../constants/db_keys.dart';
import '../../../../../../constants/enum.dart';
import '../../../../../../utils/mixin/shared_preferences_client_mixin.dart';

part 'reader_webtoon_prefs.g.dart';

// Global long-strip prefs, consumed by the long-strip renderer
// (multichapter_continuous_reader_mode.dart). The frozen boundary there is the
// scroll/position/index math, not these render knobs (docs/architecture/reader.md).

@riverpod
class WebtoonScaleTypeKey extends _$WebtoonScaleTypeKey
    with SharedPreferenceEnumClientMixin<WebtoonScaleType> {
  @override
  WebtoonScaleType? build() =>
      initialize(DBKeys.webtoonScaleType, enumList: WebtoonScaleType.values);
}

@riverpod
class LongStripWidthLimitUsePixels extends _$LongStripWidthLimitUsePixels
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.longStripWidthLimitUsePixels);
}

@riverpod
class LongStripWidthLimitPercent extends _$LongStripWidthLimitPercent
    with SharedPreferenceClientMixin<int> {
  @override
  int? build() => initialize(DBKeys.longStripWidthLimitPercent);
}

@riverpod
class LongStripWidthLimitPx extends _$LongStripWidthLimitPx
    with SharedPreferenceClientMixin<int> {
  @override
  int? build() => initialize(DBKeys.longStripWidthLimitPx);
}

@riverpod
class CropBordersWebtoon extends _$CropBordersWebtoon
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.cropBordersWebtoon);
}

/// Own key for "Long strip with gaps".
@riverpod
class CropBordersGaps extends _$CropBordersGaps
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.cropBordersGaps);
}

@riverpod
class SmoothAutoScroll extends _$SmoothAutoScroll
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.smoothAutoScroll);
}

@riverpod
class ReaderScrollAmountKey extends _$ReaderScrollAmountKey
    with SharedPreferenceEnumClientMixin<ReaderScrollAmount> {
  @override
  ReaderScrollAmount? build() => initialize(
        DBKeys.readerScrollAmount,
        enumList: ReaderScrollAmount.values,
      );
}

@riverpod
class AutoScrollIntervalSeconds extends _$AutoScrollIntervalSeconds
    with SharedPreferenceClientMixin<int> {
  @override
  int? build() => initialize(DBKeys.autoScrollIntervalSeconds);
}

@riverpod
class AutoAdvanceIntervalSeconds extends _$AutoAdvanceIntervalSeconds
    with SharedPreferenceClientMixin<int> {
  @override
  int? build() => initialize(DBKeys.autoAdvanceIntervalSeconds);
}

// Webtoon wide-page split (+invert): persists for a later engine PR — the
// frozen webtoon engine can't remap 1 page → 2 entries yet.

@riverpod
class DualPageSplitWebtoon extends _$DualPageSplitWebtoon
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.dualPageSplitWebtoon);
}

@riverpod
class DualPageInvertWebtoon extends _$DualPageInvertWebtoon
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.dualPageInvertWebtoon);
}
