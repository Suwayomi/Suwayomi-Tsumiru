// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../../constants/db_keys.dart';
import '../../../../../../constants/enum.dart';
import '../../../../../../utils/mixin/shared_preferences_client_mixin.dart';

part 'reader_orientation.g.dart';

@riverpod
class ReaderOrientationKey extends _$ReaderOrientationKey
    with SharedPreferenceEnumClientMixin<ReaderOrientation> {
  @override
  ReaderOrientation? build() => initialize(
        DBKeys.readerOrientation,
        enumList: ReaderOrientation.values,
      );
}

extension ReaderOrientationLock on ReaderOrientation {
  /// Orientations to lock the reader to; null = Default, leave the app alone.
  List<DeviceOrientation>? get deviceOrientations => switch (this) {
        ReaderOrientation.defaultRotation => null,
        ReaderOrientation.free => DeviceOrientation.values,
        ReaderOrientation.portrait => const [
            DeviceOrientation.portraitUp,
            DeviceOrientation.portraitDown,
          ],
        ReaderOrientation.landscape => const [
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ],
        ReaderOrientation.lockedPortrait => const [
            DeviceOrientation.portraitUp
          ],
        ReaderOrientation.lockedLandscape => const [
            DeviceOrientation.landscapeLeft
          ],
        ReaderOrientation.reversePortrait => const [
            DeviceOrientation.portraitDown
          ],
      };
}
