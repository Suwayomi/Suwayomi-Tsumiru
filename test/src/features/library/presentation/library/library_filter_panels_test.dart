// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// ignore_for_file: prefer_const_constructors

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/library/data/default_category.dart';
import 'package:tsumiru/src/features/library/domain/category/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/library/presentation/category/controller/edit_category_controller.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_controller.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_manga_list.dart';
import 'package:tsumiru/src/features/library/presentation/library/library_screen.dart';
import 'package:tsumiru/src/features/library/presentation/library/widgets/desktop_library_toolbar.dart';
import 'package:tsumiru/src/features/manga_book/data/updates/updates_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/settings/presentation/syncyomi/data/syncyomi_settings_provider.dart';
import 'package:tsumiru/src/features/tracking/data/graphql/__generated__/query.graphql.dart';
import 'package:tsumiru/src/features/tracking/data/tracker_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/widgets/desktop/desktop_top_bar.dart';

Fragment$CategoryDto _category(int id, String name) => Fragment$CategoryDto(
  defaultCategory: false,
  id: id,
  includeInDownload: Enum$IncludeOrExclude.UNSET,
  includeInUpdate: Enum$IncludeOrExclude.UNSET,
  name: name,
  order: id,
  mangas: Fragment$CategoryDto$mangas(totalCount: 0),
  meta: const [],
);

Fragment$MangaDto$source _mangaSource() => Fragment$MangaDto$source(
  displayName: 'Test Source',
  iconUrl: '',
  id: '1',
  contentWarning: Enum$ContentWarning.SAFE,
  lang: 'en',
  name: 'Test Source',
  $extension: Fragment$MangaDto$source$extension(isObsolete: false),
);

Fragment$MangaDto _manga(int id, List<String> genre) => Fragment$MangaDto(
  id: id,
  title: 'Manga $id',
  chapters: Fragment$MangaDto$chapters(totalCount: 0),
  genre: genre,
  initialized: true,
  meta: const [],
  source: _mangaSource(),
  sourceId: '1',
  status: Enum$MangaStatus.ONGOING,
  categories: Fragment$MangaDto$categories(nodes: const []),
  trackRecords: Fragment$MangaDto$trackRecords(nodes: const []),
  updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
  url: 'https://example.com/manga/$id',
  user: Fragment$MangaDto$user(
    bookmarkCount: 0,
    downloadCount: 0,
    inLibrary: true,
    inLibraryAt: '0',
    unreadCount: 0,
  ),
);

/// Pumps the real [LibraryScreen] with two empty categories and two tagged
/// manga (Action x2, Fantasy x1). Never hits the network.
///
/// On desktop widths the screen goes inside a replica of the desktop shell: a
/// 256 px sidebar plus the real [DesktopTopBar] (which shows the library
/// toolbar from its slot), with the library in a nested [Navigator] like
/// go_router's branch Navigator. The nested Navigator owns its own Overlay
/// covering only the content area, which is what caught the window-global
/// anchor bug (panels pinned to the window's right edge instead of the
/// button's). Narrow surfaces pump the screen directly (phone, no shell).
Future<ProviderContainer> _createContainer({
  List<Fragment$TrackerDto> trackers = const <Fragment$TrackerDto>[],
}) async {
  SharedPreferences.setMockInitialValues({});
  final sp = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(sp),
      loggedInTrackersProvider.overrideWithValue(AsyncData(trackers)),
      updateRunningSocketProvider.overrideWithValue(
        const AsyncData<bool?>(null),
      ),
      failedUpdateCountProvider.overrideWithValue(const AsyncData(0)),
      syncYomiSettingsProvider.overrideWithValue(const AsyncData(null)),
      settledDefaultCategoryIdProvider.overrideWithValue(1),
      nonZeroCategoryListProvider.overrideWithValue(
        AsyncData([_category(1, 'One'), _category(2, 'Two')]),
      ),
      visibleCategoryListProvider.overrideWithValue(
        AsyncData([_category(1, 'One'), _category(2, 'Two')]),
      ),
      categoryMangaListProvider.overrideWith(
        (ref, categoryId) async => <Fragment$MangaDto>[],
      ),
      categoryMangaListWithQueryAndFilterProvider(
        categoryId: 1,
      ).overrideWithValue(AsyncData<List<Fragment$MangaDto>?>(null)),
      categoryMangaListWithQueryAndFilterProvider(
        categoryId: 2,
      ).overrideWithValue(AsyncData<List<Fragment$MangaDto>?>(null)),
      libraryTagListProvider.overrideWithValue(
        const AsyncData(<String>['Action', 'Fantasy']),
      ),
      libraryMangaListProvider.overrideWith(
        (ref) async => [
          _manga(1, ['Action', 'Fantasy']),
          _manga(2, ['Action']),
        ],
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<ProviderContainer> _pumpLibrary(
  WidgetTester tester, {
  required Size surface,
  List<Fragment$TrackerDto> trackers = const <Fragment$TrackerDto>[],
}) async {
  final container = await _createContainer(trackers: trackers);
  tester.view.physicalSize = surface;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  const library = LibraryScreen(categoryId: 1);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('window_manager'), (
        call,
      ) async {
        if (call.method == 'isMaximized') return false;
        return null;
      });
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), null),
  );
  final Widget home = surface.width >= 1200
      ? Scaffold(
          body: Row(
            children: [
              const SizedBox(width: 256),
              Expanded(
                child: Column(
                  children: [
                    const DesktopTopBar(),
                    Expanded(
                      child: Navigator(
                        onGenerateRoute: (_) =>
                            MaterialPageRoute(builder: (_) => library),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        )
      : library;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Taps the toolbar's Filter button. The shell bar slot is narrower than the
/// old body header, so at 1400 the toolbar is in compact mode (icon buttons,
/// no text labels): tap the Filter icon, which both modes render, instead of
/// the label text that only full mode shows.
Finder _filterButton() => find.descendant(
  of: find.byType(DesktopLibraryToolbar),
  matching: find.byIcon(Icons.filter_list_rounded),
);

Future<void> _openFilterPanel(WidgetTester tester) async {
  await tester.tap(_filterButton());
  await tester.pumpAndSettle();
}

void main() {
  group('Library filter panel (desktop 1400x980)', () {
    testWidgets('Yes/No segments write true/false on two filters', (
      tester,
    ) async {
      final container = await _pumpLibrary(
        tester,
        surface: const Size(1400, 980),
      );
      await _openFilterPanel(tester);

      // Row order: Downloaded, Storage, Read Status, Started, ...
      await tester.tap(find.text('Yes').at(0));
      await tester.pump();
      expect(container.read(libraryMangaFilterDownloadedProvider), isTrue);

      await tester.tap(find.text('No').at(0));
      await tester.pump();
      expect(container.read(libraryMangaFilterDownloadedProvider), isFalse);

      await tester.tap(find.text('Yes').at(1));
      await tester.pump();
      expect(container.read(libraryMangaFilterStartedProvider), isTrue);

      await tester.tap(find.text('No').at(1));
      await tester.pump();
      expect(container.read(libraryMangaFilterStartedProvider), isFalse);
      expect(tester.takeException(), isNull);
    });
  });
}
