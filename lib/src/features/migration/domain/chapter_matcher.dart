// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

library;

import 'package:collection/collection.dart';

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

/// Only adds state; null patch fields leave the target unchanged.
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

class ChapterMatchResult {
  const ChapterMatchResult({
    required this.patches,
    required this.unmatchedState,
  });

  final List<ChapterPatch> patches;

  /// Source chapters with unmatched state; callers must retain the source.
  final int unmatchedState;
}

// Negative chapter numbers are unknown placeholders, not progress.
double? latestChapterNumber(Iterable<num?>? values) {
  double? best;
  for (final value in values ?? const <num?>[]) {
    final n = value?.toDouble();
    if (n == null || n < 0) continue;
    if (best == null || n > best) best = n;
  }
  return best;
}

/// Monotonic merge: recognized numbers use tolerance; unknown numbers require exact lowercase names.
ChapterMatchResult matchChapterState({
  required List<ChapterState> source,
  required List<ChapterState> target,
  double numberTolerance = 0.01,
}) {
  // Seed from target state so multiple source matches cannot reduce progress.
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
    // Carry progress even for read chapters.
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

/// Links download IDs using chapter matching rules; each target is claimed at most once.
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
