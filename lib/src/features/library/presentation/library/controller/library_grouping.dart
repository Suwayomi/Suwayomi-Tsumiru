// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../constants/db_keys.dart';
import '../../../../../constants/enum.dart';
import '../../../../../utils/misc/language_flag.dart';
import '../../../../../utils/mixin/shared_preferences_client_mixin.dart';
import '../../../../../utils/mixin/state_provider_mixin.dart';
import '../../../../manga_book/domain/manga/manga_model.dart';
import '../../../data/default_category.dart';
import '../../../domain/category/category_model.dart';
import '../../../domain/library_group.dart';
import '../../../domain/track_status.dart';
import '../../category/controller/edit_category_controller.dart';
import 'library_manga_list.dart';

part 'library_grouping.g.dart';


typedef MangaProxy = ({
  int id,
  String sourceId,
  String sourceName,
  String sourceLang,
  String status,
  List<int> categoryIds,

  /// All bound tracker statuses; empty when untracked.
  List<int> trackStatuses,

  /// Source genres and custom tags in their original casing.
  List<String> tags,
});

typedef CategoryProxy = ({int id, String name});

MangaProxy mangaToProxy(MangaDto m) => (
  id: m.id,
  sourceId: m.sourceId,
  sourceName: m.source?.name ?? '',
  sourceLang: m.source?.lang ?? '',
  status: m.status.name,
  categoryIds: m.categories.nodes.map((c) => c.id).toList(),
  trackStatuses: m.trackRecords.nodes.map((n) => n.status).toList(),
  // Use the same tag definition as the filter and tag: search.
  tags: [...m.genre, ...(m.metaData.userTags ?? const <String>[])],
);

CategoryProxy categoryToProxy(CategoryDto c) => (id: c.id, name: c.name);


/// Tab ID is the category ID, status rank, or zero for other groups.
typedef GroupedTab = ({int id, String name, List<int> mangaIds});


List<GroupedTab> groupLibrary(
  List<MangaProxy> all,
  int groupType,
  List<CategoryProxy> categories, {
  int? defaultCategoryId = 0,
}) {
  switch (groupType) {
    case LibraryGroup.bySource:
      return _groupBySource(all);

    case LibraryGroup.byStatus:
      return _groupByStatus(all);

    case LibraryGroup.byTrackStatus:
      return _groupByTrackStatus(all);

    case LibraryGroup.byTag:
      return _groupByTag(all);

    case LibraryGroup.byLanguage:
      return _groupByLanguage(all);

    case LibraryGroup.ungrouped:
      return [(id: 0, name: 'All', mangaIds: all.map((m) => m.id).toList())];

    case LibraryGroup.byDefault:
    default:
      return _groupByDefault(all, categories, defaultCategoryId);
  }
}

List<GroupedTab> _groupByDefault(
  List<MangaProxy> all,
  List<CategoryProxy> categories,
  int? defaultCategoryId,
) {
  final buckets = <int, List<int>>{
    for (final category in categories) category.id: [],
  };
  if (defaultCategoryId != null) {
    buckets.putIfAbsent(defaultCategoryId, () => []);
  }
  for (final manga in all) {
    final ids = manga.categoryIds.isEmpty && defaultCategoryId != null
        ? [defaultCategoryId]
        : manga.categoryIds;
    for (final id in ids.toSet()) {
      buckets.putIfAbsent(id, () => []).add(manga.id);
    }
  }
  return [
    if (defaultCategoryId != null &&
        !categories.any((c) => c.id == defaultCategoryId) &&
        buckets[defaultCategoryId]!.isNotEmpty)
      (
        id: defaultCategoryId,
        name: 'Default',
        mangaIds: buckets[defaultCategoryId]!,
      ),
    for (final category in categories)
      (id: category.id, name: category.name, mangaIds: buckets[category.id]!),
  ];
}

