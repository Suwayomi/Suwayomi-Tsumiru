// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../../constants/db_keys.dart';
import '../../../../../../constants/enum.dart';
import '../../../../../../utils/mixin/shared_preferences_client_mixin.dart';
import '../reader_invert_tap_tile/reader_invert_tap_tile.dart';

part 'reader_tap_invert.g.dart';

/// New 4-value tap-invert key. Null while unset, so the legacy bool below
/// stays authoritative for users who never touched the new control.
@riverpod
class ReaderTapInvertKey extends _$ReaderTapInvertKey
    with SharedPreferenceEnumClientMixin<TapInvert> {
  @override
  TapInvert? build() =>
      initialize(DBKeys.readerTapInvert, enumList: TapInvert.values);
}

/// Effective global tap-invert: the new key when set, else the legacy
/// invertTap bool (true→both). The old key is compat-read only, never written.
@riverpod
TapInvert readerTapInvertCompat(Ref ref) =>
    ref.watch(readerTapInvertKeyProvider) ??
    TapInvert.fromLegacyInvert(ref.watch(invertTapProvider));
