// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../constants/db_keys.dart';
import '../../../constants/endpoints.dart';
import '../../../constants/enum.dart';
import '../../../global_providers/global_providers.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/logger/logger.dart';
import '../../../utils/misc/toast/toast.dart';
import '../../../utils/platform/is_android_native.dart';
import '../../auth/data/auth_credentials_store.dart';
import '../../manga_book/data/downloads/downloads_repository.dart';
import '../../manga_book/data/manga_book/manga_book_repository.dart';
import '../../manga_book/domain/chapter_batch/chapter_batch_model.dart';
import '../../manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import '../../manga_book/presentation/manga_details/controller/scanlator_propagation.dart';
import '../../settings/presentation/downloads/data/delete_chapters_settings_repository.dart';
import '../../settings/presentation/server/widget/client/server_port_tile/server_port_tile.dart';
import '../../settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';
import '../../settings/presentation/server/widget/credential_popup/credentials_popup.dart';
import '../../tracking/controller/manga_track_records_controller.dart';
import '../../tracking/data/tracker_repository.dart';
import '../../tracking/domain/track_progress_gate.dart';
import '../../tracking/domain/tracking_settings_providers.dart';
import 'background/background_download_controller_shim.dart';
import 'chapter_download_engine.dart';
import 'offline_background_downloads.dart';
import 'offline_database.dart';
import 'offline_download_coordinator.dart';
import 'offline_download_manager.dart';
import 'offline_page_store.dart';
import 'offline_reconciler.dart';
import 'offline_repository.dart';
import 'offline_series_entry.dart';
import 'offline_settings_providers.dart';
import 'offline_types.dart';
import 'reconcile_types.dart';

part 'offline_download_providers.g.dart';

/// True only on Android native, where the foreground-service worker owns
/// downloads (web-safe + correct in unit tests — see [isAndroidNative]).
bool get _useBgService => isAndroidNative;

/// THE single entry point that kicks off downloading after chapters are
/// queued into drift — starts the FGS worker on Android, else drains via the
/// main-isolate pump. Centralised (and overridable in tests) so no trigger can
/// ever again silently rely on the Android-disabled pump.
final downloadStarterProvider = Provider<Future<void> Function()>((Ref ref) {
  return () async {
    if (!ref.read(offlineActiveProvider)) return;
    if (isAndroidNative) {
      await ref
          .read(backgroundDownloadControllerProvider)
          .ensureServiceRunning();
    } else {
      await ref.read(offlineDownloadCoordinatorProvider)?.pumpDownloads();
    }
  };
});

/// Pause or resume ALL on-device downloads. Persists the flag (survives a
/// restart) and acts immediately on the active pipeline (FGS on Android,
/// main-isolate pump elsewhere) — the persisted flag is what every download
/// starter gates on, so no path can restart downloads while paused.
Future<void> setOfflineDownloadsPaused(WidgetRef ref, bool paused) async {
  ref.read(offlineDownloadsPausedProvider.notifier).update(paused);
  if (isAndroidNative) {
    final controller = ref.read(backgroundDownloadControllerProvider);
    if (paused) {
      await controller.pause();
    } else {
      await controller.resume();
    }
  } else {
    final coordinator = ref.read(offlineDownloadCoordinatorProvider);
    if (paused) {
      coordinator?.pause();
    } else {
      coordinator?.resume();
    }
  }
}

Future<void> clearOfflineCatalog(WidgetRef ref) async {
  if (!ref.read(offlineEnabledProvider)) return;

  final background = ref.read(backgroundDownloadControllerProvider);
  await clearOfflineCatalogWithDependencies(
    stopBackground: background.stopAndClearWorkOrder,
    stopMainPump: () async {
      final coordinator = ref.read(offlineDownloadCoordinatorProvider);
      coordinator?.pause();
      // Wait for the in-flight chapter to observe the cancel and unwind, so no
      // page write lands after the wipe below.
      await coordinator?.awaitIdle();
    },
    clearDatabase: ref.read(offlineDatabaseProvider).clearAll,
    // Best-effort: a file-delete failure (locked file, permissions) must not
    // abort the clear before the identity stamp resets — the DB is already
    // wiped, so leftover bytes are just dead weight, not stale content.
    clearFiles: () async {
      try {
        await ref.read(offlinePageStoreProvider).clearAll();
      } catch (e) {
        logger.e('Offline: clearing downloaded files failed: $e');
      }
    },
    clearIdentity: () async {
      final preferences = ref.read(sharedPreferencesProvider);
      await preferences.remove(DBKeys.offlineCatalogServerId.name);
      await preferences.remove(DBKeys.offlineServerMismatchDismissedList.name);
    },
    finish: background.finishCatalogClear,
  );
  ref.invalidate(offlineActiveProvider);
  ref.invalidate(offlineReadDatabaseProvider);
}

Future<void> clearOfflineCatalogWithDependencies({
  required Future<void> Function() stopBackground,
  required Future<void> Function() stopMainPump,
  required Future<void> Function() clearDatabase,
  required Future<void> Function() clearFiles,
  required Future<void> Function() clearIdentity,
  required void Function() finish,
}) async {
  // stopBackground sets the restart-suppression flag; keep it inside the try
  // so finish() always clears it, or a leaked flag would silently drop every
  // background-worker event for the rest of the session.
  try {
    await stopBackground();
    await stopMainPump();
    await clearDatabase();
    await clearFiles();
    await clearIdentity();
  } finally {
    finish();
  }
}

/// True while any chapter is queued or downloading on this device — drives the
/// On-device Pause/Resume control and the global paused badge. False when
/// offline is unavailable.
@riverpod
Stream<bool> offlineHasPending(Ref ref) {
  if (!ref.watch(offlineActiveProvider)) return Stream.value(false);
  return ref.watch(offlineDatabaseProvider).watchOfflineChapters().map(
        (chapters) => chapters.any((c) =>
            c.deviceState == OfflineDeviceState.queued ||
            c.deviceState == OfflineDeviceState.downloading),
      );
}

