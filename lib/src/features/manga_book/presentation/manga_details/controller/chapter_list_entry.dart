// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:collection';

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
/// chapter cannot make it look missing. [ascending] identifies which neighbour
/// is the lower chapter and which edge represents the beginning of the series.
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

  final pendingGaps = SplayTreeMap<int, MissingChapterRange>()
    ..addEntries(gaps.map((gap) => MapEntry(gap.lowerChapter, gap)));
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

  void addGapsBetween(int lower, int higher) {
    final fresh = <MissingChapterRange>[];
    var key = pendingGaps.firstKeyAfter(lower - 1);
    while (key != null) {
      final gap = pendingGaps[key]!;
      if (gap.higherChapter > higher) break;
      fresh.add(gap);
      pendingGaps.remove(key);
      key = pendingGaps.firstKeyAfter(key);
    }
    addGaps(fresh);
  }

  if (ascending && initialGap != null) {
    pendingGaps.remove(initialGap.lowerChapter);
    addGaps([initialGap]);
  }

  for (var index = 0; index < sortedChapters.length; index++) {
    if (index > 0) {
      final previous = sortedChapters[index - 1].chapterNumber;
      final current = sortedChapters[index].chapterNumber;
      if (previous >= 0 &&
          previous.isFinite &&
          current >= 0 &&
          current.isFinite) {
        final lower = (ascending ? previous : current).floor();
        final higher = (ascending ? current : previous).floor();
        if (higher > lower) {
          addGapsBetween(lower, higher);
        }
      }
    }
    entries.add(MangaChapterEntry(sortedChapters[index]));
  }

  if (!ascending && initialGap != null && pendingGaps.containsKey(0)) {
    pendingGaps.remove(initialGap.lowerChapter);
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
