// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'offline_page_store.dart';

/// Thrown by a [PageFetcher] when the server rejects the request with 401.
/// Signals the engine to refresh auth once and retry, rather than counting it
/// as a normal transient failure.
class PageAuthException implements Exception {
  const PageAuthException();
}

/// One page to download: its server URL and its index within the chapter.
typedef PageRef = ({int index, String url});

/// Fetches one page's bytes over HTTP given the server page path/URL. The
/// closure MUST resolve the server base AND the current auth (ui_login `?token=`
/// query param, or basic/simple_login headers) itself, at call time — that's
/// what makes auth run-time-fresh instead of baked at enqueue. It MUST throw
/// [PageAuthException] on a 401 so the engine can refresh and retry; any other
/// failure should throw a plain exception (treated as transient).
typedef PageFetcher = Future<PageBytes> Function(String pageUrl);

/// Refreshes auth after a 401. Returns true if a new credential is now
/// available (retry worth attempting), false if auth is genuinely dead (give
/// up). Single-flight is the caller's responsibility (AuthCoordinator handles
/// it), so concurrent pages hitting 401 at once collapse to one refresh.
typedef AuthRefresher = Future<bool> Function();

/// Outcome of downloading one chapter's outstanding pages.
class ChapterDownloadOutcome {
  const ChapterDownloadOutcome({
    required this.storedPages,
    required this.cancelled,
    required this.authFailed,
    this.error,
  });

  /// Pages written to disk this run: pageIndex -> (relPath, bytes).
  final Map<int, ({String relPath, int bytes})> storedPages;

  /// True if the run stopped because [isCancelled] went true.
  final bool cancelled;

  /// True if a page 401'd and the refresh reported auth is dead — the chapter
  /// can't proceed until the user re-authenticates.
  final bool authFailed;

  /// The first non-auth error that ended the run, if any.
  final Object? error;

  bool get succeeded => error == null && !cancelled && !authFailed;
}

/// Downloads a single chapter's pages, Komikku-style: up to
/// [parallelPageLimit] pages in flight at once (default 5), each retried a few
/// times with short backoff for transient blips, and auth refreshed once on a
/// 401 before retrying. Pure Dart and dependency-injected so it runs the same
/// on Android and the Linux desktop build and is testable without HTTP, dart:io
/// or the real auth stack.
///
/// Deliberately does ONE chapter: like Komikku's single-source model, the
/// orchestrator runs chapters one at a time (everything comes from our own
/// server, so there's nothing to spread chapter-level load against). The win is
/// page-level parallelism, which also hides the server's cold upstream-fetch
/// latency for chapters it hasn't cached yet.
class ChapterDownloadEngine {
  ChapterDownloadEngine({
    required this.fetchPage,
    required this.writePage,
    required this.refreshAuth,
    this.parallelPageLimit = 5,
    this.maxAttempts = 3,
    this.backoff = _defaultBackoff,
  });

  final PageFetcher fetchPage;
  final OfflinePageStore writePage;
  final AuthRefresher refreshAuth;
  final int parallelPageLimit;
  final int maxAttempts;
  final Duration Function(int attempt) backoff;

  static Duration _defaultBackoff(int attempt) =>
      Duration(milliseconds: 300 * (1 << (attempt - 1))); // 300ms, 600, 1200

  /// Download [pages] for chapter [chapterId]. Returns when all are stored, the
  /// run is cancelled, auth dies, or a page exhausts its retries. Calls
  /// [onPageStored] as each page lands so the caller can persist its catalog row
  /// and update progress incrementally.
  Future<ChapterDownloadOutcome> download({
    required int mangaId,
    required int chapterId,
    required List<PageRef> pages,
    required bool Function() isCancelled,
    Future<void> Function(int pageIndex, String relPath, int bytes)?
        onPageStored,
  }) async {
    final stored = <int, ({String relPath, int bytes})>{};
    if (pages.isEmpty) {
      return ChapterDownloadOutcome(
          storedPages: stored, cancelled: false, authFailed: false);
    }

    final queue = List<PageRef>.of(pages);
    var cursor = 0;
    var authFailed = false;
    Object? fatalError;

    Future<void> worker() async {
      while (true) {
        if (isCancelled() || authFailed || fatalError != null) return;
        if (cursor >= queue.length) return;
        final page = queue[cursor++];
        final result = await _downloadOne(mangaId, chapterId, page);
        switch (result) {
          case _PageOk(:final relPath, :final bytes):
            stored[page.index] = (relPath: relPath, bytes: bytes);
            if (onPageStored != null) {
              await onPageStored(page.index, relPath, bytes);
            }
          case _PageAuthDead():
            authFailed = true;
          case _PageError(:final error):
            fatalError ??= error;
        }
      }
    }

    final workerCount =
        parallelPageLimit < queue.length ? parallelPageLimit : queue.length;
    await Future.wait([for (var i = 0; i < workerCount; i++) worker()]);

    return ChapterDownloadOutcome(
      storedPages: stored,
      cancelled: isCancelled(),
      authFailed: authFailed,
      error: fatalError,
    );
  }

  Future<_PageResult> _downloadOne(
      int mangaId, int chapterId, PageRef page) async {
    var refreshedForAuth = false;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final bytes = await fetchPage(page.url);
        final written = await writePage.writePage(
          mangaId,
          chapterId,
          page.index,
          bytes.bytes,
          bytes.ext,
        );
        return _PageOk(relPath: written.relPath, bytes: written.bytes);
      } on PageAuthException {
        // Refresh once; concurrent 401s collapse via the refresher's
        // single-flight. If auth is dead, stop trying.
        if (!refreshedForAuth) {
          refreshedForAuth = true;
          final ok = await refreshAuth();
          if (!ok) return const _PageAuthDead();
          continue; // retry immediately with the fresh token (doesn't count)
        }
        // Already refreshed once and still 401 → auth is dead for this run.
        return const _PageAuthDead();
      } catch (e) {
        if (attempt >= maxAttempts) return _PageError(e);
        await Future.delayed(backoff(attempt));
      }
    }
    return const _PageError('exhausted retries');
  }
}

sealed class _PageResult {
  const _PageResult();
}

class _PageOk extends _PageResult {
  const _PageOk({required this.relPath, required this.bytes});
  final String relPath;
  final int bytes;
}

class _PageError extends _PageResult {
  const _PageError(this.error);
  final Object error;
}

class _PageAuthDead extends _PageResult {
  const _PageAuthDead();
}