/// Live on-device download state for a chapter (none / queued / downloading /
/// downloaded / error). Always `none` when offline is unavailable.
@riverpod
Stream<OfflineDeviceState> offlineChapterState(Ref ref, int chapterId) {
  if (!ref.watch(offlineActiveProvider)) {
    return Stream.value(OfflineDeviceState.none);
  }
  return ref.watch(offlineRepositoryProvider).watchChapterState(chapterId);
}

/// Live download progress for a chapter as a fraction 0..1 (pages on disk /
/// total pages), or null when the total isn't known yet — drives the
/// determinate progress arc on a downloading chapter.
@riverpod
Stream<double?> offlineChapterProgress(Ref ref, int chapterId) {
  if (!ref.watch(offlineActiveProvider)) {
    return Stream.value(null);
  }
  final repo = ref.watch(offlineRepositoryProvider);
  // Re-read the page total on every tick (not once up front) so the arc flips
  // from indeterminate to real the moment it's known — webtoon chapters only
  // learn their count once the downloader resolves pages mid-download.
  return repo.watchChapterDownloadedPages(chapterId).asyncMap((done) async {
    final total = (await repo.db.chapterById(chapterId))?.pageCount ?? 0;
    return total <= 0 ? null : (done / total).clamp(0.0, 1.0);
  }).distinct();
}

/// Save a chapter's pages to the device from the synced catalog row; no-op if
/// offline is unavailable or the chapter hasn't been synced yet. Manual save
/// is sticky (pinned) — if not yet server-downloaded, enqueues a server
/// download first, then pulls immediately so the device copy is available as
/// soon as the server's own fetch completes.
Future<void> saveChapterToDevice(WidgetRef ref, int chapterId) async {
  final coordinator = ref.read(offlineDownloadCoordinatorProvider);
  if (coordinator == null) return;
  final repo = ref.read(offlineRepositoryProvider);
  final chapter = await repo.chapterById(chapterId);
  if (chapter == null) return;
  // Manual save is sticky.
  await ref.read(offlineDatabaseProvider).setChapterPinned(chapterId, true);
  // Ensure the SERVER also has the chapter (device ⊆ server): the cached
  // `serverIsDownloaded` flag can be stale (not reset on delete), so verify
  // against the server before trusting it — a failed/offline check falls back
  // to the cached value.
  var serverHasIt = chapter.serverIsDownloaded;
  if (serverHasIt) {
    final fresh = await AsyncValue.guard(() =>
        ref.read(mangaBookRepositoryProvider).getChapter(chapterId: chapterId));
    serverHasIt = fresh.value?.isDownloaded ?? serverHasIt;
  }
  if (!serverHasIt) {
    // Commit a server download too (grows the server library). The device copy
    // doesn't wait on it — the server streams pages from source meanwhile.
    await ref
        .read(downloadsRepositoryProvider)
        .addChaptersBatchToDownloadQueue([chapterId]);
  }
  // Queue it (drift `queued` is the single source of truth). On Android the
  // foreground-service worker owns the downloading; elsewhere the main-isolate
  // pump drains it.
  await coordinator.queueChapter(chapterId);
  await ref.read(downloadStarterProvider)();
}

/// Record reading progress for a chapter. Persists it to the on-device catalog
/// FIRST (so it survives offline + app restart — the bug where progress was
/// lost reading offline), then pushes to the server; on a successful push the
/// dirty flag is cleared, otherwise it stays pending for the next online sync.
Future<AsyncValue<void>> recordReadingProgress(
  WidgetRef ref, {
  required int mangaId,
  required int chapterId,
  required int lastPageRead,
  required bool isRead,
}) async {
  final offline = ref.read(offlineActiveProvider);
  final result = await recordReadingProgressWithDependencies(
    offlineEnabled: offline,
    offlineDatabase: offline ? ref.read(offlineDatabaseProvider) : null,
    repository: ref.read(mangaBookRepositoryProvider),
    chapterId: chapterId,
    lastPageRead: lastPageRead,
    isRead: isRead,
  );
  // Completing a chapter also marks its hidden scanlator duplicates read, or
  // they'd corrupt counts and resume on other clients.
  if (isRead && !result.hasError) {
    final siblings = expandIdsAcrossScanlators(ref,
        mangaId: mangaId, chapterIds: [chapterId])
      ..remove(chapterId);
    if (siblings.isNotEmpty) {
      final siblingsOk = await recordReadStateWithDependencies(
        offlineEnabled: offline,
        offlineDatabase: offline ? ref.read(offlineDatabaseProvider) : null,
        repository: ref.read(mangaBookRepositoryProvider),
        chapterIds: siblings,
        isRead: true,
        // Match the bulk mark-read action: siblings drop stale progress too.
        resetPosition: true,
      );
      // No retry state for a failed sibling write — surface it rather than
      // reporting the read as fully recorded.
      if (!siblingsOk) {
        return AsyncValue.error(
          Exception('marking duplicate copies read failed'),
          StackTrace.current,
        );
      }
    }
  }
  return result;
}

