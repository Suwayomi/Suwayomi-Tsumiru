// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../constants/db_keys.dart';
import '../../../../../constants/enum.dart';
import '../../../../../features/offline/data/offline_download_providers.dart';
import '../../../../../features/offline/data/offline_read_fallback.dart';
import '../../../../../features/offline/data/offline_repository.dart';
import '../../../../../features/settings/presentation/library/widgets/refresh_chapters_from_source_tile/refresh_chapters_from_source_tile.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/mixin/shared_preferences_client_mixin.dart';
import '../../../../library/domain/category/category_model.dart';
import '../../../data/manga_book/manga_book_repository.dart';
import '../../../domain/chapter/chapter_model.dart';
import '../../../domain/manga/manga_model.dart';

part 'manga_details_controller.g.dart';

@riverpod
class MangaWithId extends _$MangaWithId {
  @override
  Future<MangaDto?> build({required int mangaId}) async {
    final manga = await mangaWithOfflineFallback(
      fetch: () =>
          ref.watch(mangaBookRepositoryProvider).getManga(mangaId: mangaId),
      db: ref.watch(offlineEnabledProvider)
          ? ref.watch(offlineDatabaseProvider)
          : null,
      offlineEnabled: ref.watch(offlineEnabledProvider),
      mangaId: mangaId,
    );
    // Don't mirror browsed (non-library) manga into the offline catalog.
    if (manga != null && manga.inLibrary) {
      unawaited(
          ref.read(offlineSyncProvider)?.syncManga(manga) ?? Future.value());
    }
    return manga;
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
  }
}

@riverpod
class MangaChapterList extends _$MangaChapterList {
  @override
  Future<List<ChapterDto>?> build({required int mangaId}) async {
    final repo = ref.watch(mangaBookRepositoryProvider);
    final refreshFromSource =
        ref.watch(refreshChaptersFromSourceProvider).ifNull();
    // Tracks whether we actually scraped the source on this open. A source
    // scrape (getChapterList) also populates the manga's description/metadata
    // server-side, so afterwards we refresh MangaWithId to pick it up (#363).
    var didSourceFetch = false;
    final result = await chaptersWithOfflineFallback(
      fetch: () async {
        // Read the chapters the server already has stored (like the WebUI).
        final stored = await repo.getStoredChapterList(mangaId);
        // Show them as-is unless the source has never been fetched (no chapters
        // yet) or the user opted into refreshing from the source on open.
        if (!refreshFromSource && stored != null && stored.isNotEmpty) {
          return stored;
        }
        try {
          final fetched = await repo.getChapterList(mangaId);
          if (fetched != null && fetched.isNotEmpty) {
            didSourceFetch = true;
            return fetched;
          }
        } catch (_) {
          // Source down / gone — fall back to the server's stored chapters
          // instead of showing an empty list (issue #28).
        }
        return stored;
      },
      db: ref.watch(offlineEnabledProvider)
          ? ref.watch(offlineDatabaseProvider)
          : null,
      offlineEnabled: ref.watch(offlineEnabledProvider),
      mangaId: mangaId,
    );
    ref.keepAlive();
    if (result != null) {
      unawaited(
          (ref.read(offlineSyncProvider)?.syncChapters(result) ??
                  Future.value())
              .then((_) => reconcileManga(ref, mangaId)));
    }
    if (didSourceFetch) {
      // The source scrape above also populated this manga's description and
      // metadata server-side, but MangaWithId loaded BEFORE that with an empty
      // description (the client never calls fetchManga). Refresh it so the
      // details screen shows the metadata on first open instead of only after a
      // manual refresh (#363). Deferred past this build so we don't invalidate a
      // provider mid-build.
      Future.microtask(
          () => ref.invalidate(mangaWithIdProvider(mangaId: mangaId)));
    }
    return result;
  }

