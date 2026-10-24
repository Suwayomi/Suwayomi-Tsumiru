// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:convert';

import 'package:diacritic/diacritic.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../constants/db_keys.dart';
import '../../../../../constants/enum.dart';
import '../../../../../features/offline/data/offline_download_providers.dart';
import '../../../../../global_providers/global_providers.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/mixin/shared_preferences_client_mixin.dart';
import '../../../../../utils/mixin/state_provider_mixin.dart';
import '../../../../../utils/webui_meta/webui_settings.dart';
import '../../../../browse_center/domain/content_rating.dart';
import '../../../../manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import '../../../../manga_book/domain/manga/manga_model.dart';
import '../../../../tracking/data/tracker_repository.dart';
import '../../../data/default_category.dart';
import '../../../domain/category/category_model.dart';
import '../../../domain/library_search_query.dart';
import '../../../domain/track_status.dart';
import 'library_grouping.dart';
import 'library_manga_list.dart';

part 'library_controller.g.dart';

/// Stable Knuth hash for Random sort; incrementing [seed] re-rolls the library order.
/// XOR the seed before multiplication so it changes relative ordering.
int randomKey(int id, int seed) => ((id ^ seed) * 2654435761) & 0x7fffffff;

/// Case/accent-insensitive fold; locale-specific collation such as Swedish å is not supported.
int compareTitlesFolded(String a, String b) => removeDiacritics(
  a.toLowerCase(),
).compareTo(removeDiacritics(b.toLowerCase()));

