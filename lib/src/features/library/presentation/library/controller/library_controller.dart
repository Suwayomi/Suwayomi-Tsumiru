// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../constants/db_keys.dart';
import '../../../domain/track_status.dart';
import '../../../../../constants/enum.dart';
import '../../../../../features/offline/data/offline_download_providers.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/mixin/shared_preferences_client_mixin.dart';
import '../../../../../global_providers/global_providers.dart';
import '../../../../../utils/mixin/state_provider_mixin.dart';
import '../../../../manga_book/domain/manga/manga_model.dart';
import '../../../../tracking/data/tracker_repository.dart';
import '../../../domain/category/category_model.dart';
import '../../../domain/library_search_query.dart';
import 'library_grouping.dart';
import 'library_manga_list.dart';

part 'library_controller.g.dart';

/// Knuth multiplicative hash used by the Random sort.
///
/// Returns a stable, non-negative integer for a given manga [id] and [seed].
/// Incrementing [seed] re-rolls the ordering across the whole library.
///
/// XORing id with seed BEFORE the multiply ensures the seed changes relative
/// ordering between entries (a constant XOR after the multiply would only shift
/// all keys by the same value, leaving ordering unchanged).
int randomKey(int id, int seed) => ((id ^ seed) * 2654435761) & 0x7fffffff;

