// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../constants/db_keys.dart';
import '../../../../../constants/enum.dart';
import '../../../../../utils/mixin/shared_preferences_client_mixin.dart';

export '../../../../../constants/enum.dart' show UpdatesGroupingMode;

part 'updates_grouping_controller.g.dart';

@riverpod
class UpdatesGroupingModeNotifier extends _$UpdatesGroupingModeNotifier
    with SharedPreferenceEnumClientMixin<UpdatesGroupingMode> {
  @override
  UpdatesGroupingMode? build() => initialize(
        DBKeys.updatesGroupingMode,
        enumList: UpdatesGroupingMode.values,
        initial: UpdatesGroupingMode.disabled,
      );
}
