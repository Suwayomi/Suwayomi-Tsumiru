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

// Global long-strip prefs (Komikku parity). Smart-scale is wired on the
// non-infinity webtoon path; the infinity path's height-cache math is the
// frozen scroll boundary (see docs/architecture/reader.md).

@riverpod
class WebtoonScaleTypeKey extends _$WebtoonScaleTypeKey
    with SharedPreferenceEnumClientMixin<WebtoonScaleType> {
  @override
  WebtoonScaleType? build() =>
      initialize(DBKeys.webtoonScaleType, enumList: WebtoonScaleType.values);
}

@riverpod
class CropBordersWebtoon extends _$CropBordersWebtoon
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.cropBordersWebtoon);
}

/// Own key for "Long strip with gaps" (Komikku cropBordersContinuousVertical).
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
