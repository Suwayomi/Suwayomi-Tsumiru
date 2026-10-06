// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import '../../../domain/chapter/chapter_model.dart';
import '../../../domain/chapter/missing_chapters.dart';

sealed class MangaChapterListEntry {
  const MangaChapterListEntry();
}

class MangaChapterEntry extends MangaChapterListEntry {
  const MangaChapterEntry(this.chapter);

  final ChapterDto chapter;
}

class MissingChaptersEntry extends MangaChapterListEntry {
  const MissingChaptersEntry({required this.id, required this.count});

  final String id;
  final int count;
}

/// Inserts each catalogue gap once into an already sorted chapter list.
///
/// Gaps come from [sortedChapters], before display filters are applied. The
/// [visibleChapterIds] set only controls chapter rows, so filtering a present
/// chapter cannot make it look missing. Each gap is anchored to its higher
/// chapter once, regardless of display order. [ascending] controls which side
/// of that row the notice occupies and the edge for an initial gap.
List<MangaChapterListEntry> buildMangaChapterListEntries({
  required List<ChapterDto> sortedChapters,
  required Set<int> visibleChapterIds,
  required bool ascending,
}) {
  if (visibleChapterIds.isEmpty) return const [];

  final gaps = findMissingChapterRanges(
    sortedChapters.map((chapter) => chapter.chapterNumber),
  );
  if (gaps.isEmpty) {
    return [
      for (final chapter in sortedChapters)
        if (visibleChapterIds.contains(chapter.id)) MangaChapterEntry(chapter),
    ];
  }

  final pendingGaps = {for (final gap in gaps) gap.higherChapter: gap};
  final entries = <MangaChapterListEntry>[];
  final hasChapterZero = sortedChapters.any(
    (chapter) =>
        chapter.chapterNumber >= 0 &&
        chapter.chapterNumber.isFinite &&
        chapter.chapterNumber.floor() == 0,
  );
  final initialGap = gaps.first.lowerChapter == 0 && !hasChapterZero
      ? gaps.first
      : null;

  void addGaps(List<MissingChapterRange> fresh) {
    if (fresh.isEmpty) return;
    entries.add(
      MissingChaptersEntry(
        id: fresh.map((range) => range.id).join('_'),
        count: fresh.fold(0, (total, range) => total + range.count),
      ),
    );
  }

  if (initialGap != null) {
    pendingGaps.remove(initialGap.higherChapter);
    if (ascending) addGaps([initialGap]);
  }

  for (final chapter in sortedChapters) {
    final number = chapter.chapterNumber;
    final gap = number >= 0 && number.isFinite
        ? pendingGaps.remove(number.floor())
        : null;
    if (ascending && gap != null) addGaps([gap]);
    entries.add(MangaChapterEntry(chapter));
    if (!ascending && gap != null) addGaps([gap]);
  }

  if (!ascending && initialGap != null) {
    addGaps([initialGap]);
  }

  final visibleEntries = <MangaChapterListEntry>[];
  for (final entry in entries) {
    if (entry is MangaChapterEntry &&
        !visibleChapterIds.contains(entry.chapter.id)) {
      continue;
    }
    final previous = visibleEntries.isEmpty ? null : visibleEntries.last;
    if (entry is MissingChaptersEntry && previous is MissingChaptersEntry) {
      visibleEntries[visibleEntries.length - 1] = MissingChaptersEntry(
        id: '${previous.id}_${entry.id}',
        count: previous.count + entry.count,
      );
    } else {
      visibleEntries.add(entry);
    }
  }
  return visibleEntries;
}
