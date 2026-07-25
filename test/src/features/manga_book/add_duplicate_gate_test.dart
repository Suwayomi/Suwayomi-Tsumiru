// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

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
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/widgets/add_to_library_category.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

import 'reader/reader_test_fixtures.dart';

Fragment$MangaDto$trackRecords$nodes _node({
  int trackerId = 1,
  String remoteId = '42',
}) => Fragment$MangaDto$trackRecords$nodes(
  id: 1,
  trackerId: trackerId,
  remoteId: remoteId,
  status: 1,
  score: 0,
  title: 'Tracked',
);

MangaDto _manga({
  required int id,
  required String title,
  List<Fragment$MangaDto$trackRecords$nodes> trackerNodes = const [],
}) => testManga().copyWith.call(
  id: id,
  title: title,
  trackRecords: Fragment$MangaDto$trackRecords(
    totalCount: trackerNodes.length,
    nodes: trackerNodes,
  ),
);

CategoryDto _cat({required int id, required String name}) =>
    Fragment$CategoryDto(
      defaultCategory: false,
      id: id,
      includeInDownload: Enum$IncludeOrExclude.UNSET,
      includeInUpdate: Enum$IncludeOrExclude.UNSET,
      name: name,
      order: id,
      mangas: Fragment$CategoryDto$mangas(totalCount: 0),
      meta: const [],
    );

GraphQLClient _dummyClient() =>
    GraphQLClient(link: HttpLink('http://localhost:0'), cache: GraphQLCache());

class _RecordingRepo extends MangaBookRepository {
  _RecordingRepo() : super(_dummyClient());

  final List<int> addedToLibrary = <int>[];

  @override
  Future<MangaDto?> addMangaToLibrary(int mangaId) async {
    addedToLibrary.add(mangaId);
    return null;
  }

  @override
  Future<void> addMangaToCategory(int mangaId, int categoryId) async {}
}

class _FixedCategories extends CategoryController {
  @override
  Future<List<CategoryDto>?> build() async => [_cat(id: 0, name: 'Default')];
}

class _FixedDefault extends LibraryDefaultCategory {
  _FixedDefault(this._value);
  final int _value;
  @override
  int? build() => _value;
}

ProviderContainer _container({
  required _RecordingRepo repo,
  required FutureOr<List<MangaDto>?> Function(Ref ref) library,
}) => ProviderContainer(overrides: [
      mangaBookRepositoryProvider.overrideWithValue(repo),
      categoryControllerProvider.overrideWith(() => _FixedCategories()),
      // Default/uncategorized: add proceeds with no picker once the gate clears.
      libraryDefaultCategoryProvider.overrideWith(() => _FixedDefault(0)),
      libraryTrackerNamesProvider.overrideWithValue(const {}),
      libraryMangaListProvider.overrideWith(library),
    ]);

Widget _harness(
  ProviderContainer c,
  MangaDto manga, {
  Future<bool> Function(MangaDto from, MangaDto to)? migrateDuplicate,
  void Function(BuildContext context, MangaDto manga)? openEntry,
}) => UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Consumer(
          builder: (context, ref, _) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => addMangaToLibraryWithCategory(
                  ref,
                  context,
                  manga,
                  migrateDuplicate: migrateDuplicate,
                  openEntry: openEntry,
                ),
                child: const Text('add'),
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('a duplicate pops the dialog and blocks the add until Add anyway',
      (tester) async {
    final repo = _RecordingRepo();
    final existing = _manga(id: 2, title: 'Solo Leveling');
    final candidate = _manga(id: 76, title: 'Solo Leveling');
    final c = _container(repo: repo, library: (ref) async => [existing]);
    addTearDown(c.dispose);

    await tester.pumpWidget(_harness(c, candidate));
    await tester.tap(find.text('add'));
    await tester.pumpAndSettle();

    // Dialog is up, nothing added yet.
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(repo.addedToLibrary, isEmpty);

    await tester.tap(find.text('Add anyway'));
    await tester.pumpAndSettle();

    expect(repo.addedToLibrary, contains(76));
  });

  testWidgets('Cancel on the duplicate dialog adds nothing', (tester) async {
    final repo = _RecordingRepo();
    final existing = _manga(id: 2, title: 'Solo Leveling');
    final candidate = _manga(id: 76, title: 'Solo Leveling');
    final c = _container(repo: repo, library: (ref) async => [existing]);
    addTearDown(c.dispose);

    await tester.pumpWidget(_harness(c, candidate));
    await tester.tap(find.text('add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(repo.addedToLibrary, isEmpty);
  });

  testWidgets('a library-list error fails open — the add proceeds',
      (tester) async {
    final repo = _RecordingRepo();
    final candidate = _manga(id: 76, title: 'Solo Leveling');
    final c = _container(
      repo: repo,
      library: (ref) async => throw Exception('offline'),
    );
    addTearDown(c.dispose);

    await tester.pumpWidget(_harness(c, candidate));
    await tester.tap(find.text('add'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(repo.addedToLibrary, contains(76));
  });

  testWidgets('no duplicate in the library adds straight through',
      (tester) async {
    final repo = _RecordingRepo();
    final other = _manga(id: 2, title: 'Something Else');
    final candidate = _manga(id: 76, title: 'Solo Leveling');
    final c = _container(repo: repo, library: (ref) async => [other]);
    addTearDown(c.dispose);

    await tester.pumpWidget(_harness(c, candidate));
    await tester.tap(find.text('add'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(repo.addedToLibrary, contains(76));
  });

  testWidgets('migrating a duplicate ends the add — no second add call',
      (tester) async {
    final repo = _RecordingRepo();
    // Tracker-certain duplicate with a distinct title so the card is tappable.
    final existing =
        _manga(id: 2, title: 'Existing Entry', trackerNodes: [_node()]);
    final candidate =
        _manga(id: 76, title: 'New Candidate', trackerNodes: [_node()]);
    final migrateCalls = <(int, int)>[];
    final c = _container(repo: repo, library: (ref) async => [existing]);
    addTearDown(c.dispose);

    await tester.pumpWidget(_harness(
      c,
      candidate,
      migrateDuplicate: (from, to) async {
        migrateCalls.add((from.id, to.id));
        return true;
      },
    ));
    await tester.tap(find.text('add'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Existing Entry'));
    await tester.pumpAndSettle();

    expect(migrateCalls, contains((2, 76)));
    expect(repo.addedToLibrary, isEmpty);
  });

  testWidgets('opening a duplicate ends the add and navigates to it',
      (tester) async {
    final repo = _RecordingRepo();
    final existing =
        _manga(id: 2, title: 'Existing Entry', trackerNodes: [_node()]);
    final candidate =
        _manga(id: 76, title: 'New Candidate', trackerNodes: [_node()]);
    final openedIds = <int>[];
    final c = _container(repo: repo, library: (ref) async => [existing]);
    addTearDown(c.dispose);

    await tester.pumpWidget(_harness(
      c,
      candidate,
      openEntry: (context, manga) => openedIds.add(manga.id),
    ));
    await tester.tap(find.text('add'));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Existing Entry'));
    await tester.pumpAndSettle();

    expect(openedIds, contains(2));
    expect(repo.addedToLibrary, isEmpty);
  });
}
