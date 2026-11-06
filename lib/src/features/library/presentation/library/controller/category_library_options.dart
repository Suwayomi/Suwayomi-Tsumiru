import 'dart:convert';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../constants/db_keys.dart';
import '../../../../../constants/enum.dart';
import '../../../../../utils/logger/logger.dart';
import '../../../../../utils/misc/app_utils.dart';
import '../../../../../utils/misc/toast/toast.dart';
import '../../../../../utils/mixin/shared_preferences_client_mixin.dart';
import '../../../../../utils/webui_meta/webui_meta_codec.dart';
import '../../../../offline/data/offline_database.dart';
import '../../../../offline/data/offline_repository.dart';
import '../../../../offline/data/offline_runtime_storage.dart';
import '../../../data/category_repository.dart';
import '../../../data/default_category.dart';
import '../../../domain/category/category_model.dart';
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

const categoryFilterKeys = [
  'hasUnreadChapters',
  'hasReadChapters',
  'hasDownloadedChapters',
  'hasBookmarkedChapters',
  'hasDuplicateChapters',
  'hasStatus',
  'hasSource',
  'hasTrackerBinding',
];

final _categoryMetaKey = RegExp(
  '^webUI_(sortBy|sortDesc|migration|${categoryFilterKeys.join('|')})'
  r'(_(length|[0-9]+))?$',
);

bool isCategoryLibraryMetaKey(String key) => _categoryMetaKey.hasMatch(key);

