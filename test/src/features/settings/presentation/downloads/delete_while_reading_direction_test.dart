// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/settings/presentation/downloads/data/delete_chapters_settings_repository.dart';

ChapterDto _ch(int id, {bool isRead = false}) => Fragment$ChapterDto(
  id: id,
  mangaId: 1,
  name: 'c$id',
  chapterNumber: id.toDouble(),
  sourceOrder: id,
  isRead: isRead,
  isBookmarked: false,
  isDownloaded: true,
  lastPageRead: 0,
  pageCount: 10,
  fetchedAt: '$id',
  uploadDate: '$id',
  lastReadAt: '0',
  url: '',
  meta: const <Fragment$ChapterDto$meta>[],
);

/// What `_whileReadingTarget` now hands the shared calculation: every chapter,
/// in source order, whatever the details screen happens to be showing.
List<ChapterDto> _readingOrder(List<ChapterDto> chapters) =>
    [...chapters]..sort((a, b) => a.sourceOrder.compareTo(b.sourceOrder));

void main() {
  group('delete-while-reading targets reading order, not the visible list', () {
    final library = [
      _ch(1, isRead: true),
      _ch(2, isRead: true),
      _ch(3, isRead: true),
      _ch(4),
      _ch(5),
    ];

    test('slot N targets N-1 chapters behind the one just read', () {
      final order = _readingOrder(library);
      expect(chapterIdToDeleteWhileReading(order, true, 3, 1), 3);
      expect(chapterIdToDeleteWhileReading(order, true, 3, 2), 2);
      expect(chapterIdToDeleteWhileReading(order, true, 3, 3), 1);
    });

    test('a newest-first screen makes no difference', () {
      final asDisplayed = library.reversed.toList(growable: false);
      expect(
        chapterIdToDeleteWhileReading(_readingOrder(asDisplayed), true, 3, 2),
        2,
      );
    });

    test('read chapters stay in range, so every slot still resolves', () {
      final order = _readingOrder(library);
      for (var slots = 1; slots <= 3; slots++) {
        expect(
          chapterIdToDeleteWhileReading(order, true, 3, slots),
          isNotNull,
          reason: 'slot $slots must still find chapter 3 once it is read',
        );
      }
    });

    test('slots count chapters, never gaps left by a filtered-out chapter', () {
      final everything = _readingOrder(library);
      final asIfFiltered = [_ch(1, isRead: true), _ch(3, isRead: true), _ch(5)];
      expect(chapterIdToDeleteWhileReading(everything, true, 3, 2), 2);
      expect(
        chapterIdToDeleteWhileReading(asIfFiltered, true, 3, 2),
        1,
        reason:
            'the old path counted positions in the visible list, which '
            'skipped chapter 2 entirely',
      );
    });
  });
}
