// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'offline_database.dart';
import 'reconcile_types.dart';

/// Always includes pinned chapters; a null [sortAxis] uses chapter number, then source order.
Set<int> desiredChapterIds(
  List<OfflineChapter> chapters,
  OfflineKeepRule rule,
  int keepUnreadCount, {
  ChapterSortAxis? sortAxis,
}) {
  final pinned = {
    for (final c in chapters)
      if (c.pinned) c.id,
  };
  final ruleSet = switch (rule) {
    OfflineKeepRule.off => <int>{},
    OfflineKeepRule.all => {for (final c in chapters) c.id},
    OfflineKeepRule.allUnread => {
      for (final c in chapters)
        if (!c.isRead) c.id,
    },
    // Keep the floor and window on one axis; unnumbered specials cannot share the numbered axis.
    OfflineKeepRule.nUnread => () {
      int? epoch(String? v) => v == null ? null : int.tryParse(v);
      int stamp(OfflineChapter c, ChapterSortAxis? axis) =>
          switch (axis) {
            ChapterSortAxis.uploadedAt => epoch(c.uploadDate),
            ChapterSortAxis.fetchedAt => epoch(c.fetchedAt),
            _ => null,
          } ??
          0;

      // Timestamp sorts need a down-sync before they have values; fall back until then.
      final axis =
          (sortAxis == ChapterSortAxis.uploadedAt ||
                  sortAxis == ChapterSortAxis.fetchedAt) &&
              !chapters.any((c) => stamp(c, sortAxis) > 0)
          ? null
          : sortAxis;

      final byNumber = axis == null
          ? chapters.any((c) => (c.chapterNumber ?? 0) > 0)
          : axis == ChapterSortAxis.chapterNumber;

      bool ranked(OfflineChapter c) => switch (axis) {
        null => !byNumber || (c.chapterNumber ?? 0) > 0,
        ChapterSortAxis.source => true, // chapterIndex is always present
        ChapterSortAxis.chapterNumber => (c.chapterNumber ?? 0) > 0,
        ChapterSortAxis.uploadedAt ||
        ChapterSortAxis.fetchedAt => stamp(c, axis) > 0,
        ChapterSortAxis.alphabetical => true, // name is always present
      };
      int byIndex(OfflineChapter a, OfflineChapter b) =>
          a.chapterIndex.compareTo(b.chapterIndex);
      int byAxis(OfflineChapter a, OfflineChapter b) => switch (axis) {
        null =>
          byNumber
              ? a.chapterNumber!.compareTo(b.chapterNumber!)
              : byIndex(a, b),
        ChapterSortAxis.source => byIndex(a, b),
        ChapterSortAxis.chapterNumber => a.chapterNumber!.compareTo(
          b.chapterNumber!,
        ),
        ChapterSortAxis.uploadedAt ||
        ChapterSortAxis.fetchedAt => stamp(a, axis).compareTo(stamp(b, axis)),
        // Match the chapter list so download-ahead follows the reader.
        ChapterSortAxis.alphabetical => a.name.toLowerCase().compareTo(
          b.name.toLowerCase(),
        ),
      };
      // Date/name ties are distinct chapters; number ties are scanlator duplicates excluded by the floor.
      final breakTies =
          axis == ChapterSortAxis.uploadedAt ||
          axis == ChapterSortAxis.fetchedAt ||
          axis == ChapterSortAxis.alphabetical;
      int readOrder(OfflineChapter a, OfflineChapter b) {
        final r = byAxis(a, b);
        return r != 0 || !breakTies ? r : byIndex(a, b);
      }

      final read = chapters.where((c) => c.isRead && ranked(c));
      final floor = read.isEmpty
          ? null
          : read.reduce((m, c) => readOrder(c, m) > 0 ? c : m);
      return (chapters
              .where(
                (c) =>
                    !c.isRead &&
                    ranked(c) &&
                    c.deviceState != OfflineDeviceState.error &&
                    (floor == null || readOrder(c, floor) > 0),
              )
              .toList()
            ..sort((a, b) {
              final r = readOrder(a, b);
              return r != 0 ? r : byIndex(a, b);
            }))
          .take(keepUnreadCount)
          .map((c) => c.id)
          .toSet();
    }(),
  };
  return ruleSet..addAll(pinned);
}

