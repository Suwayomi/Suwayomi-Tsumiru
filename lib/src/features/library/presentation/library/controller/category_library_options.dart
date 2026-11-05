import 'dart:convert';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../constants/db_keys.dart';
import '../../../../../constants/enum.dart';
import '../../../../../utils/misc/app_utils.dart';
import '../../../../../utils/misc/toast/toast.dart';
import '../../../../../utils/mixin/shared_preferences_client_mixin.dart';
import '../../../../../utils/webui_meta/webui_meta_codec.dart';
import '../../../data/category_repository.dart';
import '../../../domain/library_group.dart';
import '../../category/controller/edit_category_controller.dart';
import 'library_controller.dart';
import 'library_grouping.dart';
import 'library_manga_list.dart';

part 'category_library_options.g.dart';

const categorySortModes = {
  MangaSort.alphabetical: 'alphabetically',
  MangaSort.unread: 'unreadChapters',
  MangaSort.dateAdded: 'dateAdded',
  MangaSort.lastUpdated: 'latestFetchedChapter',
  MangaSort.lastChapterDate: 'latestUploadedChapter',
  MangaSort.totalChapters: 'totalChapters',
  MangaSort.lastRead: 'lastRead',
  MangaSort.random: 'random',
};

class CategoryLibraryOptions {
  CategoryLibraryOptions({
    this.sort,
    this.ascending,
    this.unread,
    this.started,
    this.downloaded,
    this.bookmarked,
    this.duplicate,
    Map<String, bool?>? status,
    Map<String, bool?>? source,
    Map<int, bool?>? trackers,
    this.trackerMode,
  }) : status = status == null ? null : Map.unmodifiable(status),
       source = source == null ? null : Map.unmodifiable(source),
       trackers = trackers == null ? null : Map.unmodifiable(trackers);

  final MangaSort? sort;
  final bool? ascending;
  final bool? unread;
  final bool? started;
  final bool? downloaded;
  final bool? bookmarked;
  final bool? duplicate;
  final Map<String, bool?>? status;
  final Map<String, bool?>? source;
  final Map<int, bool?>? trackers;
  final String? trackerMode;

  factory CategoryLibraryOptions.fromMeta(Map<String, String> meta) {
    Object? decode(String key) {
      try {
        final raw = readWebUiValue(meta, key);
        return raw == null ? null : jsonDecode(raw);
      } on FormatException {
        return null;
      }
    }

    bool? boolean(String key) => switch (readWebUiValue(meta, key)) {
      null || 'null' || 'undefined' => null,
      final value => decodeWebUiBool(value),
    };
    Map<String, bool?>? filterMap(Object? value) {
      if (value is! Map<String, dynamic> ||
          value.values.any((v) => v != null && v is! bool)) {
        return null;
      }
      return value.cast<String, bool?>();
    }

    final binding = decode('hasTrackerBinding');
    final filters = binding is Map<String, dynamic>
        ? filterMap(binding['filters'])
        : null;
    final validBinding =
        binding is Map<String, dynamic> &&
        filters != null &&
        filters.keys.every((key) => int.tryParse(key) != null) &&
        (binding['mode'] == null ||
            binding['mode'] == 'OR' ||
            binding['mode'] == 'AND');
    final rawSort = readWebUiValue(meta, 'sortBy');
    final direction = boolean('sortDesc');
    return CategoryLibraryOptions(
      sort: categorySortModes.entries
          .where((entry) => entry.value == rawSort)
          .firstOrNull
          ?.key,
      ascending: direction == null ? null : !direction,
      unread: boolean('hasUnreadChapters'),
      started: boolean('hasReadChapters'),
      downloaded: boolean('hasDownloadedChapters'),
      bookmarked: boolean('hasBookmarkedChapters'),
      duplicate: boolean('hasDuplicateChapters'),
      status: filterMap(decode('hasStatus')),
      source: filterMap(decode('hasSource')),
      trackers: validBinding
          ? {for (final e in filters.entries) int.parse(e.key): e.value}
          : null,
      trackerMode: validBinding ? binding['mode'] as String? ?? 'OR' : null,
    );
  }

