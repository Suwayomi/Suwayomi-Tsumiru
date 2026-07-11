// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/offline/data/chapter_download_engine.dart';
import 'package:tsumiru/src/features/offline/data/offline_page_store.dart';

class _NoopStore implements OfflinePageStore {
  @override
  Future<({String relPath, int bytes})> writePage(
          int m, int c, int i, List<int> b, String e) async =>
      (relPath: 'x', bytes: b.length);
  @override
  Future<void> deleteChapter(int m, int c) async {}
  @override
  Future<int> chapterBytes(int m, int c) async => 0;
  @override
  Future<void> clearAll() async {}
}

void main() {
  test('a PageOfflineException yields outcome.offline, not error/authFailed',
      () async {
    final engine = ChapterDownloadEngine(
      fetchPage: (_) async => throw const PageOfflineException(),
      writePage: _NoopStore(),
      refreshAuth: () async => true,
    );
    final outcome = await engine.download(
      mangaId: 1,
      chapterId: 2,
      pages: const [(index: 0, url: 'u0')],
      isCancelled: () => false,
    );
    expect(outcome.offline, isTrue);
    expect(outcome.error, isNull);
    expect(outcome.authFailed, isFalse);
    expect(outcome.succeeded, isFalse);
    expect(outcome.storedPages, isEmpty);
  });

  test('offline short-circuits immediately (no retry/backoff burn)', () async {
    var calls = 0;
    final engine = ChapterDownloadEngine(
      fetchPage: (_) async {
        calls++;
        throw const PageOfflineException();
      },
      writePage: _NoopStore(),
      refreshAuth: () async => true,
      maxAttempts: 3,
    );
    await engine.download(
      mangaId: 1,
      chapterId: 2,
      pages: const [(index: 0, url: 'u0')],
      isCancelled: () => false,
    );
    expect(calls, 1); // not retried 3x
  });
}
