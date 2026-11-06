// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/library/data/category_repository.dart';
import 'package:tsumiru/src/features/library/domain/category/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/library/presentation/category/controller/edit_category_controller.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/category_library_options.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_controller.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_grouping.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_manga_list.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/tracking/data/tracker_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';

MangaDto _manga(int id, {required String title, int unreadCount = 0}) =>
    Fragment$MangaDto(
      id: id,
      title: title,
      chapters: Fragment$MangaDto$chapters(totalCount: 5),
      genre: const [],
      initialized: true,
      meta: const [],
      sourceId: '1',
      status: Enum$MangaStatus.ONGOING,
      categories: Fragment$MangaDto$categories(nodes: const []),
      trackRecords: Fragment$MangaDto$trackRecords(nodes: const []),
      updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
      url: '/manga/$id',
      user: Fragment$MangaDto$user(
        bookmarkCount: 0,
        downloadCount: 0,
        inLibrary: true,
        inLibraryAt: '0',
        unreadCount: unreadCount,
      ),
    );

List<int> _sorted(
  List<MangaDto> input, {
  required MangaSort by,
  required bool ascending,
  bool pinZeroUnreadLast = true,
}) => applyLibraryFilterSort(
  input,
  query: null,
  mangaFilterUnread: null,
  mangaFilterDownloaded: null,
  mangaFilterCompleted: null,
  mangaFilterStarted: null,
  mangaFilterBookmarked: null,
  mangaFilterOffline: null,
  offlineMangaIds: const {},
  mangaFilterLewd: null,
  mangaFilterMinRating: 0,
  filterCategories: false,
  filterCategoriesInclude: const {},
  filterCategoriesExclude: const {},
  filterTags: false,
  filterTagsInclude: const {},
  filterTagsExclude: const {},
  sortedBy: by,
  sortedDirection: ascending,
  pinZeroUnreadLast: pinZeroUnreadLast,
).map((m) => m.id).toList();