List<MangaDto> applyLibraryFilterSort(
  List<MangaDto> input, {
  Set<int>? mangaIds,
  required String? query,
  required bool? mangaFilterUnread,
  required bool? mangaFilterDownloaded,
  required bool? mangaFilterCompleted,
  required bool? mangaFilterStarted,
  required bool? mangaFilterBookmarked,
  required bool? mangaFilterOffline,
  required Set<int> offlineMangaIds,
  required bool? mangaFilterLewd,
  required int mangaFilterMinRating,
  required bool filterCategories,
  required Set<String> filterCategoriesInclude,
  required Set<String> filterCategoriesExclude,
  required bool filterTags,
  required Set<String> filterTagsInclude,
  required Set<String> filterTagsExclude,
  required MangaSort sortedBy,
  required bool sortedDirection,
  bool? duplicateChapters,
  Map<String, bool?> statusFilters = const {},
  Map<String, bool?> sourceFilters = const {},
  int seed = 0,
  bool ignoreFilters = false,
  bool fuzzySearch = false,
  Map<int, double> trackerScales = const {},
  Map<int, bool?> trackerFilters = const {},
  Map<int, String> trackerNames = const {},
}) {
  final searchQuery = LibrarySearchQuery.parse(query);
  final filterTagsIncludeLower = filterTagsInclude
      .map((e) => e.toLowerCase())
      .toSet();
  final filterTagsExcludeLower = filterTagsExclude
      .map((e) => e.toLowerCase())
      .toSet();

  bool filter(MangaDto manga) {
    if (mangaIds != null && !mangaIds.contains(manga.id)) return false;
    if (ignoreFilters && !searchQuery.isEmpty) {
      return searchQuery.matches(
        manga.filterFields(trackerNames),
        fuzzy: fuzzySearch,
      );
    }
    bool matches(Map<String, bool?> filters, String value) {
      final included = filters.entries.where((e) => e.value == true);
      return filters[value] != false &&
          (included.isEmpty || included.any((e) => e.key == value));
    }

    if (duplicateChapters != null &&
        (manga.hasDuplicateChapters ?? false) != duplicateChapters) {
      return false;
    }
    if (!matches(statusFilters, manga.status.name) ||
        !matches(sourceFilters, manga.sourceId)) {
      return false;
    }
    if (mangaFilterUnread != null &&
        (mangaFilterUnread ^ manga.user.unreadCount.isGreaterThan(0))) {
      return false;
    }
    if (mangaFilterDownloaded != null &&
        (mangaFilterDownloaded ^ manga.user.downloadCount.isGreaterThan(0))) {
      return false;
    }
    if (mangaFilterCompleted != null &&
        (mangaFilterCompleted ^ (manga.status.name == "COMPLETED"))) {
      return false;
    }
    // Started requires a completed chapter; partial page progress does not count.
    if (mangaFilterStarted != null &&
        (mangaFilterStarted ^ manga.readChapterCount.isGreaterThan(0))) {
      return false;
    }
    if (mangaFilterBookmarked != null &&
        (mangaFilterBookmarked ^ manga.user.bookmarkCount.isGreaterThan(0))) {
      return false;
    }
    if (mangaFilterOffline != null &&
        (mangaFilterOffline ^ offlineMangaIds.contains(manga.id))) {
      return false;
    }
    if (mangaFilterLewd != null &&
        (mangaFilterLewd ^
            isAdultManga(manga.source?.contentWarning, manga.genre))) {
      return false;
    }
    final fields = manga.filterFields(trackerNames);
    if (mangaFilterMinRating > 0 &&
        (fields.rating ?? 0) < mangaFilterMinRating) {
      return false;
    }
    if (filterCategories) {
      final ids = manga.categories.nodes.map((c) => c.id.toString()).toSet();
      if (filterCategoriesInclude.isNotEmpty &&
          ids.intersection(filterCategoriesInclude).isEmpty) {
        return false;
      }
      if (filterCategoriesExclude.isNotEmpty &&
          ids.intersection(filterCategoriesExclude).isNotEmpty) {
        return false;
      }
    }
    if (filterTags) {
      final tags = {
        for (final t in fields.genres) t.toLowerCase(),
        for (final t in fields.userTags) t.toLowerCase(),
      };
      // Include accepts any selected tag; exclude always wins.
      if (filterTagsIncludeLower.isNotEmpty &&
          tags.intersection(filterTagsIncludeLower).isEmpty) {
        return false;
      }
      if (filterTagsExcludeLower.isNotEmpty &&
          tags.intersection(filterTagsExcludeLower).isNotEmpty) {
        return false;
      }
    }
    for (final entry in trackerFilters.entries) {
      final pref = entry.value;
      if (pref == null) continue;
      final hasTracker = manga.trackRecords.nodes.any(
        (n) => n.trackerId == entry.key,
      );
      if (pref ^ hasTracker) return false;
    }
    if (!searchQuery.matches(fields, fuzzy: fuzzySearch)) return false;
    return true;
  }

  int sortPrimary(MangaDto m1, MangaDto m2) {
    final sortDirToggle = (sortedDirection ? 1 : -1);
    // Random ignores direction so its toggle cannot compete with re-roll.
    if (sortedBy == MangaSort.random) {
      return randomKey(m1.id, seed).compareTo(randomKey(m2.id, seed));
    }
    // Untracked scores (-1) sort last before applying either direction.
    if (sortedBy == MangaSort.trackerScore) {
      final s1 = meanNormalizedScore(
        m1.trackRecords.nodes,
        trackerScales: trackerScales,
      );
      final s2 = meanNormalizedScore(
        m2.trackRecords.nodes,
        trackerScales: trackerScales,
      );
      if (s1 < 0 && s2 < 0) return 0;
      if (s1 < 0) return 1; // m1 untracked → always last
      if (s2 < 0) return -1; // m2 untracked → always last
      return s1.compareTo(s2) * sortDirToggle;
    }
    // Finished series sort last before applying either direction.
    if (sortedBy == MangaSort.unread) {
      final u1 = m1.user.unreadCount.getValueOnNullOrNegative();
      final u2 = m2.user.unreadCount.getValueOnNullOrNegative();
      if (u1 == u2) return 0;
      if (u1 == 0) return 1;
      if (u2 == 0) return -1;
      return u1.compareTo(u2) * sortDirToggle;
    }
    return (switch (sortedBy) {
          MangaSort.alphabetical => compareTitlesFolded(m1.title, m2.title),
          MangaSort.unread => 0,
          MangaSort.dateAdded =>
            (m1.user.inLibraryAt.getValueOnNullOrNegative()).compareTo(
              m2.user.inLibraryAt.getValueOnNullOrNegative(),
            ),
          MangaSort.lastUpdated =>
            (int.tryParse(m1.latestFetchedChapter?.fetchedAt ?? '0') ?? 0)
                .compareTo(
                  int.tryParse(m2.latestFetchedChapter?.fetchedAt ?? '0') ?? 0,
                ),
          MangaSort.lastChapterDate =>
            (int.tryParse(m1.latestUploadedChapter?.uploadDate ?? '0') ?? 0)
                .compareTo(
                  int.tryParse(m2.latestUploadedChapter?.uploadDate ?? '0') ??
                      0,
                ),
          MangaSort.totalChapters => m1.chapters.totalCount.compareTo(
            m2.chapters.totalCount,
          ),
          // Last update uses chapter-list refresh time, distinct from the latest chapter's fetch date.
          MangaSort.lastUpdate =>
            (int.tryParse(m1.chaptersLastFetchedAt ?? '0') ?? 0).compareTo(
              int.tryParse(m2.chaptersLastFetchedAt ?? '0') ?? 0,
            ),
          MangaSort.rating => (m1.metaData.rating ?? 0).compareTo(
            m2.metaData.rating ?? 0,
          ),
          MangaSort.lastRead =>
            (int.tryParse(m1.user.lastReadChapter?.user.lastReadAt ?? '0') ?? 0)
                .compareTo(
                  int.tryParse(
                        m2.user.lastReadChapter?.user.lastReadAt ?? '0',
                      ) ??
                      0,
                ),
          MangaSort.random => randomKey(
            m1.id,
            seed,
          ).compareTo(randomKey(m2.id, seed)),
          MangaSort.trackerScore => 0,
        }) *
        sortDirToggle;
  }

  int sort(MangaDto m1, MangaDto m2) {
    final p = sortPrimary(m1, m2);
    if (p != 0) return p;
    // Apply title/id ties after direction so they stay stable; List.sort itself is unstable.
    final byTitle = compareTitlesFolded(m1.title, m2.title);
    return byTitle != 0 ? byTitle : m1.id.compareTo(m2.id);
  }

  return input.where(filter).toList()..sort(sort);
}

