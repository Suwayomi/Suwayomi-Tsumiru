// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../constants/db_keys.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/misc/toast/toast.dart';
import '../../../utils/mixin/shared_preferences_client_mixin.dart';
import '../../manga_book/presentation/manga_details/controller/manga_details_controller.dart';
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

  /// Remove a chapter from reading history.
  Future<void> removeFromHistory(int chapterId) async {
    final current = state.value ?? const <HistoryItemDto>[];
    HistoryItemDto? removed;
    for (final item in current) {
      if (item.id == chapterId) {
        removed = item;
        break;
      }
    }
    final result = await AsyncValue.guard(
      () =>
          ref.read(historyRepositoryProvider).removeChapterFromHistory(chapterId),
    );
    if (!ref.mounted) return;
    if (result.hasError) {
      // Don't invalidate as though it succeeded — item would just reappear.
      ref.read(toastProvider)?.showError(result.error.toString());
      return;
    }
    if (removed != null) {
      ref.invalidate(mangaChapterListProvider(mangaId: removed.mangaId));
      ref.invalidate(mangaWithIdProvider(mangaId: removed.mangaId));
    }
    // Rebuild from the top so the removed chapter drops out.
    ref.invalidateSelf();
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

@riverpod
List<HistoryGroup> historyGroupedByDate(Ref ref) {
  final historyItems = ref.watch(readingHistoryProvider).value ?? [];

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
