// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:workmanager/workmanager.dart';

import 'notification_worker.dart';

const kNewChapterCheckTask = 'tsumiru.newChapterCheck';

// Manual checks need a separate unique-work name to avoid suppressing the periodic schedule.
const kNewChapterPeriodicName = 'tsumiru.newChapterCheck.periodic';
const kNewChapterCheckNowName = 'tsumiru.newChapterCheck.now';

// Follow-up work uses its own identity while waiting for server downloads, preserving periodic scheduling.
const kNewChapterFollowUpName = 'tsumiru.newChapterCheck.followup';

// WorkManager requires a top-level vm:entry-point callback in the new isolate.
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
