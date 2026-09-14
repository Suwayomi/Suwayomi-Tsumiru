// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:collection/collection.dart';

import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../domain/chapter/chapter_model.dart';

/// Group key for chapters with no scanlator; displayed via l10n as "Unknown".
const String kUnknownScanlatorGroup = '';

String scanlatorGroupOf(ChapterDto c) =>
    c.scanlator.isNotBlank ? c.scanlator! : kUnknownScanlatorGroup;

/// Filters by scanlator without assuming that equal chapter numbers identify
/// alternate releases. Every row from a preferred group survives, including
/// specials and series whose numbering restarts. [keepChapterId] keeps an open
/// reader chapter visible even when its group is not preferred.
List<ChapterDto> filterPreferredScanlators(
  List<ChapterDto> chapters,
  List<String> preferred, {
  int? keepChapterId,
}) {
  if (preferred.isEmpty) return chapters;
  return [
    for (final chapter in chapters)
      if (chapter.id == keepChapterId ||
          preferred.contains(scanlatorGroupOf(chapter)))
        chapter,
  ];
}

String _normalizedChapterName(String name) =>
    name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

bool _canConfidentlyMatch(ChapterDto previous, ChapterDto chapter) {
  if (!(previous.chapterNumber >= 0) || !(chapter.chapterNumber >= 0)) {
    return false;
  }
  return previous.chapterNumber == chapter.chapterNumber &&
      _normalizedChapterName(previous.name) ==
          _normalizedChapterName(chapter.name) &&
      scanlatorGroupOf(previous) != scanlatorGroupOf(chapter);
}

/// Groups only releases that satisfy the conservative reader match. Sorting
/// by source order first keeps otherwise-identical rows independent when an
/// intervening chapter shows that they belong to different runs.
List<List<ChapterDto>> _confidentReleaseGroups(List<ChapterDto> chapters) {
  final sourceOrdered = [...chapters]
    ..sort((a, b) {
      final bySourceOrder = a.sourceOrder.compareTo(b.sourceOrder);
      return bySourceOrder != 0 ? bySourceOrder : a.id.compareTo(b.id);
    });
  final releaseGroups = <List<ChapterDto>>[];
  for (final chapter in sourceOrdered) {
    if (releaseGroups.isEmpty) {
      releaseGroups.add([chapter]);
      continue;
    }
    final current = releaseGroups.last;
    final groupAlreadyPresent = current.any(
      (candidate) => scanlatorGroupOf(candidate) == scanlatorGroupOf(chapter),
    );
    if (!groupAlreadyPresent &&
        _canConfidentlyMatch(current.last, chapter)) {
      current.add(chapter);
    } else {
      releaseGroups.add([chapter]);
    }
  }
  return releaseGroups;
}

Map<int, List<int>> _releaseIdsByChapterId(List<ChapterDto> chapters) {
  final idsByChapter = <int, List<int>>{};
  for (final releases in _confidentReleaseGroups(chapters)) {
    final ids = [for (final release in releases) release.id];
    for (final release in releases) {
      idsByChapter[release.id] = ids;
    }
  }
  return idsByChapter;
}

ChapterDto _pickReaderRelease(
  List<ChapterDto> releases, {
  required String scanlatorGroup,
  required List<String> preferred,
  required bool offline,
  int? keepChapterId,
}) {
  final kept = releases.firstWhereOrNull((c) => c.id == keepChapterId);
  if (kept != null) return kept;

  final downloaded = releases.where((c) => c.isDownloaded).toList();
  final candidates = offline && downloaded.isNotEmpty ? downloaded : releases;
  return candidates.firstWhereOrNull(
        (c) => scanlatorGroupOf(c) == scanlatorGroup,
      ) ??
      preferred
          .map((group) => candidates.firstWhereOrNull(
                (c) => scanlatorGroupOf(c) == group,
              ))
          .firstWhereOrNull((c) => c != null) ??
      candidates.reduce((a, b) =>
          a.sourceOrder <= b.sourceOrder ? a : b);
}

/// Builds the reader path without globally grouping equal chapter numbers.
/// Only adjacent source-order rows with the same normalized name and number,
/// and with distinct scanlators, are considered alternate releases. Anything
/// uncertain remains an independent reader entry.
List<ChapterDto> applyReaderSessionScanlator(
  List<ChapterDto> chapters, {
  required String scanlatorGroup,
  List<String> preferred = const [],
  bool offline = false,
  int? keepChapterId,
}) {
  if (chapters.isEmpty) return chapters;

  final selectedIds = <int>{
    for (final releases in _confidentReleaseGroups(chapters))
      _pickReaderRelease(
        releases,
        scanlatorGroup: scanlatorGroup,
        preferred: preferred,
        offline: offline,
        keepChapterId: keepChapterId,
      ).id,
  };
  return [
    for (final chapter in chapters)
      if (selectedIds.contains(chapter.id)) chapter,
  ];
}

/// IDs of releases confidently matched to [chapterId], including itself.
List<int> duplicateChapterIds(List<ChapterDto> allChapters, int chapterId) =>
    _releaseIdsByChapterId(allChapters)[chapterId] ?? [chapterId];

/// Expands read/delete mutations across confident alternate-release groups.
/// Identity when the raw chapter list is unavailable.
List<int> expandIdsForDuplicates(
  List<ChapterDto>? allChapters,
  List<int> chapterIds,
) {
  if (allChapters == null) return chapterIds;
  final idsByChapter = _releaseIdsByChapterId(allChapters);
  final expanded = <int>{};
  for (final id in chapterIds) {
    expanded.addAll(idsByChapter[id] ?? [id]);
  }
  return expanded.toList();
}

/// Unread releases in a confident group that already contains a read release.
List<int> reconcileIdsForReadNumbers(List<ChapterDto> allChapters) => [
      for (final releases in _confidentReleaseGroups(allChapters))
        if (releases.any((chapter) => chapter.isRead))
          for (final chapter in releases)
            if (!chapter.isRead) chapter.id,
    ];
