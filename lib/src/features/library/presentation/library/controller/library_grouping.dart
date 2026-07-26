// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../constants/db_keys.dart';
import '../../../../../constants/enum.dart';
import '../../../../../utils/misc/language_flag.dart';
import '../../../../../utils/mixin/shared_preferences_client_mixin.dart';
import '../../../../../utils/mixin/state_provider_mixin.dart';
import '../../../../manga_book/domain/manga/manga_model.dart';
import '../../../domain/category/category_model.dart';
import '../../../domain/library_group.dart';
import '../../../domain/track_status.dart';
import '../../category/controller/edit_category_controller.dart';
import 'library_manga_list.dart';

part 'library_grouping.g.dart';

// ─────────────────── lightweight proxy types ────────────────────────────────

/// Duck-typed projection of [MangaDto] fields needed for grouping.
/// The test creates these directly; the real code converts MangaDto via
/// [mangaToProxy].
typedef MangaProxy = ({
  int id,
  String sourceId,
  String sourceName,
  String sourceLang,
  String status,
  List<int> categoryIds,
  /// Track status integers from all bound track records.
  /// Empty for untracked manga.
  List<int> trackStatuses,

  /// Source genres + the user's own tags, as stored (original casing).
  /// Empty for untagged manga.
  List<String> tags,
});

/// Duck-typed projection of [CategoryDto] fields needed for grouping.
typedef CategoryProxy = ({
  int id,
  String name,
});

MangaProxy mangaToProxy(MangaDto m) => (
      id: m.id,
      sourceId: m.sourceId,
      sourceName: m.source?.name ?? '',
      sourceLang: m.source?.lang ?? '',
      status: m.status.name,
      categoryIds: m.categories.nodes.map((c) => c.id).toList(),
      trackStatuses: m.trackRecords.nodes.map((n) => n.status).toList(),
      // Same definition the tags FILTER uses, so buckets and `tag:` searches
      // never disagree.
      tags: [...m.genre, ...(m.metaData.userTags ?? const <String>[])],
    );

CategoryProxy categoryToProxy(CategoryDto c) => (id: c.id, name: c.name);

// ─────────────────── GroupedTab ─────────────────────────────────────────────

/// A single tab produced by [groupLibrary].
///
/// [id] is tab-type-specific:
/// - BY_DEFAULT: category id (0 = uncategorized)
/// - BY_SOURCE:  0 (not used for lookup)
/// - BY_STATUS:  the [statusOrder] rank (1–7)
/// - UNGROUPED:  0
typedef GroupedTab = ({int id, String name, List<int> mangaIds});

// ─────────────────── pure grouping function ──────────────────────────────────

/// Returns the ordered list of [GroupedTab]s for [groupType].
///
/// This is a PURE function with no I/O — all data is passed in. The test
/// suite calls it directly with [MangaProxy] / [CategoryProxy] fakes.
List<GroupedTab> groupLibrary(
  List<MangaProxy> all,
  int groupType,
  List<CategoryProxy> categories,
) {
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
      return [
        (id: 0, name: 'All', mangaIds: all.map((m) => m.id).toList()),
      ];

    case LibraryGroup.byDefault:
    default:
      return _groupByDefault(all, categories);
  }
}

List<GroupedTab> _groupByDefault(
  List<MangaProxy> all,
  List<CategoryProxy> categories,
) {
  // Fan-out: a manga in N categories appears in all N tabs.
  // No-category manga go to the Default tab (id 0).
  final Map<int, List<int>> buckets = {};

  // Seed with all visible categories so empty tabs still appear
  // (existing category tabs stay even if 0 manga match).
  for (final cat in categories) {
    buckets[cat.id] = [];
  }
  // id 0 = Default/Uncategorized
  buckets[0] = [];

  for (final m in all) {
    if (m.categoryIds.isEmpty) {
      buckets[0]!.add(m.id);
    } else {
      for (final catId in m.categoryIds) {
        buckets.putIfAbsent(catId, () => []).add(m.id);
      }
    }
  }

  // Order: Default (0) first if non-empty, then seeded categories in order.
  final List<GroupedTab> tabs = [];

  // Default tab first
  if (buckets[0]!.isNotEmpty) {
    tabs.add((id: 0, name: 'Default', mangaIds: buckets[0]!));
  }

  // Then the seeded categories, in order
  for (final cat in categories) {
    final ids = buckets[cat.id] ?? [];
    tabs.add((id: cat.id, name: cat.name, mangaIds: ids));
  }

  return tabs;
}

