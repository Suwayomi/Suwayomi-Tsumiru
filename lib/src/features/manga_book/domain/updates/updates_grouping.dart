// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import '../../../../utils/extensions/custom_extensions.dart';
import '../chapter/chapter_model.dart';

/// An ungrouped chapter has an empty [tail].
class UpdatesGroupedEntry {
  const UpdatesGroupedEntry({required this.head, required this.tail});

  final ChapterWithMangaDto head;
  final List<ChapterWithMangaDto> tail;

  int get mangaId => head.mangaId;
}

/// Groups only consecutive same-manga/same-day rows; choose the head after collecting the full run.
List<UpdatesGroupedEntry> groupUpdatesForDisplay(
  List<ChapterWithMangaDto> items,
) {
  final runs = <List<ChapterWithMangaDto>>[];
  for (final item in items) {
    final last = runs.lastOrNull;
    if (last != null &&
        last.first.mangaId == item.mangaId &&
        int.tryParse(
          item.fetchedAt,
        ).isSameDayAs(int.tryParse(last.first.fetchedAt))) {
      last.add(item);
    } else {
      runs.add([item]);
    }
  }
  return [for (final run in runs) _closeRun(run)];
}

UpdatesGroupedEntry _closeRun(List<ChapterWithMangaDto> run) {
  final head = pickGroupHead(run);
  return UpdatesGroupedEntry(
    head: head,
    tail: [
      for (final c in run)
        if (c.id != head.id) c,
    ],
  );
}

/// Chooses the newest unread release, or newest release if all are read; requires a nonempty list.
ChapterWithMangaDto pickGroupHead(List<ChapterWithMangaDto> chapters) {
  assert(chapters.isNotEmpty);
  final unread = [
    for (final c in chapters)
      if (!c.user.isRead) c,
  ];
  final candidates = unread.isNotEmpty ? unread : chapters;
  return candidates.reduce((a, b) => _releasedAfter(b, a) ? b : a);
}

/// Break equal fetch timestamps by sourceOrder, which increases in reading order.
bool _releasedAfter(ChapterWithMangaDto a, ChapterWithMangaDto b) {
  final fetchedCompare = (int.tryParse(a.fetchedAt) ?? 0).compareTo(
    int.tryParse(b.fetchedAt) ?? 0,
  );
  if (fetchedCompare != 0) return fetchedCompare > 0;
  return a.sourceOrder.compareTo(b.sourceOrder) > 0;
}

/// Headers mark the first occurrence of each day; live offset pagination can repeat days out of order.
Set<int> dateHeaderIndices(List<ChapterWithMangaDto> items) {
  final seenDays = <int>{};
  final headerIndices = <int>{};
  for (var i = 0; i < items.length; i++) {
    final fetchedAt = int.tryParse(items[i].fetchedAt);
    if (fetchedAt == null) continue;
    final dayKey = DateTime.fromMillisecondsSinceEpoch(
      fetchedAt * 1000,
    ).startOfDay.millisecondsSinceEpoch;
    if (seenDays.add(dayKey)) headerIndices.add(i);
  }
  return headerIndices;
}

/// Maps head flat indices to display indices; absent entries are tails and should render nothing.
Map<int, int> headFlatIndexToDisplayIndex(List<UpdatesGroupedEntry> groups) {
  final map = <int, int>{};
  var flatCursor = 0;
  for (var g = 0; g < groups.length; g++) {
    map[flatCursor] = g;
    flatCursor += 1 + groups[g].tail.length;
  }
  return map;
}
