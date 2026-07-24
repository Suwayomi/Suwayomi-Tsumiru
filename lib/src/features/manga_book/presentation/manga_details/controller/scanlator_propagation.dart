// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../data/manga_book/manga_book_repository.dart';
import '../../../domain/chapter_batch/chapter_batch_model.dart';
import 'manga_details_controller.dart';
import 'scanlator_dedup.dart';

/// Write-side counterpart of the deduped view, for widget call sites.
/// Identity when the series has no preference.
List<int> expandIdsAcrossScanlators(
  WidgetRef ref, {
  required int mangaId,
  required List<int> chapterIds,
}) {
  if (ref.read(mangaPreferredScanlatorsProvider(mangaId: mangaId)).isEmpty) {
    return chapterIds;
  }
  return expandIdsForDuplicates(
    ref.read(mangaChapterListProvider(mangaId: mangaId)).value,
    chapterIds,
  );
}

/// One-time catch-up when a preference is set: copies of already-read numbers
/// get marked read so badges/other clients converge.
Future<void> reconcileReadAcrossScanlators(
  Ref ref, {
  required int mangaId,
}) async {
  final all = ref.read(mangaChapterListProvider(mangaId: mangaId)).value;
  if (all == null) return;
  final ids = reconcileIdsForReadNumbers(all);
  if (ids.isEmpty) return;
  await ref.read(mangaBookRepositoryProvider).modifyBulkChapters(
        // lastPageRead reset matches the bulk mark-read action's shape.
        ChapterBatch(
            ids: ids, patch: ChapterChange(isRead: true, lastPageRead: 0)),
      );
  ref.invalidate(mangaChapterListProvider(mangaId: mangaId));
}