  Future<void> refresh([bool onlineFetch = false]) async {
    final repo = ref.read(mangaBookRepositoryProvider);
    // Only scrape the source when the user explicitly asked (pull-to-refresh /
    // update button -> onlineFetch) or has the "refresh from source" setting on.
    // Otherwise read the server's STORED chapters — mirrors build()'s gate
    // (#28), so merely opening a series (the on-mount refresh) no longer fires a
    // full, slow source re-scrape on every visit; an explicit refresh still
    // tries the source and falls back to stored if it's unavailable.
    final refreshFromSource =
        onlineFetch || ref.read(refreshChaptersFromSourceProvider).ifNull();
    // offlineDatabaseProvider throws on web; only touch it when offline is on.
    final offlineEnabled = ref.read(offlineEnabledProvider);
    // Wrap in chaptersWithOfflineFallback like build() does, so an explicit
    // refresh while the device is offline serves the on-device catalog instead
    // of erroring/clearing the list.
    final result = await AsyncValue.guard(() => chaptersWithOfflineFallback(
          fetch: () async {
            final stored = await repo.getStoredChapterList(mangaId);
            if (!refreshFromSource && stored != null && stored.isNotEmpty) {
              return stored;
            }
            try {
              final fetched = await repo.getChapterList(mangaId);
              if (fetched != null && fetched.isNotEmpty) return fetched;
            } catch (_) {
              // Source down / gone — fall back to stored instead of clearing.
            }
            return stored;
          },
          db: offlineEnabled ? ref.read(offlineDatabaseProvider) : null,
          offlineEnabled: offlineEnabled,
          mangaId: mangaId,
        ));
    ref.keepAlive();
    if (result.hasError) {
      state = result.copyWithPrevious(state);
    } else {
      state = result;
      final chapters = result.valueOrNull;
      if (chapters != null) {
        // Mirror build(): down-sync the fresh list (which orphans chapters the
        // server no longer lists) then reconcile to evict them — so a
        // server-side delete discovered via pull-to-refresh is cleaned up too,
        // not only on a cold provider rebuild.
        unawaited(
            (ref.read(offlineSyncProvider)?.syncChapters(chapters) ??
                    Future.value())
                .then((_) => reconcileManga(ref, mangaId)));
      }
    }
  }

  void updateChapter(int index, ChapterDto chapter) {
    try {
      final newList = [...?state.valueOrNull];
      newList[index] = chapter;
      state = AsyncData<List<ChapterDto>?>(newList).copyWithPrevious(state);
    } catch (e) {
      //
    }
  }
}

@riverpod
Set<String> mangaScanlatorList(Ref ref, {required int mangaId}) {
  final chapterList = ref.watch(mangaChapterListProvider(mangaId: mangaId));
  final scanlatorList = <String>{};
  chapterList.whenData((data) {
    if (data == null) return;
    for (final chapter in data) {
      if (chapter.scanlator.isNotBlank) {
        scanlatorList.add(chapter.scanlator!);
      }
    }
  });
  return scanlatorList;
}

@riverpod
class MangaChapterFilterScanlator extends _$MangaChapterFilterScanlator {
  @override
  String build({required int mangaId}) {
    final manga = ref.watch(mangaWithIdProvider(mangaId: mangaId));
    return manga.valueOrNull?.metaData.scanlator ?? MangaMetaKeys.scanlator.key;
  }

  void update(String? scanlator) async {
    await AsyncValue.guard(
      () => ref.read(mangaBookRepositoryProvider).patchMangaMeta(
            mangaId: mangaId,
            key: MangaMetaKeys.scanlator.key,
            value: scanlator ?? MangaMetaKeys.scanlator.key,
          ),
    );
    ref.invalidate(mangaWithIdProvider(mangaId: mangaId));
    state = scanlator ?? MangaMetaKeys.scanlator.key;
  }
}

@riverpod
AsyncValue<List<ChapterDto>?> mangaChapterListWithFilter(
  Ref ref, {
  required int mangaId,
}) {
  final chapterList = ref.watch(mangaChapterListProvider(mangaId: mangaId));
  final chapterFilterUnread = ref.watch(mangaChapterFilterUnreadProvider);
  final chapterFilterDownloaded =
      ref.watch(mangaChapterFilterDownloadedProvider);
  final chapterFilterBookmark = ref.watch(mangaChapterFilterBookmarkedProvider);
  final ChapterSort sortedBy = ref.watch(mangaChapterSortProvider) ??
      DBKeys.chapterSortDirection.initial;
  final sortedDirection =
      ref.watch(mangaChapterSortDirectionProvider).ifNull(true);

  final chapterFilterScanlator =
      ref.watch(mangaChapterFilterScanlatorProvider(mangaId: mangaId));

  bool applyChapterFilter(ChapterDto chapter) {
    if (chapterFilterUnread != null &&
        (chapterFilterUnread ^ !(chapter.isRead.ifNull()))) {
      return false;
    }

    if (chapterFilterDownloaded != null &&
        (chapterFilterDownloaded ^ (chapter.isDownloaded.ifNull()))) {
      return false;
    }

    if (chapterFilterBookmark != null &&
        (chapterFilterBookmark ^ (chapter.isBookmarked.ifNull()))) {
      return false;
    }

    if (chapterFilterScanlator != MangaMetaKeys.scanlator.key &&
        chapter.scanlator != chapterFilterScanlator) {
      return false;
    }
    return true;
  }

  int applyChapterSort(ChapterDto m1, ChapterDto m2) {
    final sortDirToggle = (sortedDirection ? 1 : -1);
    return (switch (sortedBy) {
          ChapterSort.fetchedDate => (int.tryParse(m1.fetchedAt) ?? 0)
              .compareTo(int.tryParse(m2.fetchedAt) ?? 0),
          ChapterSort.source => (m1.index).compareTo(m2.index),
          ChapterSort.uploadDate => (int.tryParse(m1.uploadDate) ?? 0)
              .compareTo(int.tryParse(m2.uploadDate) ?? 0),
        }) *
        sortDirToggle;
  }

  return chapterList.copyWithData(
    (data) => [...?data?.where(applyChapterFilter)]..sort(applyChapterSort),
  );
}

