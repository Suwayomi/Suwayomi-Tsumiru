// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../global_providers/global_providers.dart';
import '../../../notifications/controller/notifications_controller.dart';
import 'catchup_spec_writer.dart';
import 'catchup_work_spec.dart';

// Notification and catch-up demand share one WorkManager schedule.
final backgroundCatchupEnabledProvider =
    NotifierProvider<BackgroundCatchupEnabled, bool>(
        BackgroundCatchupEnabled.new);

class BackgroundCatchupEnabled extends Notifier<bool> {
  @override
  bool build() =>
      CatchupStateStore(ref.read(sharedPreferencesProvider)).enabled;

  Future<void> setEnabled(bool value) async {
    await CatchupStateStore(ref.read(sharedPreferencesProvider))
        .setEnabled(value);
    state = value;
    await ref.read(notificationsControllerProvider).sync();
    if (value) await writeCatchupWorkSpec(ref.read);
  }
}

// Detection stays scheduled when file fetching is disabled; no reschedule is needed.
final backgroundCatchupDownloadEnabledProvider =
    NotifierProvider<BackgroundCatchupDownloadEnabled, bool>(
        BackgroundCatchupDownloadEnabled.new);

class BackgroundCatchupDownloadEnabled extends Notifier<bool> {
  @override
  bool build() =>
      CatchupStateStore(ref.read(sharedPreferencesProvider)).downloadEnabled;

  Future<void> setEnabled(bool value) async {
    await CatchupStateStore(ref.read(sharedPreferencesProvider))
        .setDownloadEnabled(value);
    state = value;
  }
}
