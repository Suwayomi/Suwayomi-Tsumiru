// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../offline/data/offline_read_fallback.dart';
import '../../../../offline/data/offline_repository.dart';
import '../../../data/manga_book/manga_book_repository.dart';
import '../../../domain/chapter/chapter_model.dart';
import '../../../domain/chapter_page/chapter_page_model.dart';

part 'reader_controller.g.dart';

@riverpod
FutureOr<ChapterDto?> chapter(
  Ref ref, {
  required int chapterId,
}) =>
    // Offline: a downloaded chapter must still open when the server is
    // unreachable, so fall back to the on-device catalog row.
    chapterMetaWithOfflineFallback(
      fetch: () => ref
          .watch(mangaBookRepositoryProvider)
          .getChapter(chapterId: chapterId),
      // Only read the native-only DB when offline is available (never on web).
      db: ref.watch(offlineReadDatabaseProvider),
      offlineEnabled: ref.watch(offlineActiveProvider),
      chapterId: chapterId,
    );

@riverpod
Future<ChapterPagesDto?> chapterPages(Ref ref, {required int chapterId}) async {
  // Offline: if this chapter is downloaded on-device, serve its pages from disk
  // (as file:// URIs that ServerImage renders locally) instead of the server.
  // Falls through to the network when not downloaded / offline is unavailable.
  if (ref.watch(offlineReadDatabaseProvider) != null) {
    final local =
        await ref.watch(offlineRepositoryProvider).localChapterPages(chapterId);
    if (local != null && local.isNotEmpty) {
      return ChapterPagesDto(
        chapter: ChapterPagesChapterDto(id: chapterId, pageCount: local.length),
        pages: [for (final path in local) Uri.file(path).toString()],
      );
    }
  }
  return ref
      .watch(mangaBookRepositoryProvider)
      .getChapterPages(chapterId: chapterId);
}
