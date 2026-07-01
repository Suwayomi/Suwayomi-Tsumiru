// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../../constants/db_keys.dart';
import '../../../../../../utils/mixin/shared_preferences_client_mixin.dart';

part 'reader_auto_webtoon_mode.g.dart';

// Global Auto Webtoon Mode pref (Komikku parity, default ON). Detection lives
// in manga_book/presentation/reader/controller/auto_webtoon.dart.

@riverpod
class AutoWebtoonMode extends _$AutoWebtoonMode
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.autoWebtoonMode);
}
