// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../../constants/db_keys.dart';
import '../../../../../../constants/enum.dart';
import '../../../../../../utils/mixin/shared_preferences_client_mixin.dart';
import '../reader_invert_tap_tile/reader_invert_tap_tile.dart';

part 'reader_tap_invert.g.dart';

/// Null leaves the legacy bool authoritative until this preference is set.
@riverpod
class ReaderTapInvertKey extends _$ReaderTapInvertKey
    with SharedPreferenceEnumClientMixin<TapInvert> {
  @override
  TapInvert? build() =>
      initialize(DBKeys.readerTapInvert, enumList: TapInvert.values);
}

/// Reads the new key, falling back to the read-only legacy bool (true means both axes).
@riverpod
TapInvert readerTapInvertCompat(Ref ref) =>
    ref.watch(readerTapInvertKeyProvider) ??
    TapInvert.fromLegacyInvert(ref.watch(invertTapProvider));

// Seed both viewers from the resolved global preference.

@riverpod
class PagedTapInvertKey extends _$PagedTapInvertKey
    with SharedPreferenceEnumClientMixin<TapInvert> {
  @override
  TapInvert? build() => initialize(
        DBKeys.pagedTapInvert,
        enumList: TapInvert.values,
        initial: ref.read(readerTapInvertCompatProvider),
      );
}

@riverpod
class LongStripTapInvertKey extends _$LongStripTapInvertKey
    with SharedPreferenceEnumClientMixin<TapInvert> {
  @override
  TapInvert? build() => initialize(
        DBKeys.longStripTapInvert,
        enumList: TapInvert.values,
        initial: ref.read(readerTapInvertCompatProvider),
      );
}