/// Under nUnread, retains downloaded unread chapters even outside the download-ahead window.
/// Read chapters still expire; other rules retain exactly what they request.
Set<int> retainedChapterIds(
  List<OfflineChapter> chapters,
  OfflineKeepRule rule,
  int keepUnreadCount, {
  ChapterSortAxis? sortAxis,
}) {
  final desired = desiredChapterIds(
    chapters,
    rule,
    keepUnreadCount,
    sortAxis: sortAxis,
  );
  if (rule != OfflineKeepRule.nUnread) return desired;
  return {
    ...desired,
    for (final c in chapters)
      if (!c.isRead && c.deviceState == OfflineDeviceState.downloaded) c.id,
  };
}

/// Retains slots − 1 read chapters, newest by read timestamp with reading-order fallback.
Set<int> readChaptersInDeleteWindow(List<OfflineChapter> chapters, int slots) {
  if (slots <= 1) return const {};
  int readAt(OfflineChapter c) => int.tryParse(c.lastReadAt ?? '') ?? 0;
  final read = chapters.where((c) => c.isRead).toList()
    ..sort((a, b) {
      final byTime = readAt(b).compareTo(readAt(a));
      if (byTime != 0) return byTime;
      final byOrder = b.chapterIndex.compareTo(a.chapterIndex);
      // Scanlator duplicates share an index; id makes the selection deterministic.
      return byOrder != 0 ? byOrder : b.id.compareTo(a.id);
    });
  return read.take(slots - 1).map((c) => c.id).toSet();
}

/// Eviction reasons use the first matching bucket in [applySafetyNets].
enum EvictReason {
  notDesired,

  timeNet,

  storageCap,
}

/// Pinned chapters are never evicted; [protected] bypasses rule eviction only, not safety nets.
({Set<int> evict, Map<int, EvictReason> reasons, bool overCapWarning})
    applySafetyNets({
  required List<OfflineChapter> downloaded,
  required Set<int> desired,
  required SafetyNetConfig nets,
  required DateTime now,
  Set<int> protected = const {},
}) {
  final evict = <int>{};
  final reasons = <int, EvictReason>{};

  for (final c in downloaded) {
    if (!c.pinned && !desired.contains(c.id) && !protected.contains(c.id)) {
      evict.add(c.id);
      reasons[c.id] = EvictReason.notDesired;
    }
  }

  if (nets.timeEvictEnabled) {
    for (final c in downloaded) {
      final dt = c.downloadedAt;
      if (!c.pinned &&
          dt != null &&
          now.difference(dt).inDays > nets.keepDays) {
        evict.add(c.id);
        reasons.putIfAbsent(c.id, () => EvictReason.timeNet);
      }
    }
  }

  var overCapWarning = false;
  if (nets.storageCapEnabled) {
    final candidates =
        downloaded.where((c) => !c.pinned && !evict.contains(c.id)).toList()
          ..sort(
            (a, b) => (a.downloadedAt ?? DateTime(0)).compareTo(
              b.downloadedAt ?? DateTime(0),
            ),
          );
    var retainedBytes = downloaded
        .where((c) => !evict.contains(c.id))
        .fold(0, (s, c) => s + c.bytes);
    var i = 0;
    while (retainedBytes > nets.storageCapBytes && i < candidates.length) {
      retainedBytes -= candidates[i].bytes;
      evict.add(candidates[i].id);
      reasons.putIfAbsent(candidates[i].id, () => EvictReason.storageCap);
      i++;
    }
    if (retainedBytes > nets.storageCapBytes) {
      overCapWarning = true; // only pinned left
    }
  }

  return (evict: evict, reasons: reasons, overCapWarning: overCapWarning);
}
