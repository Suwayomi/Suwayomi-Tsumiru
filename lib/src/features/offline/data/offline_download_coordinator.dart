// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/logger/logger.dart';
import '../../../utils/network/graphql_errors.dart';
import '../../../utils/platform/is_android_native.dart';
import '../../account/data/account_permission.dart';
import 'chapter_commit.dart';
import 'chapter_download_engine.dart';
import 'chapter_manifest.dart';
import 'offline_database.dart';
import 'offline_page_store.dart';

typedef PageUrlsResolver = Future<List<String>> Function(int chapterId);

/// Reports progress before page rows become visible at commit.
typedef DownloadProgressSink =
    void Function(int chapterId, int done, int total);

/// Downloads one chapter at a time, resolving auth per request and refreshing on 401.
class OfflineDownloadCoordinator {
  OfflineDownloadCoordinator({
    required this.db,
    required this.resolvePages,
    required this.engine,
    required this.store,
    this.persistedPaused,
    this.onServerUnreachable,
    this.onPermissionDenied,
    this.isCurrentSession,
    this.onProgress,
    this.onProgressDone,
  });

  final OfflineDatabase db;
  final PageUrlsResolver resolvePages;
  final ChapterDownloadEngine engine;
  final OfflinePageStore store;

  final DownloadProgressSink? onProgress;

  final void Function(int chapterId)? onProgressDone;

  /// Signals outages so reconnect can restart a parked queue.
  void Function()? onServerUnreachable;
  final Future<void> Function()? onPermissionDenied;
  final bool Function()? isCurrentSession;
  bool _permissionHeld = false;

  /// Null means no persisted pause.
  final bool Function()? persistedPaused;

  bool _paused = false;

  bool get isPaused => _paused || (persistedPaused?.call() ?? false);

  // Shared across provider rebuilds so old pumps observe new delete claims.

  static final Set<int> _active = {};

  // Cleared after the in-flight download observes cancellation.
  static final Set<int> _cancelled = {};

  // Reference counts keep overlapping deletes guarded until the last claimant exits.
  static final Map<int, int> _deleting = {};

  // One drain across all coordinator instances.
  static bool _pumping = false;
  bool _pausedForOffline = false;

  static void resetSharedStateForTest() {
    _active.clear();
    _cancelled.clear();
    _deleting.clear();
    _pumping = false;
  }

  bool isActive(int chapterId) => _active.contains(chapterId);

  /// Leaves staged pages available for resume.
  void cancel(int chapterId) {
    if (_active.contains(chapterId)) _cancelled.add(chapterId);
  }

