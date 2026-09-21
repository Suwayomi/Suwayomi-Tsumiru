// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import '../../../constants/enum.dart';
import 'offline_types.dart';

/// WebUI's own per-manga meta keys (Metadata.constants.ts,
/// GLOBAL_METADATA_KEYS — no per-device prefix). Deliberately NOT part of
/// Tsumiru's own `flutter_`-prefixed [MangaMetaKeys] convention: these are a
/// foreign namespace, kept only for cross-client interop with WebUI's own
/// per-manga chapter sort.
const kWebUiSortByMetaKey = 'webUI_sortBy';
const kWebUiReverseMetaKey = 'webUI_reverse';

/// Parses a raw `webUI_sortBy` meta value. Unknown, legacy, or absent -> null.
ChapterSortAxis? chapterSortAxisFromMetaValue(String? raw) =>
    raw == null ? null : ChapterSortAxis.values.asNameMap()[raw];

/// WebUI compares its own `reverse` meta via `value === 'true'` verbatim —
/// mirror that exactly rather than a looser boolean parse.
bool? chapterSortReverseFromMetaValue(String? raw) =>
    raw == null ? null : raw == 'true';

String chapterSortReverseToMetaValue(bool reverse) => reverse.toString();

/// UI-facing enum ([ChapterSort], 5 values incl. `alphabetical`) <-> wire/DB
/// axis enum ([ChapterSortAxis], the 4 WebUI-interoperable values). Names
/// deliberately differ for 2 of 4 values (`uploadDate`/`uploadedAt`,
/// `fetchedDate`/`fetchedAt`) — never use `.name` for this hop, only for the
/// [ChapterSortAxis] <-> meta-string hop above, where the names truly match.
ChapterSortAxis? webUiAxisFromChapterSort(ChapterSort sort) => switch (sort) {
  ChapterSort.source => ChapterSortAxis.source,
  ChapterSort.chapterNumber => ChapterSortAxis.chapterNumber,
  ChapterSort.uploadDate => ChapterSortAxis.uploadedAt,
  ChapterSort.fetchedDate => ChapterSortAxis.fetchedAt,
  ChapterSort.alphabetical => null,
};

ChapterSort chapterSortFromWebUiAxis(ChapterSortAxis axis) => switch (axis) {
  ChapterSortAxis.source => ChapterSort.source,
  ChapterSortAxis.chapterNumber => ChapterSort.chapterNumber,
  ChapterSortAxis.uploadedAt => ChapterSort.uploadDate,
  ChapterSortAxis.fetchedAt => ChapterSort.fetchedDate,
};