/// Compares entries ignoring server-derived age/chaptersAge; null on either side counts as changed.
bool libraryEntryOutdated(MangaDto? listed, MangaDto? fresh) {
  if (listed == null || fresh == null) return true;
  return fresh.copyWith(
        age: listed.age,
        chaptersAge: listed.chaptersAge,
        hasDuplicateChapters: listed.hasDuplicateChapters,
      ) !=
      listed;
}

@riverpod
Future<List<MangaDto>?> categoryMangaList(Ref ref, int categoryId) async {
  final defaultIdFuture = ref.watch(defaultCategoryIdProvider.future);
  final allFuture = ref.watch(libraryMangaListProvider.future);
  final defaultId = await defaultIdFuture;
  final all = await allFuture;
  if (all == null) return null;
  return all.where((m) {
    final ids = m.categories.nodes.map((c) => c.id).toList();
    return ids.contains(categoryId) || (categoryId == defaultId && ids.isEmpty);
  }).toList();
}

@riverpod
class LibraryDisplayCategory extends _$LibraryDisplayCategory
    with StateProviderMixin<CategoryDto?> {
  @override
  CategoryDto? build() => null;
}

@riverpod
class CategoryMangaListWithQueryAndFilter
    extends _$CategoryMangaListWithQueryAndFilter {
  @override
  AsyncValue<List<MangaDto>?> build({required int categoryId}) {
    final mangaList = ref.watch(categoryMangaListProvider(categoryId));
    final query = ref.watch(libraryQueryDebouncedProvider);
    final mangaFilterUnread = ref.watch(libraryMangaFilterUnreadProvider);
    final mangaFilterDownloaded = ref.watch(
      libraryMangaFilterDownloadedProvider,
    );
    final mangaFilterCompleted = ref.watch(libraryMangaFilterCompletedProvider);
    final mangaFilterStarted = ref.watch(libraryMangaFilterStartedProvider);
    final mangaFilterBookmarked = ref.watch(
      libraryMangaFilterBookmarkedProvider,
    );
    final mangaFilterOffline = ref.watch(libraryMangaFilterOfflineProvider);
    final offlineMangaIds =
        ref.watch(offlineDeviceMangaIdsProvider).value ?? const <int>{};
    final mangaFilterLewd = ref.watch(libraryMangaFilterLewdProvider);
    final filterCategories = ref
        .watch(libraryFilterCategoriesProvider)
        .ifNull(false);
    final filterCategoriesInclude =
        (ref.watch(libraryFilterCategoriesIncludeProvider) ?? const <String>[])
            .toSet();
    final filterCategoriesExclude =
        (ref.watch(libraryFilterCategoriesExcludeProvider) ?? const <String>[])
            .toSet();
    final filterTags = ref.watch(libraryFilterTagsProvider).ifNull(false);
    final filterTagsInclude =
        (ref.watch(libraryFilterTagsIncludeProvider) ?? const <String>[])
            .toSet();
    final filterTagsExclude =
        (ref.watch(libraryFilterTagsExcludeProvider) ?? const <String>[])
            .toSet();
    final MangaSort sortedBy =
        ref.watch(libraryMangaSortProvider) ?? DBKeys.mangaSort.initial;
    final sortedDirection = ref
        .watch(libraryMangaSortDirectionProvider)
        .ifNull(true);
    final seed =
        ref.watch(librarySortRandomSeedProvider) ??
        DBKeys.librarySortRandomSeed.initial as int;

    return mangaList.map<AsyncValue<List<MangaDto>?>>(
      data: (e) => AsyncData(
        e.value == null
            ? null
            : applyLibraryFilterSort(
                e.value!,
                query: query,
                ignoreFilters: ref.watch(webUiBoolProvider('ignoreFilters')),
                fuzzySearch: ref.watch(webUiBoolProvider('fuzzySearch')),
                duplicateChapters: ref.watch(libraryDuplicateChaptersProvider),
                statusFilters: ref.watch(libraryEntryFiltersProvider('status')),
                sourceFilters: ref.watch(libraryEntryFiltersProvider('source')),
                mangaFilterUnread: mangaFilterUnread,
                mangaFilterDownloaded: mangaFilterDownloaded,
                mangaFilterCompleted: mangaFilterCompleted,
                mangaFilterStarted: mangaFilterStarted,
                mangaFilterBookmarked: mangaFilterBookmarked,
                mangaFilterOffline: mangaFilterOffline,
                offlineMangaIds: offlineMangaIds,
                mangaFilterLewd: mangaFilterLewd,
                mangaFilterMinRating:
                    ref.watch(libraryMangaFilterMinRatingProvider) ?? 0,
                filterCategories: filterCategories,
                filterCategoriesInclude: filterCategoriesInclude,
                filterCategoriesExclude: filterCategoriesExclude,
                filterTags: filterTags,
                filterTagsInclude: filterTagsInclude,
                filterTagsExclude: filterTagsExclude,
                sortedBy: sortedBy,
                sortedDirection: sortedDirection,
                seed: seed,
                trackerScales: ref.watch(libraryTrackerScalesProvider),
                trackerFilters: ref.watch(libraryTrackerFiltersProvider),
                trackerNames: ref.watch(libraryTrackerNamesProvider),
              ),
      ),
      error: (e) => e,
      loading: (e) => e,
    );
  }

  void invalidate() {
    ref.invalidate(libraryMangaListProvider);
    ref.invalidate(categoryMangaListProvider(categoryId));
  }
}