List<GroupedTab> _groupBySource(List<MangaProxy> all) {
  final Map<String, ({String name, String lang, List<int> mangaIds})> buckets =
      {};
  for (final m in all) {
    final sid = m.sourceId;
    final name = m.sourceLang == kLocalSourceLang
        ? 'Local source'
        : m.sourceName;
    final entry = buckets.putIfAbsent(
      sid,
      () => (name: name, lang: m.sourceLang, mangaIds: []),
    );
    entry.mangaIds.add(m.id);
  }
  // Sources installed for multiple locales share a name; append language to distinguish them.
  final nameCounts = <String, int>{};
  for (final b in buckets.values) {
    nameCounts[b.name] = (nameCounts[b.name] ?? 0) + 1;
  }
  final sorted = buckets.entries.toList()
    ..sort(
      (a, b) =>
          a.value.name.toLowerCase().compareTo(b.value.name.toLowerCase()),
    );
  // The grouped-list provider requires unique tab ids; nonnumeric source ids use their hash.
  return sorted.map((e) {
    final isDuplicateName = (nameCounts[e.value.name] ?? 0) > 1;
    final label = isDuplicateName && e.value.lang != kLocalSourceLang
        ? '${e.value.name} (${e.value.lang.toUpperCase()})'
        : e.value.name;
    return (
      id: int.tryParse(e.key) ?? e.key.hashCode,
      name: label,
      mangaIds: e.value.mangaIds,
    );
  }).toList();
}

List<GroupedTab> _groupByStatus(List<MangaProxy> all) {
  final Map<String, List<int>> buckets = {};
  for (final m in all) {
    final status = statusOrder.containsKey(m.status) ? m.status : 'UNKNOWN';
    buckets.putIfAbsent(status, () => []).add(m.id);
  }
  final sorted = buckets.entries.toList()
    ..sort(
      (a, b) => (statusOrder[a.key] ?? 7).compareTo(statusOrder[b.key] ?? 7),
    );
  return sorted
      .map(
        (e) => (
          id: statusOrder[e.key] ?? 7,
          name: _statusLabel(e.key),
          mangaIds: e.value,
        ),
      )
      .toList();
}

String _statusLabel(String status) => switch (status) {
  'ONGOING' => 'Ongoing',
  'COMPLETED' => 'Completed',
  'PUBLISHING_FINISHED' => 'Publishing finished',
  'LICENSED' => 'Licensed',
  'ON_HIATUS' => 'On hiatus',
  'CANCELLED' => 'Cancelled',
  _ => 'Unknown',
};

/// Name-derived IDs remain stable as buckets change; prefixes separate namespaces.
int _nameId(String prefix, String name) => Object.hash(prefix, name);

/// Negative sentinel IDs cannot collide with real category or status IDs.
const int _kNoTagId = -101;
const int _kNoLanguageId = -102;

List<GroupedTab> _groupByTag(List<MangaProxy> all) {
  // Fan out by case-insensitive tag, preserving first-seen display casing.
  final Map<String, ({String display, List<int> mangaIds})> buckets = {};
  final List<int> untagged = [];

  for (final m in all) {
    final seen = <String>{};
    for (final raw in m.tags) {
      final tag = raw.trim();
      if (tag.isEmpty) continue;
      final key = tag.toLowerCase();
      // A genre that is also a custom tag must appear only once per manga.
      if (!seen.add(key)) continue;
      buckets
          .putIfAbsent(key, () => (display: tag, mangaIds: []))
          .mangaIds
          .add(m.id);
    }
    if (seen.isEmpty) untagged.add(m.id);
  }

  final sorted = buckets.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));

  return [
    for (final e in sorted)
      (
        id: _nameId('tag', e.key),
        name: e.value.display,
        mangaIds: e.value.mangaIds,
      ),
    if (untagged.isNotEmpty)
      (id: _kNoTagId, name: 'Untagged', mangaIds: untagged),
  ];
}

