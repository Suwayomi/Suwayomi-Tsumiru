// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import '../../../../utils/extensions/custom_extensions.dart';
import '../chapter/chapter_model.dart';

/// One display row on the Updates page: a representative [head] chapter, plus
/// any further same-manga/same-day chapters folded into [tail]. An ungrouped
/// chapter is an entry with an empty [tail].
class UpdatesGroupedEntry {
  const UpdatesGroupedEntry({required this.head, required this.tail});

  final ChapterWithMangaDto head;
  final List<ChapterWithMangaDto> tail;

  int get mangaId => head.mangaId;
}

/// Groups consecutive chapters that share the same manga and the same calendar
/// day into [UpdatesGroupedEntry] records. Ungrouped chapters become an entry
/// with an empty tail. Grouping only merges strictly consecutive rows — a
/// manga interrupted by a different one in between starts a new group.
///
/// Each run is kept in original (chronological) order until it is closed, so
/// [pickGroupHead] always sees the group's true member order — folding the
/// head choice into the run incrementally would let an already-superseded
/// pick reappear once later reads/unreads are added.
List<UpdatesGroupedEntry> groupUpdatesForDisplay(
  List<ChapterWithMangaDto> items,
) {
  final runs = <List<ChapterWithMangaDto>>[];
  for (final item in items) {
    final last = runs.lastOrNull;
    if (last != null &&
        last.first.mangaId == item.mangaId &&
        int.tryParse(item.fetchedAt)
            .isSameDayAs(int.tryParse(last.first.fetchedAt))) {
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
    tail: [for (final c in run) if (c.id != head.id) c],
  );
}

/// Picks the representative chapter for a group: the last unread chapter,
/// or the first chapter if all are already read — matching WebUI behaviour.
ChapterWithMangaDto pickGroupHead(List<ChapterWithMangaDto> chapters) {
  assert(chapters.isNotEmpty);
  return chapters.lastWhere(
    (c) => !c.isRead,
    orElse: () => chapters.first,
  );
}

/// Maps each group's head flat-list index to its position in [groups] —
/// computed once for the whole result and shared, instead of every row's
/// `itemBuilder` call doing its own O(groups) scan to answer "is this flat
/// index a group head, and if so which group?" A flat index absent from the
/// map is a tail member (or out of range): the caller should render nothing
/// for it, since its group already rendered at the head's index.
Map<int, int> headFlatIndexToDisplayIndex(List<UpdatesGroupedEntry> groups) {
  final map = <int, int>{};
  var flatCursor = 0;
  for (var g = 0; g < groups.length; g++) {
    map[flatCursor] = g;
    flatCursor += 1 + groups[g].tail.length;
  }
  return map;
}
