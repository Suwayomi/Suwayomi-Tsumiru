// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../constants/db_keys.dart';
import '../../../constants/endpoints.dart';
import '../../../constants/enum.dart';
import '../../../global_providers/global_providers.dart';
import '../../../graphql/__generated__/schema.graphql.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/logger/logger.dart';
import '../../../utils/misc/toast/toast.dart';
import '../../../utils/network/gateway_status.dart';
import '../../../utils/network/graphql_errors.dart';
import '../../../utils/platform/is_android_native.dart';
import '../../account/data/account_permission.dart';
import '../../auth/data/auth_credentials_store.dart';
import '../../auth/data/custom_headers_store.dart';
import '../../library/presentation/library/controller/library_manga_list.dart';
import '../../manga_book/data/downloads/downloads_repository.dart';
import '../../manga_book/data/manga_book/manga_book_repository.dart';
import '../../manga_book/domain/chapter_batch/chapter_batch_model.dart';
import '../../manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import '../../manga_book/presentation/manga_details/controller/scanlator_dedup.dart';
import '../../manga_book/presentation/manga_details/controller/scanlator_propagation.dart';
import '../../manga_book/presentation/reader/utils/reader_progress_queue.dart';
import '../../notifications/controller/notifications_controller.dart';
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
import 'offline_awaiting_server_downloads.dart';
import 'offline_background_downloads.dart';
import 'offline_chapter_catchup.dart';
import 'offline_database.dart';
import 'offline_download_coordinator.dart';
import 'offline_download_manager.dart';
import 'offline_download_permission.dart';
import 'offline_download_progress.dart';
import 'offline_page_store.dart';
import 'offline_reconciler.dart';
import 'offline_repository.dart';
import 'offline_runtime_storage.dart';
import 'offline_series_entry.dart';
import 'offline_settings_providers.dart';
import 'offline_storage_identity.dart';
import 'reconcile_types.dart';

part 'offline_download_providers.g.dart';

bool get _useBgService => isAndroidNative;

/// Routes downloads to the Android worker or the main-isolate pump.
/// User-initiated starts may override outage backoff; automatic starts must honor it.
final backgroundDownloadsPlatformProvider = Provider<bool>(
  (ref) => isAndroidNative,
);

final downloadStarterProvider =
    Provider<Future<void> Function({bool userInitiated})>((Ref ref) {
      return ({bool userInitiated = false}) async {
        if (!ref.read(offlineActiveProvider) ||
            !downloadPermissionAllowed(ref.container.read)) {
          return;
        }
        if (ref.read(backgroundDownloadsPlatformProvider)) {
          try {
            await writeCatchupWorkSpec(ref.read);
            await ref.read(notificationsControllerProvider).sync();
          } catch (error) {
            logger.e('Offline: scheduling queued downloads failed: $error');
            final locales = WidgetsBinding.instance.platformDispatcher.locales;
            final l10n = lookupAppLocalizations(
              locales.isNotEmpty ? locales.first : const Locale('en'),
            );
            ref
                .read(toastProvider)
                ?.showError(l10n.backgroundDownloadScheduleFailed);
          }
          await ref
              .read(backgroundDownloadControllerProvider)
              .requestStart(userInitiated: userInitiated);
        } else {
          await ref.read(offlineDownloadCoordinatorProvider)?.pumpDownloads();
        }
      };
    });

/// Persists pause and applies it immediately to the active download pipeline.
Future<void> setOfflineDownloadsPaused(WidgetRef ref, bool paused) async {
  final saved = await ref
      .read(sharedPreferencesProvider)
      .setBool(DBKeys.offlineDownloadsPaused.name, paused);
  if (!saved) throw StateError('Could not persist download pause');
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
  if (isAndroidNative) {
    await writeCatchupWorkSpec(ref.read);
    await ref.read(notificationsControllerProvider).sync();
  }
}

Future<void> clearOfflineCatalog(WidgetRef ref) async {
  if (!ref.read(offlineEnabledProvider)) return;

  final background = ref.read(backgroundDownloadControllerProvider);
  await background.withOwnership(() async {
    await CatchupStateStore(ref.read(sharedPreferencesProvider)).clearState();
    await clearOfflineCatalogWithDependencies(
      stopBackground: background.stopAndClearWorkOrder,
      stopMainPump: () async {
        final coordinator = ref.read(offlineDownloadCoordinatorProvider);
        await coordinator?.pauseAndDrain();
      },
      clearDatabase: ref.read(offlineDatabaseProvider).clearAll,
      // File cleanup must not prevent identity reset after the database has been cleared.
      clearFiles: () async {
        try {
          await ref.read(offlinePageStoreProvider).clearAll();
        } catch (e) {
          logger.e('Offline: clearing downloaded files failed: $e');
        }
      },
      clearIdentity: () async {
        final preferences = ref.read(sharedPreferencesProvider);
        await preferences.remove(offlineCatalogServerIdKey(preferences));
        await preferences.remove(
          DBKeys.offlineServerMismatchDismissedList.name,
        );
      },
      finish: background.finishCatalogClear,
    );
  });
  // Old worker obligations must not survive a storage identity reset.
  await CatchupStateStore(ref.read(sharedPreferencesProvider)).clearState();
  ref.invalidate(offlineActiveProvider);
  ref.invalidate(offlineReadDatabaseProvider);
  if (isAndroidNative) {
    await ref.read(notificationsControllerProvider).sync();
  }
}