/// Applies the library filter + sort pipeline to [input].
///
/// All filter/sort values are passed in as resolved scalars so that the
/// calling provider retains full control over its `ref.watch` calls and
/// Riverpod dependency tracking is unaffected.
///
/// [mangaIds] is an optional allowlist — when non-null only manga whose id
/// is in the set pass through (used by [GroupedMangaListWithQueryAndFilter]).
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
  int seed = 0,
  Map<int, double> trackerScales = const {},
  Map<int, bool?> trackerFilters = const {},
  Map<int, String> trackerNames = const {},
}) {
  final searchQuery = LibrarySearchQuery.parse(query);
  // Tags match case-insensitively (aligning with the `tag:` search operator),
  // so lower-case the selections once up front.
  final filterTagsIncludeLower =
      filterTagsInclude.map((e) => e.toLowerCase()).toSet();
  final filterTagsExcludeLower =
      filterTagsExclude.map((e) => e.toLowerCase()).toSet();

  bool filter(MangaDto manga) {
    if (mangaIds != null && !mangaIds.contains(manga.id)) return false;
    if (mangaFilterUnread != null &&
        (mangaFilterUnread ^ manga.unreadCount.isGreaterThan(0))) {
      return false;
    }
    if (mangaFilterDownloaded != null &&
        (mangaFilterDownloaded ^ manga.downloadCount.isGreaterThan(0))) {
      return false;
    }
    if (mangaFilterCompleted != null &&
        (mangaFilterCompleted ^ (manga.status.name == "COMPLETED"))) {
      return false;
    }
    if (mangaFilterStarted != null &&
        (mangaFilterStarted ^ (manga.lastReadChapter != null))) {
      return false;
    }
    if (mangaFilterBookmarked != null &&
        (mangaFilterBookmarked ^ manga.bookmarkCount.isGreaterThan(0))) {
      return false;
    }
    if (mangaFilterOffline != null &&
        (mangaFilterOffline ^ offlineMangaIds.contains(manga.id))) {
      return false;
    }
    if (mangaFilterLewd != null &&
        (mangaFilterLewd ^ (manga.source?.isNsfw ?? false))) {
      return false;
    }
    // Meta-derived fields (rating, tags) plus the DSL-searchable fields, built
    // once and reused by the rating filter, tags filter, and search below.
    final fields = manga.filterFields(trackerNames);
    if (mangaFilterMinRating > 0 &&
        (fields.rating ?? 0) < mangaFilterMinRating) {
      return false;
    }
    if (filterCategories) {
      final ids =
          manga.categories.nodes.map((c) => c.id.toString()).toSet();
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
      // A manga's tags = source genres + the user's custom tags (lower-cased).
      final tags = {
        for (final t in fields.genres) t.toLowerCase(),
        for (final t in fields.userTags) t.toLowerCase(),
      };
      // Include is OR (has any selected tag); exclude wins over include.
      if (filterTagsIncludeLower.isNotEmpty &&
          tags.intersection(filterTagsIncludeLower).isEmpty) {
        return false;
      }
      if (filterTagsExcludeLower.isNotEmpty &&
          tags.intersection(filterTagsExcludeLower).isNotEmpty) {
        return false;
      }
    }
    // Per-tracker filters: for each tracker id with a non-null preference,
    // true = manga must have a record for that tracker,
    // false = manga must NOT have a record for that tracker.
    for (final entry in trackerFilters.entries) {
      final pref = entry.value;
      if (pref == null) continue;
      final hasTracker = manga.trackRecords.nodes
          .any((n) => n.trackerId == entry.key);
      if (pref ^ hasTracker) return false;
    }
    if (!searchQuery.matches(fields)) return false;
    return true;
  }

  int sort(MangaDto m1, MangaDto m2) {
    final sortDirToggle = (sortedDirection ? 1 : -1);
    // Random sort: direction is pinned (always ascending by key) so that the
    // direction toggle button doesn't fight the re-roll affordance.
    if (sortedBy == MangaSort.random) {
      return randomKey(m1.id, seed).compareTo(randomKey(m2.id, seed));
    }
    // Tracker-score sort: untracked manga (sentinel -1) always sort last,
    // regardless of direction — must be handled before the direction toggle.
    if (sortedBy == MangaSort.trackerScore) {
      final s1 = meanNormalizedScore(m1.trackRecords.nodes,
          trackerScales: trackerScales);
      final s2 = meanNormalizedScore(m2.trackRecords.nodes,
          trackerScales: trackerScales);
      if (s1 < 0 && s2 < 0) return 0;
      if (s1 < 0) return 1;  // m1 untracked → always last
      if (s2 < 0) return -1; // m2 untracked → always last
      return s1.compareTo(s2) * sortDirToggle;
    }
    return (switch (sortedBy) {
          MangaSort.alphabetical => (m1.title).compareTo(m2.title),
          MangaSort.unread => (m1.unreadCount.getValueOnNullOrNegative())
              .compareTo(m2.unreadCount.getValueOnNullOrNegative()),
          MangaSort.dateAdded => (m1.inLibraryAt.getValueOnNullOrNegative())
              .compareTo(m2.inLibraryAt.getValueOnNullOrNegative()),
          MangaSort.lastUpdated =>
            (int.tryParse(m1.latestFetchedChapter?.fetchedAt ?? '0') ?? 0)
                .compareTo(
                    int.tryParse(m2.latestFetchedChapter?.fetchedAt ?? '0') ??
                        0),
          MangaSort.lastChapterDate => (int.tryParse(
                      m1.latestUploadedChapter?.uploadDate ?? '0') ??
                  0)
              .compareTo(
                  int.tryParse(m2.latestUploadedChapter?.uploadDate ?? '0') ??
                      0),
          MangaSort.totalChapters =>
            m1.chapters.totalCount.compareTo(m2.chapters.totalCount),
          // "Last update" = the manga's library-update time. Suwayomi's
          // chaptersLastFetchedAt is when this manga's chapter list was last
          // refreshed (distinct from ChapterFetchDate/LatestChapter above).
          MangaSort.lastUpdate =>
            (int.tryParse(m1.chaptersLastFetchedAt ?? '0') ?? 0)
                .compareTo(int.tryParse(m2.chaptersLastFetchedAt ?? '0') ?? 0),
          // Personal star rating (0 = unrated, sorts lowest).
          MangaSort.rating => (m1.metaData.rating ?? 0)
              .compareTo(m2.metaData.rating ?? 0),
          // Normal order (m1 vs m2): ascending = oldest-read first,
          // descending = newest-read first. (Previously the operands were
          // swapped, which inverted our arrows — our "ascending" showed
          // newest first.)
          MangaSort.lastRead =>
            (int.tryParse(m1.lastReadChapter?.lastReadAt ?? '0') ?? 0)
                .compareTo(
                    int.tryParse(m2.lastReadChapter?.lastReadAt ?? '0') ?? 0),
          // random is handled above; this arm is unreachable.
          MangaSort.random =>
            randomKey(m1.id, seed).compareTo(randomKey(m2.id, seed)),
          // trackerScore is handled above; this arm is unreachable.
          MangaSort.trackerScore => 0,
        }) *
        sortDirToggle;
  }

  return input.where(filter).toList()..sort(sort);
}

