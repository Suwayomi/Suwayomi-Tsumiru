// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import '../../../utils/logger/logger.dart';
import '../../../utils/platform/is_android_native.dart';
import 'chapter_download_engine.dart';
import 'offline_database.dart';

/// Resolves a chapter's page URLs (wraps the GraphQL fetchChapterPages call).
typedef PageUrlsResolver = Future<List<String>> Function(int chapterId);

/// Measures the total on-disk bytes of a downloaded chapter's pages.
typedef ChapterBytesMeasurer = Future<int> Function(int mangaId, int chapterId);

/// Orchestrates background chapter downloads on top of [ChapterDownloadEngine].
///
/// Download ONE chapter at a time (everything comes from our
/// own server, so there's nothing to spread chapter-level load against), with
/// page-level parallelism inside the engine. Auth is resolved at request time
/// by the engine's fetcher and refreshed on a 401 — nothing is baked at enqueue,
/// which is what stranded the old `background_downloader` tasks with expired
/// tokens. Deps are injected so the flow is testable without GraphQL, HTTP or
/// dart:io.
class OfflineDownloadCoordinator {
  OfflineDownloadCoordinator({
    required this.db,
    required this.resolvePages,
    required this.engine,
    required this.measureChapterBytes,
    this.persistedPaused,
  });

  final OfflineDatabase db;
  final PageUrlsResolver resolvePages;
  final ChapterDownloadEngine engine;
  final ChapterBytesMeasurer measureChapterBytes;

  /// Reads the persisted "downloads paused" flag (injected so the pump survives
  /// a restart with the pause intact, without the coordinator depending on
  /// SharedPreferences directly). Null in tests = never persistently paused.
  final bool Function()? persistedPaused;

  /// In-session pause, set by [pause]/[resume] for an immediate brake. The gate
  /// is the OR of this and the persisted flag, so a restart honours a saved
  /// pause even though this resets to false.
  bool _paused = false;

  /// True when on-device downloads are paused (in-session or persisted).
  bool get isPaused => _paused || (persistedPaused?.call() ?? false);

  /// Chapter currently being downloaded by the engine (in-memory). One at a
  /// time, so at most one entry.
  final Set<int> _active = {};

  /// Chapters asked to stop mid-download (delete / pause). Cleared once the
  /// in-flight download observes it and unwinds.
  final Set<int> _cancelled = {};

  /// True while a pump loop is draining the queue. PROCESS-WIDE (static) so that
  /// even if the provider rebuilds mid-drain (e.g. the concurrency setting
  /// settles) and a second coordinator instance is created, only ONE loop ever
  /// drains the shared DB queue — otherwise both race and re-download every
  /// chapter. Mirrors the auth refresh single-flight.
  static bool _pumping = false;

  /// True if this chapter is actively downloading right now.
  bool isActive(int chapterId) => _active.contains(chapterId);

  /// Ask an in-flight chapter to stop; the pump leaves its already-stored pages
  /// on disk so a later run resumes rather than restarts.
  void cancel(int chapterId) {
    if (_active.contains(chapterId)) _cancelled.add(chapterId);
  }

  /// Pause all on-device downloading: stop starting new chapters and cancel the
  /// in-flight one (left `downloading` = resumable). The persisted flag is set
  /// by the caller; this is the immediate in-session brake.
  void pause() {
    _paused = true;
    _cancelled.addAll(_active);
  }