Future<void> clearOfflineCatalogWithDependencies({
  required Future<void> Function() stopBackground,
  required Future<void> Function() stopMainPump,
  required Future<void> Function() clearDatabase,
  required Future<void> Function() clearFiles,
  required Future<void> Function() clearIdentity,
  required void Function() finish,
}) async {
  // finish() must clear restart suppression even if stopBackground throws.
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

/// False when offline storage is unavailable.
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

/// Reads local state before server identity is verified; none if storage is unavailable.
@riverpod
Stream<OfflineDeviceState> offlineChapterState(Ref ref, int chapterId) {
  if (!ref.watch(offlineEnabledProvider)) {
    return Stream.value(OfflineDeviceState.none);
  }
  return ref.watch(offlineRepositoryProvider).watchChapterState(chapterId);
}

/// Progress in 0..1, or null when inactive; page rows appear only at commit.
@riverpod
double? offlineChapterProgress(Ref ref, int chapterId) {
  if (!ref.watch(offlineEnabledProvider)) return null;
  // Select one chapter so each page update does not rebuild the entire chapter list.
  final progress = ref.watch(
    offlineDownloadProgressProvider.select((all) => all[chapterId]),
  );
  if (progress == null || progress.total <= 0) return null;
  return (progress.done / progress.total).clamp(0.0, 1.0);
}

/// Pins a manual save; queues server fetching if needed. No-op without a synced local row.
Future<void> saveChapterToDevice(WidgetRef ref, int chapterId) {
  final read = ProviderScope.containerOf(ref.context, listen: false).read;
  return _trackForegroundWrite(read, (current) async {
    final coordinator = read(offlineDownloadCoordinatorProvider);
    if (coordinator == null) return;
    final repo = read(offlineRepositoryProvider);
    final db = read(offlineDatabaseProvider);
    final chapter = await repo.chapterById(chapterId);
    if (!current() || chapter == null) return;
    try {
      await verifyDownloadPermission(read);
      if (!current()) return;
      final pinned = await db.transaction(() async {
        final latest = await db.chapterById(chapterId);
        if (!current() ||
            latest == null ||
            latest.downloadGeneration != chapter.downloadGeneration) {
          return false;
        }
        await db.setChapterPinned(chapterId, true);
        return true;
      });
      if (!current() || !pinned) return;
      var serverHasIt = chapter.serverIsDownloaded;
      if (serverHasIt) {
        final fresh = await read(
          mangaBookRepositoryProvider,
        ).getChapter(chapterId: chapterId);
        if (!current()) return;
        serverHasIt = fresh?.user.isDownloaded ?? serverHasIt;
      }
      if (!serverHasIt) {
        await verifyDownloadPermission(read);
        if (!current()) return;
        await read(
          downloadsRepositoryProvider,
        ).addChaptersBatchToDownloadQueue([chapterId]);
        if (!current()) return;
      }
      // Adoption is best-effort: the active worker may hold the storage lock, but queueing remains valid.
      await adoptWorkerObligations(read);
      final queuedGeneration = await db.transaction(() async {
        final latest = await db.chapterById(chapterId);
        if (!current() ||
            latest == null ||
            latest.downloadGeneration != chapter.downloadGeneration) {
          return null;
        }
        await db.resetServerFetchAttempts(chapterId);
        await coordinator.queueChapter(
          chapterId,
          allowErrored: true,
          expectedGeneration: chapter.downloadGeneration,
        );
        final queued = await db.chapterById(chapterId);
        return queued?.deviceState == OfflineDeviceState.queued
            ? queued!.downloadGeneration
            : null;
      });
      if (!current() || queuedGeneration == null) return;
      final queued = await db.chapterById(chapterId);
      if (current() &&
          queued?.downloadGeneration == queuedGeneration &&
          queued?.deviceState == OfflineDeviceState.queued) {
        await read(downloadStarterProvider)(userInitiated: true);
      }
    } catch (error) {
      final cause = error is OperationMessageException
          ? error.exception
          : error;
      if (current() && isPermissionDenied(cause)) {
        await pauseDownloadsForPermission(read);
        await db.transaction(() async {
          if (!current()) return;
          final latest = await db.chapterById(chapterId);
          if (latest == null ||
              latest.downloadGeneration != chapter.downloadGeneration ||
              latest.deviceState == OfflineDeviceState.downloaded) {
            return;
          }
          await db.setChapterDeviceState(chapterId, OfflineDeviceState.error);
        });
      }
      rethrow;
    }
  });
}

/// Persists locally before pushing; failed pushes remain dirty for the next sync.
Future<AsyncValue<void>> recordReadingProgress(
  WidgetRef ref, {
  required int mangaId,
  required int chapterId,
  required int lastPageRead,
  required bool isRead,
  int? generation,
}) {
  final queue = ref
      .read(readerProgressQueuesProvider)
      .putIfAbsent(chapterId, ReaderProgressQueue.new);
  final expectedGeneration = generation ?? queue.generation;
  if (queue.syncing || expectedGeneration != queue.generation) {
    return Future.value(const AsyncValue.data(null));
  }
  final current = ref
      .read(authCredentialsStoreProvider.notifier)
      .captureSession();
  if (!current()) return Future.value(const AsyncValue.data(null));
  final offline = ref.read(offlineActiveProvider);
  final db = offline ? ref.read(offlineDatabaseProvider) : null;
  final repository = ref.read(mangaBookRepositoryProvider);
  final completionChapterIds = isRead
      ? expandIdsAcrossScanlators(
          ref,
          mangaId: mangaId,
          chapterIds: [chapterId],
        )
      : null;
  return ref
      .read(offlineRuntimeStorageProvider.notifier)
      .track(
        () => queue.run(() {
          if (expectedGeneration != queue.generation) {
            return Future.value(const AsyncValue<void>.data(null));
          }
          return recordReadingProgressWithDependencies(
          offlineEnabled: offline,
          offlineDatabase: db,
          repository: repository,
          chapterId: chapterId,
          lastPageRead: lastPageRead,
          isRead: isRead,
          completionChapterIds: completionChapterIds,
          isCurrentSession: current,
          );
        }),
      );
}

/// Returns push failures so online-only callers can surface unsaved progress.
Future<AsyncValue<void>> recordReadingProgressWithDependencies({
  required bool offlineEnabled,
  required OfflineDatabase? offlineDatabase,
  required MangaBookRepository repository,
  required int chapterId,
  required int lastPageRead,
  required bool isRead,
  List<int>? completionChapterIds,
  bool Function()? isCurrentSession,
}) async {
  bool current() => isCurrentSession?.call() ?? true;
  if (!current()) return const AsyncValue.data(null);
  // Complete hidden scanlator duplicates in one batch so partial failures cannot split read state.
  if (isRead &&
      completionChapterIds != null &&
      completionChapterIds.length > 1) {
    final result = await _recordReadStateResultWithDependencies(
      offlineEnabled: offlineEnabled,
      offlineDatabase: offlineDatabase,
      repository: repository,
      chapterIds: completionChapterIds,
      isRead: true,
      resetPosition: false,
      manual: false,
      isCurrentSession: isCurrentSession,
    );
    if (!current()) return const AsyncValue.data(null);
    if (result.hasError && offlineEnabled && offlineDatabase != null) {
      final e = result.error!;
      final cause = e is OperationMessageException ? e.exception : e;
      if (!isConnectionError(cause)) return result;
    } else if (result.hasError) {
    return result;
    }
  }

  // Reading forward changes position only until completion; mark-unread is a separate action.
  final bool? markRead = isRead ? true : null;
  final db = offlineDatabase;
  if (offlineEnabled && db != null) {
    await db.setChapterProgress(
      chapterId,
      lastPageRead: lastPageRead,
      isRead: markRead,
    );
  }
  if (!current()) return const AsyncValue.data(null);
  final result = await AsyncValue.guard(
    () => repository.putChapter(
      chapterId: chapterId,
      // Omit isRead entirely for partial progress so server read state stays intact.
      patch: markRead == null
          ? ChapterChange(lastPageRead: lastPageRead)
          : ChapterChange(lastPageRead: lastPageRead, isRead: markRead),
    ),
  );
  if (!current()) return const AsyncValue.data(null);
  if (offlineEnabled && db != null && !result.hasError) {
    await db.clearProgressDirtyIfUnchanged(
      chapterId,
      lastPageRead: lastPageRead,
    );
    if (!current()) return const AsyncValue.data(null);
    // Completion dirties read state too; clearing only progress would push the same completion again.
    if (markRead != null) {
      await db.clearReadStateDirtyIfUnchanged(chapterId, isRead: markRead);
    }
  }
  // Offline capture already persists this change for retry.
  if (result.hasError && offlineEnabled && db != null) {
    final e = result.error!;
    final cause = e is OperationMessageException ? e.exception : e;
    if (isConnectionError(cause)) return const AsyncValue.data(null);
  }
  return result;
}

/// Persists locally before pushing; failed pushes remain dirty for the next sync.
Future<void> recordBookmark(
  WidgetRef ref, {
  required int chapterId,
  required bool isBookmarked,
}) {
  final current = ref
      .read(authCredentialsStoreProvider.notifier)
      .captureSession();
  if (!current()) return Future.value();
  final offline = ref.read(offlineActiveProvider);
  final db = offline ? ref.read(offlineDatabaseProvider) : null;
  final repository = ref.read(mangaBookRepositoryProvider);
  return ref.read(offlineRuntimeStorageProvider.notifier).track(() async {
    if (!current()) return;
    if (db != null) await db.setChapterBookmark(chapterId, isBookmarked);
    if (!current()) return;
    final result = await AsyncValue.guard(
      () => repository.putChapter(
        chapterId: chapterId,
        patch: ChapterChange(isBookmarked: isBookmarked),
      ),
    );
    if (!current()) return;
    if (db != null && !result.hasError) {
      await db.clearBookmarkDirtyIfUnchanged(
        chapterId,
        isBookmarked: isBookmarked,
      );
    }
  });
}

/// Persists before pushing; failed writes stay dirty. Returns server success for tracker/delete gates.
/// [resetPosition] resets lastPageRead to 0.
Future<bool> recordReadStateWithDependencies({
  required bool offlineEnabled,
  required OfflineDatabase? offlineDatabase,
  required MangaBookRepository repository,
  required List<int> chapterIds,
  required bool isRead,
  bool resetPosition = false,
  bool Function()? isCurrentSession,
}) async {
  final result = await _recordReadStateResultWithDependencies(
    offlineEnabled: offlineEnabled,
    offlineDatabase: offlineDatabase,
    repository: repository,
    chapterIds: chapterIds,
    isRead: isRead,
    resetPosition: resetPosition,
    manual: true,
    isCurrentSession: isCurrentSession,
  );
  return !result.hasError;
}

Future<AsyncValue<void>> _recordReadStateResultWithDependencies({
  required bool offlineEnabled,
  required OfflineDatabase? offlineDatabase,
  required MangaBookRepository repository,
  required List<int> chapterIds,
  required bool isRead,
  required bool resetPosition,
  required bool manual,
  bool Function()? isCurrentSession,
}) async {
  bool current() => isCurrentSession?.call() ?? true;
  if (!current()) return const AsyncValue.data(null);
  final db = offlineDatabase;
  if (offlineEnabled && db != null) {
    for (final id in chapterIds) {
      if (!current()) return const AsyncValue.data(null);
      if (resetPosition) {
        await db.setChapterProgress(
          id,
          lastPageRead: 0,
          isRead: isRead,
          manual: manual,
        );
      } else {
        await db.setChapterReadState(id, isRead);
      }
    }
  }
  if (!current()) return const AsyncValue.data(null);
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
  if (!current()) return const AsyncValue.data(null);
  if (offlineEnabled && db != null && !result.hasError) {
    for (final id in chapterIds) {
      if (!current()) return const AsyncValue.data(null);
      await db.clearReadStateDirtyIfUnchanged(id, isRead: isRead);
      if (!current()) return const AsyncValue.data(null);
      if (resetPosition) {
        await db.clearProgressDirtyIfUnchanged(id, lastPageRead: 0);
      }
    }
  }
  return result;
}

Future<bool> recordReadState(
  WidgetRef ref, {
  required List<int> chapterIds,
  required bool isRead,
  bool resetPosition = false,
}) {
  final current = ref
      .read(authCredentialsStoreProvider.notifier)
      .captureSession();
  if (!current()) return Future.value(false);
  final offline = ref.read(offlineActiveProvider);
  final db = offline ? ref.read(offlineDatabaseProvider) : null;
  final repository = ref.read(mangaBookRepositoryProvider);
  return ref
      .read(offlineRuntimeStorageProvider.notifier)
      .track(
        () => recordReadStateWithDependencies(
          offlineEnabled: offline,
          offlineDatabase: db,
          repository: repository,
          chapterIds: chapterIds,
          isRead: isRead,
          resetPosition: resetPosition,
          isCurrentSession: current,
        ),
      );
}

// Device deletion follows local settings; server deletion cascades to device copies.

/// Resolves slots behind the read chapter (1 = just read); null if unavailable or out of range.
@visibleForTesting
Future<int?> whileReadingDeleteTarget(
  ReadFn read,
  int mangaId,
  int readChapterId,
  int slots,
) async {
  try {
    // Filters must not turn the N-back target into a count of visible gaps.
    final listProvider = mangaChapterListProvider(mangaId: mangaId);
    final preferred = read(mangaPreferredScanlatorsProvider(mangaId: mangaId));
    final showAll = read(
      mangaShowAllScanlatorVersionsProvider(mangaId: mangaId),
    );
    var chapters = read(listProvider).value;
    // Wait for the list: skipping an in-flight load would permanently miss this finish-time delete.
    chapters ??= await read(listProvider.future);
    if (chapters == null) return null;

    // Preserve the chapter being read even when its scanlator is hidden.
    final visible = preferred.isEmpty || showAll
        ? chapters
        : filterPreferredScanlators(
            chapters,
            preferred,
            keepChapterId: readChapterId,
          );

    // List.sort is unstable; id makes duplicate source-order targets deterministic.
    final inReadingOrder = [...visible]
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
    logger.w('Offline: resolving the delete-while-reading target failed: $e');
    return null;
  }
}

Future<DeleteChaptersSettings?> _serverDeleteSettings(ReadFn read) async {
  try {
    return await read(deleteChaptersSettingsControllerProvider.future);
  } catch (_) {
    return null;
  }
}

Future<void> _trackForegroundWrite(
  ReadFn read,
  Future<void> Function(bool Function()) action,
) {
  final current = read(authCredentialsStoreProvider.notifier).captureSession();
  if (!current()) return Future.value();
  return read(offlineRuntimeStorageProvider.notifier).track(() async {
    try {
      if (current()) await action(current);
    } catch (_) {
      if (current()) rethrow;
    }
  });
}

/// Supports reader-exit work after the route WidgetRef has been disposed.
typedef ReadFn = T Function<T>(ProviderListenable<T> provider);

/// Protects open chapters from rule eviction until reader disposal.
final sessionReadChaptersProvider =
    NotifierProvider<SessionReadChapters, Set<int>>(SessionReadChapters.new);

class SessionReadChapters extends Notifier<Set<int>> {
  @override
  Set<int> build() => {};

  void record(int chapterId) {
    if (state.contains(chapterId)) return;
    state = {...state, chapterId};
  }

  void discard(Set<int> chapterIds) {
    if (chapterIds.isEmpty) return;
    final next = state.difference(chapterIds);
    if (next.length != state.length) state = next;
  }
}

typedef PendingReadDelete = ({int mangaId, int chapterId, bool server});

/// Defers while-reading deletions until reader exit.
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

  /// Exit flush must await target resolutions still in progress.
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

/// Resolve targets at finish time; later list or scanlator changes must not alter them.
Future<void> noteChapterFinishedInReader(
  WidgetRef ref, {
  required int mangaId,
  required int chapterId,
}) {
  final read = ProviderScope.containerOf(ref.context, listen: false).read;
  final pending = read(pendingReadDeletesProvider.notifier);
  final work = _trackForegroundWrite(
    read,
    (current) => _resolveReadDeletes(
      read,
      pending,
      current,
      mangaId: mangaId,
      chapterId: chapterId,
    ),
  );
  pending.trackResolution(work);
  return work;
}

Future<void> _resolveReadDeletes(
  ReadFn read,
  PendingReadDeletes pending,
  bool Function() current, {
  required int mangaId,
  required int chapterId,
}) async {
  try {
    if (read(offlineActiveProvider)) {
      final s = read(localDeleteSettingsProvider);
      if (s.deleteWhileReading > 0) {
        final target = await whileReadingDeleteTarget(
          read,
          mangaId,
          chapterId,
          s.deleteWhileReading,
        );
        if (!current()) return;
        if (target != null) {
          pending.enqueue((mangaId: mangaId, chapterId: target, server: false));
        }
      }

      // Buffer one extra chapter at reading boundaries; exit reconciliation restores the normal window.
      final manager = read(offlineDownloadManagerProvider);
      final coordinator = read(offlineDownloadCoordinatorProvider);
      if (manager != null && coordinator != null && current()) {
        await reconcileMangaCore(
          db: read(offlineDatabaseProvider),
          repo: read(offlineRepositoryProvider),
          manager: manager,
          coordinator: coordinator,
          nets: read(safetyNetConfigProvider),
          mangaId: mangaId,
          sessionProtected: read(sessionReadChaptersProvider),
          deleteWhileReadingSlots: s.deleteWhileReading + 1,
          downloadProtectionWindow:
              read(localDownloadProtectionWindowProvider) ?? false,
          enqueueServerDownload: (ids) async {
            await read(
              downloadsRepositoryProvider,
            ).addChaptersBatchToDownloadQueue(ids);
            awaitingServerDownloads.add(mangaId);
            await persistAwaitingServerDownloads(read);
          },
          withOwnership: read(
            backgroundDownloadControllerProvider,
          ).withOwnership,
          removeFromWorker: (id, gen) async {
            final ctrl = read(backgroundDownloadControllerProvider);
            await ctrl.onRemoved(id);
            await ctrl.recordChapterDeleted(id, gen);
          },
        );
        if (!current()) return;
        await read(downloadStarterProvider)();
      }
    }

    if (!current()) return;
    final serverSettings = await _serverDeleteSettings(read);
    if (!current()) return;
    if (serverSettings != null && serverSettings.deleteWhileReading > 0) {
      final target = await whileReadingDeleteTarget(
        read,
        mangaId,
        chapterId,
        serverSettings.deleteWhileReading,
      );
      if (!current()) return;
      if (target != null) {
        pending.enqueue((mangaId: mangaId, chapterId: target, server: true));
      }
    }
  } catch (e) {
    // Reader teardown can dispose the ref during target resolution; skip deletion then.
    logger.w('Offline: resolving while-reading deletes failed: $e');
  }
}

/// Rechecks bookmarks at flush time so a bookmark added after finishing still protects the chapter.
Future<void> flushPendingReadDeletes(ProviderContainer container) =>
    _trackForegroundWrite(container.read, (current) async {
      final notifier = container.read(pendingReadDeletesProvider.notifier);
      await notifier.resolutionsSettled;
      if (!current()) return;
      final pending = notifier.drain();
      for (final p in pending) {
        if (!current()) return;
        if (p.server) {
          final s = await _serverDeleteSettings(container.read);
          if (!current()) return;
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
          await _deleteDeviceCopyIfDeletable(
            container.read,
            p.chapterId,
            allow,
          );
        }
      }
    });


/// Pass container.read for work that can outlive its widget.
Future<void> maybeDeleteOnManualLocal(ReadFn read, {required int chapterId}) =>
    _trackForegroundWrite(read, (current) async {
      if (!read(offlineActiveProvider)) return;
      final s = read(localDeleteSettingsProvider);
      if (!s.deleteManuallyMarkedRead) return;
      await _deleteDeviceCopyIfDeletable(read, chapterId, s.deleteWithBookmark);
    });

// Delete-on-read also unpins manual saves so reconciliation does not download them again.
Future<void> _deleteDeviceCopyIfDeletable(
  ReadFn read,
  int chapterId,
  bool allowBookmarked,
) => _trackForegroundWrite(read, (current) async {
  try {
    if (read(offlineDownloadManagerProvider) == null) return;
    final c = await read(offlineRepositoryProvider).chapterById(chapterId);
    if (!current()) return;
    if (c == null || c.deviceState != OfflineDeviceState.downloaded) return;
    if (c.isBookmarked && !allowBookmarked) return;
    await _deleteChapterFromDeviceRead(read, chapterId);
  } catch (e) {
    logger.e('Offline: on-device delete-on-read failed for $chapterId: $e');
  }
});


/// Deletes the server copy and cascades to the device; pass container.read after async widget work.
Future<void> maybeDeleteOnManualServer(
  ReadFn read, {
  required int? mangaId,
  required int chapterId,
}) => _trackForegroundWrite(read, (current) async {
  if (mangaId == null) return;
  final s = await _serverDeleteSettings(read);
  if (!current()) return;
  if (s == null || !s.deleteManuallyMarkedRead) return;
  await _deleteServerCopyIfDeletable(
    read,
    mangaId,
    chapterId,
    s.deleteWithBookmark,
  );
});

// Use the unfiltered list and pending local bookmarks when deciding whether to delete.
Future<void> _deleteServerCopyIfDeletable(
  ReadFn read,
  int mangaId,
  int chapterId,
  bool allowBookmarked,
) => _trackForegroundWrite(read, (current) async {
  try {
    final listProvider = mangaChapterListProvider(mangaId: mangaId);
    // At reader exit the chapter list may be refetching; await it before deciding.
    final chapters =
        read(listProvider).value ?? await read(listProvider.future);
    if (!current()) return;
    final idx = chapters?.indexWhere((e) => e.id == chapterId) ?? -1;
    if (chapters == null || idx < 0) return;
    final c = chapters[idx];
    if (!c.user.isDownloaded) return;
    var isBookmarked = c.user.isBookmarked;
    if (read(offlineActiveProvider)) {
      final row = await read(offlineRepositoryProvider).chapterById(chapterId);
      if (!current()) return;
      if (row?.isBookmarked ?? false) isBookmarked = true;
    }
    if (isBookmarked && !allowBookmarked) return;
    await read(mangaBookRepositoryProvider).deleteChapters([chapterId]);
    if (!current()) return;
    await cascadeServerDeleteToDevice(read, [chapterId]);
  } catch (e) {
    logger.e('Offline: server delete-on-read failed for $chapterId: $e');
  }
});

/// Pushes pending changes and nudges trackers for successfully synced read chapters.
Future<void> pushPendingProgress(
  ProviderContainer container, {
  bool suppressTrackerNudge = false,
}) => container
    .read(offlineRuntimeStorageProvider.notifier)
    .track(
      () => _pushPendingProgress(
        container,
        suppressTrackerNudge: suppressTrackerNudge,
      ),
    );

Future<void> _pushPendingProgress(
  ProviderContainer container, {
  bool suppressTrackerNudge = false,
}) async {
  if (!container.read(offlineActiveProvider)) return;
  final auth = container.read(authCredentialsStoreProvider.notifier);
  final epoch = auth.sessionEpoch;
  bool current() => !auth.sessionChanging && auth.sessionEpoch == epoch;
  if (!current()) return;
  final db = container.read(offlineDatabaseProvider);
  final repo = container.read(mangaBookRepositoryProvider);

  final syncedReadMangaIds = <int>{};
  // Use persisted provenance to apply the same tracker gate as the original manual action.
  final syncedReadIsManual = <int, bool>{};

  for (final c in await db.dirtyChapters()) {
    if (!current()) return;
    var pushProgress = c.progressDirty;
    var pushReadState = c.readStateDirty;
    // Furthest read wins across devices; bookmarks sync independently.
    if (pushProgress || pushReadState) {
      final server = (await AsyncValue.guard(
        () => repo.getChapter(chapterId: c.id),
      )).asData?.value;
      if (!current()) return;
      if (server != null) {
        final serverRead = server.user.isRead.ifNull();
        final serverAhead = serverRead
            ? !c
                  .isRead // server finished it; our push would un-finish it
            : c.isRead
            // Completion outranks any partial server position.
            ? false
            : server.user.lastPageRead.getValueOnNullOrNegative() >
                  c.lastPageRead;
        if (serverAhead) {
          pushProgress = false;
          pushReadState = false;
          // Settle values and baseline together; clearing flags alone leaves a stale unread correction.
          await db.adoptServerReadState(
            c.id,
            expectedIsRead: c.isRead,
            expectedLastPageRead: c.lastPageRead,
            serverIsRead: serverRead,
            serverLastPageRead: server.user.lastPageRead
                .getValueOnNullOrNegative(),
          );
        }
      }
    }
    if (!current()) return;
    if (!pushProgress && !pushReadState && !c.bookmarkDirty) continue;
    final result = await AsyncValue.guard(
      () => repo.putChapter(
        chapterId: c.id,
        patch: ChapterChange(
          // Send each field only under its own dirty flag; position writes must not upload stale read state.
          lastPageRead: pushProgress ? c.lastPageRead : null,
          isRead: pushReadState ? c.isRead : null,
          isBookmarked: c.bookmarkDirty ? c.isBookmarked : null,
        ),
      ),
    );
    if (!current()) return;
    if (!result.hasError) {
      // Concurrent local edits must remain dirty for the next pass.
      if (c.progressDirty) {
        await db.clearProgressDirtyIfUnchanged(
          c.id,
          lastPageRead: c.lastPageRead,
        );
      }
      if (!current()) return;
      if (c.readStateDirty) {
        await db.clearReadStateDirtyIfUnchanged(c.id, isRead: c.isRead);
      }
      if (!current()) return;
      if (c.bookmarkDirty) {
        await db.clearBookmarkDirtyIfUnchanged(
          c.id,
          isBookmarked: c.isBookmarked,
        );
      }
      if (c.readStateDirty && c.isRead) {
        syncedReadMangaIds.add(c.mangaId);
        syncedReadIsManual[c.mangaId] =
            (syncedReadIsManual[c.mangaId] ?? false) || c.readStateManual;
      }
    }
  }

  // Migration flushes progress without touching the source entry's trackers.
  if (!current()) return;
  if (suppressTrackerNudge || syncedReadMangaIds.isEmpty) return;
  final enabledAfterReading = container
      .read(updateProgressAfterReadingProvider)
      .ifNull();
  final enabledManualMarkRead = container
      .read(updateProgressManualMarkReadProvider)
      .ifNull();

  final tracker = container.read(trackerRepositoryProvider);
  for (final mangaId in syncedReadMangaIds) {
    if (!current()) return;
    try {
      final records = await container.read(
        mangaTrackRecordsProvider(mangaId: mangaId).future,
      );
      if (!current()) return;
      if (!shouldTrackProgress(
        isRead: true,
        enabledAfterReading: enabledAfterReading,
        enabledManualMarkRead: enabledManualMarkRead,
        manual: syncedReadIsManual[mangaId] ?? false,
        trackRecordCount: records.length,
      )) {
        continue;
      }
      final trackResult = await AsyncValue.guard(
        () => tracker.trackProgress(mangaId),
      );
      if (!current()) return;
      try {
        trackResult.showToastOnError(container.read(toastProvider));
      } catch (_) {
      }
    } catch (e) {
      // Tracker failures must not interrupt progress sync.
      logger.e('Offline: tracker push skipped for manga $mangaId: $e');
    }
  }
}

/// Cascades server deletion to device copies; pass container.read if the widget can be disposed.
Future<void> cascadeServerDeleteToDevice(ReadFn read, List<int> chapterIds) =>
    _trackForegroundWrite(read, (current) async {
      if (read(offlineDownloadManagerProvider) == null) return;
      for (final id in chapterIds) {
        if (!current()) return;
        await _deleteChapterFromDeviceRead(read, id);
      }
    });

Future<void> deleteChapterFromDevice(WidgetRef ref, int chapterId) =>
    _deleteChapterFromDeviceRead(ref.read, chapterId);

Future<void> _deleteChapterFromDeviceRead(ReadFn read, int chapterId) =>
    _trackForegroundWrite(read, (current) async {
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
    });

Future<void> _deleteChapterFromDeviceContainer(
  ProviderContainer container,
  int chapterId,
) => _deleteChapterFromDeviceRead(container.read, chapterId);

// Hold the chapter lock across row and file deletion so commits cannot republish it.
Future<void> _deleteChapterFromDeviceCore({
  required OfflineDownloadManager manager,
  required OfflineDatabase db,
  required OfflineRepository repo,
  required OfflineDownloadCoordinator? coordinator,
  required BackgroundDownloadController? bgController,
  required int chapterId,
}) async {
  if (bgController != null) {
    await bgController.withOwnership(
      () => _deleteChapterFromDeviceOwned(
        manager: manager,
        db: db,
        repo: repo,
        coordinator: coordinator,
        bgController: bgController,
        chapterId: chapterId,
      ),
    );
    return;
  }
  await _deleteChapterFromDeviceOwned(
    manager: manager,
    db: db,
    repo: repo,
    coordinator: coordinator,
    bgController: null,
    chapterId: chapterId,
  );
}

Future<void> _deleteChapterFromDeviceOwned({
  required OfflineDownloadManager manager,
  required OfflineDatabase db,
  required OfflineRepository repo,
  required OfflineDownloadCoordinator? coordinator,
  required BackgroundDownloadController? bgController,
  required int chapterId,
}) async {
  // Bump before cancellation so re-queued work outranks all events from this download.
  final newGen = await db.bumpChapterGeneration(chapterId);
  if (bgController != null) {
    await bgController.onRemoved(chapterId);
    // Persist the new tombstone so replay rejects pre-delete terminal events.
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

/// Removes library membership and device copies while preserving server downloads.
/// Uses a container so navigation cannot interrupt cleanup.
Future<void> removeMangaFromLibraryAndPurge(
  ProviderContainer container,
  int mangaId,
) => _trackForegroundWrite(
  container.read,
  (current) => container
      .read(backgroundDownloadControllerProvider)
      .withOwnership(
        () => _removeMangaFromLibraryAndPurgeOwned(container, mangaId, current),
      ),
);

Future<void> _removeMangaFromLibraryAndPurgeOwned(
  ProviderContainer container,
  int mangaId,
  bool Function() current,
) async {
  if (!current()) return;
  final db = container.read(offlineActiveProvider)
      ? container.read(offlineDatabaseProvider)
      : null;
  await container
      .read(mangaBookRepositoryProvider)
      .removeMangaFromLibrary(mangaId);
  if (!current()) return;
  container.invalidate(libraryMangaListProvider);
  if (db == null) return;
  await db.setKeepRule(mangaId, OfflineKeepRule.off, 3);
  // Cancel incomplete downloads too, or in-flight work can recreate files after removal.
  if (!current()) return;
  for (final c in await db.chaptersForManga(mangaId)) {
    if (!current()) return;
    if (c.deviceState != OfflineDeviceState.none) {
      await _deleteChapterFromDeviceContainer(container, c.id);
    }
  }
  if (!current()) return;
  await writeCatchupWorkSpec(container.read);
}

/// Null on web or when offline storage is unavailable.
@riverpod
OfflineDownloadManager? offlineDownloadManager(Ref ref) {
  if (!ref.watch(offlineActiveProvider)) return null;
  final isCurrentSession = watchAuthSession(ref);
  final repo = ref.watch(mangaBookRepositoryProvider);
  final read = ref.container.read;
  return OfflineDownloadManager(
    db: ref.watch(offlineDatabaseProvider),
    store: ref.watch(offlinePageStoreProvider),
    fetchPageUrls: (chapterId) async {
      if (!isCurrentSession()) {
        throw StateError('Authentication session changed');
      }
      await verifyDownloadPermission(read);
      if (!isCurrentSession()) {
        throw StateError('Authentication session changed');
      }
      final result = await repo.getChapterPages(chapterId: chapterId);
      if (result == null) throw const AccountPermissionUnavailable();
      return result.pages;
    },
    fetchBytes: (url) =>
        fetchOfflinePageBytes(ref, url, isCurrentSession: isCurrentSession),
  );
}

// Reuse connections across page requests instead of repeating TCP/TLS setup.
@Riverpod(keepAlive: true)
http.Client offlinePageClient(Ref ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
}

/// Resolves current auth per request; 401 throws [PageAuthException] for refresh/retry.
Future<PageBytes> fetchOfflinePageBytes(
  Ref ref,
  String pageUrl, {
  required bool Function() isCurrentSession,
}) async {
  if (!isCurrentSession()) throw StateError('Authentication session changed');
  final authType = ref.read(authTypeKeyProvider);
  final basicToken = ref.read(credentialsProvider).value;
  final creds = ref.read(authCredentialsStoreProvider).value;
  final base = Endpoints.baseApi(
    baseUrl: ref.read(serverUrlProvider),
    port: ref.read(serverPortProvider),
    addPort: ref.read(serverPortToggleProvider).ifNull(),
    appendApiToUrl: false,
  );
  final fetchUrl = '$base$pageUrl';

  final headers = <String, String>{};
  if (authType == AuthType.basic && basicToken != null) {
    headers['Authorization'] = basicToken;
  } else if (authType == AuthType.simpleLogin) {
    final cookie = creds?.simpleLoginCookieHeader;
    if (cookie != null) headers.addAll(cookie);
  } else if (authType == AuthType.uiLogin &&
      (creds?.uiAccessToken?.isNotEmpty ?? false)) {
    headers['Authorization'] = 'Bearer ${creds!.uiAccessToken}';
  }
  applyCustomHeaders(headers, ref.read(customHttpHeadersProvider).value);

  final http.Response res;
  try {
    res = await ref
        .read(offlinePageClientProvider)
        .get(Uri.parse(fetchUrl), headers: headers)
        .timeout(const Duration(seconds: 30));
  } on SocketException catch (e) {
    // Connection loss parks resumable work rather than consuming page-failure retries.
    throw PageOfflineException('SocketException: $e');
  } on http.ClientException catch (e) {
    throw PageOfflineException('ClientException: $e');
  } on TimeoutException {
    throw const PageOfflineException('timed out after 30s on page fetch');
  }
  if (!isCurrentSession()) throw StateError('Authentication session changed');
  if (res.statusCode == 403) {
    throw const AccountPermissionDenied(Enum$UserPermission.DOWNLOAD_CHAPTERS);
  }
  if (res.statusCode == 401) {
    throw const PageAuthException();
  }
  if (isGatewayStatus(res.statusCode)) {
    throw PageOfflineException('HTTP ${res.statusCode} on page fetch');
  }
  if (res.statusCode != 200) {
    throw Exception('offline page fetch failed ($pageUrl): ${res.statusCode}');
  }
  return (
    bytes: res.bodyBytes,
    ext: pageImageExt(res.headers['content-type'], res.bodyBytes),
  );
}

/// Local downloads remain visible before identity verification and during server outages.
@riverpod
Stream<Set<int>> offlineDeviceMangaIds(Ref ref) {
  if (!ref.watch(offlineEnabledProvider)) return Stream.value(const {});
  return ref
      .watch(offlineRepositoryProvider)
      .watchDeviceDownloadedMangaIds()
      .distinct(const SetEquality<int>().equals);
}

@riverpod
Future<OfflineKeepRule> mangaKeepRule(Ref ref, int mangaId) async {
  if (!ref.watch(offlineActiveProvider)) return OfflineKeepRule.off;
  return ref.watch(offlineRepositoryProvider).keepRuleFor(mangaId);
}

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

@riverpod
Future<int> mangaDownloadedCount(Ref ref, int mangaId) async {
  if (!ref.watch(offlineActiveProvider)) return 0;
  return (await ref
          .watch(offlineDatabaseProvider)
          .downloadedChaptersForManga(mangaId))
      .length;
}

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

// Manual provider: riverpod_generator cannot resolve the drift type before its generation phase.
final offlineChaptersForMangaProvider =
    StreamProvider.family<List<OfflineChapter>, int>((ref, mangaId) {
      if (!ref.watch(offlineEnabledProvider)) return Stream.value(const []);
      return ref
          .watch(offlineDatabaseProvider)
          .watchChaptersForManga(mangaId)
          .map(
            (rows) => rows
                .where((c) => c.deviceState != OfflineDeviceState.none)
                .toList(),
          );
    });

/// Includes content or an active keep-rule; sorted active-first, then by bytes and rule.
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
          failed: r.failed,
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

/// Keeps downloaded chapters, drops unfinished work, and disables the rule.
/// Pin before clearing the rule so concurrent reconciliation cannot evict retained chapters.
Future<void> detachKeepRule(WidgetRef ref, int mangaId) {
  final container = ProviderScope.containerOf(ref.context, listen: false);
  return _trackForegroundWrite(
    container.read,
    (current) => container
        .read(backgroundDownloadControllerProvider)
        .withOwnership(() => _detachKeepRuleOwned(container, mangaId, current)),
  );
}

Future<void> _detachKeepRuleOwned(
  ProviderContainer container,
  int mangaId,
  bool Function() current,
) async {
  if (!current()) return;
  if (!container.read(offlineActiveProvider)) return;
  final db = container.read(offlineDatabaseProvider);
  final repo = container.read(offlineRepositoryProvider);
  for (final c in await db.chaptersForManga(mangaId)) {
    if (!current()) return;
    if (c.deviceState == OfflineDeviceState.queued ||
        c.deviceState == OfflineDeviceState.downloading) {
      await _deleteChapterFromDeviceRead(container.read, c.id);
    }
  }
  if (!current()) return;
  final cfg = await repo.keepConfigFor(mangaId);
  // Re-read and pin atomically with clearing the rule; Android cancellation above is async.
  if (!current()) return;
  await db.transaction(() async {
    for (final c in await db.downloadedChaptersForManga(mangaId)) {
      await db.setChapterPinned(c.id, true);
    }
    await db.setKeepRule(mangaId, OfflineKeepRule.off, cfg.count);
  });
  if (!current()) return;
  await reconcileMangaContainer(container, mangaId);
}

Future<void> removeAllDownloadsFromDevice(WidgetRef ref) {
  final container = ProviderScope.containerOf(ref.context, listen: false);
  return _trackForegroundWrite(container.read, (current) async {
    final db = container.read(offlineDatabaseProvider);
    final mangas = await db.libraryManga();
    if (!current()) return;
    for (final manga in mangas) {
      if (!current()) return;
      final chapters = await db.downloadedChaptersForManga(manga.id);
      if (!current()) return;
      for (final chapter in chapters) {
        if (!current()) return;
        try {
          await _deleteChapterFromDeviceRead(container.read, chapter.id);
        } catch (_) {}
        if (!current()) return;
      }
    }
  });
}

/// Deletes device copies while leaving server copies untouched.
Future<void> removeKeepRuleAndDelete(WidgetRef ref, int mangaId) {
  final container = ProviderScope.containerOf(ref.context, listen: false);
  return _trackForegroundWrite(
    container.read,
    (current) => container
        .read(backgroundDownloadControllerProvider)
        .withOwnership(
          () => _removeKeepRuleAndDeleteOwned(container, mangaId, current),
        ),
  );
}

Future<void> _removeKeepRuleAndDeleteOwned(
  ProviderContainer container,
  int mangaId,
  bool Function() current,
) async {
  if (!current()) return;
  if (!container.read(offlineActiveProvider)) return;
  final db = container.read(offlineDatabaseProvider);
  final repo = container.read(offlineRepositoryProvider);
  if (!current()) return;
  final cfg = await repo.keepConfigFor(mangaId);
  if (!current()) return;
  await db.setKeepRule(mangaId, OfflineKeepRule.off, cfg.count);
  if (!current()) return;
  for (final c in await db.chaptersForManga(mangaId)) {
    if (!current()) return;
    if (c.deviceState != OfflineDeviceState.none) {
      await _deleteChapterFromDeviceRead(container.read, c.id);
    }
  }
  if (!current()) return;
  await writeCatchupWorkSpec(container.read);
}

Future<void> changeKeepRule(
  WidgetRef ref,
  int mangaId,
  OfflineKeepRule rule,
  int count,
) {
  final read = ProviderScope.containerOf(ref.context, listen: false).read;
  return _trackForegroundWrite(read, (current) async {
    if (!read(offlineActiveProvider)) return;
    if (rule != OfflineKeepRule.off) await verifyDownloadPermission(read);
    if (!current()) return;
    var reconciled = false;
    final starter = read(downloadStarterProvider);
    try {
      await read(backgroundDownloadControllerProvider).withOwnership(() async {
        if (!current()) return;
        await read(offlineDatabaseProvider).setKeepRule(mangaId, rule, count);
        if (!current()) return;
        await _reconcileAccountManga(read, mangaId, startDownload: false);
        if (!current()) return;
        reconciled = true;
        await writeCatchupWorkSpec(read);
      });
    } finally {
      if (reconciled && current()) await starter(userInitiated: true);
    }
  });
}

@riverpod
Future<int> offlineUsageBytes(Ref ref) async {
  if (!ref.watch(offlineActiveProvider)) return 0;
  return ref.read(offlineRepositoryProvider).totalDownloadedBytes();
}

@riverpod
Future<int> offlineMangaBytes(Ref ref, {required int mangaId}) async {
  if (!ref.watch(offlineActiveProvider)) return 0;
  return ref.read(offlineRepositoryProvider).downloadedBytesForManga(mangaId);
}

@riverpod
SafetyNetConfig safetyNetConfig(Ref ref) => SafetyNetConfig(
  timeEvictEnabled: ref.watch(offlineTimeEvictEnabledProvider) ?? false,
  keepDays: ref.watch(offlineKeepDaysProvider) ?? 30,
  storageCapEnabled: ref.watch(offlineStorageCapEnabledProvider) ?? false,
  storageCapBytes:
      (ref.watch(offlineStorageCapMbProvider) ?? 2000) * 1024 * 1024,
);

Future<void> reconcileMangaCore({
  required OfflineDatabase db,
  required OfflineRepository repo,
  required OfflineDownloadManager manager,
  required OfflineDownloadCoordinator coordinator,
  required SafetyNetConfig nets,
  required int mangaId,
  Future<void> Function(List<int> chapterIds)? enqueueServerDownload,
  Future<void> Function()? verifyPermission,
  Future<void> Function()? onPermissionDenied,
  bool Function()? isCurrent,
  Future<void> Function(int chapterId, int generation)? removeFromWorker,
  Future<void> Function(Future<void> Function())? withOwnership,
  Set<int> sessionProtected = const {},
  int deleteWhileReadingSlots = 0,
  Set<int> newlyReadChapterIds = const {},
  bool downloadProtectionWindow = false,
}) async {
  Future<void> verifyCurrentPermission() async {
    if (isCurrent?.call() == false) throw const AccountPermissionUnavailable();
    await verifyPermission?.call();
    if (isCurrent?.call() == false) throw const AccountPermissionUnavailable();
  }

  await verifyCurrentPermission();
  final keepConfig = await repo.keepConfigFor(mangaId);
  final originalChapters = {
    for (final chapter in await db.chaptersForManga(mangaId))
      chapter.id: chapter,
  };
  final generations = {
    for (final chapter in originalChapters.values)
      chapter.id: chapter.downloadGeneration,
  };
  await OfflineReconciler(
    db: db,
    nets: nets,
    sessionProtected: sessionProtected,
    deleteWhileReadingSlots: deleteWhileReadingSlots,
    newlyReadChapterIds: newlyReadChapterIds,
    downloadProtectionWindow: downloadProtectionWindow,
    now: DateTime.now(),
    // Only queue here; the caller owns starting downloads. Isolate individual queue failures.
    onDownload: (id) async {
      try {
        if (!generations.containsKey(id)) return;
        await coordinator.queueChapter(
          id,
          expectedGeneration: generations[id],
          expectedKeepConfig: keepConfig,
        );
      } catch (e) {
        logger.e('Offline: reconcile queue skipped for chapter $id: $e');
      }
    },
    onEvict: (id) async {
      Future<OfflineChapter?> currentEviction() async {
        final chapter = await repo.chapterById(id);
        final config = await repo.keepConfigFor(mangaId);
        final original = originalChapters[id];
        if (chapter == null ||
            original == null ||
            chapter.downloadGeneration != original.downloadGeneration ||
            chapter.pinned != original.pinned ||
            config != keepConfig) {
          return null;
        }
        return chapter;
      }

      Future<void> evict() async {
        await verifyCurrentPermission();
        if (await currentEviction() == null) return;
        try {
          await coordinator.beginDelete(id);
          await ChapterFileLock.run(id, () async {
            await verifyCurrentPermission();
            final c = await currentEviction();
            if (c == null) return;
            final newGen = await db.bumpChapterGeneration(id);
            if (removeFromWorker != null) await removeFromWorker(id, newGen);
            await manager.deleteChapter(c);
          });
        } catch (e) {
          final cause = e is OperationMessageException ? e.exception : e;
          if (cause is AccountPermissionUnavailable ||
              isPermissionDenied(cause)) {
            rethrow;
          }
          logger.e('Offline: reconcile evict skipped for chapter $id: $e');
        } finally {
          coordinator.endDelete(id);
        }
      }

      if (withOwnership != null) {
        await withOwnership(evict);
      } else {
        await evict();
      }
    },
    onServerDownload: enqueueServerDownload == null
        ? null
        : (ids) async {
            try {
              await enqueueServerDownload(ids.toList());
            } catch (e) {
              final cause = e is OperationMessageException ? e.exception : e;
              if (isPermissionDenied(cause)) {
                if (isCurrent == null || isCurrent()) {
                  await onPermissionDenied?.call();
                  await db.transaction(() async {
                    if (isCurrent != null && !isCurrent()) return;
                    for (final id in ids) {
                      final chapter = await db.chapterById(id);
                      if (chapter != null &&
                          chapter.downloadGeneration == generations[id] &&
                          chapter.deviceState !=
                              OfflineDeviceState.downloaded) {
                        await db.setChapterDeviceState(
                          id,
                          OfflineDeviceState.error,
                        );
                      }
                    }
                  });
                }
                throw cause;
              }
              if (cause is AccountPermissionUnavailable) throw cause;
              rethrow;
            }
          },
  ).reconcileManga(mangaId);
}

Future<void> reconcileManga(
  Ref ref,
  int mangaId, {
  Set<int> newlyReadChapterIds = const {},
}) => _reconcileAccountManga(
  ref.container.read,
  mangaId,
  newlyReadChapterIds: newlyReadChapterIds,
);

Future<void> reconcileMangaWidget(
  WidgetRef ref,
  int mangaId, {
  bool startDownload = true,
  Set<int> newlyReadChapterIds = const {},
}) => _reconcileAccountManga(
  ProviderScope.containerOf(ref.context, listen: false).read,
  mangaId,
  startDownload: startDownload,
  userInitiated: true,
  newlyReadChapterIds: newlyReadChapterIds,
);

Future<void> reconcileMangaContainer(
  ProviderContainer container,
  int mangaId,
) => _reconcileAccountManga(container.read, mangaId);

Future<void> _reconcileAccountManga(
  OfflineRead read,
  int mangaId, {
  bool startDownload = true,
  bool userInitiated = false,
  Set<int> newlyReadChapterIds = const {},
}) => read(offlineRuntimeStorageProvider.notifier).track(() async {
  if (!read(offlineActiveProvider) || !downloadPermissionAllowed(read)) return;
  final current = read(authCredentialsStoreProvider.notifier).captureSession();
  if (!current()) return;
  final manager = read(offlineDownloadManagerProvider);
  final coordinator = read(offlineDownloadCoordinatorProvider);
  if (manager == null || coordinator == null) return;
  final downloads = read(downloadsRepositoryProvider);
  final background = read(backgroundDownloadControllerProvider);
  final starter = read(downloadStarterProvider);
  final preferences = read(sharedPreferencesProvider);
  final awaitingKey = offlinePreferenceKey(
    read,
    DBKeys.offlineCatchUpAwaitingPull,
  );
  final reconciled = await background.withOwnership(() async {
    if (!await adoptWorkerObligations(read)) return false;
    await reconcileMangaCore(
      verifyPermission: () => verifyDownloadPermission(read),
      onPermissionDenied: () async {
        if (current()) await pauseDownloadsForPermission(read);
      },
      isCurrent: current,
      db: read(offlineDatabaseProvider),
      repo: read(offlineRepositoryProvider),
      manager: manager,
      coordinator: coordinator,
      nets: read(safetyNetConfigProvider),
      mangaId: mangaId,
      sessionProtected: read(sessionReadChaptersProvider),
      deleteWhileReadingSlots: read(
        localDeleteSettingsProvider,
      ).deleteWhileReading,
      newlyReadChapterIds: newlyReadChapterIds,
      downloadProtectionWindow:
          read(localDownloadProtectionWindowProvider) ?? false,
      enqueueServerDownload: (ids) async {
        if (!current()) throw StateError('Authentication session changed');
        await verifyDownloadPermission(read);
        if (!current()) throw StateError('Authentication session changed');
        await downloads.addChaptersBatchToDownloadQueue(ids);
        if (!current()) throw StateError('Authentication session changed');
        awaitingServerDownloads.add(mangaId);
        await preferences.setStringList(awaitingKey, [
          for (final id in awaitingServerDownloads) '$id',
        ]);
      },
      withOwnership: background.withOwnership,
      removeFromWorker: (id, gen) async {
        if (!current()) throw StateError('Authentication session changed');
        await background.onRemoved(id);
        if (!current()) throw StateError('Authentication session changed');
        await background.recordChapterDeleted(id, gen);
      },
    );
    return true;
  });
  if (reconciled && startDownload && current()) {
    await starter(userInitiated: userInitiated);
  }
});

/// Reconciles local content at launch without requesting source fetches from the server.
Future<void> reconcileAllAtLaunch(ProviderContainer container) => container
    .read(offlineRuntimeStorageProvider.notifier)
    .track(() => _reconcileAllAtLaunch(container));

Future<void> _reconcileAllAtLaunch(ProviderContainer container) async {
  final current = container
      .read(authCredentialsStoreProvider.notifier)
      .captureSession();
  if (!current()) return;
  if (!container.read(offlineServerAccessProvider) ||
      !downloadPermissionAllowed(container.read)) {
    return;
  }
  final manager = container.read(offlineDownloadManagerProvider);
  final coordinator = container.read(offlineDownloadCoordinatorProvider);
  if (manager == null || coordinator == null) return;
  final db = container.read(offlineDatabaseProvider);
  final repo = container.read(offlineRepositoryProvider);
  final nets = container.read(safetyNetConfigProvider);
  final background = container.read(backgroundDownloadControllerProvider);
  await background.withOwnership(() async {
    if (!await adoptWorkerObligations(container.read)) return;
    for (final m in await db.libraryManga()) {
      if (!current() || !downloadPermissionAllowed(container.read)) return;
      await reconcileMangaCore(
        verifyPermission: () => verifyDownloadPermission(container.read),
        onPermissionDenied: () async {
          if (current()) await pauseDownloadsForPermission(container.read);
        },
        isCurrent: current,
        db: db,
        repo: repo,
        manager: manager,
        coordinator: coordinator,
        nets: nets,
        mangaId: m.id,
        deleteWhileReadingSlots: container
            .read(localDeleteSettingsProvider)
            .deleteWhileReading,
        withOwnership: background.withOwnership,
        removeFromWorker: (id, gen) async {
          if (!current()) throw StateError('Authentication session changed');
          await background.onRemoved(id);
          if (!current()) throw StateError('Authentication session changed');
          await background.recordChapterDeleted(id, gen);
        },
      );
    }
  });
}

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