/// Returns the server-push outcome so callers aren't blind to a failed write.
/// For an online-only user there's no pending row to retry, so a swallowed
/// error means the progress is lost silently — the reader surfaces this.
Future<AsyncValue<void>> recordReadingProgressWithDependencies({
  required bool offlineEnabled,
  required OfflineDatabase? offlineDatabase,
  required MangaBookRepository repository,
  required int chapterId,
  required int lastPageRead,
  required bool isRead,
}) async {
  // Reading forward never un-reads: partial writes record position only (isRead
  // omitted); only completion marks read. Mark-unread is a separate path.
  final bool? markRead = isRead ? true : null;
  final db = offlineDatabase;
  if (offlineEnabled && db != null) {
    await db.setChapterProgress(
      chapterId,
      lastPageRead: lastPageRead,
      isRead: markRead,
    );
  }
  final result = await AsyncValue.guard(
    () => repository.putChapter(
      chapterId: chapterId,
      // Omit isRead (not null) when partial so the server keeps its read-state.
      patch: markRead == null
          ? ChapterChange(lastPageRead: lastPageRead)
          : ChapterChange(lastPageRead: lastPageRead, isRead: markRead),
    ),
  );
  if (offlineEnabled && db != null && !result.hasError) {
    await db.clearProgressDirtyIfUnchanged(chapterId,
        lastPageRead: lastPageRead);
    // Completion set isRead (and thus readStateDirty) too — clear that flag on
    // the same successful push so a completed read isn't re-pushed forever.
    if (markRead != null) {
      await db.clearReadStateDirtyIfUnchanged(chapterId, isRead: markRead);
    }
  }
  return result;
}

/// Toggle a chapter's bookmark, offline-aware. Writes it to the on-device
/// catalog first (survives offline + restart) and marks it dirty, then pushes
/// to the server — a failed push stays pending for the next sync (#33).
Future<void> recordBookmark(
  WidgetRef ref, {
  required int chapterId,
  required bool isBookmarked,
}) async {
  final offline = ref.read(offlineActiveProvider);
  if (offline) {
    await ref
        .read(offlineDatabaseProvider)
        .setChapterBookmark(chapterId, isBookmarked);
  }
  // Bookmark dirtiness is tracked separately from read progress, so push only
  // the bookmark and clear only its flag — any pending offline read stays
  // dirty and flushes independently via pushPendingProgress.
  final result = await AsyncValue.guard(
    () => ref.read(mangaBookRepositoryProvider).putChapter(
          chapterId: chapterId,
          patch: ChapterChange(isBookmarked: isBookmarked),
        ),
  );
  if (offline && !result.hasError) {
    await ref
        .read(offlineDatabaseProvider)
        .clearBookmarkDirtyIfUnchanged(chapterId, isBookmarked: isBookmarked);
  }
}

/// Mark chapters read/unread, offline-aware. Writes the local row FIRST (the
/// ch-99 loop's root cause was list mark-read never touching it), then the
/// server bulk write; on failure the change stays dirty and up-syncs on
/// reconnect. [resetPosition] mirrors the mark-read action's `lastPageRead: 0`
/// reset; returns the server write's success so callers gate trackers/
/// delete-on-manual on being online.
Future<bool> recordReadStateWithDependencies({
  required bool offlineEnabled,
  required OfflineDatabase? offlineDatabase,
  required MangaBookRepository repository,
  required List<int> chapterIds,
  required bool isRead,
  bool resetPosition = false,
}) async {
  final db = offlineDatabase;
  if (offlineEnabled && db != null) {
    for (final id in chapterIds) {
      if (resetPosition) {
        await db.setChapterProgress(id, lastPageRead: 0, isRead: isRead);
      } else {
        await db.setChapterReadState(id, isRead);
      }
    }
  }
  final result = await AsyncValue.guard(
    () => repository.modifyBulkChapters(
      ChapterBatch(
        ids: chapterIds,
        patch: resetPosition
            ? ChapterChange(isRead: isRead, lastPageRead: 0)
            : ChapterChange(isRead: isRead),
      ),
    ),
  );
  if (offlineEnabled && db != null && !result.hasError) {
    for (final id in chapterIds) {
      await db.clearReadStateDirtyIfUnchanged(id, isRead: isRead);
      if (resetPosition) {
        await db.clearProgressDirtyIfUnchanged(id, lastPageRead: 0);
      }
    }
  }
  return !result.hasError;
}

/// Widget entry point for [recordReadStateWithDependencies] — resolves the
/// offline deps from [ref]. Mirrors [recordReadingProgress].
Future<bool> recordReadState(
  WidgetRef ref, {
  required List<int> chapterIds,
  required bool isRead,
  bool resetPosition = false,
}) {
  final offline = ref.read(offlineActiveProvider);
  return recordReadStateWithDependencies(
    offlineEnabled: offline,
    offlineDatabase: offline ? ref.read(offlineDatabaseProvider) : null,
    repository: ref.read(mangaBookRepositoryProvider),
    chapterIds: chapterIds,
    isRead: isRead,
    resetPosition: resetPosition,
  );
}

// === Delete-on-read =========================================================
// Two INDEPENDENT features (see delete_chapters_settings_repository):
// on-device (local prefs) deletes THIS phone's copy; server (shared with the
// WebUI) deletes the server's copy, which cascades to the device (device ⊆
// server). Each no-ops if its own setting is off, and the N-behind target only
// ever lands on a chapter already behind the reader, so the continuous reader
// never loses pages it still needs.

/// Resolve the chapter to delete `slots` behind [readChapterId] in the manga's
/// reading order (1 = the just-read chapter). Null if out of range or the list
/// isn't loaded.
int? _whileReadingTarget(
    WidgetRef ref, int mangaId, int readChapterId, int slots) {
  final chapters = ref
      .read(mangaChapterListWithFilterProvider(mangaId: mangaId))
      .value;
  if (chapters == null) return null;
  final isAsc = ref.read(mangaChapterSortDirectionProvider) ??
      (DBKeys.chapterSortDirection.initial as bool);
  return chapterIdToDeleteWhileReading(chapters, isAsc, readChapterId, slots);
}

/// The server delete settings, loaded from the server (null offline / on error,
/// so the server delete simply doesn't run — it needs a connection anyway).
Future<DeleteChaptersSettings?> _serverDeleteSettings(WidgetRef ref) async {
  try {
    return await ref.read(deleteChaptersSettingsControllerProvider.future);
  } catch (_) {
    return null;
  }
}

// --- on-device (local) ------------------------------------------------------

