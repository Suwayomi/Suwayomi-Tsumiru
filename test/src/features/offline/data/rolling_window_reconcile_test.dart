// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/reconcile_logic.dart';

// Rolling window: at each chapter boundary reconcileMangaCore is called with
//   deleteWhileReadingSlots = deleteWhileReading + 1
// so that readChaptersInDeleteWindow protects one EXTRA recently-read chapter
// (enabling back-and-forth at the boundary without re-downloading).
// On reader exit, reconcileMangaCore is called again with the normal
//   deleteWhileReadingSlots = deleteWhileReading
// to release the boundary buffer.
//
// readChaptersInDeleteWindow(chapters, slots) keeps (slots - 1) most recently
// read chapters in the protection window:
//   slots = 0 or 1 → empty (no protection)
//   slots = 2      → the 1 most recently read chapter
//   slots = 3      → the 2 most recently read chapters
//   etc.

OfflineChapter _ch(int id, {bool isRead = false, String? readAt}) =>
    OfflineChapter(
      id: id,
      mangaId: 1,
      name: 'c$id',
      chapterIndex: id,
      isRead: isRead,
      lastPageRead: 0,
      isBookmarked: false,
      serverIsDownloaded: true,
      deviceState: OfflineDeviceState.downloaded,
      pageCount: 1,
      bytes: 100,
      pinned: false,
      downloadedAt: DateTime(2026, 1, 1),
      progressDirty: false,
      bookmarkDirty: false,
      readStateDirty: false,
      readStateManual: false,
      syncedIsRead: false,
      lastReadAt: readAt,
      updatedAt: DateTime(2026),
      downloadGeneration: 0,
      serverFetchAttempts: 0,
    );

void main() {
  // Base scenario: deleteWhileReading = 1 (delete the just-read chapter).
  // Normal protection window (slots=1) → empty: nothing is kept.
  // Rolling window boundary (slots=2) → {ch3}: the just-read chapter is kept
  // for one boundary, allowing the user to flip back to ch3 without a download.
  group('rolling window with deleteWhileReading = 1 '
      '(delete the just-read chapter)', () {
    // After reading ch1 → ch2 → ch3.
    final chapters = [
      _ch(1, isRead: true, readAt: '1000'),
      _ch(2, isRead: true, readAt: '2000'),
      _ch(3, isRead: true, readAt: '3000'),
      _ch(4),
      _ch(5),
    ];
    const deleteWhileReading = 1;

    test(
      'boundary reconcile (slots+1) protects the just-read chapter '
      'so back-and-forth between ch2 and ch3 does not require a re-download',
      () {
        // slots = deleteWhileReading + 1 = 2 → keeps 1 most recently read
        expect(
          readChaptersInDeleteWindow(chapters, deleteWhileReading + 1),
          {3},
          reason:
              'ch3 (just finished) is the most recently read; '
              'keeping it at the boundary avoids a re-download on back-press',
        );
      },
    );
  });

}
