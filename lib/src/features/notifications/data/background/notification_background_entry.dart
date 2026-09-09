// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:workmanager/workmanager.dart';

import 'notification_worker.dart';

/// WorkManager task name for the periodic new-chapter check.
const kNewChapterCheckTask = 'tsumiru.newChapterCheck';

/// Unique-work names. The manual "check now" uses a SEPARATE name from the
/// periodic job — enqueuing manual work under the periodic identity can replace
/// or suppress the schedule.
const kNewChapterPeriodicName = 'tsumiru.newChapterCheck.periodic';
const kNewChapterCheckNowName = 'tsumiru.newChapterCheck.now';

/// A short-fuse follow-up wake, scheduled when a run leaves chapters waiting on
/// the server's own download (the two-hop server-fetch). Its own unique name,
/// so it never replaces or suppresses the periodic schedule. Without it, the
/// second hop waits for the next 1-6h period — or, if the app is force-closed,
/// until the next launch — which is the "a chapter is regularly forgotten in
/// catch-up" symptom.
const kNewChapterFollowUpName = 'tsumiru.newChapterCheck.followup';

/// The isolate entry point registered with `Workmanager().initialize`. Must be a
/// top-level `vm:entry-point` function — the OS spawns a fresh isolate here.
@pragma('vm:entry-point')
void notificationCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    switch (task) {
      case kNewChapterCheckTask:
        return runNewChapterCheck();
      default:
        return true;
    }
  });
}