  CategoryLibraryOptions fallbackTo(
    CategoryLibraryOptions global, {
    Set<String>? sourceIds,
  }) => CategoryLibraryOptions(
    sort: sort ?? global.sort,
    ascending: ascending ?? global.ascending,
    unread: unread,
    started: started,
    downloaded: downloaded,
    bookmarked: bookmarked,
    duplicate: duplicate,
    status: status ?? const {},
    source: {
      for (final e in (source ?? const <String, bool?>{}).entries)
        if (sourceIds == null || sourceIds.contains(e.key)) e.key: e.value,
    },
    trackers: trackers ?? const {},
    trackerMode: trackerMode ?? 'OR',
  );

  Map<String, String> toMeta() => {
    'webUI_sortBy': ?categorySortModes[sort],
    if (ascending != null) 'webUI_sortDesc': jsonEncode(!ascending!),
    if (unread != null) 'webUI_hasUnreadChapters': jsonEncode(unread),
    if (started != null) 'webUI_hasReadChapters': jsonEncode(started),
    if (downloaded != null)
      'webUI_hasDownloadedChapters': jsonEncode(downloaded),
    if (bookmarked != null)
      'webUI_hasBookmarkedChapters': jsonEncode(bookmarked),
    if (duplicate != null) 'webUI_hasDuplicateChapters': jsonEncode(duplicate),
    if (status != null) 'webUI_hasStatus': jsonEncode(status),
    if (source != null) 'webUI_hasSource': jsonEncode(source),
    if (trackers != null)
      'webUI_hasTrackerBinding': jsonEncode({
        'filters': {for (final e in trackers!.entries) '${e.key}': e.value},
        'mode': trackerMode ?? 'OR',
      }),
  };

  int get filterCount =>
      [
        unread,
        started,
        downloaded,
        bookmarked,
        duplicate,
      ].where((v) => v != null).length +
      [
        status?.values,
        source?.values,
        trackers?.values,
      ].expand((v) => v ?? const <bool?>[]).where((v) => v != null).length;
}

@riverpod
class LibraryPerCategorySettings extends _$LibraryPerCategorySettings
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.libraryPerCategorySettings);
}

@riverpod
bool useCategoryLibraryOptions(Ref ref) =>
    ref.watch(libraryPerCategorySettingsProvider) == true &&
    (ref.watch(libraryGroupTypeProvider) ?? kDefaultLibraryGroupType) ==
        LibraryGroup.byDefault;

@Riverpod(keepAlive: true)
class LibraryActiveCategory extends _$LibraryActiveCategory {
  @override
  int? build() => null;

  void update(int value) => state = value;
}

@riverpod
int? libraryOptionsCategoryId(Ref ref) {
  if (!ref.watch(useCategoryLibraryOptionsProvider)) return null;
  final sections =
      ref.watch(libraryGroupStyleKeyProvider) == LibraryGroupStyle.headers &&
      ref.watch(sectionHeadersShowAllCategoriesProvider) == true;
  final categories = ref.watch(libraryShownCategoryListProvider).value ?? [];
  final ids = categories
      .map((category) => category.id)
      .where(
        (id) =>
            !sections ||
            (ref
                    .watch(
                      categoryMangaListWithQueryAndFilterProvider(
                        categoryId: id,
                      ),
                    )
                    .value
                    ?.isNotEmpty ??
                false),
      )
      .toList();
  final active = sections
      ? ref.watch(libraryVisibleSectionProvider)
      : ref.watch(libraryActiveCategoryProvider);
  return ids.contains(active) ? active : ids.firstOrNull;
}

@riverpod
class CategoryLibraryMetadata extends _$CategoryLibraryMetadata {
  Future<void> _writes = Future.value();
  final _optimistic = <String, String?>{};
  int _pending = 0;
  bool _hasUnsyncedEdits = false;

