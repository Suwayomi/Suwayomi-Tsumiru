// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

/// Pure new-chapter detection for background notifications — no GraphQL, no
/// isolate, fully unit-testable. The background worker feeds it the server's
/// unread in-library chapters (already filtered `fetchedAt >= watermark`), and
/// it returns which series to notify plus the advanced watermark.
library;

/// The minimal shape the detector reasons about. `fetchedAt` is the server's
/// fetch timestamp as epoch millis — the authoritative "new" signal (never the
/// device clock, so client/server skew can't drop or duplicate a chapter).
typedef NotifiableChapter = ({
  int id,
  int mangaId,
  double chapterNumber,
  int fetchedAt,
});

/// Persisted detection cursor. `fetchedAt` is the high-water fetch time seen;
/// `recent` maps recently-notified chapter id → its `fetchedAt`, kept only for
/// the overlap window. The window (not a bare `>` cutoff) is what recovers a
/// chapter that commits out of order *below* the high-water mark: the worker
/// re-queries `fetchedAt >= high − overlap`, and `recent` dedupes what it
/// already sent, so a late-but-below chapter still surfaces exactly once.
class NewChapterWatermark {
  const NewChapterWatermark({this.fetchedAt = 0, this.recent = const {}});
  final int fetchedAt;
  final Map<int, int> recent;

  Map<String, dynamic> toJson() => {
        'fetchedAt': fetchedAt,
        'recent': {for (final e in recent.entries) '${e.key}': e.value},
      };

  factory NewChapterWatermark.fromJson(Map<String, dynamic> json) =>
      NewChapterWatermark(
        fetchedAt: (json['fetchedAt'] as num?)?.toInt() ?? 0,
        recent: {
          for (final e in (json['recent'] as Map? ?? const {}).entries)
            int.parse('${e.key}'): (e.value as num).toInt(),
        },
      );
}

/// One series' worth of new chapters, chapter-number ordered so "open first new
/// chapter" lands on the earliest, not the last-fetched.
class MangaNewChapters {
  const MangaNewChapters({required this.mangaId, required this.chapters});
  final int mangaId;
  final List<NotifiableChapter> chapters;
}

class NewChapterDetectionResult {
  const NewChapterDetectionResult({required this.groups, required this.watermark});
  final List<MangaNewChapters> groups;
  final NewChapterWatermark watermark;
}

/// Default overlap window (ms) the worker re-scans below the high-water mark to
/// catch out-of-order `fetchedAt` commits. Generous vs. realistic commit skew.
const kDefaultOverlapMs = 5 * 60 * 1000;

/// Given the server's candidate chapters (unread, in-library, `fetchedAt >=`
/// high-water − overlap, paginated to exhaustion by the caller), returns the
/// per-series groups to notify and the next watermark. [allowedMangaIds] null =
/// all series; otherwise the category scope.
///
/// Fresh = any candidate not already in [watermark].recent (so an out-of-order
/// commit within the overlap window still fires exactly once). The high-water
/// advances over ALL candidates seen — read/excluded ones the server still
/// returns included — so they don't re-surface; category scope is forward-only
/// past the window (re-including a category doesn't retroactively notify old
/// chapters).
NewChapterDetectionResult detectNewChapters({
  required List<NotifiableChapter> candidates,
  required NewChapterWatermark watermark,
  Set<int>? allowedMangaIds,
  int overlapMs = kDefaultOverlapMs,
}) {
  final fresh = [
    for (final c in candidates)
      if (!watermark.recent.containsKey(c.id)) c,
  ];
  final notifiable = [
    for (final c in fresh)
      if (allowedMangaIds == null || allowedMangaIds.contains(c.mangaId)) c,
  ];

  final byManga = <int, List<NotifiableChapter>>{};
  for (final c in notifiable) {
    (byManga[c.mangaId] ??= []).add(c);
  }
  final groups = [
    for (final entry in byManga.entries)
      MangaNewChapters(
        mangaId: entry.key,
        chapters: entry.value
          ..sort((a, b) => a.chapterNumber.compareTo(b.chapterNumber)),
      ),
  ];

  var maxFetched = watermark.fetchedAt;
  for (final c in candidates) {
    if (c.fetchedAt > maxFetched) maxFetched = c.fetchedAt;
  }
  // Carry the old recent set + the ids we just notified, pruned to the window
  // the next query will re-scan (`>= maxFetched − overlap`).
  final cutoff = maxFetched - overlapMs;
  final recent = <int, int>{
    for (final e in watermark.recent.entries)
      if (e.value >= cutoff) e.key: e.value,
    for (final c in notifiable)
      if (c.fetchedAt >= cutoff) c.id: c.fetchedAt,
  };

  return NewChapterDetectionResult(
    groups: groups,
    watermark: NewChapterWatermark(fetchedAt: maxFetched, recent: recent),
  );
}

/// The per-series chapter-count phrase, ported 1:1 from Komikku/Mihon
/// `getNewChaptersDescription` (`LibraryUpdateNotifier.kt:302-361`). Kept as a
/// structured label so the presenter localizes it — the logic stays testable.
sealed class NewChaptersLabel {
  const NewChaptersLabel();
}

/// No parseable chapter numbers → "N new chapters".
class GenericNewChapters extends NewChaptersLabel {
  const GenericNewChapters(this.count);
  final int count;
}

/// One parseable number → "Chapter X" (+ "and N more" when other chapters
/// lacked a number).
class SingleNewChapter extends NewChaptersLabel {
  const SingleNewChapter(this.number, this.more);
  final String number;
  final int more;
}

/// Several parseable numbers → "Chapters 1, 2.5, 3" (+ "and N more" past the cap).
class MultipleNewChapters extends NewChaptersLabel {
  const MultipleNewChapters(this.numbers, this.more);
  final List<String> numbers;
  final int more;
}

/// Komikku's `NOTIF_MAX_CHAPTERS`.
const _maxShownChapters = 5;

NewChaptersLabel newChaptersLabel(
    List<double> chapterNumbers, int totalCount) {
  // Recognized numbers only (>= 0), sorted, formatted, de-duplicated — mirrors
  // Komikku's `filter { isRecognizedNumber }.sortedBy { chapterNumber }.toSet()`.
  final formatted = <String>{};
  for (final n in chapterNumbers.where((n) => n >= 0).toList()..sort()) {
    formatted.add(_formatChapterNumber(n));
  }
  final numbers = formatted.toList();

  switch (numbers.length) {
    case 0:
      return GenericNewChapters(totalCount);
    case 1:
      return SingleNewChapter(numbers.first, totalCount - numbers.length);
    default:
      if (numbers.length > _maxShownChapters) {
        return MultipleNewChapters(
          numbers.take(_maxShownChapters).toList(),
          numbers.length - _maxShownChapters,
        );
      }
      return MultipleNewChapters(numbers, 0);
  }
}

String _formatChapterNumber(double n) =>
    n == n.roundToDouble() ? n.toInt().toString() : n.toString();
