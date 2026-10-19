// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Step-3 page coverage: every converted desktop page draws its toolbar in
// the shell bar instead of its own AppBar.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/about/data/about_repository.dart';
import 'package:tsumiru/src/features/about/presentation/about/about_screen.dart';
import 'package:tsumiru/src/features/about/presentation/about/controllers/about_controller.dart';
import 'package:tsumiru/src/features/history/domain/history_item.dart';
import 'package:tsumiru/src/features/history/presentation/history_controller.dart';
import 'package:tsumiru/src/features/history/presentation/history_screen.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_manga_list.dart';
import 'package:tsumiru/src/features/manga_book/data/updates/updates_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/migration/domain/migration_models.dart';
import 'package:tsumiru/src/features/migration/presentation/screens/migration_source_picker_screen.dart';
import 'package:tsumiru/src/features/quick_open/presentation/unified_search/desktop_search_field.dart';
import 'package:tsumiru/src/features/settings/presentation/more/more_screen.dart';
import 'package:tsumiru/src/features/settings/presentation/settings/settings_screen.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/widgets/desktop/desktop_top_bar.dart';

import '../../../helpers/unreachable_server_stubs.dart';

class _StubReadingHistory extends ReadingHistory {
  @override
  Future<List<HistoryItemDto>?> build() async => const <HistoryItemDto>[];
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

/// Pumps a real page under the shell bar at 1400x900, like the desktop
/// shells draw it. The slot registers under the empty location and the bar
/// shows it, as in the Library harness.
Future<void> _pumpPage(WidgetTester tester, Widget page) async {
  SharedPreferences.setMockInitialValues(const {});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      failedUpdateCountProvider.overrideWithValue(const AsyncData(0)),
      readingHistoryProvider.overrideWith(_StubReadingHistory.new),
      libraryMangaListProvider.overrideWith(
        (ref) async => <Fragment$MangaDto>[_manga(1, 'Alpha 1')],
      ),
      aboutProvider.overrideWithValue(const AsyncData(null)),
      packageInfoProvider.overrideWithValue(
        PackageInfo(
          appName: 'Tsumiru',
          packageName: 'test',
          version: '1',
          buildNumber: '1',
        ),
      ),
      serverHostedWebProvider.overrideWithValue(false),
      ...unreachableServerStubs,
    ],
  );
  addTearDown(container.dispose);
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
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
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => useDesktopTopBar(context)
              ? Scaffold(
                  body: Column(
                    children: [
                      const DesktopTopBar(),
                      Expanded(child: page),
                    ],
                  ),
                )
              : page,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _inBar(Finder finder) => find.descendant(
  of: find.byType(DesktopTopBar),
  matching: finder,
);

void main() {
  group('converted pages draw their toolbar in the shell bar', () {
    testWidgets('More: search field in the bar, no AppBar', (tester) async {
      await _pumpPage(tester, const MoreScreen());
      expect(tester.takeException(), isNull);

      expect(find.byType(DesktopTopBar), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      expect(
        _inBar(find.byType(DesktopSearchField)),
        findsOneWidget,
      );
      final barRect = tester.getRect(find.byType(DesktopTopBar));
      final fieldRect = tester.getRect(
        _inBar(find.byType(DesktopSearchField)),
      );
      expect(barRect.contains(fieldRect.topCenter), isTrue);
      expect(barRect.contains(fieldRect.bottomCenter), isTrue);
    });

    testWidgets('History: search field in the bar, no AppBar', (tester) async {
      await _pumpPage(tester, const HistoryScreen());
      expect(tester.takeException(), isNull);

      expect(find.byType(DesktopTopBar), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      expect(
        _inBar(find.byType(DesktopSearchField)),
        findsOneWidget,
      );
    });

    testWidgets('Settings home: title in the bar, no AppBar', (tester) async {
      await _pumpPage(tester, const SettingsScreen());
      expect(tester.takeException(), isNull);

      expect(find.byType(DesktopTopBar), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      expect(_inBar(find.text('Settings')), findsOneWidget);
    });

    testWidgets('About: title in the bar, no AppBar', (tester) async {
      await _pumpPage(tester, const AboutScreen());
      expect(tester.takeException(), isNull);

      expect(find.byType(DesktopTopBar), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      expect(_inBar(find.text('About')), findsOneWidget);
    });

    testWidgets('migration picker swaps the slot in selection mode', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        const MigrationSourceMangaScreen(
          data: MigrationSourceMangaData(sourceId: '1', sourceName: 'Src'),
        ),
      );
      expect(tester.takeException(), isNull);

      expect(find.byType(DesktopTopBar), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      expect(_inBar(find.text('Src')), findsOneWidget);

      // Long-press selects without navigating: the slot swaps to the
      // close button and the count, like the selection app bar.
      await tester.longPress(find.text('Alpha 1'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      expect(find.byType(AppBar), findsNothing);
      expect(_inBar(find.text('Src')), findsNothing);
      expect(_inBar(find.text('1')), findsOneWidget);
      expect(
        _inBar(find.byIcon(Icons.close)),
        findsOneWidget,
      );
    });
  });
}