void main() {
  test(
    'category WebUI options override globals and edits keep WebUI keys',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({
        'libraryPerCategorySettings': true,
        'mangaFilterDownloaded': true,
      });
      final repository = _MetaRepository();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
          categoryControllerProvider.overrideWith(
            () => _MetaCategories(repository),
          ),
          categoryRepositoryProvider.overrideWithValue(repository),
          libraryShownCategoryListProvider.overrideWith(
            (ref) => ref.watch(categoryControllerProvider),
          ),
          libraryMangaListProvider.overrideWith(
            (ref) async => [_manga(1, title: 'A')],
          ),
          loggedInTrackersProvider.overrideWith((ref) async => []),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        effectiveCategoryLibraryOptionsProvider(7),
        (_, _) {},
      );
      addTearDown(subscription.close);
      await container.read(categoryControllerProvider.future);
      await container.read(libraryMangaListProvider.future);
      final options = container.read(
        effectiveCategoryLibraryOptionsProvider(7),
      );
      expect(options.sort, MangaSort.unread);
      expect(options.ascending, false);
      expect(options.unread, true);
      expect(options.downloaded, isNull);
      expect(options.trackers, {1: true, 2: true});
      expect(options.trackerMode, 'OR');
      expect(options.source, {'1': true});
      container.read(libraryActiveCategoryProvider.notifier).update(7);
      final active = container.listen(activeLibraryOptionsProvider, (_, _) {});
      addTearDown(active.close);
      repository.writeGate = Completer<void>();
      container
          .read(activeLibraryOptionsProvider.notifier)
          .sort(MangaSort.dateAdded);
      container.read(activeLibraryOptionsProvider.notifier).unread(false);
      container.read(activeLibraryOptionsProvider.notifier).tracker(3, true);
      container.invalidate(categoryControllerProvider);
      await container.read(categoryControllerProvider.future);
      expect(
        container.read(activeLibraryOptionsProvider).sort,
        MangaSort.dateAdded,
      );
      expect(container.read(activeLibraryOptionsProvider).unread, false);
      container.read(activeLibraryOptionsProvider.notifier).tracker(4, true);
      repository.writeGate!.complete();
      await container.pump();
      await Future<void>.delayed(Duration.zero);
      expect(repository.meta['webUI_migration'], '10');
      expect(
        repository.meta['webUI_hasTrackerBinding'],
        '{"filters":{"1":true,"2":true,"3":true,"4":true},"mode":"OR"}',
      );
      expect(repository.meta['webUI_sortBy'], 'dateAdded');
      expect(repository.meta['webUI_hasUnreadChapters'], 'false');
      expect(repository.meta.containsKey('webUI_hasDownloadedChapters'), false);
      container.read(libraryGroupTypeProvider.notifier).update(1);
      expect(
        container.read(effectiveCategoryLibraryOptionsProvider(7)).unread,
        isNull,
      );
    },
  );

  group('alphabetical sort folds case and accents', () {
    // Komikku sorts with a PRIMARY-strength collator (LibraryScreenModel.kt:
    // 635-639, SortUtil.kt:6-15); raw compareTo is UTF-16 order, which puts
    // every capitalised title before every lowercase one.
    final items = [
      _manga(1, title: 'Zebra'),
      _manga(2, title: 'apple'),
      _manga(3, title: 'Éclair'),
    ];

    test('ascending orders by base letter, not by code unit', () {
      expect(_sorted(items, by: MangaSort.alphabetical, ascending: true), [
        2,
        3,
        1,
      ]);
    });
  });

  group('unread sort pins zero-unread last in both directions', () {
    // LibraryScreenModel.kt:669-675 keeps zero-unread last regardless of
    // direction — its zero branches are direction-aware, reversed separately.
    final items = [
      _manga(1, title: 'A', unreadCount: 0),
      _manga(2, title: 'B', unreadCount: 5),
      _manga(3, title: 'C', unreadCount: 3),
    ];

    test('zero unread stays last in both directions, ties break by title', () {
      expect(_sorted(items, by: MangaSort.unread, ascending: true), [3, 2, 1]);
      expect(_sorted(items, by: MangaSort.unread, ascending: false), [2, 3, 1]);

      // Without this, an implementation that ties on unread and then falls
      // straight to id passes every other case here.
      final tied = [
        _manga(1, title: 'Zebra', unreadCount: 3),
        _manga(2, title: 'Apple', unreadCount: 3),
      ];
      expect(_sorted(tied, by: MangaSort.unread, ascending: true), [2, 1]);
      expect(_sorted(tied, by: MangaSort.unread, ascending: false), [2, 1]);
      expect(
        _sorted(
          items,
          by: MangaSort.unread,
          ascending: true,
          pinZeroUnreadLast: false,
        ),
        [1, 3, 2],
      );
    });
  });
}

class _MetaRepository extends CategoryRepository {
  _MetaRepository()
    : super(
        GraphQLClient(
          link: HttpLink('https://unused.invalid'),
          cache: GraphQLCache(),
        ),
      );

  final meta = <String, String>{
    'webUI_sortBy': 'unreadChapters',
    'webUI_sortDesc': 'true',
    'webUI_hasUnreadChapters': 'true',
    'webUI_hasSource': '{"1":true,"removed":true}',
    'webUI_hasTrackerBinding': '{"1":true,"2":true}',
  };
  Completer<void>? writeGate;

  @override
  Future<void> setCategoryMetas(
    int categoryId,
    Map<String, String?> values,
  ) async {
    await writeGate?.future;
    for (final e in values.entries) {
      if (e.value == null) {
        meta.remove(e.key);
      } else {
        meta[e.key] = e.value!;
      }
    }
  }
}

class _MetaCategories extends CategoryController {
  _MetaCategories(this.repository);
  final _MetaRepository repository;

  @override
  Future<List<Fragment$CategoryDto>?> build() async => [
    Fragment$CategoryDto.fromJson({
      '__typename': 'CategoryType',
      'id': 7,
      'name': 'Category',
      'order': 0,
      'defaultCategory': false,
      'includeInDownload': 'UNSET',
      'includeInUpdate': 'UNSET',
      'mangas': {'__typename': 'MangaNodeList', 'totalCount': 2},
      'meta': [
        for (final e in repository.meta.entries)
          {'__typename': 'CategoryMetaType', 'key': e.key, 'value': e.value},
      ],
    }),
  ];
}