@riverpod
ChapterDto? firstUnreadInFilteredChapterList(
  Ref ref, {
  required int mangaId,
}) {
  final isAscSorted = ref.watch(mangaChapterSortDirectionProvider) ??
      DBKeys.chapterSortDirection.initial;
  final filteredList = ref
      .watch(mangaChapterListWithFilterProvider(mangaId: mangaId))
      .valueOrNull;
  if (filteredList == null) {
    return null;
  } else {
    if (isAscSorted) {
      return filteredList
          .firstWhereOrNull((element) => !element.isRead.ifNull(true));
    } else {
      return filteredList
          .lastWhereOrNull((element) => !element.isRead.ifNull(true));
    }
  }
}

@riverpod
({ChapterDto? first, ChapterDto? second})? getNextAndPreviousChapters(
  Ref ref, {
  required int mangaId,
  required int chapterId,
  bool shouldAscSort = true,
}) {
  final isAscSorted = ref.watch(mangaChapterSortDirectionProvider) ??
      DBKeys.chapterSortDirection.initial;
  final filteredList = ref
      .watch(mangaChapterListWithFilterProvider(mangaId: mangaId))
      .valueOrNull;
  if (filteredList == null) {
    return null;
  } else {
    final current =
        filteredList.indexWhere((element) => element.id == chapterId);
    final prevChapter = current > 0 ? filteredList[current - 1] : null;
    final nextChapter =
        current < (filteredList.length - 1) ? filteredList[current + 1] : null;
    return (
      first: shouldAscSort && isAscSorted ? nextChapter : prevChapter,
      second: shouldAscSort && isAscSorted ? prevChapter : nextChapter,
    );
  }
}

@riverpod
class MangaChapterSort extends _$MangaChapterSort
    with SharedPreferenceEnumClientMixin<ChapterSort> {
  @override
  ChapterSort? build() => initialize(
        DBKeys.chapterSort,
        enumList: ChapterSort.values,
      );
}

@riverpod
class MangaChapterSortDirection extends _$MangaChapterSortDirection
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.chapterSortDirection);
}

@riverpod
class MangaChapterFilterDownloaded extends _$MangaChapterFilterDownloaded
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.chapterFilterDownloaded);
}

@riverpod
class MangaChapterFilterUnread extends _$MangaChapterFilterUnread
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.chapterFilterUnread);
}

@riverpod
class MangaChapterFilterBookmarked extends _$MangaChapterFilterBookmarked
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.chapterFilterBookmarked);
}

@riverpod
class MangaCategoryList extends _$MangaCategoryList {
  @override
  FutureOr<Map<String, CategoryDto>?> build(int mangaId) async {
    final result = await ref
        .watch(mangaBookRepositoryProvider)
        .getMangaCategoryList(mangaId: mangaId);
    return {
      for (CategoryDto i in (result ?? <CategoryDto>[])) "${i.id}": i,
    };
  }

  Future<void> refresh() async {
    final result = await AsyncValue.guard(() => ref
        .read(mangaBookRepositoryProvider)
        .getMangaCategoryList(mangaId: mangaId));
    state = result.copyWithData((data) => {
          for (CategoryDto i in (data ?? <CategoryDto>[])) "${i.id}": i,
        });
  }
}
