// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/history/domain/history_item.dart';
import 'package:tsumiru/src/features/history/presentation/history_controller.dart';
import 'package:tsumiru/src/features/library/domain/category/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/library/presentation/category/controller/edit_category_controller.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_controller.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_manga_list.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/quick_open/presentation/unified_search/phone_search_view.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

import '../../../helpers/unreachable_server_stubs.dart';

const _phone = Size(412, 900);

Fragment$MangaDto _manga(int id, String title) => Fragment$MangaDto(
  id: id,
  title: title,
  thumbnailUrl: null,
  bookmarkCount: 0,
  chapters: Fragment$MangaDto$chapters(totalCount: 4),
  downloadCount: 1,
  genre: const [],
  inLibrary: true,
  inLibraryAt: '0',
  initialized: true,
  meta: const [],
  sourceId: '1',
  status: Enum$MangaStatus.ONGOING,
  categories: Fragment$MangaDto$categories(nodes: const []),
  trackRecords: Fragment$MangaDto$trackRecords(nodes: const []),
  unreadCount: 2,
  updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
  url: '/manga/$id',
);

const _emptyCategories = AsyncData(<Fragment$CategoryDto>[]);

class _FakeReadingHistory extends ReadingHistory {
  @override
  Future<List<HistoryItemDto>?> build() async => const [];
}

Finder _overlayField() => find.descendant(
  of: find.byType(PhoneSearchOverlay),
  matching: find.byType(TextField),
);

/// Pumps a bare search entry at phone size. Tests open the overlay by tapping
/// the icon, so the overlay behaviour is covered without pumping whole pages.
Future<ProviderContainer> _pumpEntry(
  WidgetTester tester, {
  required PhoneSearchOrigin origin,
  List<Fragment$MangaDto> library = const [],
}) async {
  SharedPreferences.setMockInitialValues({});
  final sp = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(sp),
      libraryMangaListProvider.overrideWith((ref) async => library),
      visibleCategoryListProvider.overrideWithValue(_emptyCategories),
      readingHistoryProvider.overrideWith(_FakeReadingHistory.new),
      ...unreachableServerStubs,
    ],
  );
  addTearDown(container.dispose);
  tester.view.physicalSize = _phone;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(child: PhoneSearchEntry(origin: origin)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _openOverlay(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.search_rounded));
  await tester.pumpAndSettle();
  expect(find.byType(PhoneSearchOverlay), findsOneWidget);
}

void main() {
  testWidgets('page row applies q and closes', (tester) async {
    final container = await _pumpEntry(
      tester,
      origin: PhoneSearchOrigin.library,
      library: [_manga(1, 'Sword Chronicles')],
    );
    await _openOverlay(tester);

    await tester.enterText(_overlayField(), 'sw');
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Search library for "sw"'));
    await tester.pumpAndSettle();

    expect(container.read(libraryQueryProvider), 'sw');
    expect(find.byType(PhoneSearchOverlay), findsNothing);
  });
}
