// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../offline/data/background/background_download_controller_shim.dart';
import '../../../../offline/data/offline_download_providers.dart';
import '../../../../offline/data/offline_read_fallback.dart';
import '../../../../offline/data/offline_repository.dart';
import '../../../../offline/data/offline_types.dart';
import '../../../../offline/data/server_reachability.dart';
import '../../../data/manga_book/manga_book_repository.dart';
import '../../../domain/chapter/chapter_model.dart';
import '../../../domain/chapter_page/chapter_page_model.dart';

part 'reader_controller.g.dart';

@riverpod
class Chapter extends _$Chapter {
  // Bumped on every build so an answer from a superseded read (an explicit
  // refresh while the background fetch was still in flight) can't overwrite
  // the value the user is now looking at.
  int _buildId = 0;

  @override
  FutureOr<ChapterDto?> build({required int chapterId}) async {
    final buildId = ++_buildId;
    final db = ref.watch(offlineReadDatabaseProvider);
    // Watched before the first await so a new endpoint or custom header
    // rebuilds this provider and the refetch goes through the new repository.
    final repository = ref.watch(mangaBookRepositoryProvider);
    // Offline: a downloaded chapter must still open when the server is
    // unreachable, so fall back to the on-device catalog row.
    return chapterMetaWithOfflineFallback(
      fetch: () => repository.getChapter(chapterId: chapterId),
      // Only read the native-only DB when offline is available (never on web).
      db: db,
      offlineEnabled: ref.watch(offlineActiveProvider),
      offlineFirst:
          ref.watch(viewOfflineNowProvider) ||
          ref.watch(serverUnreachableProvider),
      chapterId: chapterId,
      // A complete device copy opens from the catalog instantly; the server row
      // then refreshes it in the background, without a second network wait. A
      // chapter not on the device keeps the network-first read unchanged.
      deviceCopyOnDisk: db == null
          ? null
          : () => chapterCompleteOnDevice(db, chapterId),
      onServerAnswer: (chapter) {
        if (!ref.mounted || buildId != _buildId) return;
        state = AsyncData(chapter);
      },
    );
  }
}

@riverpod
Future<ChapterPagesDto?> chapterPages(Ref ref, {required int chapterId}) async {
  // Offline: if this chapter is downloaded on-device, serve its pages from disk
  // (as file:// URIs that ServerImage renders locally) instead of the server.
  // Falls through to the network when not downloaded / offline is unavailable.
  final offlineDb = ref.watch(offlineReadDatabaseProvider);
  if (offlineDb != null) {
    var local = await ref
        .watch(offlineRepositoryProvider)
        .localChapterPages(chapterId);
    // Otherwise this streams from the server on every read, and fails
    // entirely offline.
    if (local == null &&
        (await offlineDb.chapterById(chapterId))?.deviceState ==
            OfflineDeviceState.downloaded) {
      final startDownloads = ref.read(downloadStarterProvider);
      local = await ref
          .read(backgroundDownloadControllerProvider)
          .withOwnership(
            () => repairDownloadedChapterPages(
              db: offlineDb,
              store: ref.watch(offlinePageStoreProvider),
              paths: ref.watch(offlinePathsProvider),
              chapterId: chapterId,
              onRequeued: () => unawaited(startDownloads()),
            ),
          );
    }
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
