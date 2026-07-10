// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/library/domain/category/category_model.dart';
import 'package:tsumiru/src/features/library/domain/category/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/library/presentation/category/controller/edit_category_controller.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_manga_list.dart';
import 'package:tsumiru/src/features/manga_book/data/manga_book/manga_book_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/widgets/edit_manga_category_dialog.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

CategoryDto _cat({required int id, required String name}) => Fragment$CategoryDto(
      defaultCategory: false,
      id: id,
      includeInDownload: Enum$IncludeOrExclude.UNSET,
      includeInUpdate: Enum$IncludeOrExclude.UNSET,
      name: name,
      order: id,
      mangas: Fragment$CategoryDto$mangas(totalCount: 0),
      meta: const [],
    );

GraphQLClient _dummyClient() => GraphQLClient(
      link: HttpLink('http://localhost:0'),
      cache: GraphQLCache(),
    );

class _RecordingMangaBookRepo extends MangaBookRepository {
  _RecordingMangaBookRepo({this.failAdd = false}) : super(_dummyClient());

  final bool failAdd;
  final List<int> added = <int>[];
  List<CategoryDto> current = <CategoryDto>[];

  @override
  Future<List<CategoryDto>?> getMangaCategoryList({required int mangaId}) async =>
      current;

  @override
  Future<void> addMangaToCategory(int mangaId, int categoryId) async {
    if (failAdd) throw Exception('offline — mutation failed');
    added.add(categoryId);
  }

  @override
  Future<void> removeMangaFromCategory(int mangaId, int categoryId) async {}
}

class _FixedCategories extends CategoryController {
  @override
  Future<List<CategoryDto>?> build() async => [_cat(id: 2, name: 'Pornhwa')];
}

Widget _app(ProviderContainer container) => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: EditMangaCategoryDialog(mangaId: 76)),
      ),
    );

void main() {
  testWidgets(
      'toggling a category persists via the repo and re-fetches the library',
      (tester) async {
    final repo = _RecordingMangaBookRepo();
    var libraryBuilds = 0;
    final container = ProviderContainer(overrides: [
      mangaBookRepositoryProvider.overrideWithValue(repo),
      categoryControllerProvider.overrideWith(() => _FixedCategories()),
      libraryMangaListProvider.overrideWith((ref) async {
        libraryBuilds++;
        return const <MangaDto>[];
      }),
    ]);
    addTearDown(container.dispose);
    // Keep the library source alive so an invalidation actually rebuilds it.
    container.listen(libraryMangaListProvider, (_, __) {}, fireImmediately: true);

    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle();
    expect(libraryBuilds, 1);

    await tester.tap(find.text('Pornhwa'));
    await tester.pumpAndSettle();

    // The change persisted through the repo (the mutation actually ran)...
    expect(repo.added, contains(2));
    // ...and the library's single source list was invalidated + rebuilt, so
    // the manga will show under the new category tab (the reported bug).
    expect(libraryBuilds, 2);
  });

  testWidgets('a failed toggle reverts the checkbox and does not refetch',
      (tester) async {
    final repo = _RecordingMangaBookRepo(failAdd: true);
    var libraryBuilds = 0;
    final container = ProviderContainer(overrides: [
      mangaBookRepositoryProvider.overrideWithValue(repo),
      categoryControllerProvider.overrideWith(() => _FixedCategories()),
      libraryMangaListProvider.overrideWith((ref) async {
        libraryBuilds++;
        return const <MangaDto>[];
      }),
    ]);
    addTearDown(container.dispose);
    container.listen(libraryMangaListProvider, (_, __) {}, fireImmediately: true);

    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Pornhwa'));
    await tester.pumpAndSettle();

    expect(repo.added, isEmpty);
    // The optimistic tick flipped the box; the failure reverts it, so it does
    // not show a save that never landed.
    final tile = tester.widget<CheckboxListTile>(
      find.ancestor(
        of: find.text('Pornhwa'),
        matching: find.byType(CheckboxListTile),
      ),
    );
    expect(tile.value, isFalse);
    // Nothing changed on the server, so the library is not re-fetched (only the
    // initial fireImmediately build ran).
    expect(libraryBuilds, 1);
  });
}
