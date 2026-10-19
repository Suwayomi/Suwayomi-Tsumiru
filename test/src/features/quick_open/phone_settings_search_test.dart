// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Slice 1: the phone search overlay gains the same Settings section under
// Go to and above Search all sources; picking a row leaves through the
// setting's page with its highlight id.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/history/domain/history_item.dart';
import 'package:tsumiru/src/features/history/presentation/history_controller.dart';
import 'package:tsumiru/src/features/library/domain/category/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/library/presentation/category/controller/edit_category_controller.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_manga_list.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/quick_open/presentation/unified_search/phone_search_view.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

import '../../../helpers/unreachable_server_stubs.dart';

const _phone = Size(412, 900);

void _setSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

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

Future<ProviderContainer> _container({
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
  return container;
}

Future<void> _pumpOverlayWithRouter(
  WidgetTester tester,
  ProviderContainer container,
) async {
  _setSize(tester, _phone);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: GoRouter(
          initialLocation: '/',
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const Scaffold(
                body: Center(
                  child: PhoneSearchEntry(origin: PhoneSearchOrigin.plain),
                ),
              ),
            ),
            for (final page in ['general', 'appearance', 'library'])
              GoRoute(
                path: '/more/settings/$page',
                builder: (_, state) => Scaffold(
                  body: Center(
                    child: Text(
                      'SETTINGS $page highlight=${state.uri.queryParameters['highlight']}',
                    ),
                  ),
                ),
              ),
            GoRoute(
              path: '/global-search',
              builder: (_, _) => const Scaffold(
                body: Center(child: Text('GLOBAL SEARCH PAGE')),
              ),
            ),
          ],
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openOverlay(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.search_rounded));
  await tester.pumpAndSettle();
  expect(find.byType(PhoneSearchOverlay), findsOneWidget);
}

Finder _overlayField() => find.descendant(
  of: find.byType(PhoneSearchOverlay),
  matching: find.byType(TextField),
);

double _dy(WidgetTester tester, Finder finder) => tester.getCenter(finder).dy;

void main() {
  group('phone Settings search section', () {
    testWidgets('typing "theme" shows Settings with App Theme Mode', (
      tester,
    ) async {
      await _pumpOverlayWithRouter(tester, await _container());
      await _openOverlay(tester);

      await tester.enterText(_overlayField(), 'theme');
      await tester.pump();
      await tester.pump();

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('App Theme Mode'), findsOneWidget);
      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Appearance › Theme'), findsOneWidget);
      expect(
        _dy(tester, find.text('Settings')),
        lessThan(_dy(tester, find.text('Search all sources for "theme"'))),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('Settings sits between Go to and Search all sources', (
      tester,
    ) async {
      await _pumpOverlayWithRouter(
        tester,
        await _container(library: [_manga(2, 'Update Notes')]),
      );
      await _openOverlay(tester);

      await tester.enterText(_overlayField(), 'upd');
      await tester.pump();
      await tester.pump();

      expect(find.text('Library'), findsOneWidget);
      expect(find.text('Go to'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      Finder shown(String text) => find.text(text, skipOffstage: false);
      expect(
        _dy(tester, shown('Library')),
        lessThan(_dy(tester, shown('Go to'))),
      );
      expect(
        _dy(tester, shown('Go to')),
        lessThan(_dy(tester, shown('Settings'))),
      );
      expect(
        _dy(tester, shown('Settings')),
        lessThan(_dy(tester, shown('Search all sources for "upd"'))),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('picking a row opens the page with the highlight id', (
      tester,
    ) async {
      await _pumpOverlayWithRouter(tester, await _container());
      await _openOverlay(tester);

      await tester.enterText(_overlayField(), 'theme');
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('App Theme Mode'));
      await tester.pumpAndSettle();

      expect(
        find.text('SETTINGS appearance highlight=appThemeMode'),
        findsOneWidget,
      );
      expect(find.byType(PhoneSearchOverlay), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
