// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'offline_download_providers.dart';
import 'offline_download_stall.dart';
import 'offline_settings_providers.dart';

part 'offline_nav_status.g.dart';

@riverpod
bool downloadsPausedBadge(Ref ref) {
  final paused = ref.watch(offlineDownloadsPausedProvider) ?? false;
  if (!paused && ref.watch(effectiveDownloadStallProvider) == null) {
    return false;
  }
  return ref.watch(offlineHasPendingProvider).value ?? false;
}
