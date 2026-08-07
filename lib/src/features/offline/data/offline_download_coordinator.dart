// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/logger/logger.dart';
import '../../../utils/network/graphql_errors.dart';
import '../../../utils/platform/is_android_native.dart';
import 'chapter_commit.dart';
import 'chapter_download_engine.dart';
import 'chapter_manifest.dart';
import 'offline_database.dart';
import 'offline_page_store.dart';

/// Resolves a chapter's page URLs (wraps the GraphQL fetchChapterPages call).
typedef PageUrlsResolver = Future<List<String>> Function(int chapterId);

/// Reports a chapter's live page progress upward (the arc can't be counted from
/// the catalog any more — page rows only appear at commit).
typedef DownloadProgressSink =
    void Function(int chapterId, int done, int total);

/// Orchestrates background chapter downloads on top of [ChapterDownloadEngine],
/// one chapter at a time (page-level parallelism lives in the engine) since
/// everything comes from our own server. Auth is resolved fresh per request
/// and refreshed on a 401 — nothing baked at enqueue, which is what stranded
/// the old `background_downloader` tasks with expired tokens; deps are
/// injected so the flow is testable without GraphQL/HTTP/dart:io.
class OfflineDownloadCoordinator {
  OfflineDownloadCoordinator({
    required this.db,
    required this.resolvePages,
    required this.engine,
    required this.store,
    this.persistedPaused,
    this.onServerUnreachable,
    this.onProgress,
    this.onProgressDone,
  });

  final OfflineDatabase db;
  final PageUrlsResolver resolvePages;
  final ChapterDownloadEngine engine;
  final OfflinePageStore store;

  /// Live page progress for the UI arc. Null in tests.
  final DownloadProgressSink? onProgress;

  /// The chapter stopped being live — committed, failed or cancelled.
  final void Function(int chapterId)? onProgressDone;

  /// Reports "the server is unreachable" upward when a resolve fails on a
  /// connection error. Without it the pump can park during a background-only
  /// outage that no UI read ever notices, and the reconnect listener (which
  /// needs a true->false transition) would never fire to unpark it.
  void Function()? onServerUnreachable;

  /// Reads the persisted "downloads paused" flag (injected so a restart
  /// survives with the pause intact, without depending on SharedPreferences
  /// directly). Null in tests = never persistently paused.
  final bool Function()? persistedPaused;

  /// In-session pause, set by [pause]/[resume] for an immediate brake — the
  /// gate is the OR of this and the persisted flag, so a restart still honours
  /// a saved pause even though this resets to false.
  bool _paused = false;

  /// True when on-device downloads are paused (in-session or persisted).
  bool get isPaused => _paused || (persistedPaused?.call() ?? false);

  // These three and [_pumping] are PROCESS-WIDE (static): a keep-alive provider
  // rebuild mid-drain can leave an old coordinator's pump running while deletes
  // route through the new instance, so instance-local guards would let it
  // resurrect a just-deleted chapter — sharing state keeps a delete claim
  // visible across generations.

  /// Chapter currently being downloaded by the engine. One at a time, so at most
  /// one entry.
  static final Set<int> _active = {};

  /// Chapters asked to stop mid-download (delete / pause). Cleared once the
  /// in-flight download observes it and unwinds.
  static final Set<int> _cancelled = {};

  /// Chapters mid-delete, reference-counted by claimant (a user delete and a
  /// reconcile eviction can overlap). Pump/[enqueueChapter] skip any key
  /// present; the claim releases only when the last claimant calls [endDelete],
  /// so one finishing early can't unguard a chapter another is still
  /// deleting — `_cancelled` alone isn't enough since `enqueueChapter`'s
  /// `finally` clears it.
  static final Map<int, int> _deleting = {};

  /// True while a pump loop is draining the queue — only ONE loop ever drains
  /// the shared DB queue even across a mid-drain rebuild.
  static bool _pumping = false;
  // Set when a chapter parks on a dead network; cleared at each pump start.
  bool _pausedForOffline = false;

  /// Reset all process-wide state. Test-only: tests share one process, so a
  /// coordinator built in one test would otherwise inherit another's claims.
  static void resetSharedStateForTest() {
    _active.clear();
    _cancelled.clear();
    _deleting.clear();
    _pumping = false;
  }

  /// True if this chapter is actively downloading right now.
  bool isActive(int chapterId) => _active.contains(chapterId);

