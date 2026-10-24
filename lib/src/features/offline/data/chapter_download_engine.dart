// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import '../../account/data/account_permission.dart';
import 'offline_page_store.dart';

/// A 401 that permits one auth refresh and retry.
class PageAuthException implements Exception {
  const PageAuthException();
}

/// Connection loss or Wi-Fi-only blocking; leaves the chapter resumable rather than failed.
class PageOfflineException implements Exception {
  const PageOfflineException(this.reason);
  final String reason;
}

typedef PageRef = ({int index, String url});

/// Resolve server base and auth at call time; throw [PageAuthException] on 401.
typedef PageFetcher = Future<PageBytes> Function(String pageUrl);

/// True if retry can use refreshed credentials; caller must deduplicate concurrent refreshes.
typedef AuthRefresher = Future<bool> Function();

class ChapterDownloadOutcome {
  const ChapterDownloadOutcome({
    required this.storedPages,
    required this.cancelled,
    required this.authFailed,
    required this.offline,
    this.offlineReason,
    this.error,
  });

  /// Pages stored during this run only.
  final Map<int, ({String relPath, int bytes})> storedPages;

  final bool cancelled;

  /// Requires re-authentication after a failed refresh.
  final bool authFailed;

  /// Leaves the chapter resumable.
  final bool offline;

  final String? offlineReason;

  final Object? error;

  bool get succeeded => error == null && !cancelled && !authFailed && !offline;
}

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

  /// Stops on cancellation, auth failure, or exhausted retries; reports each stored page.
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
        storedPages: stored,
        cancelled: false,
        authFailed: false,
        offline: false,
      );
    }

    final queue = List<PageRef>.of(pages);
    var cursor = 0;
    var authFailed = false;
    var offline = false;
    String? offlineReason;
    Object? fatalError;

    Future<void> worker() async {
      while (true) {
        if (isCancelled() || authFailed || offline || fatalError != null) {
          return;
        }
        if (cursor >= queue.length) return;
        final page = queue[cursor++];
        final result = await _downloadOne(
          mangaId,
          chapterId,
          page,
          isCancelled,
        );
        switch (result) {
          case _PageOk(:final relPath, :final bytes):
            stored[page.index] = (relPath: relPath, bytes: bytes);
            if (onPageStored != null) {
              await onPageStored(page.index, relPath, bytes);
            }
          case _PageAuthDead():
            authFailed = true;
          case _PageOffline(:final reason):
            offline = true;
            offlineReason = reason;
          case _PageCancelled():
            return; // cancel landed mid-fetch; the loop's guard also stops us
          case _PageError(:final error):
            if (fatalError == null || error is AccountPermissionDenied) {
              fatalError = error;
            }
        }
      }
    }

    final workerCount = parallelPageLimit < queue.length
        ? parallelPageLimit
        : queue.length;
    await Future.wait([for (var i = 0; i < workerCount; i++) worker()]);

    return ChapterDownloadOutcome(
      storedPages: stored,
      cancelled: isCancelled(),
      authFailed: authFailed,
      offline: offline,
      offlineReason: offlineReason,
      error: fatalError,
    );
  }

  Future<_PageResult> _downloadOne(
    int mangaId,
    int chapterId,
    PageRef page,
    bool Function() isCancelled,
  ) async {
    var refreshedForAuth = false;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (isCancelled()) return const _PageCancelled();
      try {
        final bytes = await fetchPage(page.url);
        // A cancel can arrive during fetch; writing afterward could recreate files already purged.
        if (isCancelled()) return const _PageCancelled();
        final written = await writePage.writePage(
          mangaId,
          chapterId,
          page.index,
          bytes.bytes,
          bytes.ext,
        );
        return _PageOk(relPath: written.relPath, bytes: written.bytes);
      } on AccountPermissionDenied catch (e) {
        if (isCancelled()) return const _PageCancelled();
        return _PageError(e);
      } on PageOfflineException catch (e) {
        if (isCancelled()) return const _PageCancelled();
        // Offline work remains resumable; retrying cannot help until connectivity changes.
        return _PageOffline(e.reason);
      } on PageAuthException {
        if (isCancelled()) return const _PageCancelled();
        if (!refreshedForAuth) {
          refreshedForAuth = true;
          final ok = await refreshAuth();
          if (!ok) return const _PageAuthDead();
          continue; // retry immediately with the fresh token (doesn't count)
        }
        return const _PageAuthDead();
      } catch (e) {
        if (isCancelled()) return const _PageCancelled();
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

class _PageCancelled extends _PageResult {
  const _PageCancelled();
}

class _PageOffline extends _PageResult {
  const _PageOffline(this.reason);
  final String reason;
}