  /// Wait until nothing is actively downloading and the pump loop has exited, so
  /// a catalog clear can be sure no `onPageStored` write lands after it wipes the
  /// DB/files. Call after [pause]. Bounded so it can never hang the clear — the
  /// clear proceeds even if a stubborn page fetch hasn't observed the cancel yet
  /// (rare, and the worst case is one orphan row, which a later clear removes).
  Future<void> awaitIdle(
      {Duration timeout = const Duration(seconds: 3)}) async {
    final deadline = DateTime.now().add(timeout);
    while ((_active.isNotEmpty || _pumping) &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  /// Resume on-device downloading and drain the backlog. Returns the drain
  /// future so callers can await it (the UI fires it and forgets).
  Future<void> resume() {
    _paused = false;
    return pumpDownloads();
  }

  /// Add a chapter to the persistent download queue (state `queued`). The pump
  /// starts it when it reaches the front. Skips chapters already downloaded or
  /// in flight.
  Future<void> queueChapter(int chapterId) async {
    final c = await db.chapterById(chapterId);
    if (c == null) return;
    if (c.deviceState == OfflineDeviceState.downloaded ||
        c.deviceState == OfflineDeviceState.downloading ||
        c.deviceState == OfflineDeviceState.queued) {
      return;
    }
    await db.setChapterDeviceState(chapterId, OfflineDeviceState.queued);
  }

  /// Resolve + download a single chapter immediately (used by the pump and for
  /// a direct save). Idempotent + resumable: an already-`downloaded` chapter is
  /// skipped, pages already on disk are not re-fetched, and a chapter left
  /// `downloading` by a previous run (e.g. an app kill) simply resumes.
  Future<void> enqueueChapter(OfflineChapter chapter) async {
    if (chapter.deviceState == OfflineDeviceState.downloaded) return;
    // Paused: don't start (or re-start a stranded) chapter. Guarded here too —
    // not just in pumpDownloads — because enqueueChapter's `finally` clears the
    // chapter from `_cancelled`, so a stray pump could otherwise re-select a
    // stranded `downloading` chapter and restart it while paused.
    if (isPaused) return;
    if (_active.contains(chapter.id)) return;
    _active.add(chapter.id);
    try {
      await db.setChapterDeviceState(
          chapter.id, OfflineDeviceState.downloading);
      final urls = await resolvePages(chapter.id);
      if (urls.isEmpty) {
        logger.e('Offline: no pages resolved for chapter ${chapter.id}; '
            'marking error');
        await db.setChapterDeviceState(chapter.id, OfflineDeviceState.error);
        return;
      }
      final stored = (await (db.select(db.offlinePages)
                ..where((t) => t.chapterId.equals(chapter.id)))
              .get())
          .map((p) => p.pageIndex)
          .toSet();
      final pages = <PageRef>[
        for (var i = 0; i < urls.length; i++)
          if (!stored.contains(i)) (index: i, url: urls[i]),
      ];

      final outcome = await engine.download(
        mangaId: chapter.mangaId,
        chapterId: chapter.id,
        pages: pages,
        isCancelled: () => _cancelled.contains(chapter.id),
        onPageStored: (pageIndex, relPath, bytes) async {
          await db.into(db.offlinePages).insertOnConflictUpdate(
                OfflinePagesCompanion.insert(
                  chapterId: chapter.id,
                  pageIndex: pageIndex,
                  relativePath: relPath,
                ),
              );
        },
      );

      if (outcome.cancelled) return; // leave partial; resume later
      if (outcome.offline) {
        // No network / Wi-Fi-only blocked it — leave the chapter `downloading`
        // so it resumes on reconnect, NOT `error`.
        logger.i('Offline: chapter ${chapter.id} paused (no network); '
            'leaving downloading for resume');
        return;
      }
      if (outcome.authFailed) {
        logger.e('Offline: chapter ${chapter.id} auth failed (token dead)');
        await db.setChapterDeviceState(chapter.id, OfflineDeviceState.error);
        return;
      }
      if (outcome.error != null) {
        logger.e('Offline: chapter ${chapter.id} failed: ${outcome.error}');
        await db.setChapterDeviceState(chapter.id, OfflineDeviceState.error);
        return;
      }
      logger.i('Offline: enqueued ${pages.length} page tasks for chapter '
          '${chapter.id} (manga ${chapter.mangaId})');
      await _finalizeIfComplete(chapter.mangaId, chapter.id, urls.length);
    } catch (e) {
      logger.e('Offline: chapter ${chapter.id} download error: $e');
      await db.setChapterDeviceState(chapter.id, OfflineDeviceState.error);
    } finally {
      _active.remove(chapter.id);
      _cancelled.remove(chapter.id);
    }
  }

  /// Mark a chapter `downloaded` (with measured bytes) once all its pages are on
  /// disk. [expectedPages] is the resolved page count when known, else the
  /// catalog's `pageCount`.
  Future<bool> _finalizeIfComplete(
      int mangaId, int chapterId, int? expectedPages) async {
    final chapter = await db.chapterById(chapterId);
    if (chapter == null) return false;
    if (chapter.deviceState == OfflineDeviceState.downloaded) return true;
    final target = expectedPages ?? chapter.pageCount;
    if (target <= 0) return false;
    if (await db.downloadedPageCount(chapterId) < target) return false;
    final bytes = await measureChapterBytes(mangaId, chapterId);
    await db.setChapterDeviceState(chapterId, OfflineDeviceState.downloaded,
        bytes: bytes, downloadedAt: DateTime.now());
    logger.i('Offline: chapter $chapterId downloaded ($target pages, '
        '$bytes bytes)');
    return true;
  }

  /// Drain the queue one chapter at a time: resume any chapter left
  /// `downloading` (stranded by an app restart) first, then pull from the
  /// `queued` backlog. Single-flight — a second call while running is a no-op;
  /// the running loop picks up anything newly queued.
  Future<void> pumpDownloads() async {
    // CORRUPTION GATE: on Android the foreground-service worker isolate is the
    // sole downloader; the main-isolate pump must NEVER write page files there
    // (two isolates writing the same files/catalog corrupts it). Downloads on
    // Android are driven by BackgroundDownloadController instead.
    if (isAndroidNative) return;
    if (isPaused) return;
    if (_pumping) return;
    _pumping = true;
    try {
      while (true) {
        if (isPaused) break;
        final next = await _nextChapter();
        if (next == null) break;
        await enqueueChapter(next);
      }
    } finally {
      _pumping = false;
    }
  }

  /// The next chapter to work on: a stranded `downloading` chapter (state says
  /// downloading but nothing is in flight — left over from a kill), else the
  /// head of the `queued` backlog. Null when there's nothing to do.
  Future<OfflineChapter?> _nextChapter() async {
    final downloading =
        await db.chaptersInState(OfflineDeviceState.downloading);
    var stranded = 0;
    for (final c in downloading) {
      if (!_active.contains(c.id)) {
        stranded++;
      }
    }
    final firstStranded =
        downloading.where((c) => !_active.contains(c.id)).firstOrNull;
    logger.i('Offline pump: downloading=${downloading.length} '
        'active=${_active.length} stranded=$stranded');
    if (firstStranded != null) return firstStranded;
    return db.nextQueuedChapter();
  }
}