/// Delete THIS phone's copy of the chapter N slots behind the one just read.
Future<void> maybeDeleteOnReadLocal(
  WidgetRef ref, {
  required int mangaId,
  required int readChapterId,
}) async {
  if (!ref.read(offlineActiveProvider)) return;
  final s = ref.read(localDeleteSettingsProvider);
  if (s.deleteWhileReading <= 0) return;
  final targetId =
      _whileReadingTarget(ref, mangaId, readChapterId, s.deleteWhileReading);
  if (targetId == null) return;
  await _deleteDeviceCopyIfDeletable(ref, targetId, s.deleteWithBookmark);
}

/// Delete THIS phone's copy when a chapter is manually marked read.
Future<void> maybeDeleteOnManualLocal(
  WidgetRef ref, {
  required int chapterId,
}) async {
  if (!ref.read(offlineActiveProvider)) return;
  final s = ref.read(localDeleteSettingsProvider);
  if (!s.deleteManuallyMarkedRead) return;
  await _deleteDeviceCopyIfDeletable(ref, chapterId, s.deleteWithBookmark);
}

/// Delete a chapter's device copy iff it's downloaded and the bookmark gate
/// allows it. A manually-saved (pinned) chapter IS deleted on a new read and
/// un-pinned (via [deleteChapterFromDevice]) so the reconciler doesn't just
/// re-download it; the server copy is untouched.
Future<void> _deleteDeviceCopyIfDeletable(
  WidgetRef ref,
  int chapterId,
  bool allowBookmarked,
) async {
  try {
    if (ref.read(offlineDownloadManagerProvider) == null) return;
    final c = await ref.read(offlineRepositoryProvider).chapterById(chapterId);
    if (c == null || c.deviceState != OfflineDeviceState.downloaded) return;
    if (c.isBookmarked && !allowBookmarked) return;
    await deleteChapterFromDevice(ref, chapterId);
  } catch (e) {
    // Best-effort — a failed auto-delete must never surface during reading.
    logger.e('Offline: on-device delete-on-read failed for $chapterId: $e');
  }
}

// --- server -----------------------------------------------------------------

/// Tell the SERVER to delete its copy of the chapter N slots behind the one just
/// read (per the WebUI's delete-while-reading). The cascade then drops the
/// device copy too.
Future<void> maybeDeleteOnReadServer(
  WidgetRef ref, {
  required int mangaId,
  required int readChapterId,
}) async {
  final s = await _serverDeleteSettings(ref);
  if (s == null || s.deleteWhileReading <= 0) return;
  final targetId =
      _whileReadingTarget(ref, mangaId, readChapterId, s.deleteWhileReading);
  if (targetId == null) return;
  await _deleteServerCopyIfDeletable(
      ref, mangaId, targetId, s.deleteWithBookmark);
}

/// Tell the SERVER to delete its copy when a chapter is manually marked read.
Future<void> maybeDeleteOnManualServer(
  WidgetRef ref, {
  required int? mangaId,
  required int chapterId,
}) async {
  if (mangaId == null) return;
  final s = await _serverDeleteSettings(ref);
  if (s == null || !s.deleteManuallyMarkedRead) return;
  await _deleteServerCopyIfDeletable(
      ref, mangaId, chapterId, s.deleteWithBookmark);
}

/// Delete a chapter's SERVER copy iff downloaded and the bookmark gate allows
/// it, then cascade to drop the device copy. Gates off the UNFILTERED chapter
/// list so an active "hide read" filter can't cause a silent miss, and the
/// bookmark gate also honours a bookmark made offline that hasn't reached the
/// server yet.
Future<void> _deleteServerCopyIfDeletable(
  WidgetRef ref,
  int mangaId,
  int chapterId,
  bool allowBookmarked,
) async {
  try {
    final chapters =
        ref.read(mangaChapterListProvider(mangaId: mangaId)).value;
    final idx = chapters?.indexWhere((e) => e.id == chapterId) ?? -1;
    if (chapters == null || idx < 0) return;
    final c = chapters[idx];
    if (!c.isDownloaded) return;
    var isBookmarked = c.isBookmarked;
    if (ref.read(offlineActiveProvider)) {
      final row =
          await ref.read(offlineRepositoryProvider).chapterById(chapterId);
      if (row?.isBookmarked ?? false) isBookmarked = true;
    }
    if (isBookmarked && !allowBookmarked) return;
    await ref.read(mangaBookRepositoryProvider).deleteChapters([chapterId]);
    await cascadeServerDeleteToDevice(ref, [chapterId]);
  } catch (e) {
    // Best-effort — a failed server auto-delete must never surface mid-read.
    logger.e('Offline: server delete-on-read failed for $chapterId: $e');
  }
}

