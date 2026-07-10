// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../constants/db_keys.dart';
import '../../../utils/mixin/shared_preferences_client_mixin.dart';

part 'offline_settings_providers.g.dart';

/// Server the offline catalog reflects; gates the offline fallback so a server
/// switch can't leak the previous server's downloads (#145).
@riverpod
class OfflineCatalogServerUrl extends _$OfflineCatalogServerUrl
    with SharedPreferenceClientMixin<String> {
  @override
  String? build() => initialize(DBKeys.offlineCatalogServerUrl);
}

@riverpod
class OfflineTimeEvictEnabled extends _$OfflineTimeEvictEnabled
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.offlineTimeEvictEnabled);
}

@riverpod
class OfflineKeepDays extends _$OfflineKeepDays
    with SharedPreferenceClientMixin<int> {
  @override
  int? build() => initialize(DBKeys.offlineKeepDays);
}

@riverpod
class OfflineStorageCapEnabled extends _$OfflineStorageCapEnabled
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.offlineStorageCapEnabled);
}

@riverpod
class OfflineStorageCapMb extends _$OfflineStorageCapMb
    with SharedPreferenceClientMixin<int> {
  @override
  int? build() => initialize(DBKeys.offlineStorageCapMb);
}

/// Pages downloaded at once across all chapters. Kept low by default so a
/// self-hosted server isn't saturated (it starts returning 500/503 under
/// heavy parallelism). User-adjustable; applied live to the download queue.
@riverpod
class OfflineDownloadConcurrency extends _$OfflineDownloadConcurrency
    with SharedPreferenceClientMixin<int> {
  @override
  int? build() => initialize(DBKeys.offlineDownloadConcurrency);
}

@riverpod
class OfflineWifiOnly extends _$OfflineWifiOnly
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.downloadOnlyOverWifi);
}

/// User-initiated pause of all on-device downloads (persisted). The UI watches
/// this for the Pause/Resume control + the global paused badge; the download
/// starters gate on the persisted value directly (see [DBKeys.offlineDownloadsPaused]).
@riverpod
class OfflineDownloadsPaused extends _$OfflineDownloadsPaused
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.offlineDownloadsPaused);
}
