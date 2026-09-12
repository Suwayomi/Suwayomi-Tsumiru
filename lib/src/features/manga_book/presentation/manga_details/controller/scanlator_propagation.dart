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

/// Expands read/delete actions from the unfiltered raw chapter list. Preferred
/// scanlators only control visibility; they cannot hide a confident match.
List<int> expandIdsAcrossScanlators(
  WidgetRef ref, {
  required int mangaId,
  required List<int> chapterIds,
}) {
  return expandIdsForDuplicates(
    ref.read(mangaChapterListProvider(mangaId: mangaId)).value,
    chapterIds,
  );
}

/// One-time catch-up when a preference is set. Only confident release groups
/// inherit existing read state; uncertain same-number rows remain separate.
Future<void> reconcileReadAcrossScanlators(
  Ref ref, {
  required int mangaId,
}) async {
  final all = ref.read(mangaChapterListProvider(mangaId: mangaId)).value;
  if (all == null) return;
  final ids = reconcileIdsForReadNumbers(all);
  if (ids.isEmpty) return;
  await ref.read(mangaBookRepositoryProvider).modifyBulkChapters(
        ChapterBatch(
            ids: ids, patch: ChapterChange(isRead: true, lastPageRead: 0)),
      );
  ref.invalidate(mangaChapterListProvider(mangaId: mangaId));
}