/// Push any locally-recorded read progress that hasn't reached the server yet.
/// Run at launch + after a manga's chapters sync; after a successful push also
/// nudges the manga's external trackers for any chapter marked read, so
/// trackers stay in sync too.
Future<void> pushPendingProgress(
  ProviderContainer container, {
  bool suppressTrackerNudge = false,
}) async {
  if (!container.read(offlineActiveProvider)) return;
  final db = container.read(offlineDatabaseProvider);
  final repo = container.read(mangaBookRepositoryProvider);

  // Collect manga IDs where progress was pushed successfully AND the chapter
  // is marked read — deduplicated so we call trackProgress once per manga.
  final syncedReadMangaIds = <int>{};

  for (final c in await db.dirtyChapters()) {
    var pushProgress = c.progressDirty;
    var pushReadState = c.readStateDirty;
    // Never-regress: if another device already read further (or finished it),
    // don't push our lesser offline position — drop the dirty flags and adopt
    // the server's state on the next down-sync. Furthest read wins; bookmarks
    // are independent and still sync.
    if (pushProgress || pushReadState) {
      final server =
          (await AsyncValue.guard(() => repo.getChapter(chapterId: c.id)))
              .asData
              ?.value;
      if (server != null) {
        final serverRead = server.isRead.ifNull();
        final serverAhead = serverRead
            ? !c.isRead // server finished it; our push would un-finish it
            : c.isRead
                // We finished it; a server partial position never outranks a
                // completion (marking read leaves lastPageRead low).
                ? false
                : server.lastPageRead.getValueOnNullOrNegative() >
                    c.lastPageRead;
        if (serverAhead) {
          pushProgress = false;
          pushReadState = false;
          if (c.progressDirty) {
            await db.clearProgressDirtyIfUnchanged(c.id,
                lastPageRead: c.lastPageRead);
          }
          if (c.readStateDirty) {
            await db.clearReadStateDirtyIfUnchanged(c.id, isRead: c.isRead);
          }
        }
      }
    }
    if (!pushProgress && !pushReadState && !c.bookmarkDirty) continue;
    final result = await AsyncValue.guard(
      () => repo.putChapter(
        chapterId: c.id,
        patch: ChapterChange(
          // Send only locally-changed fields (null = omitted), each gated on
          // its OWN dirty flag: isRead rides readStateDirty (not
          // progressDirty) so a position-only write can't push a stale isRead
          // (ch-99), just as a bookmark sync can't overwrite pending read
          // progress (#13).
          lastPageRead: pushProgress ? c.lastPageRead : null,
          isRead: pushReadState ? c.isRead : null,
          isBookmarked: c.bookmarkDirty ? c.isBookmarked : null,
        ),
      ),
    );
    if (!result.hasError) {
      // Clear each flag only if the row still holds what we just pushed — a
      // newer local write that arrived mid-push keeps its flag and re-syncs
      // on the next pass.
      if (c.progressDirty) {
        await db.clearProgressDirtyIfUnchanged(c.id,
            lastPageRead: c.lastPageRead);
      }
      if (c.readStateDirty) {
        await db.clearReadStateDirtyIfUnchanged(c.id, isRead: c.isRead);
      }
      if (c.bookmarkDirty) {
        await db.clearBookmarkDirtyIfUnchanged(c.id,
            isBookmarked: c.isBookmarked);
      }
      if (c.readStateDirty && c.isRead) syncedReadMangaIds.add(c.mangaId);
    }
  }

  // Push tracker progress for mangas with read chapters synced, gated on the
  // "update after reading" toggle and tracker bindings — a tracker failure
  // must never break the progress sync. Migration's pre-copy flush suppresses
  // this nudge (suppressTrackerNudge): it wants local progress written but must
  // NOT touch the OLD entry's external trackers — tracking is carried exactly
  // once by the chosen migration policy (bindTrackRecord / fallback).
  if (suppressTrackerNudge || syncedReadMangaIds.isEmpty) return;
  final enabledAfterReading =
      container.read(updateProgressAfterReadingProvider).ifNull();

  for (final mangaId in syncedReadMangaIds) {
    try {
      final records = await container
          .read(mangaTrackRecordsProvider(mangaId: mangaId).future);
      if (!shouldTrackProgress(
        isRead: true,
        enabledAfterReading: enabledAfterReading,
        enabledManualMarkRead: false,
        manual: false,
        trackRecordCount: records.length,
      )) {
        continue;
      }
      final trackResult = await AsyncValue.guard(
        () => container.read(trackerRepositoryProvider).trackProgress(mangaId),
      );
      // Show an error toast if available (null when no widget context — e.g.
      // at launch before the navigator is mounted, or in tests).
      try {
        trackResult.showToastOnError(container.read(toastProvider));
      } catch (_) {
        // No widget binding yet — toast is best-effort; swallow silently.
      }
    } catch (e) {
      // Swallow — tracker errors must not interrupt the offline→server sync.
      logger.e('Offline: tracker push skipped for manga $mangaId: $e');
    }
  }
}

/// Enforce device ⊆ server: when chapters are deleted on the server, drop any
/// device copies too. Silent; no-op when offline is unavailable.
Future<void> cascadeServerDeleteToDevice(
    WidgetRef ref, List<int> chapterIds) async {
  if (ref.read(offlineDownloadManagerProvider) == null) return;
  for (final id in chapterIds) {
    await deleteChapterFromDevice(ref, id);
  }
}

/// Remove a chapter's device copy.
Future<void> deleteChapterFromDevice(WidgetRef ref, int chapterId) async {
  final manager = ref.read(offlineDownloadManagerProvider);
  if (manager == null) return;
  // Stop any in-flight download first so it can't resurrect the files we're
  // about to delete — Android routes through the FGS worker, elsewhere claim
  // the main-isolate coordinator.
  final coordinator =
      _useBgService ? null : ref.read(offlineDownloadCoordinatorProvider);
  // Bump the persistent download generation first so a re-queued download
  // outranks any still-in-flight event from the deleted one (survives restart).
  final newGen =
      await ref.read(offlineDatabaseProvider).bumpChapterGeneration(chapterId);
  if (_useBgService) {
    final controller = ref.read(backgroundDownloadControllerProvider);
    await controller.onRemoved(chapterId);
    // Tombstone the completion log at the new generation so a stale terminal
    // entry can't complete a later re-queued generation of this chapter.
    await controller.recordChapterDeleted(chapterId, newGen);
  } else {
    await coordinator?.beginDelete(chapterId);
  }
  try {
    final chapter =
        await ref.read(offlineRepositoryProvider).chapterById(chapterId);
    if (chapter != null) await manager.deleteChapter(chapter);
    await ref.read(offlineDatabaseProvider).setChapterPinned(chapterId, false);
  } finally {
    coordinator?.endDelete(chapterId);
  }
}

