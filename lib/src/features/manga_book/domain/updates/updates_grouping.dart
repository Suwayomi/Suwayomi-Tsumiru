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

/// Joins a series' rows from the same day even when another series sits between them.
List<UpdatesGroupedEntry> groupUpdatesForDisplay(
  List<ChapterWithMangaDto> items,
) {
  final groups = <List<ChapterWithMangaDto>>[];
  for (final item in items) {
    var placed = false;
    for (final group in groups) {
      if (group.first.mangaId == item.mangaId &&
          _sameFetchDay(group.first, item)) {
        group.add(item);
        placed = true;
        break;
      }
    }
    if (!placed) groups.add([item]);
  }
  return [for (final group in groups) _closeGroup(group)];
}

UpdatesGroupedEntry _closeGroup(List<ChapterWithMangaDto> group) {
  final head = pickGroupHead(group);
  return UpdatesGroupedEntry(
    head: head,
    tail: [
      for (final c in group)
        if (c.id != head.id) c,
    ],
  );
}

// Unparsable timestamps share one null day per manga.
bool _sameFetchDay(ChapterWithMangaDto a, ChapterWithMangaDto b) {
  final fa = int.tryParse(a.fetchedAt);
  final fb = int.tryParse(b.fetchedAt);
  if (fa == null || fb == null) return fa == null && fb == null;
  return fa.isSameDayAs(fb);
}

ChapterWithMangaDto pickGroupHead(List<ChapterWithMangaDto> chapters) {
  assert(chapters.isNotEmpty);
  final unread = [
    for (final c in chapters)
      if (!c.user.isRead) c,
  ];
  if (unread.isEmpty) {
    return chapters.reduce((a, b) => _releasedAfter(b, a) ? b : a);
  }
  return unread.reduce((a, b) => _releasedAfter(b, a) ? a : b);
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

class UpdatesDaySection {
  const UpdatesDaySection({
    required this.headerFlatIndex,
    required this.dayKey,
    required this.groups,
  });

  final int headerFlatIndex;
  final int? dayKey;
  final List<UpdatesGroupedEntry> groups;
}

List<UpdatesDaySection> groupUpdatesByDay(
  List<ChapterWithMangaDto> items,
  List<UpdatesGroupedEntry> groups,
) {
  final groupOfId = <int, int>{};
  for (var g = 0; g < groups.length; g++) {
    groupOfId[groups[g].head.id] = g;
    for (final c in groups[g].tail) {
      groupOfId[c.id] = g;
    }
  }
  final sections = <int?, UpdatesDaySection>{};
  final placed = <int>{};
  for (var i = 0; i < items.length; i++) {
    final g = groupOfId[items[i].id];
    if (g == null || !placed.add(g)) continue;
    final fetchedAt = int.tryParse(items[i].fetchedAt);
    final dayKey = fetchedAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            fetchedAt * 1000,
          ).startOfDay.millisecondsSinceEpoch;
    (sections[dayKey] ??= UpdatesDaySection(
      headerFlatIndex: i,
      dayKey: dayKey,
      groups: [],
    )).groups.add(groups[g]);
  }
  return sections.values.toList();
}

Map<int, int> headFlatIndexToDisplayIndex(
  List<ChapterWithMangaDto> items,
  List<UpdatesGroupedEntry> groups,
) {
  final groupOfId = <int, int>{};
  for (var g = 0; g < groups.length; g++) {
    groupOfId[groups[g].head.id] = g;
    for (final c in groups[g].tail) {
      groupOfId[c.id] = g;
    }
  }
  final map = <int, int>{};
  final seenGroups = <int>{};
  for (var i = 0; i < items.length; i++) {
    final g = groupOfId[items[i].id];
    if (g != null && seenGroups.add(g)) map[i] = g;
  }
  return map;
}
