import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/account/data/account_providers.dart';
import 'package:tsumiru/src/features/account/domain/account_access.dart';
import 'package:tsumiru/src/features/library/data/category_repository.dart';
import 'package:tsumiru/src/features/library/data/default_category.dart';
import 'package:tsumiru/src/features/library/domain/category/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/library/presentation/category/controller/edit_category_controller.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/category_library_options.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_controller.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_manga_list.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/features/offline/data/server_reachability.dart';
import 'package:tsumiru/src/features/tracking/data/tracker_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/utils/webui_meta/webui_settings.dart';

class CategoryLink extends Link {
  final cursors = <Object?>[];
  @override
  Stream<Response> request(Request request, [NextLink? forward]) async* {
    final after = request.variables['after'];
    cursors.add(after);
    yield Response(
      response: {},
      data: {
        '__typename': 'Query',
        'categories': {
          '__typename': 'CategoryNodeList',
          'nodes': [
            {
              '__typename': 'CategoryType',
              'id': after == null ? 3 : 81,
              'isDefaultCategory': after != null,
            },
          ],
          'pageInfo': {
            '__typename': 'PageInfo',
            'endCursor': after == null ? '3' : '81',
            'startCursor': after == null ? '3' : '81',
            'hasNextPage': after == null,
            'hasPreviousPage': after != null,
          },
        },
      },
    );
  }
}