@riverpod
Future<List<MangaDto>?> categoryMangaList(Ref ref, int categoryId) async {
  final all = await ref.watch(libraryMangaListProvider.future);
  if (all == null) return null;
  return all.where((m) {
    final ids = m.categories.nodes.map((c) => c.id).toList();
    // categoryId 0 == Default/Uncategorized (no categories)
    return categoryId == 0 ? ids.isEmpty : ids.contains(categoryId);
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
    final query = ref.watch(libraryQueryProvider);
    final mangaFilterUnread = ref.watch(libraryMangaFilterUnreadProvider);
    final mangaFilterDownloaded =
        ref.watch(libraryMangaFilterDownloadedProvider);
    final mangaFilterCompleted = ref.watch(libraryMangaFilterCompletedProvider);
    final mangaFilterStarted = ref.watch(libraryMangaFilterStartedProvider);
    final mangaFilterBookmarked =
        ref.watch(libraryMangaFilterBookmarkedProvider);
    final mangaFilterOffline = ref.watch(libraryMangaFilterOfflineProvider);
    final offlineMangaIds =
        ref.watch(offlineDeviceMangaIdsProvider).valueOrNull ?? const <int>{};
    final mangaFilterLewd = ref.watch(libraryMangaFilterLewdProvider);
    final filterCategories =
        ref.watch(libraryFilterCategoriesProvider).ifNull(false);
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
    final sortedDirection =
        ref.watch(libraryMangaSortDirectionProvider).ifNull(true);
    final seed =
        ref.watch(librarySortRandomSeedProvider) ?? DBKeys.librarySortRandomSeed.initial as int;

    return mangaList.map<AsyncValue<List<MangaDto>?>>(
      data: (e) => AsyncData(e.valueOrNull == null
          ? null
          : applyLibraryFilterSort(
              e.valueOrNull!,
              query: query,
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
            )),
      error: (e) => e,
      loading: (e) => e,
    );
  }

  void invalidate() {
    ref.invalidate(libraryMangaListProvider);
    ref.invalidate(categoryMangaListProvider(categoryId));
  }
}

@riverpod
class LibraryQuery extends _$LibraryQuery with StateProviderMixin<String?> {
  @override
  String? build() => null;
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

/// Distinct tags across the whole library, sorted case-insensitively. A manga's
/// tags are its source genres plus the user's own custom tags — both are just
/// labels on the manga, so both are filterable. Populates the tags filter dialog.
@riverpod
Future<List<String>> libraryTagList(Ref ref) async {
  final all = await ref.watch(libraryMangaListProvider.future);
  if (all == null) return const [];
  // Dedupe case-insensitively (keeping the first-seen casing for display) so a
  // library with both "Action" and "action" shows one row, matching the
  // case-insensitive tag filter.
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
  MangaSort? build() => initialize(
        DBKeys.mangaSort,
        enumList: MangaSort.values,
      );
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

/// Category new manga are added to when favorited. -1 = always ask,
/// 0 = Default/uncategorized, >0 = a specific category id.
@riverpod
class LibraryDefaultCategory extends _$LibraryDefaultCategory
    with SharedPreferenceClientMixin<int> {
  @override
  int? build() => initialize(DBKeys.libraryDefaultCategory);
}

/// Tri-state filter preference for a single tracker.
///
/// Key pattern: `mangaFilterTracker_<trackerId>`.
/// null = not filtered, true = must be tracked, false = must not be tracked.
@riverpod
class LibraryMangaFilterTracker extends _$LibraryMangaFilterTracker {
  @override
  bool? build({required int trackerId}) {
    final prefs = ref.watch(sharedPreferencesProvider);
    final key = 'mangaFilterTracker_$trackerId';
    ref.listenSelf((_, next) {
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

/// Resolved map of per-tracker filters: tracker id → bool? preference.
/// Only includes entries with a non-null filter value (i.e., active filters).
@riverpod
Map<int, bool?> libraryTrackerFilters(Ref ref) {
  final loggedIn =
      ref.watch(loggedInTrackersProvider).valueOrNull ?? const [];
  final Map<int, bool?> result = {};
  for (final tracker in loggedIn) {
    final pref = ref.watch(
        libraryMangaFilterTrackerProvider(trackerId: tracker.id));
    result[tracker.id] = pref;
  }
  return result;
}

/// Map of tracker id → scale max (derived from the numeric value of the last
/// score label).
///
/// Parses the last entry in [tracker.scores] as a double to get the true max
/// score value (e.g. "9.9" → 9.9 for MangaUpdates, "100" → 100.0 for
/// AniList). Falls back to `scores.length - 1` when the last label is not
/// numeric (e.g. letter/emoji scales), or to 10.0 when the list is empty.
///
/// Used by [applyLibraryFilterSort] to normalize scores to 0–10.
@riverpod
Map<int, double> libraryTrackerScales(Ref ref) {
  final loggedIn =
      ref.watch(loggedInTrackersProvider).valueOrNull ?? const [];
  return {
    for (final t in loggedIn)
      t.id: t.scores.isEmpty
          ? 10.0
          : (double.tryParse(t.scores.last) ??
              (t.scores.length - 1).toDouble()),
  };
}

/// Map of tracker id → display name, resolving the `tracked:<service>` search
/// metatag (e.g. `tracked:anilist`). Uses all known trackers, not just
/// logged-in ones, so a bound record still resolves after a logout.
@riverpod
Map<int, String> libraryTrackerNames(Ref ref) {
  final all = ref.watch(trackersProvider).valueOrNull ?? const [];
  return {for (final t in all) t.id: t.name};
}

@riverpod
class LibraryDisplayMode extends _$LibraryDisplayMode
    with SharedPreferenceEnumClientMixin<DisplayMode> {
  @override
  DisplayMode? build() => initialize(
        DBKeys.libraryDisplayMode,
        enumList: DisplayMode.values,
      );
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
class CategoryTabs extends _$CategoryTabs
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.categoryTabs);
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

/// Like [CategoryMangaListWithQueryAndFilter] but for a pre-computed set of
/// manga IDs (used by non-default group tabs: BY_SOURCE, BY_STATUS, UNGROUPED).
/// Applies the same query/filter/sort pipeline.
@riverpod
class GroupedMangaListWithQueryAndFilter
    extends _$GroupedMangaListWithQueryAndFilter {
  @override
  AsyncValue<List<MangaDto>?> build({required int tabId}) {
    // Keyed by the STABLE tab id (int), not the mangaId Set — a Set has no
    // value equality, so passing a freshly-built Set as the family key minted a
    // new provider on every rebuild and thrashed into an infinite loading
    // flicker. Resolve the id-set here from the grouped-tabs provider instead.
    final tabs = ref.watch(libraryGroupedTabsProvider).valueOrNull;
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
    final query = ref.watch(libraryQueryProvider);
    final mangaFilterUnread = ref.watch(libraryMangaFilterUnreadProvider);
    final mangaFilterDownloaded =
        ref.watch(libraryMangaFilterDownloadedProvider);
    final mangaFilterCompleted = ref.watch(libraryMangaFilterCompletedProvider);
    final mangaFilterStarted = ref.watch(libraryMangaFilterStartedProvider);
    final mangaFilterBookmarked =
        ref.watch(libraryMangaFilterBookmarkedProvider);
    final mangaFilterOffline = ref.watch(libraryMangaFilterOfflineProvider);
    final offlineMangaIds =
        ref.watch(offlineDeviceMangaIdsProvider).valueOrNull ?? const <int>{};
    final mangaFilterLewd = ref.watch(libraryMangaFilterLewdProvider);
    final filterCategories =
        ref.watch(libraryFilterCategoriesProvider).ifNull(false);
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
    final sortedDirection =
        ref.watch(libraryMangaSortDirectionProvider).ifNull(true);
    final seed =
        ref.watch(librarySortRandomSeedProvider) ?? DBKeys.librarySortRandomSeed.initial as int;

    return allAsync.map<AsyncValue<List<MangaDto>?>>(
      data: (e) => AsyncData(e.valueOrNull == null
          ? null
          : applyLibraryFilterSort(
              e.valueOrNull!,
              mangaIds: mangaIds,
              query: query,
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
            )),
      error: (e) => e,
      loading: (e) => e,
    );
  }
}