  /// Ask an in-flight chapter to stop; the pump leaves its already-stored pages
  /// on disk so a later run resumes rather than restarts.
  void cancel(int chapterId) {
    if (_active.contains(chapterId)) _cancelled.add(chapterId);
  }

  /// Claim a chapter for deletion, cancelling it and waiting (bounded) for the
  /// engine to stop writing. Call before deleting files/rows; pair with
  /// [endDelete] in a `finally`.
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

  /// Release a chapter claimed by [beginDelete] once its files/rows are gone.
  /// Drops the cancel only when the LAST claimant exits, so an overlapping
  /// delete keeps it guarded.
  void endDelete(int chapterId) {
    final remaining = (_deleting[chapterId] ?? 0) - 1;
    if (remaining <= 0) {
      _deleting.remove(chapterId);
      _cancelled.remove(chapterId);
    } else {
      _deleting[chapterId] = remaining;
    }
  }

  /// Pause all on-device downloading: stop starting new chapters and cancel the
  /// in-flight one (left `downloading` = resumable). The persisted flag is set
  /// by the caller; this is the immediate in-session brake.
  void pause() {
    _paused = true;
    _cancelled.addAll(_active);
  }

  /// Wait until nothing is downloading and the pump has exited, so a catalog
  /// clear is sure no `onPageStored` write lands after it wipes the DB/files.
  /// Bounded so it never hangs the clear — worst case is one orphan row,
  /// cleaned up later.
  Future<void> awaitIdle({
    Duration timeout = const Duration(seconds: 3),
  }) async {
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
    if (_deleting.containsKey(chapterId)) return;
    await db.transaction(() async {
      // Recheck inside the transaction (serialized with deleteChapter): `none`
      // is itself queueable, so without the _deleting guard a racing queue
      // request would re-queue a chapter the user just removed.
      if (_deleting.containsKey(chapterId)) return;
      final c = await db.chapterById(chapterId);
      if (c == null) return;
      if (c.deviceState == OfflineDeviceState.downloaded ||
          c.deviceState == OfflineDeviceState.downloading ||
          c.deviceState == OfflineDeviceState.queued) {
        return;
      }
      await db.setChapterDeviceState(chapterId, OfflineDeviceState.queued);
    });
  }

