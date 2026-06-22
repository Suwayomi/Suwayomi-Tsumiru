// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'offline_database.dart';
import 'reconcile_types.dart';

/// Chapter ids that should be on-device for one manga, given its keep-rule.
/// Always includes pinned chapters (manual saves are sticky, rule-independent).
Set<int> desiredChapterIds(
  List<OfflineChapter> chapters,
  OfflineKeepRule rule,
  int keepUnreadCount,
) {
  final pinned = {for (final c in chapters) if (c.pinned) c.id};
  final ruleSet = switch (rule) {
    OfflineKeepRule.off => <int>{},
    OfflineKeepRule.all => {for (final c in chapters) c.id},
    OfflineKeepRule.allUnread => {for (final c in chapters) if (!c.isRead) c.id},
    OfflineKeepRule.nUnread => (chapters.where((c) => !c.isRead).toList()
          ..sort((a, b) => a.chapterIndex.compareTo(b.chapterIndex)))
        .take(keepUnreadCount)
        .map((c) => c.id)
        .toSet(),
  };
  return ruleSet..addAll(pinned);
}

/// Decide evictions over the currently-downloaded set, honoring precedence:
/// pinned > safety-nets > rule. Pinned chapters are never evicted.
({Set<int> evict, bool overCapWarning}) applySafetyNets({
  required List<OfflineChapter> downloaded,
  required Set<int> desired,
  required SafetyNetConfig nets,
  required DateTime now,
}) {
  final evict = <int>{};

  // 1) Not wanted by any rule and not pinned.
  for (final c in downloaded) {
    if (!c.pinned && !desired.contains(c.id)) evict.add(c.id);
  }

  // 2) Time-net: non-pinned older than keepDays.
  if (nets.timeEvictEnabled) {
    for (final c in downloaded) {
      final dt = c.downloadedAt;
      if (!c.pinned && dt != null && now.difference(dt).inDays > nets.keepDays) {
        evict.add(c.id);
      }
    }
  }

  // 3) Storage cap: evict oldest non-pinned until under cap.
  var overCapWarning = false;
  if (nets.storageCapEnabled) {
    int total() => downloaded
        .where((c) => !evict.contains(c.id))
        .fold(0, (s, c) => s + c.bytes);
    final candidates = downloaded
        .where((c) => !c.pinned && !evict.contains(c.id))
        .toList()
      ..sort((a, b) => (a.downloadedAt ?? DateTime(0))
          .compareTo(b.downloadedAt ?? DateTime(0)));
    var i = 0;
    while (total() > nets.storageCapBytes && i < candidates.length) {
      evict.add(candidates[i++].id);
    }
    if (total() > nets.storageCapBytes) overCapWarning = true; // only pinned left
  }

  return (evict: evict, overCapWarning: overCapWarning);
}
