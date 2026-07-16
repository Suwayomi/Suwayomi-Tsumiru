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

/// THE single entry point that kicks off downloading after chapters have been
/// queued into drift. EVERY download trigger must call this — on Android it
/// starts the foreground-service worker, elsewhere it drains via the
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

/// Pause or resume ALL on-device downloads. Persists the flag (so it survives a
/// restart) and acts immediately on the active pipeline: the FGS worker on
/// Android, the main-isolate pump elsewhere. The persisted flag is what the
/// download starters gate on, so no enqueue/connectivity/launch path can restart
/// downloads while paused.
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
    // Best-effort: a file-delete failure (a locked file, permissions) must not
    // abort the clear before the identity stamp is reset — the DB is already
    // wiped, and leftover bytes are only dead weight, not stale content.
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
  // stopBackground sets the restart-suppression flag; keep it INSIDE the try so
  // finish() always clears it even if teardown throws — otherwise a leaked flag
  // would silently drop every background-worker event for the rest of the session.
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
  // Re-read the page total on every downloaded-page tick (instead of once up
  // front) so the arc flips from indeterminate to a real fraction the moment the
  // total becomes known — webtoon chapters only learn their page count when the
  // downloader resolves their pages mid-download.
  return repo.watchChapterDownloadedPages(chapterId).asyncMap((done) async {
    final total = (await repo.db.chapterById(chapterId))?.pageCount ?? 0;
    return total <= 0 ? null : (done / total).clamp(0.0, 1.0);
  }).distinct();
}

