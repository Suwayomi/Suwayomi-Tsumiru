// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../constants/db_keys.dart';
import '../../../../../constants/enum.dart';
import '../../../../../features/offline/data/offline_download_providers.dart';
import '../../../../../features/offline/data/offline_read_fallback.dart';
import '../../../../../features/offline/data/offline_repository.dart';
import '../../../../../features/offline/data/offline_types.dart';
import '../../../../../features/offline/data/server_reachability.dart';
import '../../../../../features/offline/data/webui_chapter_sort_meta.dart';
import '../../../../../features/settings/presentation/library/widgets/refresh_chapters_from_source_tile/refresh_chapters_from_source_tile.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/mixin/shared_preferences_client_mixin.dart';
import '../../../../auth/data/auth_credentials_store.dart';
import '../../../../history/presentation/history_controller.dart';
import '../../../../library/domain/category/category_model.dart';
import '../../../../library/presentation/library/controller/library_manga_list.dart';
import '../../../data/manga_book/manga_book_repository.dart';
import '../../../domain/chapter/chapter_model.dart';
import '../../../domain/manga/manga_model.dart';
import 'chapter_list_entry.dart';
import 'scanlator_dedup.dart';
import 'scanlator_propagation.dart';

part 'manga_details_controller.g.dart';

@riverpod
class MangaWithId extends _$MangaWithId {
  // Reject replies from builds superseded by a newer read.
  int _buildId = 0;

