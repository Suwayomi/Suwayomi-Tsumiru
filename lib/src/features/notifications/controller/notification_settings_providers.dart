// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../constants/db_keys.dart';
import '../../../utils/mixin/shared_preferences_client_mixin.dart';

part 'notification_settings_providers.g.dart';

@riverpod
class NotificationsNewChaptersEnabled extends _$NotificationsNewChaptersEnabled
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.notificationsNewChaptersEnabled);
}

@riverpod
class NotificationsDownloadsEnabled extends _$NotificationsDownloadsEnabled
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.notificationsDownloadsEnabled);
}

@riverpod
class NotificationsCheckIntervalHours extends _$NotificationsCheckIntervalHours
    with SharedPreferenceClientMixin<int> {
  @override
  int? build() => initialize(DBKeys.notificationsCheckIntervalHours);
}

@riverpod
class NotificationsWifiOnly extends _$NotificationsWifiOnly
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.notificationsWifiOnly);
}

@riverpod
class NotificationsChargingOnly extends _$NotificationsChargingOnly
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.notificationsChargingOnly);
}

@riverpod
class NotificationsHideContent extends _$NotificationsHideContent
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.notificationsHideContent);
}

@riverpod
class NotificationsCategoriesInclude extends _$NotificationsCategoriesInclude
    with SharedPreferenceClientMixin<List<String>> {
  @override
  List<String>? build() => initialize(DBKeys.notificationsCategoriesInclude);
}

@riverpod
class NotificationsCategoriesExclude extends _$NotificationsCategoriesExclude
    with SharedPreferenceClientMixin<List<String>> {
  @override
  List<String>? build() => initialize(DBKeys.notificationsCategoriesExclude);
}

@riverpod
class NotificationsAppUpdatesEnabled extends _$NotificationsAppUpdatesEnabled
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.notificationsAppUpdatesEnabled);
}

@riverpod
class NotificationsExtensionUpdatesEnabled
    extends _$NotificationsExtensionUpdatesEnabled
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.notificationsExtensionUpdatesEnabled);
}
