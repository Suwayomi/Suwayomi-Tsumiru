// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import '../../../constants/enum.dart';
import '../../manga_book/domain/manga/manga_model.dart';
import 'offline_types.dart';

/// WebUI's own per-manga meta keys (Metadata.constants.ts,
/// GLOBAL_METADATA_KEYS — no per-device prefix). Deliberately NOT part of
/// Tsumiru's own `flutter_`-prefixed [MangaMetaKeys] convention: these are a
/// foreign namespace, kept only for cross-client interop with WebUI's own
/// per-manga chapter sort.
const kWebUiSortByMetaKey = 'webUI_sortBy';
const kWebUiReverseMetaKey = 'webUI_reverse';

/// Parses a raw `webUI_sortBy` meta value. Unknown, legacy, or absent -> null.
/// Never yields [ChapterSortAxis.alphabetical]: WebUI has no such value, it
/// lives in Tsumiru's own flag (see [chapterSortAxisFromMeta]).
ChapterSortAxis? chapterSortAxisFromMetaValue(String? raw) {
  final axis = raw == null ? null : ChapterSortAxis.values.asNameMap()[raw];
  return axis == ChapterSortAxis.alphabetical ? null : axis;
}

/// A manga's effective chapter sort axis from its meta, where [metaValue]
/// looks a key up in the manga's meta list. Tsumiru's alphabetical flag wins
/// over `webUI_sortBy`, which it leaves in place for WebUI. Null = no
/// per-manga override.
ChapterSortAxis? chapterSortAxisFromMeta(
  String? Function(String key) metaValue,
) {
  if (metaValue(MangaMetaKeys.chapterSortAlphabetical.key) == 'true') {
    return ChapterSortAxis.alphabetical;
  }
  return chapterSortAxisFromMetaValue(metaValue(kWebUiSortByMetaKey));
}

/// Tsumiru's sort direction is "ascending"; WebUI's `webUI_reverse` is the
/// opposite: WebUI sorts ascending, then reverses the whole list when the meta
/// is `'true'` (its default, newest first). So `'true'` means descending here.
/// WebUI compares `value === 'true'` verbatim — mirror that exactly rather
/// than a looser boolean parse.
bool? chapterSortAscendingFromMetaValue(String? raw) =>
    raw == null ? null : raw != 'true';

String chapterSortAscendingToMetaValue(bool ascending) =>
    (!ascending).toString();

/// UI-facing enum ([ChapterSort]) <-> wire/DB axis enum ([ChapterSortAxis]).
/// Names deliberately differ for 2 values (`uploadDate`/`uploadedAt`,
/// `fetchedDate`/`fetchedAt`) — never use `.name` for this hop, only for the
/// [ChapterSortAxis] <-> meta-string hop above, where the names truly match.
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
