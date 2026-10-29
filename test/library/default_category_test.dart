import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/account/data/account_providers.dart';
import 'package:tsumiru/src/features/account/domain/account_access.dart';
import 'package:tsumiru/src/features/library/data/category_repository.dart';
import 'package:tsumiru/src/features/library/data/default_category.dart';
import 'package:tsumiru/src/features/library/domain/category/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/library/presentation/category/controller/edit_category_controller.dart';
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

Fragment$CategoryDto _category(
  int id,
  String name, {
  bool defaultCategory = false,
}) => Fragment$CategoryDto(
  defaultCategory: defaultCategory,
  id: id,
  includeInDownload: Enum$IncludeOrExclude.UNSET,
  includeInUpdate: Enum$IncludeOrExclude.UNSET,
  name: name,
  order: id,
  mangas: Fragment$CategoryDto$mangas(totalCount: 0),
  meta: const [],
);