List<GroupedTab> _groupByLanguage(List<MangaProxy> all) {
  // Local-source entries have no real language and need their own trailing bucket.
  final Map<String, List<int>> buckets = {};
  final List<int> unknown = [];

  for (final m in all) {
    final lang = m.sourceLang.trim().toLowerCase();
    if (lang.isEmpty || lang == kLocalSourceLang) {
      unknown.add(m.id);
    } else {
      buckets.putIfAbsent(lang, () => []).add(m.id);
    }
  }

  // Sort localized display names rather than ISO codes.
  final sorted = buckets.entries.toList()
    ..sort(
      (a, b) => languageDisplayName(
        a.key,
      ).toLowerCase().compareTo(languageDisplayName(b.key).toLowerCase()),
    );

  return [
    for (final e in sorted)
      (
        id: _nameId('lang', e.key),
        name: [
          languageFlagEmoji(e.key),
          languageDisplayName(e.key),
        ].whereType<String>().join(' '),
        mangaIds: e.value,
      ),
    if (unknown.isNotEmpty)
      (id: _kNoLanguageId, name: 'Local source', mangaIds: unknown),
  ];
}

List<GroupedTab> _groupByTrackStatus(List<MangaProxy> all) {
  // Fan out across track statuses; untracked manga belong to Other (99).
  final Map<int, List<int>> buckets = {};

  for (final m in all) {
    if (m.trackStatuses.isEmpty) {
      buckets.putIfAbsent(99, () => []).add(m.id);
    } else {
      // Multiple trackers with the same status must not duplicate a manga in that bucket.
      final distinctStatuses = m.trackStatuses.toSet();
      for (final st in distinctStatuses) {
        buckets.putIfAbsent(st, () => []).add(m.id);
      }
    }
  }

  final sorted = buckets.entries.toList()
    ..sort(
      (a, b) => trackStatusOrder(a.key).compareTo(trackStatusOrder(b.key)),
    );

  return sorted
      .map((e) => (id: e.key, name: trackStatusLabel(e.key), mangaIds: e.value))
      .toList();
}


@riverpod
class LibraryGroupType extends _$LibraryGroupType
    with SharedPreferenceClientMixin<int> {
  @override
  int? build() => initialize(DBKeys.libraryGroupType);
}

@riverpod
class LibraryGroupStyleKey extends _$LibraryGroupStyleKey
    with SharedPreferenceEnumClientMixin<LibraryGroupStyle> {
  @override
  LibraryGroupStyle? build() =>
      initialize(DBKeys.libraryGroupStyle, enumList: LibraryGroupStyle.values);
}

/// Live section readout written by LibrarySectionsView; never use it to drive scroll position.
@riverpod
class LibraryVisibleSection extends _$LibraryVisibleSection
    with StateProviderMixin<int?> {
  @override
  int? build() => null;
}

@riverpod
Future<List<GroupedTab>> libraryGroupedTabs(Ref ref) async {
  // Watch dependencies before awaiting so auto-dispose subscriptions survive rebuilds.
  final groupType =
      ref.watch(libraryGroupTypeProvider) ?? kDefaultLibraryGroupType;
  // Grouped modes do not use categories; watching them adds an unnecessary rebuild dependency.
  final List<CategoryProxy> catProxies = groupType == LibraryGroup.byDefault
      ? (ref.watch(visibleCategoryListProvider).value ?? const [])
            .map(categoryToProxy)
            .toList()
      : const [];
  final defaultId = groupType == LibraryGroup.byDefault
      ? ref.watch(settledDefaultCategoryIdProvider)
      : null;
  final allFuture = ref.watch(libraryMangaListProvider.future);

  final all = await allFuture;
  if (all == null) return const [];

  final proxies = all.map(mangaToProxy).toList();
  return groupLibrary(
    proxies,
    groupType,
    catProxies,
    defaultCategoryId: defaultId,
  );
}