@Riverpod(keepAlive: true)
class LibraryQuery extends _$LibraryQuery with StateProviderMixin<String?> {
  @override
  String? build() => null;
}

/// Debounces expensive filter/sort/group passes by 300 ms; the field uses the raw query.
@riverpod
class LibraryQueryDebounced extends _$LibraryQueryDebounced {
  Timer? _timer;

  @override
  String? build() {
    ref.onDispose(() => _timer?.cancel());
    ref.listen<String?>(libraryQueryProvider, (previous, next) {
      _timer?.cancel();
      _timer = Timer(const Duration(milliseconds: 300), () {
        if (ref.mounted) state = next;
      });
    });
    return ref.read(libraryQueryProvider);
  }
}

@riverpod
class LibraryMangaFilterDownloaded extends _$LibraryMangaFilterDownloaded
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.mangaFilterDownloaded);
}

@riverpod
class LibraryMangaFilterOffline extends _$LibraryMangaFilterOffline
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.mangaFilterOffline);
}

@riverpod
class LibraryMangaFilterUnread extends _$LibraryMangaFilterUnread
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.mangaFilterUnread);
}

@riverpod
class LibraryMangaFilterCompleted extends _$LibraryMangaFilterCompleted
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.mangaFilterCompleted);
}

@riverpod
class LibraryMangaFilterStarted extends _$LibraryMangaFilterStarted
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.mangaFilterStarted);
}

