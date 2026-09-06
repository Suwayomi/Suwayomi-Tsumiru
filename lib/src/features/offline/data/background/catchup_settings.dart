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

/// "Download new chapters in the background" — backs the settings toggle and
/// reconciles the shared WorkManager schedule (the job runs when notifications
/// OR this are on) plus the worker's planning snapshot.
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
    // Seed the worker's config + token and (re)schedule or cancel the job —
    // sync() owns that arbitration for both features.
    await ref.read(notificationsControllerProvider).sync();
    if (value) await writeCatchupWorkSpec(ref.read);
  }
}

/// Sub-option of [backgroundCatchupEnabledProvider]: whether the background
/// run also fetches chapter files, or only detects/queues them and leaves the
/// actual download for the next time the app is opened. Doesn't change the
/// WorkManager schedule itself — the same job keeps running for detection —
/// so no sync()/reschedule is needed here, unlike the parent toggle.
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
