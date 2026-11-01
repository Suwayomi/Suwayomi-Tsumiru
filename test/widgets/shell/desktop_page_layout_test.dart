// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/app_sizes.dart';
import 'package:tsumiru/src/constants/db_keys.dart';
import 'package:tsumiru/src/features/browse_center/presentation/browse/browse_screen.dart';
import 'package:tsumiru/src/features/browse_center/presentation/extension/controller/extension_update_badge.dart';
import 'package:tsumiru/src/features/history/data/graphql/__generated__/query.graphql.dart';
import 'package:tsumiru/src/features/history/domain/history_item.dart';
import 'package:tsumiru/src/features/history/presentation/history_controller.dart';
import 'package:tsumiru/src/features/history/presentation/history_screen.dart';
import 'package:tsumiru/src/features/history/presentation/widgets/history_item_tile.dart';
import 'package:tsumiru/src/features/library/data/default_category.dart';
import 'package:tsumiru/src/features/library/domain/category/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/library/presentation/category/controller/edit_category_controller.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_controller.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_manga_list.dart';
import 'package:tsumiru/src/features/library/presentation/library/library_screen.dart';
import 'package:tsumiru/src/features/library/presentation/library/widgets/category_tab_strip.dart';
import 'package:tsumiru/src/features/manga_book/data/updates/updates_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/presentation/downloads/downloads_screen.dart';
import 'package:tsumiru/src/features/offline/data/offline_nav_status.dart';
import 'package:tsumiru/src/features/settings/presentation/more/more_screen.dart';
import 'package:tsumiru/src/features/settings/presentation/settings/settings_screen.dart';
import 'package:tsumiru/src/features/settings/presentation/syncyomi/data/syncyomi_settings_provider.dart';
import 'package:tsumiru/src/features/tracking/data/graphql/__generated__/query.graphql.dart';
import 'package:tsumiru/src/features/tracking/data/tracker_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/tsumiru_app.dart';
import 'package:tsumiru/src/widgets/desktop/desktop_page_frame.dart';
import 'package:tsumiru/src/widgets/desktop/desktop_top_bar.dart';
import 'package:tsumiru/src/widgets/desktop/desktop_view_switch.dart';
import 'package:tsumiru/src/widgets/manga_cover/grid/manga_cover_grid_tile.dart';
import 'package:tsumiru/src/widgets/shell/big_screen_navigation_bar.dart';
import 'package:tsumiru/src/widgets/shell/detail_navigation_shell_screen.dart';

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

Fragment$MangaDto _manga(int id) => Fragment$MangaDto(
  id: id,
  title: 'Series $id',
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
    downloadCount: 0,
    inLibrary: true,
    inLibraryAt: '0',
    unreadCount: 2,
  ),
);

final HistoryItemDto _historyItem = Fragment$HistoryChapterDto(
  id: 1,
  chapterNumber: 1,
  fetchedAt: '0',
  mangaId: 7,
  name: 'Chapter 1',
  pageCount: 10,
  sourceOrder: 1,
  uploadDate: '0',
  url: '/c/1',
  meta: const [],
  manga: Fragment$HistoryChapterDto$manga(
    id: 7,
    title: 'Series',
    meta: const [],
    user: Fragment$HistoryChapterDto$manga$user(
      inLibrary: true,
      unreadCount: 3,
    ),
  ),
  user: Fragment$HistoryChapterDto$user(
    isBookmarked: false,
    isDownloaded: false,
    isRead: false,
    lastPageRead: 4,
    lastReadAt: '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
  ),
);

class _FakeReadingHistory extends ReadingHistory {
  @override
  Future<List<HistoryItemDto>?> build() async => [_historyItem];
}

