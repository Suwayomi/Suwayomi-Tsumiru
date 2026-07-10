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
import 'package:tsumiru/src/features/library/presentation/library/controller/library_controller.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_manga_list.dart';
import 'package:tsumiru/src/features/manga_book/data/manga_book/manga_book_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/widgets/add_to_library_category.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

CategoryDto _cat({required int id, required String name, bool isDefault = false}) =>
    Fragment$CategoryDto(
      defaultCategory: isDefault,
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

class _RecordingRepo extends MangaBookRepository {
  _RecordingRepo() : super(_dummyClient());

  final List<int> addedToLibrary = <int>[];
  final List<(int, int)> addedToCategory = <(int, int)>[];

  @override
  Future<MangaDto?> addMangaToLibrary(int mangaId) async {
    addedToLibrary.add(mangaId);
    return null;
  }

  @override
  Future<void> addMangaToCategory(int mangaId, int categoryId) async {
    addedToCategory.add((mangaId, categoryId));
  }
}

class _FixedCategories extends CategoryController {
  @override
  Future<List<CategoryDto>?> build() async => [
        _cat(id: 0, name: 'Default'),
        _cat(id: 1, name: 'Complete'),
        _cat(id: 2, name: 'Pornhwa'),
      ];
}

class _FixedDefault extends LibraryDefaultCategory {
  _FixedDefault(this._value);
  final int _value;
  @override
  int? build() => _value;
}

ProviderContainer _container(_RecordingRepo repo, int defaultCategory) {
  final c = ProviderContainer(overrides: [
    mangaBookRepositoryProvider.overrideWithValue(repo),
    categoryControllerProvider.overrideWith(() => _FixedCategories()),
    libraryDefaultCategoryProvider.overrideWith(() => _FixedDefault(defaultCategory)),
    libraryMangaListProvider.overrideWith((ref) async => const <MangaDto>[]),
  ]);
  return c;
}

Widget _harness(ProviderContainer c, int mangaId) => UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Consumer(
          builder: (context, ref, _) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () =>
                    addMangaToLibraryWithCategory(ref, context, mangaId),
                child: const Text('add'),
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('a specific default category is assigned silently, no prompt',
      (tester) async {
    final repo = _RecordingRepo();
    final c = _container(repo, 1); // Complete
    addTearDown(c.dispose);
    await tester.pumpWidget(_harness(c, 76));
    await tester.tap(find.text('add'));
    await tester.pumpAndSettle();

    expect(find.text('Set categories'), findsNothing);
    expect(repo.addedToLibrary, contains(76));
    expect(repo.addedToCategory, contains((76, 1)));
  });

  testWidgets('Default/uncategorized adds with no category and no prompt',
      (tester) async {
    final repo = _RecordingRepo();
    final c = _container(repo, 0);
    addTearDown(c.dispose);
    await tester.pumpWidget(_harness(c, 76));
    await tester.tap(find.text('add'));
    await tester.pumpAndSettle();

    expect(find.text('Set categories'), findsNothing);
    expect(repo.addedToLibrary, contains(76));
    expect(repo.addedToCategory, isEmpty);
  });

  testWidgets('Always ask pops the picker; OK adds and assigns the picks',
      (tester) async {
    final repo = _RecordingRepo();
    final c = _container(repo, -1);
    addTearDown(c.dispose);
    await tester.pumpWidget(_harness(c, 76));
    await tester.tap(find.text('add'));
    await tester.pumpAndSettle();

    expect(find.text('Set categories'), findsOneWidget);
    // Only user categories are offered (Default/id 0 is excluded).
    expect(find.text('Default'), findsNothing);
    await tester.tap(find.text('Pornhwa'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(repo.addedToLibrary, contains(76));
    expect(repo.addedToCategory, contains((76, 2)));
    expect(repo.addedToCategory, isNot(contains((76, 1))));
  });

  testWidgets('Always ask + Cancel adds nothing', (tester) async {
    final repo = _RecordingRepo();
    final c = _container(repo, -1);
    addTearDown(c.dispose);
    await tester.pumpWidget(_harness(c, 76));
    await tester.tap(find.text('add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(repo.addedToLibrary, isEmpty);
    expect(repo.addedToCategory, isEmpty);
  });
}
