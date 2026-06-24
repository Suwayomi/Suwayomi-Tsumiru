// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Web stub for [BackgroundDownloadController]. The real controller depends on
/// `dart:io` + `flutter_foreground_task` (native-only), which don't compile for
/// web. The conditional-import shim swaps this no-op in on web, so the
/// web-compiled call sites (`offline_download_providers.dart`, `main.dart`)
/// still build. Offline is disabled on web, so none of these are ever reached
/// at runtime there anyway.
class BackgroundDownloadController {
  BackgroundDownloadController(this._ref);

  // ignore: unused_field
  final Ref _ref;

  void register() {}
  void dispose() {}
  Future<void> ensureServiceRunning() async {}
  Future<void> onEnqueued(List<int> chapterIds) async {}
  Future<void> onRemoved(int chapterId) async {}
  Future<void> onWifiOnlyChanged(bool value) async {}
  Future<void> replayAtLaunchAndMaybeStart() async {}
}

/// Web no-op mirror of the native provider.
final backgroundDownloadControllerProvider =
    Provider<BackgroundDownloadController>(
        (ref) => BackgroundDownloadController(ref));

/// Web no-op: there is no foreground task service to initialise.
void initForegroundTaskService() {}
