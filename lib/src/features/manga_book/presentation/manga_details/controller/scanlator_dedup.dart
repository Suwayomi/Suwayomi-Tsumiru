// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:collection/collection.dart';

import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../domain/chapter/chapter_model.dart';
// The generated copyWith is an extension; it must be imported directly.
import '../../../domain/chapter/graphql/__generated__/fragment.graphql.dart';

/// Group key for chapters with no scanlator; displayed via l10n as "Unknown".
const String kUnknownScanlatorGroup = '';

String scanlatorGroupOf(ChapterDto c) =>
    c.scanlator.isNotBlank ? c.scanlator! : kUnknownScanlatorGroup;

/// One row per chapter number when [preferred] is non-empty.
///
/// Winner group per number: the in-flight copy ([keepChapterId], so an open
/// reader never loses its chapter), else an in-progress copy, else a
/// downloaded copy, else the highest-ranked group in [preferred] covering the
/// number, else the copy the source lists first. All of the winning group's
/// entries at that number survive (split chapters / v2 re-uploads share a
/// number). Rows carry aggregate read/downloaded/bookmarked state across ALL
/// copies of the number. Entries with chapterNumber <= 0 pass through.
List<ChapterDto> applyPreferredScanlators(
  List<ChapterDto> chapters,
  List<String> preferred, {
  int? keepChapterId,
}) {
  if (preferred.isEmpty) return chapters;

  final byNumber = <double, List<ChapterDto>>{};
  for (final c in chapters) {
    if (c.chapterNumber > 0) {
      byNumber.putIfAbsent(c.chapterNumber, () => []).add(c);
    }
  }

  final winnersByNumber = <double, String>{};
  for (final entry in byNumber.entries) {
    final copies = entry.value;
    final kept = keepChapterId == null
        ? null
        : copies.firstWhereOrNull((c) => c.id == keepChapterId);
    final inProgress =
        copies.firstWhereOrNull((c) => !c.isRead && c.lastPageRead > 0);
    final downloaded = copies.firstWhereOrNull((c) => c.isDownloaded);
    String? winner;
    if (kept != null) {
      winner = scanlatorGroupOf(kept);
    } else if (inProgress != null) {
      winner = scanlatorGroupOf(inProgress);
    } else if (downloaded != null) {
      winner = scanlatorGroupOf(downloaded);
    } else {
      winner = preferred.firstWhereOrNull(
          (g) => copies.any((c) => scanlatorGroupOf(c) == g));
      winner ??= scanlatorGroupOf(
          copies.reduce((a, b) => a.sourceOrder <= b.sourceOrder ? a : b));
    }
    winnersByNumber[entry.key] = winner;
  }

  return [
    for (final c in chapters)
      // Negated: `!(x > 0)` also catches NaN, unlike `x <= 0`.
      if (!(c.chapterNumber > 0))
        c
      else if (scanlatorGroupOf(c) == winnersByNumber[c.chapterNumber])
        c.copyWith(
          isRead: byNumber[c.chapterNumber]!.any((x) => x.isRead),
          isDownloaded:
              byNumber[c.chapterNumber]!.any((x) => x.isDownloaded),
          isBookmarked:
              byNumber[c.chapterNumber]!.any((x) => x.isBookmarked),
        ),
  ];
}

/// Ids of every copy sharing [chapterId]'s chapter number (self included).
/// Number <= 0 or unknown id: just the id itself.
List<int> duplicateChapterIds(List<ChapterDto> allChapters, int chapterId) {
  final chapter = allChapters.firstWhereOrNull((c) => c.id == chapterId);
  // Same NaN-safe negation as applyPreferredScanlators.
  if (chapter == null || !(chapter.chapterNumber > 0)) return [chapterId];
  return [
    for (final c in allChapters)
      if (c.chapterNumber == chapter.chapterNumber) c.id,
  ];
}

/// Write-side union of every same-number copy for each id (self included).
/// Identity when the raw list is unavailable.
List<int> expandIdsForDuplicates(
  List<ChapterDto>? allChapters,
  List<int> chapterIds,
) {
  if (allChapters == null) return chapterIds;
  final out = <int>{};
  for (final id in chapterIds) {
    out.addAll(duplicateChapterIds(allChapters, id));
  }
  return out.toList();
}

/// Unread copies whose chapter number has at least one read copy — the
/// one-time catch-up set when a preference is set on a series with history.
List<int> reconcileIdsForReadNumbers(List<ChapterDto> allChapters) {
  final readNumbers = <double>{
    for (final c in allChapters)
      if (c.isRead && c.chapterNumber > 0) c.chapterNumber,
  };
  return [
    for (final c in allChapters)
      if (!c.isRead && readNumbers.contains(c.chapterNumber)) c.id,
  ];
}