/// Remove a series from the library AND clean up its on-device downloads, so
/// they aren't left orphaned. Clears the keep-rule and deletes every device
/// copy; the SERVER's own download is left alone (see #34, #36).
Future<void> removeMangaFromLibraryAndPurge(WidgetRef ref, int mangaId) async {
  await ref.read(mangaBookRepositoryProvider).removeMangaFromLibrary(mangaId);
  if (!ref.read(offlineActiveProvider)) return;
  final db = ref.read(offlineDatabaseProvider);
  await db.setKeepRule(mangaId, OfflineKeepRule.off, 3);
  // Purge every chapter with any on-device footprint, not just fully
  // downloaded ones — queued/downloading/errored must also be cancelled, or an
  // in-flight download could finish and leave files after the series left the
  // library.
  for (final c in await db.chaptersForManga(mangaId)) {
    if (c.deviceState != OfflineDeviceState.none) {
      await deleteChapterFromDevice(ref, c.id);
    }
  }
}

/// The offline download orchestrator, wired with real network dependencies:
/// `fetchChapterPages` for URLs and an auth'd HTTP GET for page bytes. Null on
/// web / when offline storage is unavailable, so callers use
/// `?.downloadChapter(c)`.
@riverpod
OfflineDownloadManager? offlineDownloadManager(Ref ref) {
  if (!ref.watch(offlineActiveProvider)) return null;
  final repo = ref.watch(mangaBookRepositoryProvider);
  return OfflineDownloadManager(
    db: ref.watch(offlineDatabaseProvider),
    store: ref.watch(offlinePageStoreProvider),
    fetchPageUrls: (chapterId) async =>
        (await repo.getChapterPages(chapterId: chapterId))?.pages ??
        const <String>[],
    fetchBytes: (url) => fetchOfflinePageBytes(ref, url),
  );
}

/// Fetch one page image's bytes with the active auth, resolved at call time
/// (never baked) — mirrors `ServerImage`'s request building (base API without
/// `/api`, ui_login `?token=`, basic/simple_login via headers). Throws
/// [PageAuthException] on 401 so the engine refreshes and retries; any other
/// non-200 is a plain transient exception.
Future<PageBytes> fetchOfflinePageBytes(Ref ref, String pageUrl) async {
  final authType = ref.read(authTypeKeyProvider);
  final basicToken = ref.read(credentialsProvider).value;
  final creds = ref.read(authCredentialsStoreProvider).value;
  final base = Endpoints.baseApi(
    baseUrl: ref.read(serverUrlProvider),
    port: ref.read(serverPortProvider),
    addPort: ref.read(serverPortToggleProvider).ifNull(),
    appendApiToUrl: false,
  );
  var fetchUrl = '$base$pageUrl';

  final headers = <String, String>{};
  if (authType == AuthType.basic && basicToken != null) {
    headers['Authorization'] = basicToken;
  } else if (authType == AuthType.simpleLogin) {
    final cookie = creds?.simpleLoginCookieHeader;
    if (cookie != null) headers.addAll(cookie);
  } else if (authType == AuthType.uiLogin &&
      (creds?.uiAccessToken?.isNotEmpty ?? false)) {
    final sep = fetchUrl.contains('?') ? '&' : '?';
    fetchUrl =
        '$fetchUrl${sep}token=${Uri.encodeQueryComponent(creds!.uiAccessToken!)}';
  }

  final res = await http.get(Uri.parse(fetchUrl), headers: headers);
  if (res.statusCode == 401 || res.statusCode == 403) {
    throw const PageAuthException();
  }
  if (res.statusCode != 200) {
    throw Exception('offline page fetch failed ($pageUrl): ${res.statusCode}');
  }
  return (
    bytes: res.bodyBytes,
    ext: pageImageExt(res.headers['content-type'], res.bodyBytes)
  );
}

/// Manga ids with at least one chapter downloaded on this device — used by
/// the "On device" library filter. Empty set when offline is unavailable, so
/// the filter is a no-op.
@riverpod
Future<Set<int>> offlineDeviceMangaIds(Ref ref) async {
  if (!ref.watch(offlineActiveProvider)) return const {};
  return ref.watch(offlineRepositoryProvider).deviceDownloadedMangaIds();
}

/// The keep-offline rule currently set for a manga — used by the popup button
/// to show a checkmark on the active rule.
@riverpod
Future<OfflineKeepRule> mangaKeepRule(Ref ref, int mangaId) async {
  if (!ref.watch(offlineActiveProvider)) return OfflineKeepRule.off;
  return ref.watch(offlineRepositoryProvider).keepRuleFor(mangaId);
}

/// The keep-offline rule AND its unread-buffer size — so the sheet can tick the
/// exact "Keep next N unread" preset that's active.
@riverpod
Future<({OfflineKeepRule rule, int count})> mangaKeepConfig(
    Ref ref, int mangaId) async {
  if (!ref.watch(offlineActiveProvider)) {
    return (rule: OfflineKeepRule.off, count: 5);
  }
  return ref.watch(offlineRepositoryProvider).keepConfigFor(mangaId);
}

/// How many of a manga's chapters are downloaded on this device — drives the
/// series Download/On-device button label.
@riverpod
Future<int> mangaDownloadedCount(Ref ref, int mangaId) async {
  if (!ref.watch(offlineActiveProvider)) return 0;
  return (await ref
          .watch(offlineDatabaseProvider)
          .downloadedChaptersForManga(mangaId))
      .length;
}

/// Live download progress for a series: how many chapters are downloaded vs
/// currently downloading/queued. Drives the live "Downloading N" button state.
@riverpod
Stream<({int downloaded, int inFlight})> mangaOfflineProgress(
    Ref ref, int mangaId) {
  if (!ref.watch(offlineActiveProvider)) {
    return Stream.value((downloaded: 0, inFlight: 0));
  }
  return ref
      .watch(offlineDatabaseProvider)
      .watchChaptersForManga(mangaId)
      .map((rows) {
    var downloaded = 0;
    var inFlight = 0;
    for (final c in rows) {
      if (c.deviceState == OfflineDeviceState.downloaded) {
        downloaded++;
      } else if (c.deviceState == OfflineDeviceState.downloading ||
          c.deviceState == OfflineDeviceState.queued) {
        inFlight++;
      }
    }
    return (downloaded: downloaded, inFlight: inFlight);
  }).distinct(); // only rebuild the button when the counts actually change
}