String categoryLibraryMetaJson(CategoryDto category) => jsonEncode({
  for (final meta in category.meta)
    if (isCategoryLibraryMetaKey(meta.key)) meta.key: meta.value,
});

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
    final nested = binding is Map<String, dynamic> &&
        binding.containsKey('filters');
    final filters = binding is Map<String, dynamic>
        ? filterMap(nested ? binding['filters'] : binding)
        : null;
    final mode = nested ? binding['mode'] : 'OR';
    final validBinding =
        filters != null &&
        filters.keys.every((key) => int.tryParse(key) != null) &&
        (mode == null || mode == 'OR' || mode == 'AND');
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
      trackerMode: validBinding ? mode as String? ?? 'OR' : null,
    );
  }

  CategoryLibraryOptions resolveWith(
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

bool libraryShowsAllCategorySections(Ref ref) =>
    ref.watch(libraryGroupStyleKeyProvider) == LibraryGroupStyle.headers &&
    ref.watch(sectionHeadersShowAllCategoriesProvider) == true;

@riverpod
int? libraryOptionsCategoryId(Ref ref) {
  if (!ref.watch(useCategoryLibraryOptionsProvider)) return null;
  final sections = libraryShowsAllCategorySections(ref);
  final categories = ref.watch(libraryShownCategoryListProvider).value ?? [];
  final ids = categories.map((category) => category.id).toList();
  final active = sections
      ? ref.watch(libraryVisibleSectionProvider)
      : ref.watch(libraryActiveCategoryProvider);
  return ids.contains(active) ? active : ids.firstOrNull;
}

@Riverpod(keepAlive: true)
CategoryMetaSync categoryMetaSync(Ref ref) => CategoryMetaSync();

class CategoryMetaSync {
  Future<void> _tail = Future.value();

  /// Sends [values], or the category's queued offline edits, after every earlier send.
  Future<Map<String, String?>> send(
    CategoryRepository repo,
    OfflineDatabase? db,
    int categoryId, [
    Map<String, String?>? values,
  ]) {
    final result = _tail.then((_) async {
      final sent =
          values ??
          decodePendingWebUiMeta(
            (await db?.categoryById(categoryId))?.pendingWebUiMetaJson,
          );
      if (sent.isEmpty) return sent;
      await repo.setCategoryMetas(categoryId, sent);
      await db?.clearPendingCategoryMetaIfUnchanged(categoryId, sent);
      return sent;
    });
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }
}

@riverpod
class CategoryLibraryMetadata extends _$CategoryLibraryMetadata {
  Future<void> _writes = Future.value();
  final _optimistic = <String, String?>{};
  int _pending = 0;
  bool _synced = false;
  Future<void>? _loadPending;
  Map<String, String?> _storedPending = {};
  Object? _storage;
  int _generation = 0;

  @override
  Map<String, String> build(int categoryId) {
    ref.keepAlive();
    final storage = ref.watch(offlineRuntimeStorageProvider);
    if (!identical(storage, _storage)) {
      _storage = storage;
      _generation++;
      _optimistic.clear();
      _pending = 0;
      _synced = false;
      _loadPending = null;
      _storedPending = {};
    }
    final generation = _generation;
    final categories = ref.watch(categoryControllerProvider).value ?? const [];
    final category = categories.where((c) => c.id == categoryId).firstOrNull;
    if (storage != null && ref.watch(offlineActiveProvider)) {
      _loadPending ??= storage.db
          .categoryById(categoryId)
          .then((row) {
            if (!ref.mounted || generation != _generation) return;
            _storedPending = decodePendingWebUiMeta(row?.pendingWebUiMetaJson);
            ref.invalidateSelf();
          });
    }
    final metaWithPending = applyPendingWebUiMeta({
      for (final meta in category?.meta ?? []) meta.key: meta.value,
    }, _storedPending);
    return {
      for (final meta in metaWithPending.entries)
        if (!_optimistic.containsKey(meta.key)) meta.key: meta.value,
      for (final e in _optimistic.entries)
        if (e.value != null) e.key: e.value!,
    };
  }

  Future<void> clearSyncedMeta(Map<String, String?> values) async {
    await _loadPending;
    if (!ref.mounted) return;
    for (final e in values.entries) {
      if (_storedPending.containsKey(e.key) &&
          _storedPending[e.key] == e.value) {
        _storedPending.remove(e.key);
      }
      if (_optimistic.containsKey(e.key) && _optimistic[e.key] == e.value) {
        _optimistic.remove(e.key);
      }
    }
    ref.invalidateSelf();
  }

  void write(Map<String, String?> values) {
    final repo = ref.read(categoryRepositoryProvider);
    final sync = ref.read(categoryMetaSyncProvider);
    final toast = ref.read(toastProvider);
    final generation = _generation;
    final updates = {...values};
    final migration = num.tryParse(readWebUiValue(state, 'migration') ?? '0');
    // WebUI migration 10 moved hasTrackerBinding under {filters, mode}.
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
      updates['migration'] = '10';
    }
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
    final db = ref.read(offlineActiveProvider)
        ? ref.read(offlineRuntimeStorageProvider)?.db
        : null;
    final category = (ref.read(categoryControllerProvider).value ?? const [])
        .where((c) => c.id == categoryId)
        .firstOrNull;
    final defaultId = ref.read(settledDefaultCategoryIdProvider);
    final stored = <String, String?>{
      for (final plan in plans) ...{
        for (final key in plan.delete) key: null,
        ...plan.set,
      },
    };
    final persisted = db == null
        ? Future<bool>.value(false)
        : db
              .transaction(() async {
                if (await db.categoryById(categoryId) == null &&
                    category != null) {
                  await db.upsertCategory(
                    categoryId,
                    category.name,
                    category.order,
                    isHidden: category.isHidden,
                    isDefaultCategory: defaultId == null
                        ? null
                        : defaultId == categoryId,
                    autoAdd: category.defaultCategory,
                    webUiMetaJson: categoryLibraryMetaJson(category),
                  );
                }
                await db.mergePendingCategoryMeta(categoryId, stored);
                return true;
              })
              .catchError((Object error, StackTrace stackTrace) {
                logger.e(
                  'Offline: could not save category meta for $categoryId',
                  error: error,
                  stackTrace: stackTrace,
                );
                return false;
              });
    _pending++;
    _writes = _writes.then((_) async {
      final saved = await persisted;
      final synced =
          await AppUtils.guard(
            () => sync.send(repo, db, categoryId, stored),
            saved ? null : toast,
          ) !=
          null;
      if (!ref.mounted || generation != _generation) return;
      if (synced) {
        _synced = true;
      } else if (saved) {
        logger.w(
          'Offline: category meta push failed for $categoryId; saved for retry',
        );
      } else {
        for (final e in stored.entries) {
          if (_optimistic.containsKey(e.key) && _optimistic[e.key] == e.value) {
            _optimistic.remove(e.key);
          }
        }
        ref.invalidateSelf();
      }
      if (--_pending != 0) return;
      if (db != null) {
        final row = await AppUtils.guard(
          () => db.categoryById(categoryId),
          null,
        );
        if (!ref.mounted || generation != _generation || _pending != 0) return;
        _storedPending = decodePendingWebUiMeta(row?.pendingWebUiMetaJson);
      }
      if (_synced) {
        _synced = false;
        final refetched = await AppUtils.guard(() async {
          ref.invalidate(categoryControllerProvider);
          await ref.read(categoryControllerProvider.future);
          return true;
        }, toast);
        if (refetched == null) {
          if (ref.mounted && generation == _generation) _synced = true;
          return;
        }
      }
      if (ref.mounted && generation == _generation && _pending == 0) {
        _optimistic.clear();
        ref.invalidateSelf();
      }
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
  ).resolveWith(
    global,
    sourceIds: ref
        .watch(libraryMangaListProvider)
        .value
        ?.map((manga) => manga.sourceId)
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

  void entryFilter(String kind, String key, bool? value) {
    final id = ref.read(libraryOptionsCategoryIdProvider);
    if (id == null) {
      ref.read(libraryEntryFiltersProvider(kind).notifier).update({
        ...ref.read(libraryEntryFiltersProvider(kind)),
        key: value,
      });
      return;
    }
    final stored = CategoryLibraryOptions.fromMeta(
      ref.read(categoryLibraryMetadataProvider(id)),
    );
    final filters = {
      ...?(kind == 'status' ? stored.status : stored.source),
      key: value,
    };
    _write(
      kind == 'status' ? 'hasStatus' : 'hasSource',
      CategoryLibraryOptions(
        status: kind == 'status' ? filters : null,
        source: kind == 'source' ? filters : null,
      ),
    );
  }

  void tracker(int id, bool? value) {
    final filters = {...?state.trackers, id: value};
    if (!_write(
      'hasTrackerBinding',
      CategoryLibraryOptions(
        trackers: filters,
        trackerMode: state.trackerMode,
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
      for (final key in categoryFilterKeys) key: null,
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
