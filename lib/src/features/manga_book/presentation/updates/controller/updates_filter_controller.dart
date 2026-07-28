// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../constants/db_keys.dart';
import '../../../../../utils/mixin/shared_preferences_client_mixin.dart';
import '../../../domain/updates/updates_filter.dart';

export '../../../domain/updates/updates_filter.dart';

part 'updates_filter_controller.g.dart';

@riverpod
class UpdatesFilterDownloaded extends _$UpdatesFilterDownloaded
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.updatesFilterDownloaded);
}

@riverpod
class UpdatesFilterUnread extends _$UpdatesFilterUnread
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.updatesFilterUnread);
}

@riverpod
class UpdatesFilterStarted extends _$UpdatesFilterStarted
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.updatesFilterStarted);
}

@riverpod
class UpdatesFilterBookmarked extends _$UpdatesFilterBookmarked
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.updatesFilterBookmarked);
}

@riverpod
UpdatesFilter updatesFilter(Ref ref) => (
      downloaded: ref.watch(updatesFilterDownloadedProvider),
      unread: ref.watch(updatesFilterUnreadProvider),
      started: ref.watch(updatesFilterStartedProvider),
      bookmarked: ref.watch(updatesFilterBookmarkedProvider),
    );

@riverpod
bool updatesHasActiveFilters(Ref ref) =>
    ref.watch(updatesFilterProvider) != kNoUpdatesFilter;