List<GroupedTab> _groupBySource(List<MangaProxy> all) {
  final Map<String, ({String name, String lang, List<int> mangaIds})>
      buckets = {};
  for (final m in all) {
    final sid = m.sourceId;
    final name =
        m.sourceLang == kLocalSourceLang ? 'Local source' : m.sourceName;
    final entry = buckets.putIfAbsent(
      sid,
      () => (name: name, lang: m.sourceLang, mangaIds: []),
    );
    entry.mangaIds.add(m.id);
  }
  // A source installed once per locale (two MangaDex ids, say) shares its name
  // across buckets, so those get their language code appended below.
  final nameCounts = <String, int>{};
  for (final b in buckets.values) {
    nameCounts[b.name] = (nameCounts[b.name] ?? 0) + 1;
  }
  // Sort source tabs case-insensitively by name.
  final sorted = buckets.entries.toList()
    ..sort((a, b) =>
        a.value.name.toLowerCase().compareTo(b.value.name.toLowerCase()));
  // Each tab needs a UNIQUE id (the grouped-list provider is keyed by tab id).
  // Source ids are numeric strings; fall back to the string hash if not.
  return sorted
      .map((e) {
        final isDuplicateName = (nameCounts[e.value.name] ?? 0) > 1;
        final label = isDuplicateName && e.value.lang != kLocalSourceLang
            ? '${e.value.name} (${e.value.lang.toUpperCase()})'
            : e.value.name;
        return (
          id: int.tryParse(e.key) ?? e.key.hashCode,
          name: label,
          mangaIds: e.value.mangaIds,
        );
      })
      .toList();
}

