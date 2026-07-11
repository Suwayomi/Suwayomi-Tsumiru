// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/offline/data/chapter_download_engine.dart';
import 'package:tsumiru/src/features/offline/data/offline_page_store.dart';

/// In-memory page store — records what was "written".
class _FakeStore implements OfflinePageStore {
  final written = <int, int>{}; // pageIndex -> bytes
  @override
  Future<({String relPath, int bytes})> writePage(int mangaId, int chapterId,
      int pageIndex, List<int> bytes, String ext) async {
    written[pageIndex] = bytes.length;
    return (
      relPath: '$mangaId/$chapterId/$pageIndex.$ext',
      bytes: bytes.length
    );
  }

  @override
  Future<void> deleteChapter(int mangaId, int chapterId) async {}
  @override
  Future<int> chapterBytes(int mangaId, int chapterId) async => 0;
  @override
  Future<void> clearAll() async {}
}

List<PageRef> _pages(int n) =>
    [for (var i = 0; i < n; i++) (index: i, url: 'http://s/p$i')];

void main() {
  const noBackoff = Duration.zero;

  test('downloads all pages and reports each stored', () async {
    final store = _FakeStore();
    final engine = ChapterDownloadEngine(
      fetchPage: (url) async => (bytes: [1, 2, 3], ext: 'jpg'),
      writePage: store,
      refreshAuth: () async => true,
      backoff: (_) => noBackoff,
    );
    final reported = <int>[];
    final out = await engine.download(
      mangaId: 1,
      chapterId: 2,
      pages: _pages(10),
      isCancelled: () => false,
      onPageStored: (i, _, __) async => reported.add(i),
    );
    expect(out.succeeded, true);
    expect(out.storedPages.length, 10);
    expect(reported..sort(), List.generate(10, (i) => i));
    expect(store.written.length, 10);
  });

  test('refreshes auth once on 401 then succeeds', () async {
    var refreshes = 0;
    var firstTry = true;
    final engine = ChapterDownloadEngine(
      fetchPage: (url) async {
        // every page 401s once until a refresh happens
        if (firstTry) {
          firstTry = false;
          throw const PageAuthException();
        }
        return (bytes: [0], ext: 'jpg');
      },
      writePage: _FakeStore(),
      refreshAuth: () async {
        refreshes++;
        return true;
      },
      backoff: (_) => noBackoff,
    );
    final out = await engine.download(
        mangaId: 1, chapterId: 1, pages: _pages(1), isCancelled: () => false);
    expect(out.succeeded, true);
    expect(refreshes, 1);
  });

  test('gives up with authFailed when refresh says auth is dead', () async {
    final engine = ChapterDownloadEngine(
      fetchPage: (url) async => throw const PageAuthException(),
      writePage: _FakeStore(),
      refreshAuth: () async => false, // auth dead
      backoff: (_) => noBackoff,
    );
    final out = await engine.download(
        mangaId: 1, chapterId: 1, pages: _pages(3), isCancelled: () => false);
    expect(out.authFailed, true);
    expect(out.succeeded, false);
  });

  test('retries transient failures up to maxAttempts then errors', () async {
    var calls = 0;
    final engine = ChapterDownloadEngine(
      fetchPage: (url) async {
        calls++;
        throw Exception('boom');
      },
      writePage: _FakeStore(),
      refreshAuth: () async => true,
      maxAttempts: 3,
      backoff: (_) => noBackoff,
    );
    final out = await engine.download(
        mangaId: 1, chapterId: 1, pages: _pages(1), isCancelled: () => false);
    expect(out.succeeded, false);
    expect(out.error, isNotNull);
    expect(calls, 3); // 3 attempts for the single page
  });

  test('never exceeds parallelPageLimit concurrent fetches', () async {
    var inFlight = 0;
    var peak = 0;
    final engine = ChapterDownloadEngine(
      parallelPageLimit: 5,
      fetchPage: (url) async {
        inFlight++;
        peak = peak > inFlight ? peak : inFlight;
        await Future.delayed(const Duration(milliseconds: 5));
        inFlight--;
        return (bytes: [0], ext: 'jpg');
      },
      writePage: _FakeStore(),
      refreshAuth: () async => true,
      backoff: (_) => noBackoff,
    );
    await engine.download(
        mangaId: 1, chapterId: 1, pages: _pages(30), isCancelled: () => false);
    expect(peak, lessThanOrEqualTo(5));
    expect(peak, greaterThan(1)); // actually parallel
  });

  test('stops promptly when cancelled', () async {
    var fetched = 0;
    var cancel = false;
    final engine = ChapterDownloadEngine(
      parallelPageLimit: 2,
      fetchPage: (url) async {
        fetched++;
        if (fetched >= 4) cancel = true;
        return (bytes: [0], ext: 'jpg');
      },
      writePage: _FakeStore(),
      refreshAuth: () async => true,
      backoff: (_) => noBackoff,
    );
    final out = await engine.download(
        mangaId: 1,
        chapterId: 1,
        pages: _pages(100),
        isCancelled: () => cancel);
    expect(out.cancelled, true);
    expect(fetched, lessThan(100));
  });
}