@riverpod
class LibraryMangaFilterBookmarked extends _$LibraryMangaFilterBookmarked
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.mangaFilterBookmarked);
}

@riverpod
class LibraryMangaFilterLewd extends _$LibraryMangaFilterLewd
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.mangaFilterLewd);
}

@riverpod
class LibraryMangaFilterMinRating extends _$LibraryMangaFilterMinRating
    with SharedPreferenceClientMixin<int> {
  @override
  int? build() => initialize(DBKeys.mangaFilterMinRating);
}

@riverpod
class LibraryFilterCategories extends _$LibraryFilterCategories
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.filterCategories);
}

@riverpod
class LibraryFilterCategoriesInclude extends _$LibraryFilterCategoriesInclude
    with SharedPreferenceClientMixin<List<String>> {
  @override
  List<String>? build() => initialize(DBKeys.filterCategoriesInclude);
}

@riverpod
class LibraryFilterCategoriesExclude extends _$LibraryFilterCategoriesExclude
    with SharedPreferenceClientMixin<List<String>> {
  @override
  List<String>? build() => initialize(DBKeys.filterCategoriesExclude);
}

@riverpod
class LibraryFilterTags extends _$LibraryFilterTags
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.filterTags);
}

@riverpod
class LibraryFilterTagsInclude extends _$LibraryFilterTagsInclude
    with SharedPreferenceClientMixin<List<String>> {
  @override
  List<String>? build() => initialize(DBKeys.filterTagsInclude);
}

@riverpod
class LibraryFilterTagsExclude extends _$LibraryFilterTagsExclude
    with SharedPreferenceClientMixin<List<String>> {
  @override
  List<String>? build() => initialize(DBKeys.filterTagsExclude);
}

/// Source genres and custom tags, deduplicated and sorted case-insensitively.
@riverpod
Future<List<String>> libraryTagList(Ref ref) async {
  final all = await ref.watch(libraryMangaListProvider.future);
  if (all == null) return const [];
  // Preserve first-seen casing while matching the filter's case-insensitive deduplication.
  final byLower = <String, String>{};
  for (final m in all) {
    for (final g in m.genre) {
      if (g.isNotBlank) byLower.putIfAbsent(g.toLowerCase(), () => g);
    }
    for (final t in (m.metaData.userTags ?? const <String>[])) {
      byLower.putIfAbsent(t.toLowerCase(), () => t);
    }
  }
  return byLower.values.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
}

@riverpod
class LibraryMangaSort extends _$LibraryMangaSort
    with SharedPreferenceEnumClientMixin<MangaSort> {
  @override
  MangaSort? build() =>
      initialize(DBKeys.mangaSort, enumList: MangaSort.values);
}

@riverpod
class LibraryMangaSortDirection extends _$LibraryMangaSortDirection
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.mangaSortDirection);
}

@riverpod
class LibrarySortRandomSeed extends _$LibrarySortRandomSeed
    with SharedPreferenceClientMixin<int> {
  @override
  int? build() => initialize(DBKeys.librarySortRandomSeed);
}

/// Default category: -1 always asks, 0 is uncategorized, positive values are category IDs.
@riverpod
class LibraryDefaultCategory extends _$LibraryDefaultCategory
    with SharedPreferenceClientMixin<int> {
  @override
  int? build() => initialize(DBKeys.libraryDefaultCategory);
}

/// null disables filtering; true requires tracking, false excludes it.
@riverpod
class LibraryMangaFilterTracker extends _$LibraryMangaFilterTracker {
  @override
  bool? build({required int trackerId}) {
    final prefs = ref.watch(sharedPreferencesProvider);
    final key = 'mangaFilterTracker_$trackerId';
    listenSelf((_, next) {
      if (next == null) {
        prefs.remove(key);
      } else {
        prefs.setBool(key, next);
      }
    });
    return prefs.getBool(key);
  }