List<GroupedTab> _groupByStatus(List<MangaProxy> all) {
  final Map<String, List<int>> buckets = {};
  for (final m in all) {
    final status =
        statusOrder.containsKey(m.status) ? m.status : 'UNKNOWN';
    buckets.putIfAbsent(status, () => []).add(m.id);
  }
  // Sort by statusOrder rank.
  final sorted = buckets.entries.toList()
    ..sort(
        (a, b) => (statusOrder[a.key] ?? 7).compareTo(statusOrder[b.key] ?? 7));
  return sorted
      .map((e) => (
            id: statusOrder[e.key] ?? 7,
            name: _statusLabel(e.key),
            mangaIds: e.value,
          ))
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

/// Tab id for a bucket keyed by name rather than a server id — a positional
/// index would shift as soon as a new tag or language appeared. The prefix
/// separates the namespaces.
int _nameId(String prefix, String name) => Object.hash(prefix, name);

/// Sentinel ids for the trailing "no value" buckets. Negative, so they can
/// never collide with a real category / status / track-status id.
const int _kNoTagId = -101;
const int _kNoLanguageId = -102;

List<GroupedTab> _groupByTag(List<MangaProxy> all) {
  // Fan-out: a manga with N distinct tags appears in all N buckets. Matched
  // case-insensitively (like the `tag:` filter), displayed as first seen.
  final Map<String, ({String display, List<int> mangaIds})> buckets = {};
  final List<int> untagged = [];

  for (final m in all) {
    final seen = <String>{};
    for (final raw in m.tags) {
      final tag = raw.trim();
      if (tag.isEmpty) continue;
      final key = tag.toLowerCase();
      // De-dup within one manga: a genre that's also a user tag is one bucket.
      if (!seen.add(key)) continue;
      buckets.putIfAbsent(key, () => (display: tag, mangaIds: [])).mangaIds
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
    // Trailing, like BY_TRACK_STATUS's "Other".
    if (untagged.isNotEmpty)
      (id: _kNoTagId, name: 'Untagged', mangaIds: untagged),
  ];
}

List<GroupedTab> _groupByLanguage(List<MangaProxy> all) {
  // Local-source entries have no real language, so they get their own trailing
  // bucket rather than a bogus flag.
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

  // Sort by DISPLAY name, not ISO code: "German" before "Japanese", not de/ja.
  final sorted = buckets.entries.toList()
    ..sort((a, b) => languageDisplayName(a.key)
        .toLowerCase()
        .compareTo(languageDisplayName(b.key).toLowerCase()));

  return [
    for (final e in sorted)
      (
        id: _nameId('lang', e.key),
        name: [languageFlagEmoji(e.key), languageDisplayName(e.key)]
            .whereType<String>()
            .join(' '),
        mangaIds: e.value,
      ),
    if (unknown.isNotEmpty)
      (id: _kNoLanguageId, name: 'Local source', mangaIds: unknown),
  ];
}

List<GroupedTab> _groupByTrackStatus(List<MangaProxy> all) {
  // Fan-out: a manga with N distinct track statuses appears in all N tabs.
  // Manga with no track records go to the "Other" bucket (id 99).
  final Map<int, List<int>> buckets = {};

  for (final m in all) {
    if (m.trackStatuses.isEmpty) {
      buckets.putIfAbsent(99, () => []).add(m.id);
    } else {
      // De-dup: a manga tracked on two services with the same status should
      // only appear once per status bucket.
      final distinctStatuses = m.trackStatuses.toSet();
      for (final st in distinctStatuses) {
        buckets.putIfAbsent(st, () => []).add(m.id);
      }
    }
  }

  // Sort buckets: known statuses by kTrackStatusInfo order, then Other (99) last.
  final sorted = buckets.entries.toList()
    ..sort((a, b) => trackStatusOrder(a.key).compareTo(trackStatusOrder(b.key)));

  return sorted
      .map((e) => (
            id: e.key,
            name: trackStatusLabel(e.key),
            mangaIds: e.value,
          ))
      .toList();
}

// ─────────────────── providers ───────────────────────────────────────────────

/// Persisted group-type preference (0 = BY_DEFAULT).
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

/// The section at the top of the viewport in Section-Headers mode, so the app
/// bar can name it. Not persisted — a live scroll readout, written only by
/// [LibrarySectionsView] and never read back to move the scroll position.
@riverpod
class LibraryVisibleSection extends _$LibraryVisibleSection
    with StateProviderMixin<int?> {
  @override
  int? build() => null;
}

/// The full grouped tab list, combining the library manga list + group type +
/// visible categories into a list of [GroupedTab]s ready for the tab bar.
@riverpod
Future<List<GroupedTab>> libraryGroupedTabs(Ref ref) async {
  // IMPORTANT: do every `ref.watch` BEFORE the first `await`. Watching a
  // provider *after* an await drops its subscription during the async gap on
  // each rebuild; an autoDispose dep with no other listener (here
  // CategoryController) then gets disposed and recreated, re-emits
  // loading→data, and re-triggers this provider — an infinite rebuild flicker.
  final groupType =
      ref.watch(libraryGroupTypeProvider) ?? kDefaultLibraryGroupType;
  // Categories are only needed for BY_DEFAULT (which is actually served by the
  // separate _DefaultLibraryScreen, not this provider). For the grouped modes,
  // don't watch the category provider at all — it just couples them into the
  // loop above and isn't used.
  final List<CategoryProxy> catProxies = groupType == LibraryGroup.byDefault
      ? (ref.watch(visibleCategoryListProvider).value ?? const [])
          .map(categoryToProxy)
          .toList()
      : const [];
  final allFuture = ref.watch(libraryMangaListProvider.future);

  final all = await allFuture;
  if (all == null) return const [];

  final proxies = all.map(mangaToProxy).toList();
  return groupLibrary(proxies, groupType, catProxies);
}
