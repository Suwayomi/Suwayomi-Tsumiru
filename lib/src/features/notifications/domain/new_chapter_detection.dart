// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

library;

/// fetchedAt is server epoch seconds (now.epochSecond), never device time.
typedef NotifiableChapter = ({
  int id,
  int mangaId,
  double chapterNumber,
  int fetchedAt,
});

/// High-water fetch time plus recent chapter timestamps; overlap catches late commits below the high-water mark.
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

/// Chapters ordered by number so the first new chapter opens before later ones.
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

/// Five-minute overlap catches out-of-order server commits; fetchedAt uses seconds.
const kDefaultOverlapSeconds = 5 * 60;

/// Seeds overlap entries through [maxFetched] as seen, retaining newer concurrent arrivals as fresh.
NewChapterWatermark seedNewChapterWatermark({
  required int maxFetched,
  required List<NotifiableChapter> window,
}) =>
    NewChapterWatermark(
      fetchedAt: maxFetched,
      recent: {
        for (final c in window)
          if (c.fetchedAt <= maxFetched) c.id: c.fetchedAt,
      },
    );

/// Caller exhausts overlap pages; null scope allows all manga and excluded candidates still advance the watermark.
/// Re-including categories does not backfill chapters older than the overlap window.
NewChapterDetectionResult detectNewChapters({
  required List<NotifiableChapter> candidates,
  required NewChapterWatermark watermark,
  Set<int>? allowedMangaIds,
  int overlapSeconds = kDefaultOverlapSeconds,
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
  // Retain dedup IDs for the next overlap scan.
  final cutoff = maxFetched - overlapSeconds;
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

/// Structured chapter-count label localized by the presenter.
sealed class NewChaptersLabel {
  const NewChaptersLabel();
}

class GenericNewChapters extends NewChaptersLabel {
  const GenericNewChapters(this.count);
  final int count;
}

class SingleNewChapter extends NewChaptersLabel {
  const SingleNewChapter(this.number, this.more);
  final String number;
  final int more;
}

class MultipleNewChapters extends NewChaptersLabel {
  const MultipleNewChapters(this.numbers, this.more);
  final List<String> numbers;
  final int more;
}

// Maximum chapter numbers listed before an "and N more" suffix.
const _maxShownChapters = 5;

NewChaptersLabel newChaptersLabel(
    List<double> chapterNumbers, int totalCount) {
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