  /// Resolve + download a single chapter immediately (used by the pump and for
  /// a direct save). Idempotent + resumable: skips an already-`downloaded`
  /// chapter, doesn't re-fetch pages already on disk, and simply resumes a
  /// chapter left `downloading` by a prior run.
  Future<void> enqueueChapter(OfflineChapter chapter) async {
    if (_deleting.containsKey(chapter.id)) return;
    if (chapter.deviceState == OfflineDeviceState.downloaded) return;
    // Paused: don't start (or re-start a stranded) chapter. Guarded here too,
    // not just in pumpDownloads — enqueueChapter's `finally` clears
    // `_cancelled`, so a stray pump could otherwise re-select and restart a
    // stranded chapter while paused.
    if (isPaused) return;
    if (_active.contains(chapter.id)) return;
    _active.add(chapter.id);
    try {
      // Recheck _deleting and mark downloading atomically (serialized with
      // deleteChapter) — a mid-flight delete claim must win; `none` is itself
      // a valid fresh-download start, so only an active delete blocks it.
      final started = await db.transaction(() async {
        if (_deleting.containsKey(chapter.id)) return false;
        await db.setChapterDeviceState(
          chapter.id,
          OfflineDeviceState.downloading,
        );
        return true;
      });
      if (!started) return;
      final urls = await resolvePages(chapter.id);
      if (urls.isEmpty) {
        logger.e(
          'Offline: no pages resolved for chapter ${chapter.id}; '
          'marking error',
        );
        await _applyTerminalError(chapter.id);
        return;
      }
      final indices = [for (var i = 0; i < urls.length; i++) i];
      // The generation is read fresh (not taken from the possibly-stale row we
      // were handed) and stamped into staging, so commit can tell whether this
      // download still belongs to the chapter it started on.
      final generation =
          (await db.chapterById(chapter.id))?.downloadGeneration ?? 0;
      final staged = await _openStaging(
        chapter.mangaId,
        chapter.id,
        indices,
        generation,
      );
      // A determinate arc from the first frame — webtoon chapters only learn
      // their page total here, when the list resolves.
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
        isCancelled: () => _cancelled.contains(chapter.id),
        onPageStored: (pageIndex, relPath, bytes) async {
          // Pages live in staging until the chapter commits, so there is no
          // catalog row to write here — only progress to report.
          onProgress?.call(chapter.id, ++done, urls.length);
        },
      );

      if (outcome.cancelled) return; // leave staging; resume later
      if (outcome.offline) {
        // No network / Wi-Fi-only blocked it — leave the chapter `downloading`
        // so it resumes on reconnect, NOT `error`. Stop the pump too: the
        // parked row stays first in line, so pumping on would just re-pick it
        // in a hot loop while the network is down.
        _pausedForOffline = true;
        logger.i(
          'Offline: chapter ${chapter.id} paused (no network); '
          'leaving downloading for resume',
        );
        return;
      }
      if (outcome.authFailed) {
        logger.e('Offline: chapter ${chapter.id} auth failed (token dead)');
        await _applyTerminalError(chapter.id);
        return;
      }
      if (outcome.error != null) {
        logger.e('Offline: chapter ${chapter.id} failed: ${outcome.error}');
        await _applyTerminalError(chapter.id);
        return;
      }
      logger.i(
        'Offline: enqueued ${pages.length} page tasks for chapter '
        '${chapter.id} (manga ${chapter.mangaId})',
      );
      await commitStagedChapter(
        db: db,
        store: store,
        mangaId: chapter.mangaId,
        chapterId: chapter.id,
      );
    } catch (e) {
      final cause = e is OperationMessageException ? e.exception : e;
      if (isConnectionError(cause)) {
        // Page-list resolve hit a dead network, not a real chapter failure:
        // leave it downloading so the next pump resumes it (Android worker
        // parity). Park the pump too — a proxy answering 502 fails in
        // milliseconds, and re-picking the same row would hot-loop for the
        // whole outage.
        _pausedForOffline = true;
        onServerUnreachable?.call();
        logger.i(
          'Offline: chapter ${chapter.id} paused (resolve offline); '
          'leaving downloading for resume',
        );
      } else {
        logger.e('Offline: chapter ${chapter.id} download error: $e');
        await _applyTerminalError(chapter.id);
      }
    } finally {
      _active.remove(chapter.id);
      onProgressDone?.call(chapter.id);
      // Keep the cancel set while a delete still holds a claim — endDelete owns
      // clearing it once the last claimant exits.
      if (!_deleting.containsKey(chapter.id)) _cancelled.remove(chapter.id);
    }
  }

  /// Open (or adopt) the chapter's staging directory and report which pages are
  /// already there.
  ///
  /// Staging survives an interrupted run, which is what makes a resume cheap.
  /// Anything we can't positively identify as this exact download is wiped
  /// first: a different page set, a generation from before a delete, or a
  /// manifest too damaged to read. Adopting files on any weaker evidence would
  /// let a later resume count them as ours and commit a chapter assembled from
  /// two different downloads.
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

  /// Write a terminal error state only if the chapter is still ours. beginDelete
  /// waits only briefly for the engine to stop, so a slow fetch can outlive a
  /// delete that already committed `none` — a late error must not resurrect it.
  Future<void> _applyTerminalError(int chapterId) async {
    if (_deleting.containsKey(chapterId)) return;
    await db.transaction(() async {
      final c = await db.chapterById(chapterId);
      if (c == null || c.deviceState == OfflineDeviceState.none) return;
      await db.setChapterDeviceState(chapterId, OfflineDeviceState.error);
    });
  }

  /// Drain the queue one chapter at a time: resume any chapter left
  /// `downloading` (stranded by an app restart) first, then pull from the
  /// `queued` backlog. Single-flight — a second call while running is a no-op;
  /// the running loop picks up anything newly queued.
  Future<void> pumpDownloads() async {
    // CORRUPTION GATE: on Android the foreground-service worker is the sole
    // downloader — two isolates writing the same files/catalog corrupts it, so
    // this pump must never run there; BackgroundDownloadController drives
    // Android instead.
    if (isAndroidNative) return;
    if (isPaused) return;
    if (_pumping) return;
    _pumping = true;
    // A fresh pump is a fresh chance: the offline park below stops THIS drain;
    // the next trigger (launch resume, a new save, reconnect) tries again.
    _pausedForOffline = false;
    try {
      while (true) {
        if (isPaused || _pausedForOffline) break;
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
    // Skip a queue head mid-deletion so it doesn't stall the rest of the backlog.
    final queued = await db.chaptersInState(OfflineDeviceState.queued);
    return queued.where((c) => !_deleting.containsKey(c.id)).firstOrNull;
  }
}
