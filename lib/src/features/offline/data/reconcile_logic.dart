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
    // Excludes chapters already given up on (OfflineDeviceState.error) from the
    // candidate pool BEFORE cutting to `keepUnreadCount`. Without this, a
    // chapter the source can never serve (e.g. removed/renumbered upstream)
    // permanently occupies one of the N slots — the reconciler already skips
    // re-downloading an errored chapter every pass (so it never gets retried),
    // but nothing here ever let the (N+1)th unread chapter take its place, so
    // the user's "keep N downloaded" setting silently plateaus at N-1 forever.
    //
    // Also restricts to chapters AFTER the user's furthest-read position.
    // Without this, an unread gap earlier in the series (e.g. the user skipped
    // ch. 2 but read ch. 3+) causes the worker to download behind their reading
    // progress instead of ahead of it.
    //
    // Uses chapterNumber (the parsed chapter number: 1.0, 10.5, …) as the
    // ordering key because it reflects narrative reading order. Falls back to
    // chapterIndex (sourceOrder) for chapters whose number is absent or ≤ 0
    // (bonus/special chapters that the source never assigned a real number).
    OfflineKeepRule.nUnread => () {
      double readOrder(OfflineChapter c) {
        final n = c.chapterNumber;
        return (n != null && n > 0) ? n : c.chapterIndex.toDouble();
      }

      final floor = chapters
          .where((c) => c.isRead)
          .fold(-1.0, (m, c) => readOrder(c) > m ? readOrder(c) : m);
      return (chapters
                .where((c) =>
                    !c.isRead &&
                    c.deviceState != OfflineDeviceState.error &&
                    readOrder(c) > floor)
                .toList()
            ..sort((a, b) => readOrder(a).compareTo(readOrder(b))))
          .take(keepUnreadCount)
          .map((c) => c.id)
          .toSet();
    }(),
  };
  return ruleSet..addAll(pinned);
}

/// Chapter ids allowed to REMAIN on-device for one manga, given its keep-rule.
///
/// Deliberately broader than [desiredChapterIds] (which drives what to
/// *download*). The nUnread rule is a download-ahead window, not a deletion
/// window: a chapter already on the device that is still UNREAD is never
/// removed just for falling outside the next-N window or behind the
/// furthest-read floor. Without this split, marking a far-ahead chapter read
/// (or leaving a skipped gap) would silently delete unread chapters the reader
/// already has — e.g. at ch. 10 with 11..20 downloaded, marking ch. 100 read
/// would raise the floor to 100 and evict 11..20.
///
/// READ chapters are intentionally NOT retained here: under nUnread they still
/// fall out of the window and are cleaned by the rule (the rolling window),
/// on top of the delete-while-reading path. Every other rule retains exactly
/// what it downloads.
Set<int> retainedChapterIds(
  List<OfflineChapter> chapters,
  OfflineKeepRule rule,
  int keepUnreadCount,
) {
  final desired = desiredChapterIds(chapters, rule, keepUnreadCount);
  if (rule != OfflineKeepRule.nUnread) return desired;
  return {
    ...desired,
    for (final c in chapters)
      if (!c.isRead && c.deviceState == OfflineDeviceState.downloaded) c.id,
  };
}

/// Read chapters the "finished chapters to keep" setting still wants kept.
/// Slot N targets the chapter N-1 behind the one just finished, so the N-1
/// most recently read chapters are the ones the user asked to hold on to.
///
/// Ordered by the server's read timestamp, not chapter order: someone who
/// dips back to an early chapter has just-finished it, and ranking by chapter
/// number would protect wherever they got furthest instead. Rows synced before
/// per-chapter timestamps existed carry none, so they fall back to reading
/// order.
Set<int> readChaptersInDeleteWindow(List<OfflineChapter> chapters, int slots) {
  if (slots <= 1) return const {};
  int readAt(OfflineChapter c) => int.tryParse(c.lastReadAt ?? '') ?? 0;
  final read = chapters.where((c) => c.isRead).toList()
    ..sort((a, b) {
      final byTime = readAt(b).compareTo(readAt(a));
      if (byTime != 0) return byTime;
      final byOrder = b.chapterIndex.compareTo(a.chapterIndex);
      // Duplicate scanlator copies share a chapter index; id keeps the pick
      // stable instead of letting sort order decide.
      return byOrder != 0 ? byOrder : b.id.compareTo(a.id);
    });
  return read.take(slots - 1).map((c) => c.id).toSet();
}

/// Decide evictions over the currently-downloaded set, honoring precedence:
/// pinned > safety-nets > rule. Pinned chapters are never evicted.
/// [protected] chapters (read this session) dodge the rule eviction only —
/// the time and storage nets still apply, since those exist for space
/// pressure, not the rolling unread window.
({Set<int> evict, bool overCapWarning}) applySafetyNets({
  required List<OfflineChapter> downloaded,
  required Set<int> desired,
  required SafetyNetConfig nets,
  required DateTime now,
  Set<int> protected = const {},
}) {
  final evict = <int>{};

  // 1) Not wanted by any rule and not pinned.
  for (final c in downloaded) {
    if (!c.pinned && !desired.contains(c.id) && !protected.contains(c.id)) {
      evict.add(c.id);
    }
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

  // 3) Storage cap: evict oldest non-pinned until under cap. Tracks the
  // retained total as a running value instead of re-folding the whole
  // (already-filtered) list on every iteration — same result, O(n log n)
  // (the sort) instead of O(n^2) for a manga with many downloaded chapters.
  var overCapWarning = false;
  if (nets.storageCapEnabled) {
    final candidates = downloaded
        .where((c) => !c.pinned && !evict.contains(c.id))
        .toList()
      ..sort((a, b) => (a.downloadedAt ?? DateTime(0))
          .compareTo(b.downloadedAt ?? DateTime(0)));
    var retainedBytes = downloaded
        .where((c) => !evict.contains(c.id))
        .fold(0, (s, c) => s + c.bytes);
    var i = 0;
    while (retainedBytes > nets.storageCapBytes && i < candidates.length) {
      retainedBytes -= candidates[i].bytes;
      evict.add(candidates[i].id);
      i++;
    }
    if (retainedBytes > nets.storageCapBytes) {
      overCapWarning = true; // only pinned left
    }
  }

  return (evict: evict, overCapWarning: overCapWarning);
}