  @override
  Future<MangaDto?> build({required int mangaId}) async {
    final buildId = ++_buildId;
    final sessionCurrent = watchAuthSession(ref);
    bool current() => ref.mounted && sessionCurrent();
    if (!current()) return null;
    // Capture before await; the provider may be disposed while fetching.
    final sync = ref.read(offlineSyncProvider);
    // Ordered against push acks: captured before the fetch goes out.
    final fetchGen = sync?.syncGeneration ?? 0;
    // Mirror only genuine server responses — fallback DTOs already carry the
    // unread correction and must not round-trip back as server counts.
    var fromServer = false;
    final offlineDb = ref.watch(offlineReadDatabaseProvider);
    // Watch before await so endpoint/header changes rebuild with the new repository.
    final repository = ref.watch(mangaBookRepositoryProvider);
    final manga = await mangaWithOfflineFallback(
      fetch: () async {
        final r = await repository.getManga(mangaId: mangaId);
        fromServer = true;
        return r;
      },
      db: offlineDb,
      offlineEnabled: ref.watch(offlineActiveProvider),
      offlineFirst:
          ref.watch(viewOfflineNowProvider) ||
          ref.watch(serverUnreachableProvider),
      mangaId: mangaId,
      // Complete device copies render from the catalog immediately while the server refreshes in background.
      deviceCopyOnDisk: offlineDb == null
          ? null
          : () async {
              final chapters = await offlineDb.chaptersForManga(mangaId);
              return chapters.any(
                (c) => c.deviceState == OfflineDeviceState.downloaded,
              );
            },
      onServerAnswer: (server) {
        if (!current() || buildId != _buildId) return;
        state = AsyncData(server);
        if (server.user.inLibrary) {
          unawaited(
            sync?.syncManga(server, fetchedAtGen: fetchGen) ?? Future.value(),
          );
        }
      },
    );
    // Check disposal before keeping this cached across detail-page visits.
    if (!current()) return null;
    ref.keepAlive();
    // Don't mirror browsed (non-library) manga into the offline catalog.
    if (manga != null && manga.user.inLibrary && fromServer) {
      unawaited(
        sync?.syncManga(manga, fetchedAtGen: fetchGen) ?? Future.value(),
      );
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
    final sessionCurrent = watchAuthSession(ref);
    bool current() => ref.mounted && sessionCurrent();
    if (!current()) return null;
    final repo = ref.watch(mangaBookRepositoryProvider);
    final refreshFromSource = ref
        .watch(refreshChaptersFromSourceProvider)
        .ifNull();
    // Source fetches refresh metadata too, so refresh MangaWithId afterwards.
    var didSourceFetch = false;
    // Capture before await; the provider may be disposed while fetching.
    final sync = ref.read(offlineSyncProvider);
    // Mirror only genuine server responses — fallback chapter DTOs carry
    // stub fields (lastReadAt '0') that would clobber real mirrored data.
    var fromServer = false;
    final result = await chaptersWithOfflineFallback(
      fetch: () async {
        final stored = await repo.getStoredChapterList(mangaId);
        if (!current()) return null;
        fromServer = true;
        // Re-scrape only when stored chapters are absent or source refresh is enabled.
        if (!refreshFromSource && stored != null && stored.isNotEmpty) {
          return stored;
        }
        try {
          final fetched = await repo.getMangaAndChapterList(mangaId);
          if (fetched != null && fetched.isNotEmpty) {
            didSourceFetch = true;
            return fetched;
          }
        } catch (_) {
          // Keep stored chapters when the source is unavailable.
        }
        return stored;
      },
      db: ref.watch(offlineReadDatabaseProvider),
      offlineEnabled: ref.watch(offlineActiveProvider),
      offlineFirst:
          ref.watch(viewOfflineNowProvider) ||
          ref.watch(serverUnreachableProvider),
      mangaId: mangaId,
    );
    if (!current()) return null;
    ref.keepAlive();
    if (result != null && fromServer) {
      unawaited(
        (sync?.syncChapters(result) ?? Future.value(<int>{})).then((nr) {
          if (current()) {
            reconcileManga(ref, mangaId, newlyReadChapterIds: nr);
          }
        }),
      );
    }
    if (didSourceFetch) {
      // Refresh metadata after scraping; defer invalidation outside the build phase.
      Future.microtask(() {
        if (current()) ref.invalidate(mangaWithIdProvider(mangaId: mangaId));
      });
    }
    return result;
  }

  Future<void> refresh([bool onlineFetch = false]) async {
    final auth = ref.read(authCredentialsStoreProvider.notifier);
    final epoch = auth.sessionEpoch;
    bool current() =>
        ref.mounted && !auth.sessionChanging && auth.sessionEpoch == epoch;
    if (!current()) return;
    final sync = ref.read(offlineSyncProvider);
    final repo = ref.read(mangaBookRepositoryProvider);
    // Scrape only on explicit request or when source refresh is enabled.
    final refreshFromSource =
        onlineFetch || ref.read(refreshChaptersFromSourceProvider).ifNull();
    // offlineDatabaseProvider throws on web; only touch it when offline is on.
    final offlineDb = ref.read(offlineReadDatabaseProvider);
    // Explicit retry still respects the pinned offline view.
    final viewOffline =
        ref.read(viewOfflineNowProvider) || ref.read(serverUnreachableProvider);
    var didSourceFetch = false;
    // Offline refreshes use the catalog; mirror only genuine server responses.
    var fromServer = false;
    final result = await AsyncValue.guard(
      () => chaptersWithOfflineFallback(
        fetch: () async {
          final stored = await repo.getStoredChapterList(mangaId);
          if (!current()) return null;
          fromServer = true;
          if (!refreshFromSource && stored != null && stored.isNotEmpty) {
            return stored;
          }
          try {
            final fetched = await repo.getMangaAndChapterList(mangaId);
            if (fetched != null && fetched.isNotEmpty) {
              didSourceFetch = true;
              return fetched;
            }
          } catch (_) {
          }
          return stored;
        },
        db: offlineDb,
        offlineEnabled: offlineDb != null,
        offlineFirst: viewOffline,
        // An explicit source scrape can outlast the offline timeout; allow 60 seconds.
        fetchTimeout: const Duration(seconds: 60),
        mangaId: mangaId,
      ),
    );
    if (!current()) return;
    ref.keepAlive();
    // Source scraping also changes metadata, so refresh it alongside chapters.
    if (didSourceFetch && ref.mounted) {
      ref.invalidate(mangaWithIdProvider(mangaId: mangaId));
    }
    // Keep current chapters visible when a refresh fails.
    if (result.hasError) return;
    state = result;
    final chapters = result.value;
    if (chapters != null && fromServer) {
      // Mirror genuine server lists and reconcile chapters removed on the server; never mirror catalog echoes.
      unawaited(
        (sync?.syncChapters(chapters) ?? Future.value(<int>{})).then((nr) {
          if (current()) {
            reconcileManga(ref, mangaId, newlyReadChapterIds: nr);
          }
        }),
      );
    }
  }

  void updateChapter(int index, ChapterDto chapter) {
    final current = state.value;
    if (current == null || index < 0 || index >= current.length) return;
    final newList = [...current];
    newList[index] = chapter;
    state = AsyncData<List<ChapterDto>?>(newList);
  }
}

@riverpod
Set<String> mangaScanlatorList(Ref ref, {required int mangaId}) {
  final chapterList = ref.watch(mangaChapterListProvider(mangaId: mangaId));
  final scanlatorList = <String>{};
  chapterList.whenData((data) {
    if (data == null) return;
    for (final chapter in data) {
      scanlatorList.add(scanlatorGroupOf(chapter));
    }
  });
  return scanlatorList;
}

/// Read the JSON-list preference, falling back to the legacy single group without writing on read.
@riverpod
class MangaPreferredScanlators extends _$MangaPreferredScanlators {
  @override
  List<String> build({required int mangaId}) {
    final meta = ref
        .watch(mangaWithIdProvider(mangaId: mangaId))
        .value
        ?.metaData;
    return meta?.effectivePreferredScanlators ?? const [];
  }

