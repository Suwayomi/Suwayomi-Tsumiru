// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import '../../../constants/enum.dart';
import '../../manga_book/domain/manga/manga_model.dart';
import 'offline_types.dart';

// WebUI GLOBAL_METADATA_KEYS (Metadata.constants.ts) use no Tsumiru flutter_ prefix.
const kWebUiSortByMetaKey = 'webUI_sortBy';
const kWebUiReverseMetaKey = 'webUI_reverse';

/// Unknown or absent values return null; alphabetical is a separate Tsumiru flag.
ChapterSortAxis? chapterSortAxisFromMetaValue(String? raw) {
  final axis = raw == null ? null : ChapterSortAxis.values.asNameMap()[raw];
  return axis == ChapterSortAxis.alphabetical ? null : axis;
}

/// Tsumiru's alphabetical flag wins without changing WebUI meta; null means no override.
ChapterSortAxis? chapterSortAxisFromMeta(
  String? Function(String key) metaValue,
) {
  if (metaValue(MangaMetaKeys.chapterSortAlphabetical.key) == 'true') {
    return ChapterSortAxis.alphabetical;
  }
  return chapterSortAxisFromMetaValue(metaValue(kWebUiSortByMetaKey));
}

/// WebUI compares the literal 'true' to reverse ascending order; it means descending here.
bool? chapterSortAscendingFromMetaValue(String? raw) =>
    raw == null ? null : raw != 'true';

String chapterSortAscendingToMetaValue(bool ascending) =>
    (!ascending).toString();

// uploadDate/uploadedAt and fetchedDate/fetchedAt differ; do not map these enums by name.
ChapterSortAxis chapterSortAxisFromChapterSort(ChapterSort sort) =>
    switch (sort) {
      ChapterSort.source => ChapterSortAxis.source,
      ChapterSort.chapterNumber => ChapterSortAxis.chapterNumber,
      ChapterSort.uploadDate => ChapterSortAxis.uploadedAt,
      ChapterSort.fetchedDate => ChapterSortAxis.fetchedAt,
      ChapterSort.alphabetical => ChapterSortAxis.alphabetical,
    };

ChapterSort chapterSortFromAxis(ChapterSortAxis axis) => switch (axis) {
  ChapterSortAxis.source => ChapterSort.source,
  ChapterSortAxis.chapterNumber => ChapterSort.chapterNumber,
  ChapterSortAxis.uploadedAt => ChapterSort.uploadDate,
  ChapterSortAxis.fetchedAt => ChapterSort.fetchedDate,
  ChapterSortAxis.alphabetical => ChapterSort.alphabetical,
};