  @override
  Map<String, String> build(int categoryId) {
    ref.keepAlive();
    final categories = ref.watch(categoryControllerProvider).value ?? const [];
    final category = categories.where((c) => c.id == categoryId).firstOrNull;
    return {
      for (final meta in category?.meta ?? [])
        if (!_optimistic.containsKey(meta.key)) meta.key: meta.value,
      for (final e in _optimistic.entries)
        if (e.value != null) e.key: e.value!,
    };
  }

  void write(Map<String, String?> values) {
    final repo = ref.read(categoryRepositoryProvider);
    final toast = ref.read(toastProvider);
    final updates = {...values};
    final migration = num.tryParse(readWebUiValue(state, 'migration') ?? '0');
    if (migration == null || migration < 10) {
      final raw = readWebUiValue(state, 'hasTrackerBinding');
      if (!updates.containsKey('hasTrackerBinding') && raw != null) {
        try {
          final binding = jsonDecode(raw);
          if (binding is Map<String, dynamic> &&
              !binding.containsKey('filters') &&
              binding.values.every((v) => v == null || v is bool)) {
            updates['hasTrackerBinding'] = jsonEncode({
              'filters': binding,
              'mode': 'OR',
            });
          }
        } on FormatException {
          updates['hasTrackerBinding'] = null;
        }
      }
    }
    updates['migration'] = migration != null && migration > 10
        ? '$migration'
        : '10';
    final plans = [
      for (final e in updates.entries) planWebUiWrite(state, e.key, e.value),
    ];
    final next = {...state};
    for (final plan in plans) {
      for (final key in plan.delete) {
        _optimistic[key] = null;
        next.remove(key);
      }
      _optimistic.addAll(plan.set);
      next.addAll(plan.set);
    }
    state = next;
    _pending++;
    _writes = _writes.then((_) async {
      final synced = await AppUtils.guard(() async {
        for (final plan in plans) {
          for (final e in plan.set.entries) {
            await repo.setCategoryMeta(
              categoryId: categoryId,
              key: e.key,
              value: e.value,
            );
          }
          for (final key in plan.delete) {
            await repo.deleteCategoryMeta(categoryId: categoryId, key: key);
          }
        }
        return true;
      }, toast);
      if (synced != true) _hasUnsyncedEdits = true;
      if (!ref.mounted || --_pending != 0 || _hasUnsyncedEdits) return;
      await AppUtils.guard(() async {
        ref.invalidate(categoryControllerProvider);
        await ref.read(categoryControllerProvider.future);
        if (ref.mounted && _pending == 0) {
          _optimistic.clear();
          ref.invalidateSelf();
        }
      }, toast);
    });
  }
}

@riverpod
CategoryLibraryOptions effectiveCategoryLibraryOptions(
  Ref ref,
  int? categoryId,
) {
  final global = CategoryLibraryOptions(
    sort: ref.watch(libraryMangaSortProvider) ?? DBKeys.mangaSort.initial,
    ascending: ref.watch(libraryMangaSortDirectionProvider) ?? true,
    unread: ref.watch(libraryMangaFilterUnreadProvider),
    started: ref.watch(libraryMangaFilterStartedProvider),
    downloaded: ref.watch(libraryMangaFilterDownloadedProvider),
    bookmarked: ref.watch(libraryMangaFilterBookmarkedProvider),
    duplicate: ref.watch(libraryDuplicateChaptersProvider),
    status: ref.watch(libraryEntryFiltersProvider('status')),
    source: ref.watch(libraryEntryFiltersProvider('source')),
    trackers: ref.watch(libraryTrackerFiltersProvider),
    trackerMode: 'AND',
  );
  if (categoryId == null || !ref.watch(useCategoryLibraryOptionsProvider)) {
    return global;
  }
  return CategoryLibraryOptions.fromMeta(
    ref.watch(categoryLibraryMetadataProvider(categoryId)),
  ).fallbackTo(
    global,
    sourceIds: (ref.watch(libraryMangaListProvider).value ?? const [])
        .map((manga) => manga.sourceId)
        .toSet(),
  );
}