void main() {
  for (final capability in AccountCapability.values) {
    test('default identity respects $capability', () async {
      final link = CategoryLink();
      final container = ProviderContainer(
        overrides: [
          authTypeKeyProvider.overrideWithValue(AuthType.uiLogin),
          accountAccessProvider.overrideWith(
            (ref) async => AccountAccess(capability: capability),
          ),
          viewOfflineNowProvider.overrideWithValue(false),
          serverUnreachableProvider.overrideWithValue(false),
          offlineReadDatabaseProvider.overrideWithValue(null),
          categoryRepositoryProvider.overrideWithValue(
            CategoryRepository(
              GraphQLClient(link: link, cache: GraphQLCache()),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      expect(
        await container.read(defaultCategoryIdProvider.future),
        switch (capability) {
          AccountCapability.supported => 81,
          AccountCapability.unsupported => 0,
          AccountCapability.unknown => null,
        },
      );
      if (capability != AccountCapability.supported) {
        expect(link.cursors, isEmpty);
      }
    });
  }
  for (final defaultId in <int?>[81, null]) {
    test('protected or unknown default rejects category mutation', () async {
      final link = CategoryLink();
      final container = ProviderContainer(
        overrides: [
          settledDefaultCategoryIdProvider.overrideWithValue(defaultId),
          categoryControllerProvider.overrideWith(_EmptyCategories.new),
          categoryRepositoryProvider.overrideWithValue(
            CategoryRepository(
              GraphQLClient(link: link, cache: GraphQLCache()),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(categoryControllerProvider.notifier);
      expect(await controller.deleteCategory(81), isA<AsyncError<void>>());
      expect(await controller.reorderCategory(81, 2), isA<AsyncError<void>>());
      expect(link.cursors, isEmpty);
    });
  }

  test('unknown default keeps the empty Default category', () async {
    final container = ProviderContainer(
      overrides: [
        defaultCategoryIdProvider.overrideWith(
          (ref) => Future<int?>.error(StateError('session expired')),
        ),
        viewOfflineNowProvider.overrideWithValue(false),
        serverUnreachableProvider.overrideWithValue(false),
        categoryControllerProvider.overrideWith(_Categories.new),
      ],
    );
    addTearDown(container.dispose);
    await expectLater(
      container.read(defaultCategoryIdProvider.future),
      throwsA(isA<StateError>()),
    );
    await container.read(categoryControllerProvider.future);
    expect(
      container
          .read(nonZeroCategoryListProvider)
          .value
          ?.map((category) => category.id),
      [1, 2],
    );
  });

  test('filtering hides categories with no matching series', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        defaultCategoryIdProvider.overrideWith((ref) async => 1),
        settledDefaultCategoryIdProvider.overrideWithValue(1),
        viewOfflineNowProvider.overrideWithValue(false),
        serverUnreachableProvider.overrideWithValue(false),
        offlineReadDatabaseProvider.overrideWithValue(null),
        loggedInTrackersProvider.overrideWithValue(const AsyncData([])),
        libraryTrackerNamesProvider.overrideWithValue(const {}),
        webUiBoolProvider('ignoreFilters').overrideWithValue(false),
        webUiBoolProvider('fuzzySearch').overrideWithValue(false),
        libraryQueryDebouncedProvider.overrideWith(
          _ImmediateQueryDebounced.new,
        ),
        categoryControllerProvider.overrideWith(_FilterCategories.new),
        libraryMangaListProvider.overrideWith(
          (ref) async => [
            _filterManga(1, unread: 1, categories: [1]),
            _filterManga(2, unread: 0, categories: [2]),
          ],
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(libraryShownCategoryListProvider, (_, _) {});
    container.listen(
      categoryMangaListWithQueryAndFilterProvider(categoryId: 1),
      (_, _) {},
    );
    container.listen(
      categoryMangaListWithQueryAndFilterProvider(categoryId: 2),
      (_, _) {},
    );
    await container.read(categoryControllerProvider.future);
    await container.read(categoryMangaListProvider(1).future);
    await container.read(categoryMangaListProvider(2).future);

    List<int?> shown() => container
        .read(libraryShownCategoryListProvider)
        .value!
        .map((category) => category.id)
        .toList();

    expect(shown(), [1, 2]);

    container.read(libraryMangaFilterUnreadProvider.notifier).update(true);
    expect(shown(), [1]);

    container.read(showEmptyCategoriesSearchProvider.notifier).update(true);
    expect(shown(), [1, 2]);

    container.read(showEmptyCategoriesSearchProvider.notifier).update(false);
    container.read(libraryMangaFilterUnreadProvider.notifier).update(null);
    container
        .read(libraryEntryFiltersProvider('status').notifier)
        .update(const {'ONGOING': false});
    expect(shown(), [1]);

    container
        .read(libraryEntryFiltersProvider('status').notifier)
        .update(const {});
    container.read(libraryQueryProvider.notifier).update('zzz');
    expect(shown(), [1]);

    container.read(libraryQueryProvider.notifier).update(null);
    container.read(libraryPerCategorySettingsProvider.notifier).update(true);
    container.read(libraryActiveCategoryProvider.notifier).update(2);
    container.read(libraryActiveCategoryProvider.notifier).update(1);
    expect(shown(), [1, 2]);
    container.read(libraryQueryProvider.notifier).update('Manga');
    expect(shown(), [1]);
    container.read(libraryActiveCategoryProvider.notifier).update(2);
    expect(shown(), [1, 2]);
  });
}

class _EmptyCategories extends CategoryController {
  @override
  Future<Never> build() async => throw UnimplementedError();
}

class _Categories extends CategoryController {
  @override
  Future<List<Fragment$CategoryDto>?> build() async => [
    _category(1, 'Default', defaultCategory: true),
    _category(2, 'Empty'),
  ];
}

class _ImmediateQueryDebounced extends LibraryQueryDebounced {
  @override
  String? build() => ref.watch(libraryQueryProvider);
}

class _FilterCategories extends CategoryController {
  @override
  Future<List<Fragment$CategoryDto>?> build() async => [
    _category(1, 'Default', defaultCategory: true, totalCount: 1),
    _category(
      2,
      'Other',
      totalCount: 1,
      meta: [
        Fragment$CategoryDto$meta(
          key: 'webUI_hasUnreadChapters',
          value: 'true',
        ),
      ],
    ),
  ];
}

Fragment$CategoryDto _category(
  int id,
  String name, {
  bool defaultCategory = false,
  int totalCount = 0,
  List<Fragment$CategoryDto$meta> meta = const [],
}) => Fragment$CategoryDto(
  defaultCategory: defaultCategory,
  id: id,
  includeInDownload: Enum$IncludeOrExclude.UNSET,
  includeInUpdate: Enum$IncludeOrExclude.UNSET,
  name: name,
  order: id,
  mangas: Fragment$CategoryDto$mangas(totalCount: totalCount),
  meta: meta,
);

Fragment$MangaDto _filterManga(
  int id, {
  required int unread,
  required List<int> categories,
}) => Fragment$MangaDto(
  id: id,
  title: 'Manga $id',
  chapters: Fragment$MangaDto$chapters(totalCount: 0),
  genre: const [],
  initialized: true,
  meta: const [],
  source: Fragment$MangaDto$source(
    displayName: 'Test Source',
    iconUrl: '',
    id: '1',
    contentWarning: Enum$ContentWarning.SAFE,
    lang: 'en',
    name: 'Test Source',
    $extension: Fragment$MangaDto$source$extension(isObsolete: false),
  ),
  sourceId: '1',
  status: Enum$MangaStatus.ONGOING,
  categories: Fragment$MangaDto$categories(
    nodes: [
      for (final categoryId in categories)
        Fragment$MangaDto$categories$nodes(id: categoryId),
    ],
  ),
  trackRecords: Fragment$MangaDto$trackRecords(nodes: const []),
  updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
  url: 'https://example.com/manga/$id',
  user: Fragment$MangaDto$user(
    bookmarkCount: 0,
    downloadCount: 0,
    inLibrary: true,
    inLibraryAt: '0',
    unreadCount: unread,
  ),
);
