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
  group(
    'rolling window with deleteWhileReading = 1 '
    '(delete the just-read chapter)',
    () {
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
        'normal exit reconcile keeps no read chapters in the protection window',
        () {
          // slots = deleteWhileReading = 1 → readChaptersInDeleteWindow returns {}
          expect(
            readChaptersInDeleteWindow(chapters, deleteWhileReading),
            isEmpty,
            reason: 'delete-while-reading=1 targets the just-read chapter; '
                'nothing to protect behind it',
          );
        },
      );

      test(
        'boundary reconcile (slots+1) protects the just-read chapter '
        'so back-and-forth between ch2 and ch3 does not require a re-download',
        () {
          // slots = deleteWhileReading + 1 = 2 → keeps 1 most recently read
          expect(
            readChaptersInDeleteWindow(chapters, deleteWhileReading + 1),
            {3},
            reason: 'ch3 (just finished) is the most recently read; '
                'keeping it at the boundary avoids a re-download on back-press',
          );
        },
      );

      test(
        'boundary window is a strict superset of exit window',
        () {
          final exitWindow =
              readChaptersInDeleteWindow(chapters, deleteWhileReading);
          final boundaryWindow =
              readChaptersInDeleteWindow(chapters, deleteWhileReading + 1);
          expect(
            boundaryWindow.length,
            greaterThan(exitWindow.length),
            reason: 'boundary always protects at least one more read chapter '
                'than the normal exit value',
          );
          expect(
            boundaryWindow,
            containsAll(exitWindow),
            reason: 'every chapter the exit window protects is also protected '
                'at the boundary',
          );
        },
      );
    },
  );

  // Second scenario: deleteWhileReading = 2 (delete the chapter two behind).
  // Normal protection window (slots=2) → {ch3}: the most recently read.
  // Rolling window boundary (slots=3) → {ch2, ch3}: two chapters protected.
  group(
    'rolling window with deleteWhileReading = 2 '
    '(delete second-to-last read chapter)',
    () {
      final chapters = [
        _ch(1, isRead: true, readAt: '1000'),
        _ch(2, isRead: true, readAt: '2000'),
        _ch(3, isRead: true, readAt: '3000'),
        _ch(4),
        _ch(5),
      ];
      const deleteWhileReading = 2;

      test('normal exit reconcile keeps only the most recently read chapter', () {
        expect(
          readChaptersInDeleteWindow(chapters, deleteWhileReading),
          {3},
          reason: 'slots=2 protects the 1 most recently read chapter (ch3)',
        );
      });

      test(
        'boundary reconcile protects the two most recently read chapters',
        () {
          expect(
            readChaptersInDeleteWindow(chapters, deleteWhileReading + 1),
            {2, 3},
            reason: 'slots=3 protects ch2 and ch3, giving extra breathing room '
                'at the chapter boundary',
          );
        },
      );
    },
  );

  // Edge case: deleteWhileReading = 0 (delete-while-reading disabled).
  // Rolling window boundary raises to slots=1 which still keeps nothing (the
  // function returns {} for slots ≤ 1). The reconcile still runs and can
  // trigger the nUnread download ahead, even without any delete protection.
  group('rolling window with deleteWhileReading = 0 (delete disabled)', () {
    final chapters = [
      _ch(1, isRead: true),
      _ch(2, isRead: true),
      _ch(3, isRead: true),
      _ch(4),
    ];
    const deleteWhileReading = 0;

    test('exit reconcile keeps nothing (delete is off)', () {
      expect(
        readChaptersInDeleteWindow(chapters, deleteWhileReading),
        isEmpty,
      );
    });

    test('boundary reconcile (slots+1 = 1) also keeps nothing', () {
      // slots=1 is the ≤1 branch — still empty.
      expect(
        readChaptersInDeleteWindow(chapters, deleteWhileReading + 1),
        isEmpty,
        reason: 'slots=1 triggers the ≤1 guard; the boundary reconcile still '
            'runs for the nUnread download, but no delete protection applies',
      );
    });
  });

  // The nUnread desired set is purely determined by which chapters are read
  // and the keep-N count. It is independent of which deleteWhileReadingSlots
  // value the rolling window uses — the boundary trigger doesn't change it.
  group('nUnread desired set is unaffected by rolling window', () {
    test('desiredChapterIds returns the same set at boundary and at exit', () {
      final chapters = [
        _ch(1, isRead: true),
        _ch(2, isRead: true),
        _ch(3),
        _ch(4),
        _ch(5),
      ];
      const keepN = 2;
      expect(
        desiredChapterIds(chapters, OfflineKeepRule.nUnread, keepN),
        {3, 4},
        reason: 'the two next unread chapters are ch3 and ch4 regardless of '
            'which deleteWhileReadingSlots value the rolling window uses',
      );
    });
  });
}
