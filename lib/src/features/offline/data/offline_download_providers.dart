// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../constants/db_keys.dart';
import '../../../constants/endpoints.dart';
import '../../../constants/enum.dart';
import '../../../global_providers/global_providers.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/network/graphql_errors.dart';
import '../../../utils/logger/logger.dart';
import '../../../utils/misc/toast/toast.dart';
import '../../../utils/platform/is_android_native.dart';
import '../../auth/data/auth_credentials_store.dart';
import '../../library/presentation/library/controller/library_manga_list.dart';
import '../../manga_book/data/downloads/downloads_repository.dart';
import '../../manga_book/data/manga_book/manga_book_repository.dart';
import '../../manga_book/domain/chapter_batch/chapter_batch_model.dart';
import '../../manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import '../../manga_book/presentation/manga_details/controller/scanlator_dedup.dart';
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
import 'background/catchup_spec_writer.dart';
import 'background/catchup_work_spec.dart';
import 'chapter_commit.dart';
import 'chapter_download_engine.dart';
import 'offline_background_downloads.dart';
import 'offline_database.dart';
import 'offline_download_coordinator.dart';
import 'offline_download_manager.dart';
import 'offline_download_progress.dart';
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
/// Pass `userInitiated` when someone pressed something: it overrides the
/// backoff Android applies while the server is unreachable, which an automatic
/// pass must not.
final downloadStarterProvider =
    Provider<Future<void> Function({bool userInitiated})>((Ref ref) {
      return ({bool userInitiated = false}) async {
        if (!ref.read(offlineActiveProvider)) return;
        if (isAndroidNative) {
          await ref
              .read(backgroundDownloadControllerProvider)
              .requestStart(userInitiated: userInitiated);
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
  // The background worker must not outlive its world: drop its spec + ledger
  // so no stale-server obligations survive the clear.
  await CatchupStateStore(ref.read(sharedPreferencesProvider)).clearState();
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
  return ref
      .watch(offlineDatabaseProvider)
      .watchOfflineChapters()
      .map(
        (chapters) => chapters.any(
          (c) =>
              c.deviceState == OfflineDeviceState.queued ||
              c.deviceState == OfflineDeviceState.downloading,
        ),
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

/// Live download progress for a chapter as a fraction 0..1, or null when
/// nothing is downloading it right now — drives the determinate progress arc.
///
/// Reported by the downloader rather than counted from page rows: a chapter's
/// rows all appear together when it commits, so the catalog has nothing to
/// count while the download is in flight.
@riverpod
double? offlineChapterProgress(Ref ref, int chapterId) {
  if (!ref.watch(offlineActiveProvider)) return null;
  // Watch THIS chapter's entry, not the whole map. A chapter list holds a few
  // hundred of these, and reading the map wakes every one of them each time any
  // single chapter advances a page — so one download made the entire visible
  // list re-evaluate itself, hundreds of times a second.
  final progress = ref.watch(
    offlineDownloadProgressProvider.select((all) => all[chapterId]),
  );
  if (progress == null || progress.total <= 0) return null;
  return (progress.done / progress.total).clamp(0.0, 1.0);
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
    final fresh = await AsyncValue.guard(
      () => ref
          .read(mangaBookRepositoryProvider)
          .getChapter(chapterId: chapterId),
    );
    serverHasIt = fresh.value?.isDownloaded ?? serverHasIt;
  }
  if (!serverHasIt) {
    // Commit a server download too (grows the server library). The device copy
    // doesn't wait on it — the server streams pages from source meanwhile.
    await ref.read(downloadsRepositoryProvider).addChaptersBatchToDownloadQueue(
      [chapterId],
    );
  }
  // Queue it (drift `queued` is the single source of truth). On Android the
  // foreground-service worker owns the downloading; elsewhere the main-isolate
  // pump drains it. Both callers are the user pressing save or retry, which is
  // the one thing allowed to revive a terminally-failed chapter.
  await coordinator.queueChapter(chapterId, allowErrored: true);
  await ref.read(downloadStarterProvider)(userInitiated: true);
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
    final siblings = expandIdsAcrossScanlators(
      ref,
      mangaId: mangaId,
      chapterIds: [chapterId],
    )..remove(chapterId);
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
      // Offline, siblings are dirty-flagged like the chapter and retried later;
      // only an online-only failure has no fallback and must surface.
      if (!siblingsOk && !offline) {
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
    await db.clearProgressDirtyIfUnchanged(
      chapterId,
      lastPageRead: lastPageRead,
    );
    // Completion set isRead (and thus readStateDirty) too — clear that flag on
    // the same successful push so a completed read isn't re-pushed forever.
    if (markRead != null) {
      await db.clearReadStateDirtyIfUnchanged(chapterId, isRead: markRead);
    }
  }
  // Local capture already has it dirty-flagged for the next sync, so a
  // connection failure here isn't a lost write — don't surface it as one.
  if (result.hasError && offlineEnabled && db != null) {
    final e = result.error!;
    final cause = e is OperationMessageException ? e.exception : e;
    if (isConnectionError(cause)) return const AsyncValue.data(null);
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
    () => ref
        .read(mangaBookRepositoryProvider)
        .putChapter(
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
@visibleForTesting
Future<int?> whileReadingDeleteTarget(
  _Read read,
  int mangaId,
  int readChapterId,
  int slots,
) async {
  try {
    // Not the filtered/on-screen list: a filter can drop the just-read chapter
    // or turn "N back" into counting gaps instead of chapters.
    final listProvider = mangaChapterListProvider(mangaId: mangaId);
    var chapters = read(listProvider).value;
    // A chapter finished before the list resolves would otherwise be skipped
    // with no second chance.
    chapters ??= await read(listProvider.future);
    if (chapters == null) return null;

    final preferred = read(mangaPreferredScanlatorsProvider(mangaId: mangaId));
    final showAll = read(
      mangaShowAllScanlatorVersionsProvider(mangaId: mangaId),
    );
    // Pinned to the chapter actually being read: without it dedup can keep a
    // different group's copy of that number and drop this id from the list.
    final deduped = preferred.isEmpty || showAll
        ? chapters
        : applyPreferredScanlators(
            chapters,
            preferred,
            keepChapterId: readChapterId,
          );

    // Tie-broken by id: List.sort is unstable, so duplicate source orders would
    // otherwise let the Nth-back target move between reads.
    final inReadingOrder = [...deduped]
      ..sort((a, b) {
        final byOrder = a.sourceOrder.compareTo(b.sourceOrder);
        return byOrder != 0 ? byOrder : a.id.compareTo(b.id);
      });
    return chapterIdToDeleteWhileReading(
      inReadingOrder,
      true,
      readChapterId,
      slots,
    );
  } catch (e) {
    // Leaving the reader mid-await lands here too, so this is a warning rather
    // than an error — but it must be recorded, or a real failure looks exactly
    // like the bug this fixes.
    logger.w('Offline: resolving the delete-while-reading target failed: $e');
    return null;
  }
}

/// The server delete settings, loaded from the server (null offline / on error,
/// so the server delete simply doesn't run — it needs a connection anyway).
Future<DeleteChaptersSettings?> _serverDeleteSettings(_Read read) async {
  try {
    return await read(deleteChaptersSettingsControllerProvider.future);
  } catch (_) {
    return null;
  }
}

/// Lets the delete chain run off a WidgetRef mid-read or the root
/// [ProviderContainer] at reader exit, where the route's ref is already gone.
typedef _Read = T Function<T>(ProviderListenable<T> provider);

/// Chapters finished this session — shields them from keep-rule eviction
/// until next launch, so closing the reader doesn't yank one off the device.
final sessionReadChaptersProvider =
    NotifierProvider<SessionReadChapters, Set<int>>(SessionReadChapters.new);

class SessionReadChapters extends Notifier<Set<int>> {
  @override
  Set<int> build() => {};

  void record(int chapterId) {
    if (state.contains(chapterId)) return;
    state = {...state, chapterId};
  }
}

/// A while-reading delete, resolved to its target but not yet executed.
typedef PendingReadDelete = ({int mangaId, int chapterId, bool server});

/// While-reading deletes deferred until the reader closes — Komikku queues on
/// chapter finish and deletes in onActivityFinish, never mid-read.
final pendingReadDeletesProvider =
    NotifierProvider<PendingReadDeletes, Set<PendingReadDelete>>(
      PendingReadDeletes.new,
    );

class PendingReadDeletes extends Notifier<Set<PendingReadDelete>> {
  final Set<Future<void>> _resolving = {};

  @override
  Set<PendingReadDelete> build() => {};

  void enqueue(PendingReadDelete entry) {
    if (state.contains(entry)) return;
    state = {...state, entry};
  }

  /// Track a finish-time target resolution, so an exit flush can wait for
  /// entries still being computed instead of draining past them.
  void trackResolution(Future<void> work) {
    _resolving.add(work);
    work.whenComplete(() => _resolving.remove(work));
  }

  Future<void> get resolutionsSettled => Future.wait({..._resolving});

  Set<PendingReadDelete> drain() {
    final drained = state;
    state = {};
    return drained;
  }
}

/// Shields the chapter from keep-rule eviction and queues its while-reading
/// deletes. Targets resolve NOW, not at exit — the list/dedup state can shift
/// by then and pick the wrong chapter.
Future<void> noteChapterFinishedInReader(
  WidgetRef ref, {
  required int mangaId,
  required int chapterId,
}) {
  ref.read(sessionReadChaptersProvider.notifier).record(chapterId);
  final pending = ref.read(pendingReadDeletesProvider.notifier);
  final work = _resolveReadDeletes(
    ref,
    pending,
    mangaId: mangaId,
    chapterId: chapterId,
  );
  pending.trackResolution(work);
  return work;
}

Future<void> _resolveReadDeletes(
  WidgetRef ref,
  PendingReadDeletes pending, {
  required int mangaId,
  required int chapterId,
}) async {
  try {
    if (ref.read(offlineActiveProvider)) {
      final s = ref.read(localDeleteSettingsProvider);
      if (s.deleteWhileReading > 0) {
        final target = await whileReadingDeleteTarget(
          ref.read,
          mangaId,
          chapterId,
          s.deleteWhileReading,
        );
        if (target != null) {
          pending.enqueue((mangaId: mangaId, chapterId: target, server: false));
        }
      }
    }

    final serverSettings = await _serverDeleteSettings(ref.read);
    if (serverSettings != null && serverSettings.deleteWhileReading > 0) {
      final target = await whileReadingDeleteTarget(
        ref.read,
        mangaId,
        chapterId,
        serverSettings.deleteWhileReading,
      );
      if (target != null) {
        pending.enqueue((mangaId: mangaId, chapterId: target, server: true));
      }
    }
  } catch (e) {
    // A finish racing the reader's teardown can lose its ref mid-resolve;
    // skipping the delete is the safe side.
    logger.w('Offline: resolving while-reading deletes failed: $e');
  }
}

/// Runs the deferred while-reading deletes. The bookmark gate re-reads
/// settings now, so a bookmark added after finish still blocks the delete.
Future<void> flushPendingReadDeletes(ProviderContainer container) async {
  final notifier = container.read(pendingReadDeletesProvider.notifier);
  // A chapter finished right at exit may still be resolving its target; the
  // drain would strand that entry until some future reader session.
  await notifier.resolutionsSettled;
  final pending = notifier.drain();
  for (final p in pending) {
    if (p.server) {
      final s = await _serverDeleteSettings(container.read);
      await _deleteServerCopyIfDeletable(
        container.read,
        p.mangaId,
        p.chapterId,
        s?.deleteWithBookmark ?? false,
      );
    } else {
      final allow = container
          .read(localDeleteSettingsProvider)
          .deleteWithBookmark;
      await _deleteDeviceCopyIfDeletable(container.read, p.chapterId, allow);
    }
  }
}

// --- on-device (local) ------------------------------------------------------

/// Delete THIS phone's copy when a chapter is manually marked read.
Future<void> maybeDeleteOnManualLocal(
  WidgetRef ref, {
  required int chapterId,
}) async {
  if (!ref.read(offlineActiveProvider)) return;
  final s = ref.read(localDeleteSettingsProvider);
  if (!s.deleteManuallyMarkedRead) return;
  await _deleteDeviceCopyIfDeletable(ref.read, chapterId, s.deleteWithBookmark);
}

/// Delete a chapter's device copy iff it's downloaded and the bookmark gate
/// allows it. A manually-saved (pinned) chapter IS deleted on a new read and
/// un-pinned (via [deleteChapterFromDevice]) so the reconciler doesn't just
/// re-download it; the server copy is untouched.
Future<void> _deleteDeviceCopyIfDeletable(
  _Read read,
  int chapterId,
  bool allowBookmarked,
) async {
  try {
    if (read(offlineDownloadManagerProvider) == null) return;
    final c = await read(offlineRepositoryProvider).chapterById(chapterId);
    if (c == null || c.deviceState != OfflineDeviceState.downloaded) return;
    if (c.isBookmarked && !allowBookmarked) return;
    await _deleteChapterFromDeviceRead(read, chapterId);
  } catch (e) {
    // Best-effort — a failed auto-delete must never surface during reading.
    logger.e('Offline: on-device delete-on-read failed for $chapterId: $e');
  }
}

// --- server -----------------------------------------------------------------

/// Tell the SERVER to delete its copy of the chapter N slots behind the one just
/// read (per the WebUI's delete-while-reading). The cascade then drops the
/// device copy too.
/// Tell the SERVER to delete its copy when a chapter is manually marked read.
Future<void> maybeDeleteOnManualServer(
  WidgetRef ref, {
  required int? mangaId,
  required int chapterId,
}) async {
  if (mangaId == null) return;
  final s = await _serverDeleteSettings(ref.read);
  if (s == null || !s.deleteManuallyMarkedRead) return;
  await _deleteServerCopyIfDeletable(
    ref.read,
    mangaId,
    chapterId,
    s.deleteWithBookmark,
  );
}

/// Delete a chapter's SERVER copy iff downloaded and the bookmark gate allows
/// it, then cascade to drop the device copy. Gates off the UNFILTERED chapter
/// list so an active "hide read" filter can't cause a silent miss, and the
/// bookmark gate also honours a bookmark made offline that hasn't reached the
/// server yet.
Future<void> _deleteServerCopyIfDeletable(
  _Read read,
  int mangaId,
  int chapterId,
  bool allowBookmarked,
) async {
  try {
    final listProvider = mangaChapterListProvider(mangaId: mangaId);
    // Running at reader exit, the list may be mid-refetch — wait for it rather
    // than silently skipping the delete on a null .value.
    final chapters =
        read(listProvider).value ?? await read(listProvider.future);
    final idx = chapters?.indexWhere((e) => e.id == chapterId) ?? -1;
    if (chapters == null || idx < 0) return;
    final c = chapters[idx];
    if (!c.isDownloaded) return;
    var isBookmarked = c.isBookmarked;
    if (read(offlineActiveProvider)) {
      final row = await read(offlineRepositoryProvider).chapterById(chapterId);
      if (row?.isBookmarked ?? false) isBookmarked = true;
    }
    if (isBookmarked && !allowBookmarked) return;
    await read(mangaBookRepositoryProvider).deleteChapters([chapterId]);
    await _cascadeServerDeleteToDeviceRead(read, [chapterId]);
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
      final server = (await AsyncValue.guard(
        () => repo.getChapter(chapterId: c.id),
      )).asData?.value;
      if (server != null) {
        final serverRead = server.isRead.ifNull();
        final serverAhead = serverRead
            ? !c
                  .isRead // server finished it; our push would un-finish it
            : c.isRead
            // We finished it; a server partial position never outranks a
            // completion (marking read leaves lastPageRead low).
            ? false
            : server.lastPageRead.getValueOnNullOrNegative() > c.lastPageRead;
        if (serverAhead) {
          pushProgress = false;
          pushReadState = false;
          // The local change lost, so settle the whole row to the state we
          // just fetched — not merely drop the flags, which would leave the
          // stale local values (and their unread correction) frozen in place.
          await db.adoptServerReadState(
            c.id,
            expectedIsRead: c.isRead,
            expectedLastPageRead: c.lastPageRead,
            serverIsRead: serverRead,
            serverLastPageRead: server.lastPageRead.getValueOnNullOrNegative(),
          );
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
        await db.clearProgressDirtyIfUnchanged(
          c.id,
          lastPageRead: c.lastPageRead,
        );
      }
      if (c.readStateDirty) {
        await db.clearReadStateDirtyIfUnchanged(c.id, isRead: c.isRead);
      }
      if (c.bookmarkDirty) {
        await db.clearBookmarkDirtyIfUnchanged(
          c.id,
          isBookmarked: c.isBookmarked,
        );
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
  final enabledAfterReading = container
      .read(updateProgressAfterReadingProvider)
      .ifNull();

  for (final mangaId in syncedReadMangaIds) {
    try {
      final records = await container.read(
        mangaTrackRecordsProvider(mangaId: mangaId).future,
      );
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
Future<void> cascadeServerDeleteToDevice(WidgetRef ref, List<int> chapterIds) =>
    _cascadeServerDeleteToDeviceRead(ref.read, chapterIds);

Future<void> _cascadeServerDeleteToDeviceRead(
  _Read read,
  List<int> chapterIds,
) async {
  if (read(offlineDownloadManagerProvider) == null) return;
  for (final id in chapterIds) {
    await _deleteChapterFromDeviceRead(read, id);
  }
}

/// Remove a chapter's device copy (widget entry).
Future<void> deleteChapterFromDevice(WidgetRef ref, int chapterId) =>
    _deleteChapterFromDeviceRead(ref.read, chapterId);

Future<void> _deleteChapterFromDeviceRead(_Read read, int chapterId) async {
  final manager = read(offlineDownloadManagerProvider);
  if (manager == null) return;
  await _deleteChapterFromDeviceCore(
    manager: manager,
    db: read(offlineDatabaseProvider),
    repo: read(offlineRepositoryProvider),
    coordinator: _useBgService
        ? null
        : read(offlineDownloadCoordinatorProvider),
    bgController: _useBgService
        ? read(backgroundDownloadControllerProvider)
        : null,
    chapterId: chapterId,
  );
}

/// Same delete driven by a [ProviderContainer] so it survives the caller's
/// widget being disposed mid-purge (see [removeMangaFromLibraryAndPurge]).
Future<void> _deleteChapterFromDeviceContainer(
  ProviderContainer container,
  int chapterId,
) async {
  final manager = container.read(offlineDownloadManagerProvider);
  if (manager == null) return;
  await _deleteChapterFromDeviceCore(
    manager: manager,
    db: container.read(offlineDatabaseProvider),
    repo: container.read(offlineRepositoryProvider),
    coordinator: _useBgService
        ? null
        : container.read(offlineDownloadCoordinatorProvider),
    bgController: _useBgService
        ? container.read(backgroundDownloadControllerProvider)
        : null,
    chapterId: chapterId,
  );
}

/// Concrete-deps core so both entries share one delete path.
///
/// The sequence itself is unchanged from what shipped — bump, cancel,
/// tombstone, clear rows, delete files. The only addition is the per-chapter
/// lock, which is what stops a commit landing between the row clear and the
/// file delete and republishing the chapter the user just removed.
Future<void> _deleteChapterFromDeviceCore({
  required OfflineDownloadManager manager,
  required OfflineDatabase db,
  required OfflineRepository repo,
  required OfflineDownloadCoordinator? coordinator,
  required BackgroundDownloadController? bgController,
  required int chapterId,
}) async {
  // Bump the persistent download generation first so a re-queued download
  // outranks any still-in-flight event from the deleted one (survives restart).
  final newGen = await db.bumpChapterGeneration(chapterId);
  // Stop any in-flight download so it can't resurrect the files — Android via
  // the FGS worker, elsewhere the main-isolate coordinator.
  if (bgController != null) {
    await bgController.onRemoved(chapterId);
    // Tombstone the completion log at the new generation so a stale terminal
    // entry can't complete a later re-queued generation of this chapter.
    await bgController.recordChapterDeleted(chapterId, newGen);
  } else {
    await coordinator?.beginDelete(chapterId);
  }
  try {
    await ChapterFileLock.run(chapterId, () async {
      final chapter = await repo.chapterById(chapterId);
      if (chapter != null) await manager.deleteChapter(chapter);
      await db.setChapterPinned(chapterId, false);
    });
  } finally {
    coordinator?.endDelete(chapterId);
  }
}

/// Remove a series from the library AND clean up its on-device downloads, so
/// they aren't left orphaned. Clears the keep-rule and deletes every device
/// copy; the SERVER's own download is left alone (see #34, #36). Runs on a
/// [ProviderContainer] so a mid-purge navigation can't abort the cleanup.
Future<void> removeMangaFromLibraryAndPurge(
  ProviderContainer container,
  int mangaId,
) async {
  await container
      .read(mangaBookRepositoryProvider)
      .removeMangaFromLibrary(mangaId);
  // The add path invalidates this list; the remove path must too, or cached
  // consumers (library, duplicate scan) keep serving the removed entry.
  container.invalidate(libraryMangaListProvider);
  if (!container.read(offlineActiveProvider)) return;
  final db = container.read(offlineDatabaseProvider);
  await db.setKeepRule(mangaId, OfflineKeepRule.off, 3);
  // Purge every chapter with any on-device footprint, not just fully
  // downloaded ones — queued/downloading/errored must also be cancelled, or an
  // in-flight download could finish and leave files after the series left the
  // library.
  for (final c in await db.chaptersForManga(mangaId)) {
    if (c.deviceState != OfflineDeviceState.none) {
      await _deleteChapterFromDeviceContainer(container, c.id);
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

/// One HTTP client for every page of every chapter, kept open for the life of
/// the app.
///
/// `http.get` builds a client, opens a connection and closes it again per call,
/// so downloading meant a fresh TCP connection and a full TLS handshake for
/// EVERY page — dozens a second, all to the same host we were already talking
/// to. Reusing one client lets those connections stay open, which is what makes
/// the handshake cost disappear rather than merely shrink.
@Riverpod(keepAlive: true)
http.Client offlinePageClient(Ref ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
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

  final http.Response res;
  try {
    res = await ref
        .read(offlinePageClientProvider)
        .get(Uri.parse(fetchUrl), headers: headers);
  } on SocketException {
    // Dead network is not a page failure: park resumable (Android worker
    // parity) instead of burning retries into a terminal error that poisons
    // the rest of the queue chapter by chapter.
    throw const PageOfflineException();
  } on http.ClientException {
    throw const PageOfflineException();
  }
  if (res.statusCode == 401 || res.statusCode == 403) {
    throw const PageAuthException();
  }
  if (res.statusCode != 200) {
    throw Exception('offline page fetch failed ($pageUrl): ${res.statusCode}');
  }
  return (
    bytes: res.bodyBytes,
    ext: pageImageExt(res.headers['content-type'], res.bodyBytes),
  );
}

/// Manga ids with at least one chapter downloaded on this device — used by
/// the "On device" library filter and the on-device cover badge.
///
/// Gated on [offlineEnabledProvider], not [offlineActiveProvider]: what sits on
/// this device's disk is a purely local fact, so it must survive an unreachable
/// server and the cold start before `serverInstanceId` resolves. Empty set on
/// web / when init failed, so both callers no-op.
///
/// A live stream, not a one-shot read: the Library screen's on-device
/// badge/filter previously only ever saw the snapshot from when this provider
/// was first built, so a chapter finishing its download from the manga
/// details page or the Downloads screen never showed up on Library until the
/// next navigation or manual refresh. `distinct()` (by set content, not
/// identity) keeps a per-page write during an in-progress download — which
/// touches the same table but never changes which manga have a `downloaded`
/// chapter — from re-notifying watchers with an unchanged value.
@riverpod
Stream<Set<int>> offlineDeviceMangaIds(Ref ref) {
  if (!ref.watch(offlineEnabledProvider)) return Stream.value(const {});
  return ref
      .watch(offlineRepositoryProvider)
      .watchDeviceDownloadedMangaIds()
      .distinct(const SetEquality<int>().equals);
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
  Ref ref,
  int mangaId,
) async {
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
  Ref ref,
  int mangaId,
) {
  if (!ref.watch(offlineActiveProvider)) {
    return Stream.value((downloaded: 0, inFlight: 0));
  }
  return ref.watch(offlineDatabaseProvider).watchChaptersForManga(mangaId).map((
    rows,
  ) {
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
  WidgetRef ref,
  int mangaId,
  OfflineKeepRule rule,
  int count,
) async {
  if (!ref.read(offlineActiveProvider)) return;
  await ref.read(offlineDatabaseProvider).setKeepRule(mangaId, rule, count);
  await reconcileMangaWidget(ref, mangaId);
  // The background worker plans from the spec — a rule change re-snapshots it.
  await writeCatchupWorkSpec(ref.read);
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
  Future<void> Function(int chapterId, int generation)? removeFromWorker,
  Set<int> sessionProtected = const {},
  int deleteWhileReadingSlots = 0,
}) {
  return OfflineReconciler(
    db: db,
    nets: nets,
    sessionProtected: sessionProtected,
    deleteWhileReadingSlots: deleteWhileReadingSlots,
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
        // Bump before anything else, and unconditionally — an eviction is a
        // delete, so a producer still holding staging for this chapter has to
        // be outranked whether or not the Android worker is wired up here.
        final newGen = await db.bumpChapterGeneration(id);
        // Cancel the active downloader before removing files, or an in-flight
        // download re-writes the chapter after the purge. beginDelete claims
        // the desktop engine; removeFromWorker stops the Android FGS worker
        // (null in the launch/test core, where the coordinator is the only
        // downloader).
        await coordinator.beginDelete(id);
        if (removeFromWorker != null) await removeFromWorker(id, newGen);
        await ChapterFileLock.run(id, () async {
          final c = await repo.chapterById(id);
          if (c != null) await manager.deleteChapter(c);
        });
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
              logger.e(
                'Offline: reconcile server-download enqueue skipped: $e',
              );
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
    sessionProtected: ref.read(sessionReadChaptersProvider),
    deleteWhileReadingSlots: ref
        .read(localDeleteSettingsProvider)
        .deleteWhileReading,
    enqueueServerDownload: (ids) => ref
        .read(downloadsRepositoryProvider)
        .addChaptersBatchToDownloadQueue(ids),
    removeFromWorker: (id, gen) async {
      final ctrl = ref.read(backgroundDownloadControllerProvider);
      await ctrl.onRemoved(id);
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
    sessionProtected: ref.read(sessionReadChaptersProvider),
    deleteWhileReadingSlots: ref
        .read(localDeleteSettingsProvider)
        .deleteWhileReading,
    enqueueServerDownload: (ids) => ref
        .read(downloadsRepositoryProvider)
        .addChaptersBatchToDownloadQueue(ids),
    removeFromWorker: (id, gen) async {
      final ctrl = ref.read(backgroundDownloadControllerProvider);
      await ctrl.onRemoved(id);
      await ctrl.recordChapterDeleted(id, gen);
    },
  );
  // Start downloading the freshly-queued chapters. THIS was the missing wire
  // that made "Download all / unread" silently do nothing on Android.
  await ref.read(downloadStarterProvider)(userInitiated: true);
}

/// Container entry — same as [reconcileMangaWidget] but survives the caller's
/// widget being disposed, so a migrate/bulk-migrate reconcile still lands after
/// the user navigates away.
Future<void> reconcileMangaContainer(
  ProviderContainer container,
  int mangaId,
) async {
  if (!container.read(offlineActiveProvider)) return;
  final manager = container.read(offlineDownloadManagerProvider);
  final coordinator = container.read(offlineDownloadCoordinatorProvider);
  if (manager == null || coordinator == null) return;
  await reconcileMangaCore(
    db: container.read(offlineDatabaseProvider),
    repo: container.read(offlineRepositoryProvider),
    manager: manager,
    coordinator: coordinator,
    nets: container.read(safetyNetConfigProvider),
    mangaId: mangaId,
    sessionProtected: container.read(sessionReadChaptersProvider),
    deleteWhileReadingSlots: container
        .read(localDeleteSettingsProvider)
        .deleteWhileReading,
    enqueueServerDownload: (ids) => container
        .read(downloadsRepositoryProvider)
        .addChaptersBatchToDownloadQueue(ids),
    removeFromWorker: (id, gen) async {
      final ctrl = container.read(backgroundDownloadControllerProvider);
      await ctrl.onRemoved(id);
      await ctrl.recordChapterDeleted(id, gen);
    },
  );
  await container.read(downloadStarterProvider)();
}

/// Launch entry point (main.dart holds a ProviderContainer, not a Ref).
///
/// Deliberately passes no `enqueueServerDownload`: asking the server for a
/// chapter it doesn't have sends it out to the source, and doing that for the
/// whole library on every start re-issued the same request forever whenever the
/// server was behind — a permanent CPU load and an endless challenge-solving
/// storm for sources the reader never opened (#354). Filling the server is the
/// server's own job (`autoDownloadNewChapters`, bounded by
/// `autoDownloadNewChaptersLimit`); the request belongs to the moment a reader
/// asks for a series, not to the app starting. Everything else here is local:
/// evicting orphans and pulling chapters the server already holds.
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
      deleteWhileReadingSlots: container
          .read(localDeleteSettingsProvider)
          .deleteWhileReading,
      removeFromWorker: (id, gen) async {
        final ctrl = container.read(backgroundDownloadControllerProvider);
        await ctrl.onRemoved(id);
        await ctrl.recordChapterDeleted(id, gen);
      },
    );
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