/// Every series with an offline footprint — chapters present OR an active
/// keep-rule — with per-series counts, bytes, and the manga row. Single source
/// for the Downloads → On device tab (shows downloads AND manages keep-rules);
/// sorted active-first, then biggest, then strongest rule.
@riverpod
Stream<List<OfflineSeriesEntry>> offlineSeries(Ref ref) {
  if (!ref.watch(offlineActiveProvider)) return Stream.value(const []);
  return ref.watch(offlineDatabaseProvider).watchOfflineSeries().map((rows) {
    final sorted = [
      for (final r in rows)
        OfflineSeriesEntry(
          manga: r.manga,
          downloaded: r.downloaded,
          inFlight: r.inFlight,
          bytes: r.bytes,
        ),
    ];
    sorted.sort((a, b) {
      if ((a.inFlight > 0) != (b.inFlight > 0)) return a.inFlight > 0 ? -1 : 1;
      if (a.bytes != b.bytes) return b.bytes.compareTo(a.bytes);
      return b.manga.keepRule.index.compareTo(a.manga.keepRule.index);
    });
    return sorted;
  });
}

/// Stop auto-keeping [mangaId] offline but KEEP chapters already downloaded;
/// unfinished ones are dropped ("keep what I have", not "finish the rest").
/// Order matters: pin every still-downloaded chapter BEFORE clearing the rule,
/// so a reconcile racing this can't evict anything before the pin lands —
/// only then is it safe to reconcile.
Future<void> detachKeepRule(WidgetRef ref, int mangaId) async {
  if (!ref.read(offlineActiveProvider)) return;
  final db = ref.read(offlineDatabaseProvider);
  for (final c in await db.chaptersForManga(mangaId)) {
    if (c.deviceState == OfflineDeviceState.queued ||
        c.deviceState == OfflineDeviceState.downloading) {
      await deleteChapterFromDevice(ref, c.id);
    }
  }
  final cfg = await ref.read(offlineRepositoryProvider).keepConfigFor(mangaId);
  // Pin the downloaded set and clear the rule ATOMICALLY: the cancel above is
  // async on Android, so re-read the downloaded set HERE inside the same
  // transaction that flips the rule off — guaranteeing every downloaded
  // chapter is already pinned the instant the rule clears, so no reconcile can
  // evict it. A chapter still finishing after this was in-flight at detach
  // time and is intentionally dropped.
  await db.transaction(() async {
    for (final c in await db.downloadedChaptersForManga(mangaId)) {
      await db.setChapterPinned(c.id, true);
    }
    await db.setKeepRule(mangaId, OfflineKeepRule.off, cfg.count);
  });
  await reconcileMangaWidget(ref, mangaId);
}

/// Stop keeping [mangaId] offline AND delete every on-device chapter (the
/// server copy is untouched). Mirrors the per-series "remove" action.
Future<void> removeKeepRuleAndDelete(WidgetRef ref, int mangaId) async {
  if (!ref.read(offlineActiveProvider)) return;
  final db = ref.read(offlineDatabaseProvider);
  final cfg = await ref.read(offlineRepositoryProvider).keepConfigFor(mangaId);
  await db.setKeepRule(mangaId, OfflineKeepRule.off, cfg.count);
  for (final c in await db.chaptersForManga(mangaId)) {
    if (c.deviceState != OfflineDeviceState.none) {
      await deleteChapterFromDevice(ref, c.id);
    }
  }
}

/// Change the keep-rule for [mangaId] and reconcile (download/evict to match).
Future<void> changeKeepRule(
    WidgetRef ref, int mangaId, OfflineKeepRule rule, int count) async {
  if (!ref.read(offlineActiveProvider)) return;
  await ref.read(offlineDatabaseProvider).setKeepRule(mangaId, rule, count);
  await reconcileMangaWidget(ref, mangaId);
}

/// Total bytes of on-device offline content — for the storage settings UI.
@riverpod
Future<int> offlineUsageBytes(Ref ref) async {
  if (!ref.watch(offlineActiveProvider)) return 0;
  return ref.read(offlineRepositoryProvider).totalDownloadedBytes();
}

/// Device-wide safety nets — read from persisted user settings.
@riverpod
SafetyNetConfig safetyNetConfig(Ref ref) => SafetyNetConfig(
      timeEvictEnabled: ref.watch(offlineTimeEvictEnabledProvider) ?? false,
      keepDays: ref.watch(offlineKeepDaysProvider) ?? 30,
      storageCapEnabled: ref.watch(offlineStorageCapEnabledProvider) ?? false,
      storageCapBytes:
          (ref.watch(offlineStorageCapMbProvider) ?? 2000) * 1024 * 1024,
    );