  /// Call before deleting files/rows; pair with [endDelete] in finally.
  Future<void> beginDelete(
    int chapterId, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    _deleting.update(chapterId, (n) => n + 1, ifAbsent: () => 1);
    _cancelled.add(chapterId);
    final deadline = DateTime.now().add(timeout);
    while (_active.contains(chapterId) && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  /// Releases cancellation only after the last overlapping delete ends.
  void endDelete(int chapterId) {
    final remaining = (_deleting[chapterId] ?? 0) - 1;
    if (remaining <= 0) {
      _deleting.remove(chapterId);
      _cancelled.remove(chapterId);
    } else {
      _deleting[chapterId] = remaining;
    }
  }

  /// Cancels in-flight work for resume; the caller must persist the pause separately.
  void pause() {
    _paused = true;
    _cancelled.addAll(_active);
  }

  Future<void> awaitIdle({Duration timeout = const Duration(seconds: 3)}) =>
      _awaitIdle(timeout);

  Future<void> pauseAndDrain({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final wasPaused = _paused;
    pause();
    try {
      await awaitIdle(timeout: timeout);
    } catch (_) {
      _paused = wasPaused;
      rethrow;
    }
  }

  static Future<void> stopAll({Duration timeout = const Duration(seconds: 3)}) {
    _cancelled.addAll(_active);
    return _awaitIdle(timeout);
  }

  static Future<void> _awaitIdle(Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while ((_active.isNotEmpty || _pumping) &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (_active.isNotEmpty || _pumping) {
      throw StateError('Downloads did not stop');
    }
  }

  Future<void> resume() {
    _paused = false;
    return pumpDownloads();
  }

  /// Only explicit user retries may set [allowErrored] to revive terminal failures.
  Future<void> queueChapter(
    int chapterId, {
    bool allowErrored = false,
    int? expectedGeneration,
    ({OfflineKeepRule rule, int count})? expectedKeepConfig,
  }) async {
    if (_deleting.containsKey(chapterId)) return;
    await db.transaction(() async {
      // Recheck under the transaction: a racing delete must block queueing even a none row.
      if (_deleting.containsKey(chapterId)) return;
      final c = await db.chapterById(chapterId);
      if (c == null) return;
      if (expectedGeneration != null &&
          c.downloadGeneration != expectedGeneration) {
        return;
      }
      if (expectedKeepConfig != null) {
        final manga = await (db.select(
          db.offlineMangas,
        )..where((m) => m.id.equals(c.mangaId))).getSingleOrNull();
        if (manga == null ||
            manga.keepRule != expectedKeepConfig.rule ||
            manga.keepUnreadCount != expectedKeepConfig.count) {
          return;
        }
      }
      if (c.deviceState == OfflineDeviceState.downloaded ||
          c.deviceState == OfflineDeviceState.downloading ||
          c.deviceState == OfflineDeviceState.queued) {
        return;
      }
      if (c.deviceState == OfflineDeviceState.error && !allowErrored) return;
      if (c.deviceState == OfflineDeviceState.error) {
        await db.bumpChapterGeneration(chapterId);
      }
      await db.setChapterDeviceState(chapterId, OfflineDeviceState.queued);
    });
  }

  /// Resumes staging and skips already downloaded chapters.
  Future<void> enqueueChapter(OfflineChapter chapter) async {
    if (_deleting.containsKey(chapter.id) ||
        isCurrentSession?.call() == false) {
      return;
    }
    if (chapter.deviceState == OfflineDeviceState.downloaded) return;
    // Direct saves bypass the pump, so they must honor pause here too.
    if (isPaused) return;
    if (_active.contains(chapter.id)) return;
    _active.add(chapter.id);
    try {
      // Claim and state transition must be atomic with deletion.
      final started = await db.transaction(() async {
        if (_deleting.containsKey(chapter.id) ||
            isCurrentSession?.call() == false) {
          return false;
        }
        final latest = await db.chapterById(chapter.id);
        if (latest == null ||
            latest.downloadGeneration != chapter.downloadGeneration ||
            latest.deviceState == OfflineDeviceState.downloaded) {
          return false;
        }
        await db.setChapterDeviceState(
          chapter.id,
          OfflineDeviceState.downloading,
        );
        return true;
      });
      if (!started) return;
      final urls = await resolvePages(chapter.id);
      if (!await _ownsAttempt(chapter)) return;
      if (urls.isEmpty) {
        logger.e(
          'Offline: no pages resolved for chapter ${chapter.id}; '
          'marking error',
        );
        await _applyTerminalError(chapter);
        return;
      }
      final indices = [for (var i = 0; i < urls.length; i++) i];
      final generation = chapter.downloadGeneration;
      final staged = await _openStaging(
        chapter.mangaId,
        chapter.id,
        indices,
        generation,
      );
      await db.setChapterPageCount(chapter.id, urls.length);
      var done = staged.length;
      onProgress?.call(chapter.id, done, urls.length);

      final pages = <PageRef>[
        for (var i = 0; i < urls.length; i++)
          if (!staged.contains(i)) (index: i, url: urls[i]),
      ];

      final outcome = await engine.download(
        mangaId: chapter.mangaId,
        chapterId: chapter.id,
        pages: pages,
        isCancelled: () =>
            _cancelled.contains(chapter.id) ||
            isPaused ||
            isCurrentSession?.call() == false,
        onPageStored: (pageIndex, relPath, bytes) async {
          // Pages remain in staging until commit, so this callback must not publish catalog page rows.
          onProgress?.call(chapter.id, ++done, urls.length);
        },
      );

      if (outcome.cancelled) return; // leave staging; resume later
      if (outcome.error != null && isPermissionDenied(outcome.error!)) {
        _permissionHeld = true;
        if (!await _ownsAttempt(chapter)) return;
        await onPermissionDenied?.call();
        await _applyTerminalError(chapter);
        return;
      }
      if (outcome.offline) {
        // Stop draining while offline; the resumable head would otherwise hot-loop.
        _pausedForOffline = true;
        // Reconnect requires the unreachable transition to restart the queue.
        onServerUnreachable?.call();
        logger.i(
          'Offline: chapter ${chapter.id} paused (no network); '
          'leaving downloading for resume',
        );
        return;
      }
      if (outcome.authFailed) {
        _permissionHeld = true;
        return;
      }
      if (outcome.error != null) {
        logger.e('Offline: chapter ${chapter.id} failed: ${outcome.error}');
        await _applyTerminalError(chapter, reason: outcome.error.toString());
        return;
      }
      logger.i(
        'Offline: enqueued ${pages.length} page tasks for chapter '
        '${chapter.id} (manga ${chapter.mangaId})',
      );
      if (isPaused || isCurrentSession?.call() == false) return;
      await commitStagedChapter(
        db: db,
        store: store,
        mangaId: chapter.mangaId,
        chapterId: chapter.id,
      );
    } catch (e) {
      final cause = e is OperationMessageException ? e.exception : e;
      if (cause is AccountPermissionUnavailable ||
          cause is PageAuthException ||
          isAuthenticationRequired(cause)) {
        _permissionHeld = true;
      } else if (isPermissionDenied(cause)) {
        _permissionHeld = true;
        if (!await _ownsAttempt(chapter)) return;
        await onPermissionDenied?.call();
        await _applyTerminalError(chapter);
      } else if (isConnectionError(cause)) {
        // Park on connection failures so a fast proxy error cannot hot-loop the head.
        _pausedForOffline = true;
        onServerUnreachable?.call();
        logger.i(
          'Offline: chapter ${chapter.id} paused (resolve offline); '
          'leaving downloading for resume',
        );
      } else {
        logger.e('Offline: chapter ${chapter.id} download error: $e');
        await _applyTerminalError(chapter, reason: e.toString());
      }
    } finally {
      _active.remove(chapter.id);
      onProgressDone?.call(chapter.id);
      // Only the last delete claimant may clear cancellation.
      if (!_deleting.containsKey(chapter.id)) _cancelled.remove(chapter.id);
    }
  }

  // Resume only staging with the same pages and generation; never mix downloads.
  Future<Set<int>> _openStaging(
    int mangaId,
    int chapterId,
    List<int> indices,
    int generation,
  ) async {
    final existing = await store.readManifest(mangaId, chapterId);
    if (existing != null &&
        existing.generation == generation &&
        existing.coversSameIndices(indices)) {
      return store.stagedPageIndices(mangaId, chapterId);
    }
    if (existing != null) {
      logger.i(
        'Offline: restarting staging for chapter $chapterId '
        '(page list or generation changed)',
      );
    }
    await store.deleteStaging(mangaId, chapterId);
    await store.beginChapter(
      mangaId,
      chapterId,
      ChapterManifest(generation: generation, indices: indices),
    );
    return const {};
  }

  Future<bool> _ownsAttempt(OfflineChapter chapter) async {
    if (_deleting.containsKey(chapter.id) ||
        _cancelled.contains(chapter.id) ||
        isCurrentSession?.call() == false) {
      return false;
    }
    final latest = await db.chapterById(chapter.id);
    return isCurrentSession?.call() != false &&
        !_deleting.containsKey(chapter.id) &&
        !_cancelled.contains(chapter.id) &&
        latest != null &&
        latest.downloadGeneration == chapter.downloadGeneration &&
        latest.deviceState != OfflineDeviceState.none &&
        latest.deviceState != OfflineDeviceState.downloaded;
  }

  Future<void> _applyTerminalError(OfflineChapter chapter, {String? reason}) =>
      db.transaction(() async {
        if (!await _ownsAttempt(chapter)) return;
        await db.setChapterDeviceState(
          chapter.id,
          OfflineDeviceState.error,
          failureReason: reason,
        );
      });

  /// Single-flight; resumes stranded downloads before queued chapters.
  Future<void> pumpDownloads() async {
    // Android workers own downloading; a second isolate writing these files would corrupt them.
    if (isAndroidNative) return;
    if (isPaused) return;
    if (_pumping) return;
    _pumping = true;
    _pausedForOffline = false;
    _permissionHeld = false;
    try {
      while (true) {
        if (isPaused || _pausedForOffline || _permissionHeld) break;
        final next = await _nextChapter();
        if (next == null) break;
        await enqueueChapter(next);
      }
    } finally {
      _pumping = false;
    }
  }

  Future<OfflineChapter?> _nextChapter() async {
    final downloading = await db.chaptersInState(
      OfflineDeviceState.downloading,
    );
    var stranded = 0;
    for (final c in downloading) {
      if (!_active.contains(c.id)) {
        stranded++;
      }
    }
    final firstStranded = downloading
        .where((c) => !_active.contains(c.id) && !_deleting.containsKey(c.id))
        .firstOrNull;
    logger.i(
      'Offline pump: downloading=${downloading.length} '
      'active=${_active.length} stranded=$stranded',
    );
    if (firstStranded != null) return firstStranded;
    final queued = await db.chaptersInState(OfflineDeviceState.queued);
    return queued.where((c) => !_deleting.containsKey(c.id)).firstOrNull;
  }
}
