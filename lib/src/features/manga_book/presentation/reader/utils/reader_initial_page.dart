// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../domain/chapter/chapter_model.dart';
import '../../../domain/chapter_page/chapter_page_model.dart';

int readerInitialPageIndex({
  required ChapterDto chapter,
  required ChapterPagesDto chapterPages,
  required bool openAtEnd,
}) {
  final loadedCount = chapterPages.pages.length;
  final pageCount =
      loadedCount > 0 ? loadedCount : chapterPages.chapter.pageCount;
  final lastIndex = pageCount > 0 ? pageCount - 1 : 0;
  if (openAtEnd) return lastIndex;
  if (chapter.isRead.ifNull()) return 0;
  return _clampPageIndex(
      chapter.lastPageRead.getValueOnNullOrNegative(), lastIndex);
}

int _clampPageIndex(int index, int lastIndex) {
  if (index < 0) return 0;
  if (index > lastIndex) return lastIndex;
  return index;
}