/// Concrete-deps core — no Ref/ProviderContainer in the signature, so the
/// controller, the launch path, and tests can all call it.
Future<void> reconcileMangaCore({
  required OfflineDatabase db,
  required OfflineRepository repo,
  required OfflineDownloadManager manager,
  required OfflineDownloadCoordinator coordinator,
  required SafetyNetConfig nets,
  required int mangaId,
  Future<void> Function(List<int> chapterIds)? enqueueServerDownload,
  Future<void> Function(int chapterId)? removeFromWorker,
}) {
  return OfflineReconciler(
    db: db,
    nets: nets,
    now: DateTime.now(),
    // Only QUEUE chapters here; starting the download is the caller's job (via
    // downloadStarterProvider) so the Ref-less launch path and tests stay in
    // control. One failed queue-mark must not abort the rest.
    onDownload: (id) async {
      try {
        await coordinator.queueChapter(id);
      } catch (e) {
        logger.e('Offline: reconcile queue skipped for chapter $id: $e');
      }
    },
    onEvict: (id) async {
      try {
        // Cancel the active downloader before removing files, or an in-flight
        // download re-writes the chapter after the purge. beginDelete claims
        // the desktop engine; removeFromWorker stops the Android FGS worker
        // (null in the launch/test core, where the coordinator is the only
        // downloader).
        await coordinator.beginDelete(id);
        if (removeFromWorker != null) await removeFromWorker(id);
        final c = await repo.chapterById(id);
        if (c != null) await manager.deleteChapter(c);
      } catch (e) {
        logger.e('Offline: reconcile evict skipped for chapter $id: $e');
      } finally {
        coordinator.endDelete(id);
      }
    },
    onServerDownload: enqueueServerDownload == null
        ? null
        : (ids) async {
            try {
              await enqueueServerDownload(ids.toList());
            } catch (e) {
              logger
                  .e('Offline: reconcile server-download enqueue skipped: $e');
            }
          },
  ).reconcileManga(mangaId);
}

/// Controller / in-app entry point (generated Ref).
Future<void> reconcileManga(Ref ref, int mangaId) async {
  if (!ref.read(offlineActiveProvider)) return;
  final manager = ref.read(offlineDownloadManagerProvider);
  final coordinator = ref.read(offlineDownloadCoordinatorProvider);
  if (manager == null || coordinator == null) return;
  await reconcileMangaCore(
    db: ref.read(offlineDatabaseProvider),
    repo: ref.read(offlineRepositoryProvider),
    manager: manager,
    coordinator: coordinator,
    nets: ref.read(safetyNetConfigProvider),
    mangaId: mangaId,
    enqueueServerDownload: (ids) => ref
        .read(downloadsRepositoryProvider)
        .addChaptersBatchToDownloadQueue(ids),
    removeFromWorker: (id) async {
      final ctrl = ref.read(backgroundDownloadControllerProvider);
      await ctrl.onRemoved(id);
      final gen = await ref.read(offlineDatabaseProvider)
          .bumpChapterGeneration(id);
      await ctrl.recordChapterDeleted(id, gen);
    },
  );
  // Keep-rule sync queued any missing chapters; now start downloading them.
  await ref.read(downloadStarterProvider)();
}

/// Widget entry point — same as [reconcileManga] but accepts a [WidgetRef].
Future<void> reconcileMangaWidget(WidgetRef ref, int mangaId) async {
  if (!ref.read(offlineActiveProvider)) return;
  final manager = ref.read(offlineDownloadManagerProvider);
  final coordinator = ref.read(offlineDownloadCoordinatorProvider);
  if (manager == null || coordinator == null) return;
  await reconcileMangaCore(
    db: ref.read(offlineDatabaseProvider),
    repo: ref.read(offlineRepositoryProvider),
    manager: manager,
    coordinator: coordinator,
    nets: ref.read(safetyNetConfigProvider),
    mangaId: mangaId,
    enqueueServerDownload: (ids) => ref
        .read(downloadsRepositoryProvider)
        .addChaptersBatchToDownloadQueue(ids),
    removeFromWorker: (id) async {
      final ctrl = ref.read(backgroundDownloadControllerProvider);
      await ctrl.onRemoved(id);
      final gen = await ref.read(offlineDatabaseProvider)
          .bumpChapterGeneration(id);
      await ctrl.recordChapterDeleted(id, gen);
    },
  );
  // Start downloading the freshly-queued chapters. THIS was the missing wire
  // that made "Download all / unread" silently do nothing on Android.
  await ref.read(downloadStarterProvider)();
}

/// Launch entry point (main.dart holds a ProviderContainer, not a Ref).
Future<void> reconcileAllAtLaunch(ProviderContainer container) async {
  if (!container.read(offlineActiveProvider)) return;
  final manager = container.read(offlineDownloadManagerProvider);
  final coordinator = container.read(offlineDownloadCoordinatorProvider);
  if (manager == null || coordinator == null) return;
  final db = container.read(offlineDatabaseProvider);
  final repo = container.read(offlineRepositoryProvider);
  final nets = container.read(safetyNetConfigProvider);
  for (final m in await db.libraryManga()) {
    await reconcileMangaCore(
        db: db,
        repo: repo,
        manager: manager,
        coordinator: coordinator,
        nets: nets,
        mangaId: m.id,
        enqueueServerDownload: (ids) => container
            .read(downloadsRepositoryProvider)
            .addChaptersBatchToDownloadQueue(ids),
        removeFromWorker: (id) async {
          final ctrl = container.read(backgroundDownloadControllerProvider);
          await ctrl.onRemoved(id);
          final gen = await container
              .read(offlineDatabaseProvider)
              .bumpChapterGeneration(id);
          await ctrl.recordChapterDeleted(id, gen);
        });
  }
}

/// Pick a file extension from the content-type, falling back to magic bytes.
/// Rendering sniffs the bytes regardless, so this only keeps filenames sensible.
String pageImageExt(String? contentType, List<int> bytes) {
  final ct = contentType?.toLowerCase() ?? '';
  if (ct.contains('png')) return 'png';
  if (ct.contains('webp')) return 'webp';
  if (ct.contains('gif')) return 'gif';
  if (ct.contains('jpeg') || ct.contains('jpg')) return 'jpg';
  if (bytes.length >= 12) {
    if (bytes[0] == 0x89 && bytes[1] == 0x50) return 'png';
    if (bytes[0] == 0x47 && bytes[1] == 0x49) return 'gif';
    if (bytes[0] == 0xFF && bytes[1] == 0xD8) return 'jpg';
    if (bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[8] == 0x57) return 'webp';
  }
  return 'jpg';
}