@riverpod
class ActiveLibraryOptions extends _$ActiveLibraryOptions {
  @override
  CategoryLibraryOptions build() => ref.watch(
    effectiveCategoryLibraryOptionsProvider(
      ref.watch(libraryOptionsCategoryIdProvider),
    ),
  );

  bool _write(String key, CategoryLibraryOptions value) {
    final id = ref.read(libraryOptionsCategoryIdProvider);
    if (id == null) return false;
    ref.read(categoryLibraryMetadataProvider(id).notifier).write({
      key: value.toMeta()[webUiKey(key)],
    });
    return true;
  }

  void sort(MangaSort value) {
    if (!_write('sortBy', CategoryLibraryOptions(sort: value))) {
      ref.read(libraryMangaSortProvider.notifier).update(value);
    }
  }

  void ascending(bool value) {
    if (!_write('sortDesc', CategoryLibraryOptions(ascending: value))) {
      ref.read(libraryMangaSortDirectionProvider.notifier).update(value);
    }
  }

  void entryFilters(String kind, Map<String, bool?> value) {
    if (!_write(
      kind == 'status' ? 'hasStatus' : 'hasSource',
      CategoryLibraryOptions(
        status: kind == 'status' ? value : null,
        source: kind == 'source' ? value : null,
      ),
    )) {
      ref.read(libraryEntryFiltersProvider(kind).notifier).update(value);
    }
  }

  String _categoryTrackerMode() {
    final id = ref.read(libraryOptionsCategoryIdProvider);
    return id == null
        ? 'OR'
        : CategoryLibraryOptions.fromMeta(
                ref.read(categoryLibraryMetadataProvider(id)),
              ).trackerMode ??
              'OR';
  }

  void tracker(int id, bool? value) {
    final filters = {...?state.trackers, id: value};
    if (!_write(
      'hasTrackerBinding',
      CategoryLibraryOptions(
        trackers: filters,
        trackerMode: _categoryTrackerMode(),
      ),
    )) {
      ref
          .read(libraryMangaFilterTrackerProvider(trackerId: id).notifier)
          .update(value);
    }
  }

  void reset() {
    final id = ref.read(libraryOptionsCategoryIdProvider);
    if (id == null) return;
    ref.read(categoryLibraryMetadataProvider(id).notifier).write({
      for (final key in [
        'hasUnreadChapters',
        'hasReadChapters',
        'hasDownloadedChapters',
        'hasBookmarkedChapters',
        'hasDuplicateChapters',
        'hasStatus',
        'hasSource',
        'hasTrackerBinding',
      ])
        key: null,
    });
  }

  void unread(bool? value) {
    if (!_write('hasUnreadChapters', CategoryLibraryOptions(unread: value))) {
      ref.read(libraryMangaFilterUnreadProvider.notifier).update(value);
    }
  }

  void started(bool? value) {
    if (!_write('hasReadChapters', CategoryLibraryOptions(started: value))) {
      ref.read(libraryMangaFilterStartedProvider.notifier).update(value);
    }
  }

  void downloaded(bool? value) {
    if (!_write(
      'hasDownloadedChapters',
      CategoryLibraryOptions(downloaded: value),
    )) {
      ref.read(libraryMangaFilterDownloadedProvider.notifier).update(value);
    }
  }

  void bookmarked(bool? value) {
    if (!_write(
      'hasBookmarkedChapters',
      CategoryLibraryOptions(bookmarked: value),
    )) {
      ref.read(libraryMangaFilterBookmarkedProvider.notifier).update(value);
    }
  }

  void duplicate(bool? value) {
    if (!_write(
      'hasDuplicateChapters',
      CategoryLibraryOptions(duplicate: value),
    )) {
      ref.read(libraryDuplicateChaptersProvider.notifier).update(value);
    }
  }
}