  /// Returns false on write failure so the dialog can remain open.
  Future<bool> setPreference(List<String> groups) async {
    final repo = ref.read(mangaBookRepositoryProvider);
    final result = await AsyncValue.guard(() async {
      await repo.patchMangaMeta(
        mangaId: mangaId,
        key: MangaMetaKeys.preferredScanlators.key,
        value: jsonEncode(groups),
      );
      // Mirror rank-1 into the legacy key so older installs keep a sane filter.
      await repo.patchMangaMeta(
        mangaId: mangaId,
        key: MangaMetaKeys.scanlator.key,
        value: groups.isNotEmpty ? groups.first : MangaMetaKeys.scanlator.key,
      );
    });
    if (result.hasError) return false;
    try {
      if (ref.mounted) {
        state = groups;
        ref.invalidate(mangaWithIdProvider(mangaId: mangaId));
        if (groups.isEmpty) {
          // Stale ON would silently resume show-all on the next preference.
          ref.invalidate(
            mangaShowAllScanlatorVersionsProvider(mangaId: mangaId),
          );
        } else {
          unawaited(
            AsyncValue.guard(
              () => reconcileReadAcrossScanlators(ref, mangaId: mangaId),
            ),
          );
        }
      }
    } catch (_) {}
    return true;
  }
}

/// Resets after the series screen and its readers stop watching.
@riverpod
class MangaShowAllScanlatorVersions extends _$MangaShowAllScanlatorVersions {
  @override
  bool build({required int mangaId}) => false;
  void update(bool value) => state = value;
}

/// Uses per-manga webUI_sortBy meta, falling back to the app-wide sort.
@riverpod
class MangaChapterSortPreference extends _$MangaChapterSortPreference {
  @override
  ChapterSort? build({required int mangaId}) {
    final meta = ref.watch(mangaWithIdProvider(mangaId: mangaId)).value?.meta;
    final axis = chapterSortAxisFromMeta(
      (key) => meta?.firstWhereOrNull((m) => m.key == key)?.value,
    );
    if (axis != null) return chapterSortFromAxis(axis);
    return ref.watch(mangaChapterSortProvider);
  }

