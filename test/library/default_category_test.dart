import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/account/data/account_providers.dart';
import 'package:tsumiru/src/features/account/domain/account_access.dart';
import 'package:tsumiru/src/features/library/data/category_repository.dart';
import 'package:tsumiru/src/features/library/data/default_category.dart';
import 'package:tsumiru/src/features/library/domain/category/category_model.dart';
import 'package:tsumiru/src/features/library/domain/category/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/library/domain/library_group.dart';
import 'package:tsumiru/src/features/library/presentation/category/controller/edit_category_controller.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_controller.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_grouping.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_manga_list.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/features/offline/data/server_reachability.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';

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
  test('access refreshes do not reload the default category', () async {
    var pending = Completer<AccountAccess>();
    final link = CategoryLink();
    final container = ProviderContainer(
      overrides: [
        libraryMangaListProvider.overrideWith((ref) async => []),
        authTypeKeyProvider.overrideWithValue(AuthType.uiLogin),
        accountAccessProvider.overrideWith((ref) => pending.future),
        viewOfflineNowProvider.overrideWithValue(false),
        serverUnreachableProvider.overrideWithValue(false),
        offlineReadDatabaseProvider.overrideWithValue(null),
        categoryRepositoryProvider.overrideWithValue(
          CategoryRepository(GraphQLClient(link: link, cache: GraphQLCache())),
        ),
      ],
    );
    addTearDown(container.dispose);
    final states = <AsyncValue<int?>>[];
    container.listen(defaultCategoryIdProvider, (_, next) => states.add(next));
    container.listen(categoryMangaListProvider(81), (_, _) {});
    pending.complete(AccountAccess(capability: AccountCapability.supported));
    expect(await container.read(defaultCategoryIdProvider.future), 81);
    await container.read(categoryMangaListProvider(81).future);
    states.clear();
    for (var i = 0; i < 5; i++) {
      pending = Completer<AccountAccess>();
      container.invalidate(accountAccessProvider);
      await container.pump();
      expect(container.read(defaultCategoryIdProvider).isLoading, isFalse);
      expect(container.read(categoryMangaListProvider(81)).isLoading, isFalse);
      pending.complete(AccountAccess(capability: AccountCapability.supported));
      await container.read(accountAccessProvider.future);
      await container.pump();
    }
    expect(states, isEmpty);
    expect(link.cursors, [null, 3]);
    pending = Completer<AccountAccess>();
    container.invalidate(accountAccessProvider);
    pending.complete(AccountAccess(capability: AccountCapability.unknown));
    await container.read(accountAccessProvider.future);
    await container.pump();
    expect(await container.read(defaultCategoryIdProvider.future), isNull);
  });
  for (final defaultId in [0, 81]) {
    for (final hidden in [false, true]) {
      test('empty default $defaultId respects hidden=$hidden', () async {
        final container = ProviderContainer(
          overrides: [
            categoryControllerProvider.overrideWith(
              () => _CategoryList([
                Fragment$CategoryDto(
                  id: defaultId,
                  name: 'Default',
                  order: 0,
                  defaultCategory: false,
                  includeInDownload: Enum$IncludeOrExclude.UNSET,
                  includeInUpdate: Enum$IncludeOrExclude.UNSET,
                  mangas: Fragment$CategoryDto$mangas(totalCount: 0),
                  meta: hidden
                      ? [
                          Fragment$CategoryDto$meta(
                            key: kCategoryHiddenMetaKey,
                            value: 'true',
                          ),
                        ]
                      : [],
                ),
              ]),
            ),
            settledDefaultCategoryIdProvider.overrideWithValue(defaultId),
            showHiddenCategoriesProvider.overrideWith(_HideCategories.new),
            viewOfflineNowProvider.overrideWithValue(false),
            serverUnreachableProvider.overrideWithValue(false),
          ],
        );
        addTearDown(container.dispose);
        final subscription = container.listen(
          visibleCategoryListProvider,
          (_, _) {},
        );
        addTearDown(subscription.close);
        await container.read(categoryControllerProvider.future);
        expect(
          container
              .read(visibleCategoryListProvider)
              .requireValue!
              .map((c) => c.id),
          hidden ? [] : [defaultId],
        );
      });
    }
  }
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

  test('default identity can appear after the first page', () async {
    final link = CategoryLink();
    final repository = CategoryRepository(
      GraphQLClient(link: link, cache: GraphQLCache()),
    );
    expect(await repository.getDefaultCategoryId(), 81);
    expect(link.cursors, [null, 3]);
  });
  test('nonzero default groups explicit and uncategorized membership once', () {
    MangaProxy manga(int id, List<int> categories) => (
      id: id,
      sourceId: '',
      sourceName: '',
      sourceLang: '',
      status: '',
      categoryIds: categories,
      trackStatuses: [],
      tags: [],
    );
    final result = groupLibrary(
      [
        manga(1, []),
        manga(2, [81]),
        manga(3, [3]),
      ],
      LibraryGroup.byDefault,
      [(id: 81, name: 'Default'), (id: 3, name: 'Auto add')],
      defaultCategoryId: 81,
    );
    expect(result.map((tab) => tab.id), [81, 3]);
    expect(result.first.mangaIds, [1, 2]);
    expect(result.last.mangaIds, [3]);
  });
}

class _EmptyCategories extends CategoryController {
  @override
  Future<Never> build() async => throw UnimplementedError();
}

class _CategoryList extends CategoryController {
  _CategoryList(this.categories);
  final List<CategoryDto> categories;
  @override
  Future<List<CategoryDto>?> build() async => categories;
}

class _HideCategories extends ShowHiddenCategories {
  @override
  bool? build() => false;
}
