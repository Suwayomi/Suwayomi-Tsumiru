// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/misc/toast/toast.dart';
import '../controller/manga_track_records_controller.dart';
import '../data/tracker_repository.dart';
import 'tracking_settings_providers.dart';

/// Pure predicate — no Flutter / Riverpod deps, so it is trivially unit-testable.
///
/// Returns true when all of the following hold:
///   * [isRead] — the chapter was just marked read.
///   * [trackRecordCount] > 0 — at least one tracker is bound to the manga.
///   * The relevant toggle is on:
///       - auto path ([manual] == false) → [enabledAfterReading]
///       - manual-mark-read path ([manual] == true) → [enabledManualMarkRead]
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

/// Core: fires [TrackerRepository.trackProgress] when [shouldTrackProgress]
/// passes. Takes already-captured dependencies (no [WidgetRef]), so it is safe
/// to await even after the originating widget has disposed — the fire-and-forget
/// callers below capture everything from `ref` BEFORE their first await.
///
/// Errors are surfaced as a toast and swallowed so a tracker hiccup never
/// interrupts reading.
Future<void> _pushTrackProgressIfEnabled({
  required TrackerRepository repo,
  required Toast? toast,
  required int mangaId,
  required bool isRead,
  required bool manual,
  required bool enabledAfterReading,
  required bool enabledManualMarkRead,
  required int trackRecordCount,
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
  result.showToastOnError(toast, withMicrotask: true);
}

/// Wiring helper for call sites that already have the track-record count in
/// scope. Captures `ref` synchronously, then defers to the no-`ref` core.
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
    );

/// Convenience overload for call sites that don't have the track-record count
/// in scope (library / updates bulk mark-read). FETCHES the records — issuing a
/// network request if they aren't cached — because those screens mark chapters
/// read without the manga-details screen ever loading the records, so a
/// cache-only read would see zero bound trackers and wrongly skip the sync.
/// All `ref` reads happen up front (before any await) so it stays safe when
/// fired-and-forgotten as the originating widget disposes.
Future<void> maybeTrackProgressOnReadFetch(
  WidgetRef ref, {
  required int mangaId,
  required bool isRead,
  required bool manual,
}) async {
  final repo = ref.read(trackerRepositoryProvider);
  final toast = ref.read(toastProvider);
  final enabledAfterReading =
      ref.read(updateProgressAfterReadingProvider).ifNull();
  final enabledManualMarkRead =
      ref.read(updateProgressManualMarkReadProvider).ifNull();
  // Cheap gate BEFORE the records fetch: the reader calls this on every page
  // turn ([isRead] is false until the last page), so skip the network
  // round-trip entirely unless this is a read event with its toggle enabled.
  // The full gate (incl. trackRecordCount) still runs below once fetched.
  if (!isRead || !(manual ? enabledManualMarkRead : enabledAfterReading)) {
    return;
  }
  final recordsFuture =
      ref.read(mangaTrackRecordsProvider(mangaId: mangaId).future);

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
  );
}