  /// On write failure, retain the displayed sort and return the error.
  Future<AsyncValue<void>> update(ChapterSort sort) async {
    final repo = ref.read(mangaBookRepositoryProvider);
    final axis = chapterSortAxisFromChapterSort(sort);
    final alphabeticalKey = MangaMetaKeys.chapterSortAlphabetical.key;
    final result = await AsyncValue.guard(() async {
      if (axis == ChapterSortAxis.alphabetical) {
        // Tsumiru-only flag; webUI_sortBy stays for WebUI and for a later
        // switch back to a real axis.
        await repo.patchMangaMeta(
          mangaId: mangaId,
          key: alphabeticalKey,
          value: 'true',
        );
      } else {
        final meta = ref
            .read(mangaWithIdProvider(mangaId: mangaId))
            .value
            ?.meta;
        if (meta?.any((m) => m.key == alphabeticalKey) ?? false) {
          await repo.deleteMangaMeta(mangaId: mangaId, key: alphabeticalKey);
        }
        await repo.patchMangaMeta(
          mangaId: mangaId,
          key: kWebUiSortByMetaKey,
          value: axis.name,
        );
      }
    });
    if (!ref.mounted) return result;
    ref.invalidate(mangaWithIdProvider(mangaId: mangaId));
    if (!result.hasError) state = sort;
    return result;
  }
}

/// webUI_reverse true means descending; this display preference does not reverse offline retention.
@riverpod
class MangaChapterSortDirectionPreference
    extends _$MangaChapterSortDirectionPreference {
  @override
  bool? build({required int mangaId}) {
    final meta = ref.watch(mangaWithIdProvider(mangaId: mangaId)).value?.meta;
    final raw = meta
        ?.firstWhereOrNull((m) => m.key == kWebUiReverseMetaKey)
        ?.value;
    return chapterSortAscendingFromMetaValue(raw) ??
        ref.watch(mangaChapterSortDirectionProvider);
  }

  Future<AsyncValue<void>> update(bool ascending) async {
    final result = await AsyncValue.guard(
      () => ref
          .read(mangaBookRepositoryProvider)
          .patchMangaMeta(
            mangaId: mangaId,
            key: kWebUiReverseMetaKey,
            value: chapterSortAscendingToMetaValue(ascending),
          ),
    );
    if (!ref.mounted) return result;
    ref.invalidate(mangaWithIdProvider(mangaId: mangaId));
    if (!result.hasError) state = ascending;
    return result;
  }
}

/// Personal rating in manga meta: 0 means unrated, 1..5 are stars.
@riverpod
class MangaRating extends _$MangaRating {
  @override
  int build({required int mangaId}) {
    final manga = ref.watch(mangaWithIdProvider(mangaId: mangaId));
    return (manga.value?.metaData.rating ?? 0).clamp(0, 5);
  }

  Future<void> update(int rating) async {
    final next = rating.clamp(0, 5);
    await AsyncValue.guard(
      () => ref
          .read(mangaBookRepositoryProvider)
          .patchMangaMeta(
            mangaId: mangaId,
            key: MangaMetaKeys.rating.key,
            // MangaMetaTypeInput.value is String!; numeric values fail the mutation.
            value: '$next',
          ),
    );
    if (!ref.mounted) return;
    ref.invalidate(mangaWithIdProvider(mangaId: mangaId));
    ref.invalidate(libraryMangaListProvider);
    state = next;
  }
}

/// User tags are a JSON string array in manga meta, distinct from source genres.
@riverpod
class MangaUserTags extends _$MangaUserTags {
  @override
  List<String> build({required int mangaId}) {
    final manga = ref.watch(mangaWithIdProvider(mangaId: mangaId));
    return manga.value?.metaData.userTags ?? const [];
  }