  void update(bool? value) => state = value;
}

/// Only active, non-null per-tracker filters are included.
@riverpod
Map<int, bool?> libraryTrackerFilters(Ref ref) {
  final loggedIn = ref.watch(loggedInTrackersProvider).value ?? const [];
  final Map<int, bool?> result = {};
  for (final tracker in loggedIn) {
    final pref = ref.watch(
      libraryMangaFilterTrackerProvider(trackerId: tracker.id),
    );
    result[tracker.id] = pref;
  }
  return result;
}

/// Tracker scale maxima use the numeric last score label, falling back to length - 1 or 10 if empty.
@riverpod
Map<int, double> libraryTrackerScales(Ref ref) {
  final loggedIn = ref.watch(loggedInTrackersProvider).value ?? const [];
  return {
    for (final t in loggedIn)
      t.id: t.scores.isEmpty
          ? 10.0
          : (double.tryParse(t.scores.last) ??
                (t.scores.length - 1).toDouble()),
  };
}

/// Uses all known trackers so `tracked:<service>` still resolves bound records after logout.
@riverpod
Map<int, String> libraryTrackerNames(Ref ref) {
  final all = ref.watch(trackersProvider).value ?? const [];
  return {for (final t in all) t.id: t.name};
}

@riverpod
class LibraryDisplayMode extends _$LibraryDisplayMode
    with SharedPreferenceEnumClientMixin<DisplayMode> {
  @override
  DisplayMode? build() =>
      initialize(DBKeys.libraryDisplayMode, enumList: DisplayMode.values);
}

@riverpod
class LibraryPortraitColumns extends _$LibraryPortraitColumns
    with SharedPreferenceClientMixin<int> {
  @override
  int? build() => initialize(DBKeys.libraryPortraitColumns);
}

@riverpod
class LibraryLandscapeColumns extends _$LibraryLandscapeColumns
    with SharedPreferenceClientMixin<int> {
  @override
  int? build() => initialize(DBKeys.libraryLandscapeColumns);
}

@riverpod
class LibraryListScale extends _$LibraryListScale
    with SharedPreferenceClientMixin<double> {
  @override
  double? build() => initialize(DBKeys.listScale);
}

@riverpod
class CategoryTabs extends _$CategoryTabs
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.categoryTabs);
}

@riverpod
class SectionHeadersShowAllCategories extends _$SectionHeadersShowAllCategories
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.sectionHeadersShowAllCategories);
}

@riverpod
class ShowHiddenCategories extends _$ShowHiddenCategories
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.showHiddenCategories);
}

@riverpod
class CategoryNumberOfItems extends _$CategoryNumberOfItems
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.categoryNumberOfItems);
}