void main() {
  testWidgets('desktop pages start on the shared page line', (tester) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('window_manager'),
          (call) async => call.method == 'isMaximized' ? false : null,
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('window_manager'),
            null,
          ),
    );
    final categories = [_category(1, 'One'), _category(2, 'Two')];

    Future<void> pump(Widget page, {bool persistentSearch = false}) async {
      SharedPreferences.setMockInitialValues({
        DBKeys.libraryPersistentSearchBar.name: persistentSearch,
      });
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            downloadsPausedBadgeProvider.overrideWith((ref) => false),
            extensionUpdateBadgeCountProvider.overrideWith((ref) async => 0),
            failedUpdatesProvider.overrideWith((ref) async => []),
            loggedInTrackersProvider.overrideWithValue(
              const AsyncData(<Fragment$TrackerDto>[]),
            ),
            updateRunningSocketProvider.overrideWithValue(
              const AsyncData<bool?>(null),
            ),
            failedUpdateCountProvider.overrideWithValue(const AsyncData(0)),
            syncYomiSettingsProvider.overrideWithValue(const AsyncData(null)),
            settledDefaultCategoryIdProvider.overrideWithValue(1),
            nonZeroCategoryListProvider.overrideWithValue(
              AsyncData(categories),
            ),
            visibleCategoryListProvider.overrideWithValue(
              AsyncData(categories),
            ),
            categoryMangaListProvider.overrideWith(
              (ref, categoryId) async => <Fragment$MangaDto>[],
            ),
            libraryMangaListProvider.overrideWith(
              (ref) async => <Fragment$MangaDto>[],
            ),
            for (final id in [1, 2])
              categoryMangaListWithQueryAndFilterProvider(
                categoryId: id,
              ).overrideWithValue(
                AsyncData([for (var i = 1; i <= 6; i++) _manga(id * 100 + i)]),
              ),
            readingHistoryProvider.overrideWith(_FakeReadingHistory.new),
          ],
          child: MaterialApp(
            scrollBehavior: const AppScrollBehavior(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: DetailNavigationShellScreen(child: page),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    }

    void expectOnLine(
      String page,
      Finder content, {
      double top = 0,
      double? centredWidth,
    }) {
      final sidebar = tester.getRect(find.byType(BigScreenNavigationBar));
      final topBar = tester.getRect(find.byType(DesktopTopBar));
      final rect = tester.getRect(content.first);
      final pageWidth = topBar.right - sidebar.right - kDesktopPageInset;
      final centring = centredWidth == null
          ? 0
          : max(0, (pageWidth - centredWidth) / 2);
      expect(
        rect.left - sidebar.right,
        kDesktopPageInset + centring,
        reason: '$page left edge',
      );
      expect(
        rect.top - topBar.bottom,
        top == 0 ? kDesktopPageInset : top,
        reason: '$page top edge',
      );
    }

    tester.view.physicalSize = const Size(1000, 700);
    await pump(const LibraryScreen(categoryId: 1));
    expect(tester.takeException(), isNull);
    final tabLabel = find.text('One', findRichText: true);
    expect(
      tester.getRect(tabLabel).left -
          tester.getRect(find.byType(BigScreenNavigationBar)).right,
      kDesktopPageInset,
      reason: 'Library first category label',
    );
    final cover = find.descendant(
      of: find.byType(MangaCoverGridTile).first,
      matching: find.byType(Material),
    );
    expectOnLine(
      'Library grid',
      cover,
      top: kCategoryTabStripHeight + DesktopPageHeader.gap,
    );

    await pump(const LibraryScreen(categoryId: 1), persistentSearch: true);
    expect(tester.takeException(), isNull);
    expectOnLine(
      'Library persistent search grid',
      cover,
      top: kCategoryTabStripHeight + DesktopPageHeader.gap,
    );
    final coverRight = find.byType(MangaCoverGridTile).evaluate().map(
      (element) => tester.getRect(
        find.descendant(
          of: find.byWidget(element.widget),
          matching: find.byType(Material),
        ).first,
      ).right,
    ).reduce(max);
    expect(
      tester.view.physicalSize.width - coverRight,
      kDesktopScrollbarGutter,
      reason: 'Library persistent search covers clear the scrollbar thumb',
    );

    void expectSelectedCategory(String name) {
      final label = tester.widget<RichText>(find.text(name, findRichText: true));
      final span = label.text.getSpanForPosition(const TextPosition(offset: 0))!;
      expect(span.style!.fontWeight, FontWeight.w600);
    }

    expectSelectedCategory('One');
    final swipeStart =
        tester.getCenter(find.byType(CategoryTabStrip)) + const Offset(250, 200);
    await tester.dragFrom(
      swipeStart,
      const Offset(-600, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expectSelectedCategory('One');
    await tester.dragFrom(
      swipeStart,
      const Offset(-600, 0),
      kind: PointerDeviceKind.touch,
    );
    await tester.pumpAndSettle();
    expectSelectedCategory('Two');

    await pump(const HistoryScreen());
    expect(tester.takeException(), isNull);
    expectOnLine(
      'History heading',
      find.text('Today'),
      centredWidth: kDesktopListMaxWidth,
    );
    final thumbnail = find.descendant(
      of: find.byType(HistoryItemTile),
      matching: find.byType(ClipRRect),
    );
    expect(
      tester.getRect(thumbnail.first).left -
          tester.getRect(find.byType(BigScreenNavigationBar)).right,
      kDesktopPageInset,
      reason: 'History thumbnail',
    );

    await pump(
      BrowseScreen(
        currentIndex: 0,
        onDestinationSelected: (_) {},
        children: const [SizedBox(), SizedBox(), SizedBox()],
      ),
    );
    expect(tester.takeException(), isNull);
    expectOnLine('Browse', find.byType(DesktopViewSwitch));

    await pump(const DownloadsScreen());
    expect(tester.takeException(), isNull);
    expectOnLine('Downloads', find.byType(DesktopViewSwitch));
    await tester.tap(find.text('On device'));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    expectOnLine('Downloads on device', find.byType(DesktopViewSwitch));

    await pump(const MoreScreen());
    expect(tester.takeException(), isNull);
    expectOnLine(
      'More',
      find.text('Account'),
      centredWidth: kDesktopSettingsMaxWidth,
    );

    await pump(const SettingsScreen());
    expect(tester.takeException(), isNull);
    expectOnLine(
      'Settings',
      find.text('App'),
      centredWidth: kDesktopSettingsMaxWidth,
    );
  });
}