  Future<void> _persist(List<String> tags) async {
    await AsyncValue.guard(
      () => ref
          .read(mangaBookRepositoryProvider)
          .patchMangaMeta(
            mangaId: mangaId,
            key: MangaMetaKeys.tags.key,
            value: jsonEncode(tags),
          ),
    );
    if (!ref.mounted) return;
    ref.invalidate(mangaWithIdProvider(mangaId: mangaId));
    ref.invalidate(libraryMangaListProvider);
    state = tags;
  }

  Future<void> add(String tag) {
    final t = tag.trim();
    if (t.isEmpty || state.contains(t)) return Future.value();
    return _persist([...state, t]);
  }

  Future<void> remove(String tag) =>
      _persist(state.where((t) => t != tag).toList());
}

/// Mounted lists refetch their rows when this changes; the updates list keeps
/// a local paging controller no provider invalidation can reach.
@riverpod
class CustomCoverRevision extends _$CustomCoverRevision {
  @override
  int build() => 0;

  void bump() => state++;
}

/// Custom cover link shown instead of the server cover; null restores it.
@riverpod
class MangaCustomCover extends _$MangaCustomCover {
  @override
  String? build({required int mangaId}) {
    final meta = ref.watch(mangaWithIdProvider(mangaId: mangaId)).value?.meta;
    return meta
        ?.where((m) => m.key == MangaMetaKeys.customCover.key)
        .firstOrNull
        ?.value;
  }

  Future<void> setCover(String coverUrl) async {
    final result = await AsyncValue.guard(
      () => ref
          .read(mangaBookRepositoryProvider)
          .setCustomCover(mangaId: mangaId, coverUrl: coverUrl),
    );
    if (!ref.mounted || result.hasError) return;
    state = coverUrl;
    _refreshCovers();
  }

  Future<void> clear() async {
    final result = await AsyncValue.guard(
      () => ref
          .read(mangaBookRepositoryProvider)
          .clearCustomCover(mangaId: mangaId),
    );
    if (!ref.mounted || result.hasError) return;
    state = null;
    _refreshCovers();
  }