@riverpod
class GroupedMangaListWithQueryAndFilter
    extends _$GroupedMangaListWithQueryAndFilter {
  @override
  AsyncValue<List<MangaDto>?> build({required int tabId}) {
    // Key by stable tab id: freshly built Sets lack value equality and would recreate providers.
    final tabs = ref.watch(libraryGroupedTabsProvider).value;
    Set<int> mangaIds = const <int>{};
    if (tabs != null) {
      for (final t in tabs) {
        if (t.id == tabId) {
          mangaIds = t.mangaIds.toSet();
          break;
        }
      }
    }
    final allAsync = ref.watch(libraryMangaListProvider);
    final query = ref.watch(libraryQueryDebouncedProvider);
    final mangaFilterUnread = ref.watch(libraryMangaFilterUnreadProvider);
    final mangaFilterDownloaded = ref.watch(
      libraryMangaFilterDownloadedProvider,
    );
    final mangaFilterCompleted = ref.watch(libraryMangaFilterCompletedProvider);
    final mangaFilterStarted = ref.watch(libraryMangaFilterStartedProvider);
    final mangaFilterBookmarked = ref.watch(
      libraryMangaFilterBookmarkedProvider,
    );
    final mangaFilterOffline = ref.watch(libraryMangaFilterOfflineProvider);
    final offlineMangaIds =
        ref.watch(offlineDeviceMangaIdsProvider).value ?? const <int>{};
    final mangaFilterLewd = ref.watch(libraryMangaFilterLewdProvider);
    final filterCategories = ref
        .watch(libraryFilterCategoriesProvider)
        .ifNull(false);
    final filterCategoriesInclude =
        (ref.watch(libraryFilterCategoriesIncludeProvider) ?? const <String>[])
            .toSet();
    final filterCategoriesExclude =
        (ref.watch(libraryFilterCategoriesExcludeProvider) ?? const <String>[])
            .toSet();
    final filterTags = ref.watch(libraryFilterTagsProvider).ifNull(false);
    final filterTagsInclude =
        (ref.watch(libraryFilterTagsIncludeProvider) ?? const <String>[])
            .toSet();
    final filterTagsExclude =
        (ref.watch(libraryFilterTagsExcludeProvider) ?? const <String>[])
            .toSet();
    final MangaSort sortedBy =
        ref.watch(libraryMangaSortProvider) ?? DBKeys.mangaSort.initial;
    final sortedDirection = ref
        .watch(libraryMangaSortDirectionProvider)
        .ifNull(true);
    final seed =
        ref.watch(librarySortRandomSeedProvider) ??
        DBKeys.librarySortRandomSeed.initial as int;

    return allAsync.map<AsyncValue<List<MangaDto>?>>(
      data: (e) => AsyncData(
        e.value == null
            ? null
            : applyLibraryFilterSort(
                e.value!,
                mangaIds: mangaIds,
                query: query,
                ignoreFilters: ref.watch(webUiBoolProvider('ignoreFilters')),
                fuzzySearch: ref.watch(webUiBoolProvider('fuzzySearch')),
                duplicateChapters: ref.watch(libraryDuplicateChaptersProvider),
                statusFilters: ref.watch(libraryEntryFiltersProvider('status')),
                sourceFilters: ref.watch(libraryEntryFiltersProvider('source')),
                mangaFilterUnread: mangaFilterUnread,
                mangaFilterDownloaded: mangaFilterDownloaded,
                mangaFilterCompleted: mangaFilterCompleted,
                mangaFilterStarted: mangaFilterStarted,
                mangaFilterBookmarked: mangaFilterBookmarked,
                mangaFilterOffline: mangaFilterOffline,
                offlineMangaIds: offlineMangaIds,
                mangaFilterLewd: mangaFilterLewd,
                mangaFilterMinRating:
                    ref.watch(libraryMangaFilterMinRatingProvider) ?? 0,
                filterCategories: filterCategories,
                filterCategoriesInclude: filterCategoriesInclude,
                filterCategoriesExclude: filterCategoriesExclude,
                filterTags: filterTags,
                filterTagsInclude: filterTagsInclude,
                filterTagsExclude: filterTagsExclude,
                sortedBy: sortedBy,
                sortedDirection: sortedDirection,
                seed: seed,
                trackerScales: ref.watch(libraryTrackerScalesProvider),
                trackerFilters: ref.watch(libraryTrackerFiltersProvider),
                trackerNames: ref.watch(libraryTrackerNamesProvider),
              ),
      ),
      error: (e) => e,
      loading: (e) => e,
    );
  }
}

@riverpod
class LibraryDuplicateChapters extends _$LibraryDuplicateChapters {
  @override
  bool? build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    const key = 'mangaFilterDuplicateChapters';
    listenSelf((_, next) {
      if (next == null) {
        prefs.remove(key);
      } else {
        prefs.setBool(key, next);
      }
    });
    return prefs.getBool(key);
  }

  void update(bool? value) => state = value;
}

@riverpod
class LibraryEntryFilters extends _$LibraryEntryFilters {
  @override
  Map<String, bool?> build(String kind) {
    final prefs = ref.watch(sharedPreferencesProvider);
    final key = 'mangaFilter_$kind';
    listenSelf((_, next) => prefs.setString(key, jsonEncode(next)));
    final value = prefs.getString(key);
    if (value == null) return {};
    return (jsonDecode(value) as Map<String, dynamic>).cast<String, bool?>();
  }

  void update(Map<String, bool?> value) => state = value;
}