/// Save a chapter's pages to the device. Looks up the synced catalog row and
/// hands it to the download manager. No-op if offline is unavailable or the
/// chapter hasn't been synced (browse it online once first).
///
/// Manual save is sticky (pinned). If the chapter is not yet server-downloaded,
/// enqueues a server download first so Suwayomi fetches the source pages, then
/// pulls them immediately with `force: true` so the device copy is available as
/// soon as the server completes its own fetch.
Future<void> saveChapterToDevice(WidgetRef ref, int chapterId) async {
  final coordinator = ref.read(offlineDownloadCoordinatorProvider);
  if (coordinator == null) return;
  final repo = ref.read(offlineRepositoryProvider);
  final chapter = await repo.chapterById(chapterId);
  if (chapter == null) return;
  // Manual save is sticky.
  await ref.read(offlineDatabaseProvider).setChapterPinned(chapterId, true);
  // Ensure the SERVER also has the chapter (device ⊆ server). The cached
  // `serverIsDownloaded` flag can be stale (e.g. it isn't reset when a chapter is
  // deleted), so when it claims the server already has the chapter, verify
  // against the server before skipping — otherwise the device keeps a copy the
  // server never saved. A failed/offline check falls back to the cached value.
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
Future<void> recordReadingProgress(
  WidgetRef ref, {
  required int chapterId,
  required int lastPageRead,
  required bool isRead,
}) async {
  final offline = ref.read(offlineActiveProvider);
  await recordReadingProgressWithDependencies(
    offlineEnabled: offline,
    offlineDatabase: offline ? ref.read(offlineDatabaseProvider) : null,
    repository: ref.read(mangaBookRepositoryProvider),
    chapterId: chapterId,
    lastPageRead: lastPageRead,
    isRead: isRead,
  );
}

Future<void> recordReadingProgressWithDependencies({
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
}

/// Toggle a chapter's bookmark, offline-aware. Writes it to the on-device
/// catalog first (so it survives offline + restart) and marks it dirty, then
/// pushes to the server; on a failed push it stays pending for the next online
/// sync (#33). Best-effort — the local write is authoritative.
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
  // the bookmark and clear only its flag — any pending offline read stays dirty
  // and is flushed independently by pushPendingProgress.
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

// === Delete-on-read =========================================================
// Two INDEPENDENT features, each with its own settings (see
// delete_chapters_settings_repository): the on-device set (local prefs) deletes
// THIS phone's copy; the server set (global meta, shared with the WebUI) deletes
// the server's copy, which then cascades to the device (device ⊆ server). On a
// read we fire both; each no-ops if its own setting is off. The N-behind target
// only ever lands on a chapter already behind the reader, so the continuous
// reader never loses pages it still needs.

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

/// Delete a chapter's device copy iff it's downloaded on the device and the
/// bookmark gate allows it. A manually-saved (pinned) chapter IS deleted on a
/// new read — and un-pinned (via [deleteChapterFromDevice]) so the reconciler
/// doesn't simply re-download it. The server copy is untouched.
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

/// Delete a chapter's SERVER copy iff it's downloaded on the server and the
/// bookmark gate allows it, then cascade to drop the device copy.
///
/// Gates off the UNFILTERED chapter list (id lookup — order is irrelevant), so
/// an active "hide read" filter can't make this silently miss. The bookmark gate
/// also honours a bookmark made offline that hasn't reached the server yet (the
/// server DTO would still read false), via the on-device catalog.
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

/// Push any locally-recorded read progress that hasn't reached the server yet
/// (e.g. read while offline). Run at launch + after a manga's chapters sync, so
/// progress made offline syncs up once the connection returns.
///
/// After a successful server push, also nudges the manga's external trackers
/// for any chapter that was marked read — so trackers stay in sync even when
/// progress was recorded while the device was offline.
Future<void> pushPendingProgress(ProviderContainer container) async {
  if (!container.read(offlineActiveProvider)) return;
  final db = container.read(offlineDatabaseProvider);
  final repo = container.read(mangaBookRepositoryProvider);

  // Collect manga IDs where progress was pushed successfully AND the chapter
  // is marked read — deduplicated so we call trackProgress once per manga.
  final syncedReadMangaIds = <int>{};

  for (final c in await db.dirtyChapters()) {
    final result = await AsyncValue.guard(
      () => repo.putChapter(
        chapterId: c.id,
        patch: ChapterChange(
          // Send only the locally-changed fields (null = omitted from the
          // patch), so a progress sync never overwrites a server bookmark that
          // hasn't down-synced, and a bookmark sync never overwrites pending
          // read progress (#13).
          lastPageRead: c.progressDirty ? c.lastPageRead : null,
          isRead: c.progressDirty ? c.isRead : null,
          isBookmarked: c.bookmarkDirty ? c.isBookmarked : null,
        ),
      ),
    );
    if (!result.hasError) {
      // Clear each flag only if the row still holds what we just pushed — a
      // newer local write that arrived during the push keeps its flag and
      // re-syncs on the next pass (no silent data loss).
      if (c.progressDirty) {
        await db.clearProgressDirtyIfUnchanged(c.id,
            lastPageRead: c.lastPageRead);
      }
      if (c.bookmarkDirty) {
        await db.clearBookmarkDirtyIfUnchanged(c.id,
            isBookmarked: c.isBookmarked);
      }
      if (c.progressDirty && c.isRead) syncedReadMangaIds.add(c.mangaId);
    }
  }

  // Push tracker progress for each manga that had read chapters synced.
  // Gate on the "update after reading" toggle and whether the manga has any
  // tracker bindings. A tracker failure must never break the progress sync.
  if (syncedReadMangaIds.isEmpty) return;
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
  // If the FGS worker is mid-download of this chapter, stop it first so it can't
  // resurrect files we're about to delete (the worker honours `remove` via the
  // engine's per-chapter cancel).
  if (_useBgService) {
    await ref.read(backgroundDownloadControllerProvider).onRemoved(chapterId);
  }
  final chapter =
      await ref.read(offlineRepositoryProvider).chapterById(chapterId);
  if (chapter != null) await manager.deleteChapter(chapter);
  await ref.read(offlineDatabaseProvider).setChapterPinned(chapterId, false);
}

/// Remove a series from the library AND clean up its on-device downloads, so
/// they aren't left orphaned (the offline catalog is library-scoped). Clears
/// the keep-rule and deletes every device copy. The SERVER's own download is
/// left alone — it isn't tied to library membership (see #34, #36).
Future<void> removeMangaFromLibraryAndPurge(WidgetRef ref, int mangaId) async {
  await ref.read(mangaBookRepositoryProvider).removeMangaFromLibrary(mangaId);
  if (!ref.read(offlineActiveProvider)) return;
  final db = ref.read(offlineDatabaseProvider);
  await db.setKeepRule(mangaId, OfflineKeepRule.off, 3);
  // Purge every chapter that has any on-device footprint — not just the fully
  // downloaded ones. Queued / downloading / errored chapters must also be
  // cancelled and cleaned up, or an in-flight download could finish (and leave
  // files) after the series has already left the library.
  for (final c in await db.chaptersForManga(mangaId)) {
    if (c.deviceState != OfflineDeviceState.none) {
      await deleteChapterFromDevice(ref, c.id);
    }
  }
}

/// The offline download orchestrator, wired with real network dependencies:
/// `fetchChapterPages` for the page URL list and an auth'd HTTP GET for each
/// page's bytes. Null on web / when offline storage is unavailable, so callers
/// can `ref.read(offlineDownloadManagerProvider)?.downloadChapter(c)`.
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

/// Fetch one page image's bytes with the active auth, resolved at CALL time
/// (never baked) — mirrors `ServerImage`'s request building: base API WITHOUT
/// the `/api` suffix (page URLs already carry `/api/...`), ui_login token as a
/// `?token=` query param, basic / simple_login via headers. Throws
/// [PageAuthException] on 401 so the download engine refreshes the token and
/// retries; any other non-200 is a plain (transient) exception.
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

/// Manga ids that have at least one chapter downloaded on this device — used
/// by the "On device" library filter. Returns an empty set when offline is
/// unavailable so the filter is a no-op.
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

/// Every series with an offline footprint on this device — chapters present
/// (downloaded / in-flight) OR an active keep-rule — with per-series counts,
/// byte size, and the manga row (carrying the rule). The single source for the
/// Downloads → On device tab, which both shows what's downloaded AND manages the
/// keep-rules. Sorted active-first, then biggest, then strongest rule.
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

/// Stop auto-keeping [mangaId] offline but KEEP the chapters already fully
/// downloaded on the device. Unfinished (queued / partially-downloaded)
/// chapters are dropped — "keep what I already have", not "finish the rest".
///
/// Order is load-bearing (see the design's interleaving analysis):
/// 1. Quiesce the series' pipeline (cancel its queued/downloading chapters) so
///    the downloaded set can't grow underneath us.
/// 2. Pin every still-downloaded chapter — pinned is immune to reconcile
///    eviction. Done BEFORE clearing the rule, so any reconcile that interleaves
///    while we pin still sees the rule active (and so evicts nothing).
/// 3. Clear the rule (count is dormant while off; preserve it).
/// 4. Reconcile — now eviction-safe: desired set = pinned = all downloaded.
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
  // async on Android (the FGS worker may finish a chapter slightly later), so
  // re-read the downloaded set HERE and pin it inside the same transaction that
  // flips the rule off. That guarantees that the instant the rule is off, every
  // chapter the catalog shows as downloaded is already pinned (immune to
  // eviction) — so neither this call's reconcile nor a concurrent one can evict
  // a downloaded chapter. A chapter still finishing after this was in-flight at
  // detach time and is intentionally dropped.
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
}) {
  return OfflineReconciler(
    db: db,
    nets: nets,
    now: DateTime.now(),
    // Only QUEUE chapters here (mark them in the persistent backlog). Starting
    // the download is the caller's job (via downloadStarterProvider) — this core
    // must NOT start anything itself, so the Ref-less launch path and tests stay
    // in control. One failed queue-mark must NOT abort the rest.
    onDownload: (id) async {
      try {
        await coordinator.queueChapter(id);
      } catch (e) {
        logger.e('Offline: reconcile queue skipped for chapter $id: $e');
      }
    },
    onEvict: (id) async {
      try {
        final c = await repo.chapterById(id);
        if (c != null) await manager.deleteChapter(c);
      } catch (e) {
        logger.e('Offline: reconcile evict skipped for chapter $id: $e');
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
            .addChaptersBatchToDownloadQueue(ids));
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