  void _refreshCovers() {
    ref.invalidate(mangaWithIdProvider(mangaId: mangaId));
    ref.invalidate(libraryMangaListProvider);
    ref.invalidate(readingHistoryProvider);
    ref.invalidate(mangaReadingHistoryProvider);
    ref.read(customCoverRevisionProvider.notifier).bump();
  }
}

@riverpod
AsyncValue<List<ChapterDto>?> mangaChapterListWithFilter(
  Ref ref, {
  required int mangaId,
  int? keepChapterId,
  String? readerScanlatorGroup,
}) {
  final chapterList = ref.watch(mangaChapterListProvider(mangaId: mangaId));
  final chapterFilterUnread = ref.watch(mangaChapterFilterUnreadProvider);
  final chapterFilterDownloaded = ref.watch(
    mangaChapterFilterDownloadedProvider,
  );
  final chapterFilterBookmark = ref.watch(mangaChapterFilterBookmarkedProvider);
  final ChapterSort sortedBy =
      ref.watch(mangaChapterSortPreferenceProvider(mangaId: mangaId)) ??
      DBKeys.chapterSort.initial;
  final sortedDirection = ref
      .watch(mangaChapterSortDirectionPreferenceProvider(mangaId: mangaId))
      .ifNull(true);

  final preferredScanlators = ref.watch(
    mangaPreferredScanlatorsProvider(mangaId: mangaId),
  );
  final showAllVersions = ref.watch(
    mangaShowAllScanlatorVersionsProvider(mangaId: mangaId),
  );
  final filterScanlators = preferredScanlators.isNotEmpty && !showAllVersions;
  final offline =
      ref.watch(viewOfflineNowProvider) || ref.watch(serverUnreachableProvider);

  bool applyChapterFilter(ChapterDto chapter) {
    if (chapter.id == keepChapterId) return true;

    if (chapterFilterUnread != null &&
        (chapterFilterUnread ^ !(chapter.user.isRead.ifNull()))) {
      return false;
    }

    if (chapterFilterDownloaded != null &&
        (chapterFilterDownloaded ^ (chapter.user.isDownloaded.ifNull()))) {
      return false;
    }

    if (chapterFilterBookmark != null &&
        (chapterFilterBookmark ^ (chapter.user.isBookmarked.ifNull()))) {
      return false;
    }

    return true;
  }

  return chapterList.copyWithData((data) {
    var list = data ?? const <ChapterDto>[];
    if (readerScanlatorGroup != null) {
      list = applyReaderSessionScanlator(
        list,
        scanlatorGroup: readerScanlatorGroup,
        preferred: preferredScanlators,
        offline: offline,
        keepChapterId: keepChapterId,
      );
    } else if (filterScanlators) {
      list = filterPreferredScanlators(
        list,
        preferredScanlators,
        keepChapterId: keepChapterId,
      );
    }
    return [...list.where(applyChapterFilter)]..sort(
      (first, second) => _compareChapters(
        first,
        second,
        sortedBy: sortedBy,
        ascending: sortedDirection,
      ),
    );
  });
}

int _compareChapters(
  ChapterDto first,
  ChapterDto second, {
  required ChapterSort sortedBy,
  required bool ascending,
}) {
  final key = switch (sortedBy) {
    ChapterSort.fetchedDate => (int.tryParse(first.fetchedAt) ?? 0).compareTo(
      int.tryParse(second.fetchedAt) ?? 0,
    ),
    ChapterSort.source => first.index.compareTo(second.index),
    ChapterSort.uploadDate => (int.tryParse(first.uploadDate) ?? 0).compareTo(
      int.tryParse(second.uploadDate) ?? 0,
    ),
    ChapterSort.chapterNumber => first.chapterNumber.compareTo(
      second.chapterNumber,
    ),
    ChapterSort.alphabetical => first.name.toLowerCase().compareTo(
      second.name.toLowerCase(),
    ),
  };
  // List.sort is unstable; break ties by source order and reverse ties when descending.
  return (key != 0 ? key : first.index.compareTo(second.index)) *
      (ascending ? 1 : -1);
}

/// Details-only entries; reader navigation and bulk actions consume plain chapters.
@riverpod
AsyncValue<List<MangaChapterListEntry>?> mangaChapterListEntries(
  Ref ref, {
  required int mangaId,
}) {
  final allChapters = ref.watch(mangaChapterListProvider(mangaId: mangaId));
  final visibleChapters = ref.watch(
    mangaChapterListWithFilterProvider(mangaId: mangaId),
  );
  final sortedBy =
      ref.watch(mangaChapterSortPreferenceProvider(mangaId: mangaId)) ??
      DBKeys.chapterSort.initial;
  final ascending =
      ref.watch(
        mangaChapterSortDirectionPreferenceProvider(mangaId: mangaId),
      ) ??
      DBKeys.chapterSortDirection.initial;

  return visibleChapters.copyWithData((visible) {
    if (visible == null) return null;
    final sortedAll = [...?allChapters.value]
      ..sort(
        (first, second) => _compareChapters(
          first,
          second,
          sortedBy: sortedBy,
          ascending: ascending,
        ),
      );
    return buildMangaChapterListEntries(
      sortedChapters: sortedAll,
      visibleChapterIds: visible.map((chapter) => chapter.id).toSet(),
      ascending: ascending,
    );
  });
}

/// Preferred-scanlator-filtered but otherwise unfiltered list for bulk actions.
@riverpod
AsyncValue<List<ChapterDto>?> mangaChapterListForBulkActions(
  Ref ref, {
  required int mangaId,
}) {
  final chapterList = ref.watch(mangaChapterListProvider(mangaId: mangaId));
  final preferred = ref.watch(
    mangaPreferredScanlatorsProvider(mangaId: mangaId),
  );
  final showAll = ref.watch(
    mangaShowAllScanlatorVersionsProvider(mangaId: mangaId),
  );
  if (preferred.isEmpty || showAll) return chapterList;
  return chapterList.copyWithData(
    (data) => data == null ? null : filterPreferredScanlators(data, preferred),
  );
}

@riverpod
ChapterDto? firstUnreadInFilteredChapterList(Ref ref, {required int mangaId}) {
  final isAscSorted =
      ref.watch(
        mangaChapterSortDirectionPreferenceProvider(mangaId: mangaId),
      ) ??
      DBKeys.chapterSortDirection.initial;
  final filteredList = ref
      .watch(mangaChapterListWithFilterProvider(mangaId: mangaId))
      .value;
  if (filteredList == null) {
    return null;
  } else {
    if (isAscSorted) {
      return filteredList.firstWhereOrNull(
        (element) => !element.user.isRead.ifNull(true),
      );
    } else {
      return filteredList.lastWhereOrNull(
        (element) => !element.user.isRead.ifNull(true),
      );
    }
  }
}

@riverpod
({ChapterDto? first, ChapterDto? second})? getNextAndPreviousChapters(
  Ref ref, {
  required int mangaId,
  required int chapterId,
  bool shouldAscSort = true,
  String? readerScanlatorGroup,
}) {
  final isAscSorted =
      ref.watch(
        mangaChapterSortDirectionPreferenceProvider(mangaId: mangaId),
      ) ??
      DBKeys.chapterSortDirection.initial;
  final filteredList = ref
      .watch(
        mangaChapterListWithFilterProvider(
          mangaId: mangaId,
          keepChapterId: chapterId,
          readerScanlatorGroup: readerScanlatorGroup,
        ),
      )
      .value;
  if (filteredList == null) {
    return null;
  } else {
    final current = filteredList.indexWhere(
      (element) => element.id == chapterId,
    );
    // Not in the filtered list (e.g. unread-only filter while re-reading):
    // otherwise current == -1 would resolve nextChapter to filteredList[0].
    if (current == -1) return (first: null, second: null);
    final prevChapter = current > 0 ? filteredList[current - 1] : null;
    final nextChapter = current < (filteredList.length - 1)
        ? filteredList[current + 1]
        : null;
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
  ChapterSort? build() =>
      initialize(DBKeys.chapterSort, enumList: ChapterSort.values);
}

@riverpod
class MangaChapterSortDirection extends _$MangaChapterSortDirection
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.chapterSortDirection);
}

