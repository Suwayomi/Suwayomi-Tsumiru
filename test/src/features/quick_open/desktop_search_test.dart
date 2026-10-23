// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/library/domain/category/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/library/presentation/category/controller/edit_category_controller.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_manga_list.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/quick_open/presentation/unified_search/desktop_search_field.dart';
import 'package:tsumiru/src/features/quick_open/presentation/unified_search/unified_search_providers.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

import '../../../helpers/unreachable_server_stubs.dart';

const _desktop = Size(1400, 980);

Fragment$MangaDto _manga(int id, String title) => Fragment$MangaDto(
  id: id,
  title: title,
  thumbnailUrl: null,
  chapters: Fragment$MangaDto$chapters(totalCount: 4),
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
    downloadCount: 1,
    inLibrary: true,
    inLibraryAt: '0',
    unreadCount: 2,
  ),
);

const _emptyCategories = AsyncData(<Fragment$CategoryDto>[]);

Widget _boundField() => Consumer(
  builder: (context, ref, _) => DesktopSearchField(
    query: ref.watch(unifiedSearchQueryProvider),
    onChanged: (value) =>
        ref.read(unifiedSearchQueryProvider.notifier).state = value,
    onNavigate: () => ref.read(unifiedSearchQueryProvider.notifier).state = '',
  ),
);

Finder _fieldTextField() => find.descendant(
  of: find.byType(DesktopSearchField),
  matching: find.byType(TextField),
);

Future<void> _pumpField(
  WidgetTester tester, {
  List<Fragment$MangaDto> library = const [],
}) async {
  tester.view.physicalSize = _desktop;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final sp = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(sp),
      libraryMangaListProvider.overrideWith((ref) async => library),
      visibleCategoryListProvider.overrideWithValue(_emptyCategories),
      ...unreachableServerStubs,
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(child: SizedBox(width: 500, child: _boundField())),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('typing opens Library hits and Search all sources', (
    tester,
  ) async {
    await _pumpField(tester, library: [_manga(1, 'Sword Chronicles')]);

    await tester.enterText(_fieldTextField(), 'sw');
    // The dropdown's first watch starts the library future; its completion
    // lands a frame later.
    await tester.pump();
    await tester.pump();

    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Sword Chronicles'), findsOneWidget);
    expect(find.text('2 unread'), findsOneWidget);
    expect(find.text('Search all sources for "sw"'), findsOneWidget);
  });
}
