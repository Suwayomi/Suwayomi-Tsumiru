// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../constants/db_keys.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/mixin/shared_preferences_client_mixin.dart';
import '../data/history_repository.dart';
import '../domain/history_group.dart';
import '../domain/history_item.dart';

part 'history_controller.g.dart';

@riverpod
class ReadingHistory extends _$ReadingHistory {
  @override
  Future<List<HistoryItemDto>?> build() async {
    final items =
        await ref.watch(historyRepositoryProvider).getReadingHistory();
    // Guard the post-await ref use: the provider may have been disposed during
    // the fetch, and keepAlive() on a dead ref throws UnmountedRefException.
    if (ref.mounted) ref.keepAlive();
    return items;
  }

  Future<void> refresh() async {
    // Don't reset to AsyncLoading — that blanks the list to a full-screen
    // spinner on pull-to-refresh. Keep the current items visible until fresh
    // data lands (the RefreshIndicator already shows the pull spinner).
    final result = await AsyncValue.guard(
      () => ref.read(historyRepositoryProvider).getReadingHistory(),
    );
    if (!ref.mounted) return;
    final items = result.asData?.value;
    if (items != null) state = AsyncData(items);
    // On error keep the current list (the pull spinner has dismissed).
  }

}

@riverpod
class MangaReadingHistory extends _$MangaReadingHistory {
  @override
  Future<List<HistoryItemDto>?> build({required int mangaId}) async {
    return ref
        .watch(historyRepositoryProvider)
        .getMangaReadingHistory(mangaId: mangaId);
  }

  Future<void> refresh() async {
    final result = await AsyncValue.guard(
      () => ref
          .read(historyRepositoryProvider)
          .getMangaReadingHistory(mangaId: mangaId),
    );
    if (ref.mounted) state = result;
  }
}

/// The History list filters, as one value; a record so equality is structural.
typedef HistoryFilter = ({
  bool? unfinishedSeries,
  bool? unread,
  bool? inLibrary,
});

const HistoryFilter kNoHistoryFilter = (
  unfinishedSeries: null,
  unread: null,
  inLibrary: null,
);

@riverpod
class HistoryFilterUnfinishedSeries extends _$HistoryFilterUnfinishedSeries
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.historyFilterUnfinishedSeries);
}

@riverpod
class HistoryFilterUnread extends _$HistoryFilterUnread
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.historyFilterUnread);
}

@riverpod
class HistoryFilterInLibrary extends _$HistoryFilterInLibrary
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.historyFilterInLibrary);
}

@riverpod
HistoryFilter historyFilter(Ref ref) => (
      unfinishedSeries: ref.watch(historyFilterUnfinishedSeriesProvider),
      unread: ref.watch(historyFilterUnreadProvider),
      inLibrary: ref.watch(historyFilterInLibraryProvider),
    );

@riverpod
bool historyHasActiveFilters(Ref ref) =>
    ref.watch(historyFilterProvider) != kNoHistoryFilter;

/// Applies [filter] to one row. Each filter is tri-state: null passes
/// everything, true keeps matches, false keeps non-matches.
bool historyItemMatchesFilter(HistoryItemDto item, HistoryFilter filter) {
  final unfinishedSeries = filter.unfinishedSeries;
  if (unfinishedSeries != null &&
      unfinishedSeries != (item.manga.unreadCount > 0)) {
    return false;
  }
  final unread = filter.unread;
  if (unread != null && unread != !item.isRead) return false;
  final inLibrary = filter.inLibrary;
  if (inLibrary != null && inLibrary != item.manga.inLibrary) return false;
  return true;
}

@riverpod
List<HistoryGroup> historyGroupedByDate(Ref ref) {
  final allItems = ref.watch(readingHistoryProvider).value ?? [];
  final filter = ref.watch(historyFilterProvider);
  final historyItems = filter == kNoHistoryFilter
      ? allItems
      : allItems
          .where((item) => historyItemMatchesFilter(item, filter))
          .toList();

  if (historyItems.isEmpty) return [];

  final Map<String, List<HistoryItemDto>> groupedItems = {};

  for (final item in historyItems) {
    final groupKey = item.readDateGroupKey;
    groupedItems.putIfAbsent(groupKey, () => []).add(item);
  }

  final groups = groupedItems.entries.map((entry) {
    return HistoryGroup(
      title: entry.key,
      items: entry.value,
    );
  }).toList();

  groups.sort((a, b) {
    final aDate = a.mostRecentReadDate;
    final bDate = b.mostRecentReadDate;

    if (aDate == null && bDate == null) return 0;
    if (aDate == null) return 1;
    if (bDate == null) return -1;

    return bDate.compareTo(aDate); // Most recent first
  });

  return groups;
}

@riverpod
List<HistoryGroup> filteredHistoryGroups(Ref ref) {
  final groups = ref.watch(historyGroupedByDateProvider);
  final searchQuery = ref.watch(historySearchQueryProvider);

  if (searchQuery.isBlank) return groups;

  final filteredGroups = groups
      .map((group) => group.filterByQuery(searchQuery))
      .where((group) => group.isNotEmpty)
      .toList();

  return filteredGroups;
}

@riverpod
class HistorySearchQuery extends _$HistorySearchQuery {
  @override
  String build() => '';

  void updateQuery(String query) {
    state = query;
  }

  void clearQuery() {
    state = '';
  }
}

// History settings providers
@riverpod
class HistoryRetentionDays extends _$HistoryRetentionDays
    with SharedPreferenceClientMixin<int> {
  @override
  int? build() => initialize(DBKeys.historyRetentionDays);

  void updateRetentionDays(int days) {
    update(days);
  }
}

@riverpod
class HistoryEnabled extends _$HistoryEnabled
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.historyEnabled);

  void toggleHistory() {
    update(!(state ?? true));
  }
}