@riverpod
class MangaChapterDisplayMode extends _$MangaChapterDisplayMode
    with SharedPreferenceEnumClientMixin<ChapterDisplay> {
  @override
  ChapterDisplay? build() =>
      initialize(DBKeys.chapterDisplay, enumList: ChapterDisplay.values);
}

@riverpod
class ChapterSwipeToLeft extends _$ChapterSwipeToLeft
    with SharedPreferenceEnumClientMixin<ChapterSwipeAction> {
  @override
  ChapterSwipeAction? build() => initialize(
    DBKeys.chapterSwipeToLeft,
    enumList: ChapterSwipeAction.values,
  );
}

@riverpod
class ChapterSwipeToRight extends _$ChapterSwipeToRight
    with SharedPreferenceEnumClientMixin<ChapterSwipeAction> {
  @override
  ChapterSwipeAction? build() => initialize(
    DBKeys.chapterSwipeToRight,
    enumList: ChapterSwipeAction.values,
  );
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
    return {for (CategoryDto i in (result ?? <CategoryDto>[])) "${i.id}": i};
  }

  Future<void> refresh() async {
    final result = await AsyncValue.guard(
      () => ref
          .read(mangaBookRepositoryProvider)
          .getMangaCategoryList(mangaId: mangaId),
    );
    state = result.copyWithData(
      (data) => {for (CategoryDto i in (data ?? <CategoryDto>[])) "${i.id}": i},
    );
  }
}
