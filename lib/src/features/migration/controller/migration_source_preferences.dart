// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../constants/db_keys.dart';
import '../../../constants/enum.dart';
import '../../../utils/mixin/shared_preferences_client_mixin.dart';

final migrationSourceSortProvider =
    NotifierProvider<MigrationSourceSortPref, MigrationSourceSort?>(
      MigrationSourceSortPref.new,
    );

class MigrationSourceSortPref extends Notifier<MigrationSourceSort?>
    with SharedPreferenceEnumClientMixin<MigrationSourceSort> {
  @override
  MigrationSourceSort? build() => initialize(
    DBKeys.migrationSourceSort,
    enumList: MigrationSourceSort.values,
  );
}

final migrationSourceAscendingProvider =
    NotifierProvider<MigrationSourceAscendingPref, bool?>(
      MigrationSourceAscendingPref.new,
    );

class MigrationSourceAscendingPref extends Notifier<bool?>
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.migrationSourceAscending);
}

final migrationSourceObsoleteOnlyProvider =
    NotifierProvider<MigrationSourceObsoleteOnlyPref, bool?>(
      MigrationSourceObsoleteOnlyPref.new,
    );

class MigrationSourceObsoleteOnlyPref extends Notifier<bool?>
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.migrationSourceObsoleteOnly);
}
