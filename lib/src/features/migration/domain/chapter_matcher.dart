// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

/// Pure chapter-state matching for migration — no GraphQL, fully unit-testable.
///
/// Shared by the single-entry engine and the bulk runner so both carry
/// read/bookmark/progress state identically.
library;

import 'package:collection/collection.dart';

/// The subset of a chapter the matcher reasons about.
class ChapterState {
  const ChapterState({
    required this.id,
    required this.chapterNumber,
    required this.name,
    required this.isRead,
    required this.isBookmarked,
    required this.lastPageRead,
  });

  final int id;
  final double chapterNumber;
  final String name;
  final bool isRead;
  final bool isBookmarked;
  final int lastPageRead;
}

/// A minimal, monotonic patch to apply to one target chapter. Only the fields
/// that ADD state are set; nulls mean "leave as-is".
class ChapterPatch {
  const ChapterPatch({
    required this.id,
    this.isRead,
    this.isBookmarked,
    this.lastPageRead,
  });

  final int id;
  final bool? isRead;
  final bool? isBookmarked;
  final int? lastPageRead;
}

/// Result of matching source state onto a target chapter set.
class ChapterMatchResult {
  const ChapterMatchResult({
    required this.patches,
    required this.unmatchedState,
  });

  /// One patch per target chapter that gains state; empty if nothing to carry.
  final List<ChapterPatch> patches;

  /// Count of source chapters that carried state but found no target match —
  /// their state can't migrate, so the caller must keep the source.
  final int unmatchedState;
}

/// Matches read/bookmark/progress from [source] onto [target] and returns the
/// minimal monotonic patch set (never un-reads, un-bookmarks, or rewinds).
///
/// Matching rules (deliberate Tsumiru divergence from Komikku, which uses exact
/// numeric equality with no tolerance and no name fallback):
///  - recognized numbers (>= 0): match by number within [numberTolerance]
///    (float-noise only), against target chapters that are themselves
///    recognized (>= 0).
///  - unrecognized numbers (< 0, e.g. oneshots): exact lowercased-name equality
///    only. NO substring/`contains` fallback — that let "Chapter 1" collide
///    with "Chapter 10".
ChapterMatchResult matchChapterState({
  required List<ChapterState> source,
  required List<ChapterState> target,
  double numberTolerance = 0.01,
}) {
  // Merge per target id, seeded from its own state, so several source chapters
  // matching one target can't overwrite higher progress with lower.
  final merged = <int, ({bool read, bool bookmark, int lastPage})>{};
  final targetById = {for (final c in target) c.id: c};
  var unmatchedState = 0;

  for (final s in source) {
    final hasState = s.isRead || s.isBookmarked || s.lastPageRead > 0;
    if (!hasState) continue;

    ChapterState? match;
    if (s.chapterNumber >= 0) {
      match = target
          .where((t) =>
              t.chapterNumber >= 0 &&
              (t.chapterNumber - s.chapterNumber).abs() < numberTolerance)
          .firstOrNull;
    } else if (s.name.trim().isNotEmpty) {
      final sourceName = s.name.toLowerCase().trim();
      match = target
          .where((t) => t.name.toLowerCase().trim() == sourceName)
          .firstOrNull;
    }

    if (match == null) {
      unmatchedState++;
      continue;
    }

    final prev = merged[match.id] ??
        (read: match.isRead, bookmark: match.isBookmarked, lastPage: match.lastPageRead);
    merged[match.id] = (
      read: prev.read || s.isRead,
      bookmark: prev.bookmark || s.isBookmarked,
      lastPage: s.lastPageRead > prev.lastPage ? s.lastPageRead : prev.lastPage,
    );
  }

  final patches = <ChapterPatch>[];
  for (final entry in merged.entries) {
    final original = targetById[entry.key]!;
    final m = entry.value;
    final setRead = m.read && !original.isRead;
    final setBookmark = m.bookmark && !original.isBookmarked;
    // Carry the furthest position independently of read state — a read chapter
    // can still record where it was left off.
    final setPosition = m.lastPage > original.lastPageRead;
    if (setRead || setBookmark || setPosition) {
      patches.add(ChapterPatch(
        id: entry.key,
        isRead: setRead ? true : null,
        isBookmarked: setBookmark ? true : null,
        lastPageRead: setPosition ? m.lastPage : null,
      ));
    }
  }

  return ChapterMatchResult(patches: patches, unmatchedState: unmatchedState);
}

/// Pairs source chapter ids to target chapter ids by chapter number — same
/// matching rule as [matchChapterState], but returns id linkage (which
/// downloaded file goes to which target chapter) instead of state patches.
/// Each target is claimed at most once, so two source chapters can't collide
/// onto the same target.
List<({int fromId, int toId})> matchChaptersByNumber({
  required List<ChapterState> source,
  required List<ChapterState> target,
  double numberTolerance = 0.01,
}) {
  final claimed = <int>{};
  final pairs = <({int fromId, int toId})>[];
  for (final s in source) {
    ChapterState? match;
    if (s.chapterNumber >= 0) {
      match = target
          .where((t) =>
              t.chapterNumber >= 0 &&
              !claimed.contains(t.id) &&
              (t.chapterNumber - s.chapterNumber).abs() < numberTolerance)
          .firstOrNull;
    } else if (s.name.trim().isNotEmpty) {
      final sourceName = s.name.toLowerCase().trim();
      match = target
          .where((t) =>
              !claimed.contains(t.id) &&
              t.name.toLowerCase().trim() == sourceName)
          .firstOrNull;
    }
    if (match == null) continue;
    claimed.add(match.id);
    pairs.add((fromId: s.id, toId: match.id));
  }
  return pairs;
}
