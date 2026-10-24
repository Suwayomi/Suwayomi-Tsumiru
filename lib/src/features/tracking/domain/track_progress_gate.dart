// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/misc/toast/toast.dart';
import '../../../utils/network/graphql_errors.dart';
import '../../offline/data/offline_repository.dart';
import '../controller/manga_track_records_controller.dart';
import '../data/tracker_repository.dart';
import 'tracking_settings_providers.dart';

typedef TrackRead = T Function<T>(ProviderListenable<T> provider);

bool shouldTrackProgress({
  required bool isRead,
  required bool enabledAfterReading,
  required bool enabledManualMarkRead,
  required bool manual,
  required int trackRecordCount,
}) =>
    isRead &&
    trackRecordCount > 0 &&
    (manual ? enabledManualMarkRead : enabledAfterReading);

// Capture dependencies before awaiting so tracking can finish after widget disposal.
Future<void> _pushTrackProgressIfEnabled({
  required TrackerRepository repo,
  required Toast? toast,
  required int mangaId,
  required bool isRead,
  required bool manual,
  required bool enabledAfterReading,
  required bool enabledManualMarkRead,
  required int trackRecordCount,
  bool offlineCaptureActive = false,
}) async {
  if (!shouldTrackProgress(
    isRead: isRead,
    enabledAfterReading: enabledAfterReading,
    enabledManualMarkRead: enabledManualMarkRead,
    manual: manual,
    trackRecordCount: trackRecordCount,
  )) {
    return;
  }
  final result = await AsyncValue.guard(() => repo.trackProgress(mangaId));
  // Offline reconnect re-sends tracker progress, so connection failures need no toast.
  if (result.hasError && offlineCaptureActive) {
    final e = result.error!;
    final cause = e is OperationMessageException ? e.exception : e;
    if (isConnectionError(cause)) return;
  }
  result.showToastOnError(toast, withMicrotask: true);
}

/// Captures ref dependencies synchronously; errors toast without interrupting reading.
Future<void> maybeTrackProgressOnRead(
  WidgetRef ref, {
  required int mangaId,
  required bool isRead,
  required bool manual,
  required int trackRecordCount,
}) =>
    _pushTrackProgressIfEnabled(
      repo: ref.read(trackerRepositoryProvider),
      toast: ref.read(toastProvider),
      enabledAfterReading:
          ref.read(updateProgressAfterReadingProvider).ifNull(),
      enabledManualMarkRead:
          ref.read(updateProgressManualMarkReadProvider).ifNull(),
      mangaId: mangaId,
      isRead: isRead,
      manual: manual,
      trackRecordCount: trackRecordCount,
      offlineCaptureActive: ref.read(offlineActiveProvider),
    );

/// Fetches uncached records so bulk mark-read can find bound trackers.
/// Pass ProviderContainer.read if the caller may have unmounted before invoking this.
/// All reads happen before awaiting; tracker errors toast without interrupting reading.
Future<void> maybeTrackProgressOnReadFetch(
  TrackRead read, {
  required int mangaId,
  required bool isRead,
  required bool manual,
}) async {
  final repo = read(trackerRepositoryProvider);
  final toast = read(toastProvider);
  final offlineCaptureActive = read(offlineActiveProvider);
  final enabledAfterReading =
      read(updateProgressAfterReadingProvider).ifNull();
  final enabledManualMarkRead =
      read(updateProgressManualMarkReadProvider).ifNull();
  // Gate before fetching records to avoid a network request on every reader page turn.
  if (!isRead || !(manual ? enabledManualMarkRead : enabledAfterReading)) {
    return;
  }
  final recordsFuture =
      read(mangaTrackRecordsProvider(mangaId: mangaId).future);

  final records = await AsyncValue.guard(() => recordsFuture);
  await _pushTrackProgressIfEnabled(
    repo: repo,
    toast: toast,
    enabledAfterReading: enabledAfterReading,
    enabledManualMarkRead: enabledManualMarkRead,
    mangaId: mangaId,
    isRead: isRead,
    manual: manual,
    trackRecordCount: records.value?.length ?? 0,
    offlineCaptureActive: offlineCaptureActive,
  );
}
