// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/account/data/account_providers.dart';
import 'package:tsumiru/src/features/browse_center/data/extension_repository/extension_repository.dart';
import 'package:tsumiru/src/features/browse_center/domain/extension/extension_model.dart';
import 'package:tsumiru/src/features/browse_center/domain/source/source_model.dart';
import 'package:tsumiru/src/features/browse_center/presentation/browse/browse_screen.dart';
import 'package:tsumiru/src/features/browse_center/presentation/extension/controller/extension_controller.dart';
import 'package:tsumiru/src/features/browse_center/presentation/extension/extension_screen.dart';
import 'package:tsumiru/src/features/browse_center/presentation/source/controller/source_controller.dart';
import 'package:tsumiru/src/features/browse_center/presentation/source/source_screen.dart';
import 'package:tsumiru/src/features/library/presentation/category/controller/edit_category_controller.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_controller.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_manga_list.dart';
import 'package:tsumiru/src/features/migration/controller/bulk_migration_providers.dart';
import 'package:tsumiru/src/features/migration/presentation/screens/migration_source_picker_screen.dart';
import 'package:tsumiru/src/features/quick_open/presentation/unified_search/desktop_search_field.dart';
import 'package:tsumiru/src/features/quick_open/presentation/unified_search/phone_search_view.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/widgets/search_field.dart';

import '../../../../helpers/fake_extension_repository.dart';
import '../../../../helpers/legacy_account_access.dart';

const _desktop = Size(1400, 980);
const _phone = Size(400, 800);

SourceDto _src({required String id, required String name}) =>
    SourceDto.fromJson({
      'displayName': name,
      'iconUrl': '',
      'id': id,
      'isConfigurable': false,
      'contentWarning': 'SAFE',
      'lang': 'en',
      'name': name,
      'supportsLatest': false,
      '__typename': 'SourceType',
      'meta': const [],
      'extension': {
        'pkgName': 'pkg',
        'repo': 'repo',
        'isObsolete': false,
        '__typename': 'ExtensionType',
      },
    });

Extension _ext({required String pkg, required String name}) => Extension(
  hasUpdate: false,
  iconUrl: '',
  isInstalled: false,
  contentWarning: Enum$ContentWarning.SAFE,
  isObsolete: false,
  lang: 'en',
  name: name,
  pkgName: pkg,
  // ignore: deprecated_member_use_from_same_package
  versionCode: 1,
  versionName: '1.0',
);

Future<ProviderContainer> _pumpBrowse(
  WidgetTester tester, {
  required Size size,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final sources = [
    _src(id: '1', name: 'Asura Scans'),
    _src(id: '2', name: 'Flame Scans'),
  ];
  final extensions = [
    _ext(pkg: 'a', name: 'Alpha Extension'),
    _ext(pkg: 'b', name: 'Beta Extension'),
  ];
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      settledAccountAccessProvider.overrideWithValue(legacyAccountAccess),
      extensionRepositoryProvider.overrideWithValue(FakeExtensionRepository()),
      libraryMangaListProvider.overrideWith((ref) async => []),
      libraryTagListProvider.overrideWithValue(const AsyncData(<String>[])),
      visibleCategoryListProvider.overrideWithValue(const AsyncData([])),
      sourceListProvider.overrideWith((ref) async => <SourceDto>[]),
      sourceMapFilteredProvider.overrideWithValue(
        AsyncData(<String, List<SourceDto>>{'en': sources}),
      ),
      pinnedSourcesProvider.overrideWithValue(const <SourceDto>[]),
      searchableSourcesProvider.overrideWithValue(
        const AsyncData(<SourceDto>[]),
      ),
      extensionMapFilteredProvider.overrideWithValue(
        AsyncData(<String, List<Extension>>{'en': extensions}),
      ),
      librarySourceGroupsProvider.overrideWith((ref) async => []),
    ],
  );
  addTearDown(container.dispose);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BrowseScreen(
          currentIndex: 0,
          onDestinationSelected: (_) {},
          children: const [
            SourceScreen(),
            ExtensionScreen(),
            MigrationSourcePickerBody(hideInnerSearchOnDesktop: true),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Finder _topField() => find.descendant(
  of: find.byType(DesktopSearchField),
  matching: find.byType(TextField),
);

/// Unmounts the tree while its container is still alive, so the search
/// field's deferred focus-node unregister reads a live provider instead of
/// throwing on the disposed container in the next test.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
}

void main() {
  group('Browse desktop search', () {
    testWidgets('top box filters the Sources list live', (tester) async {
      final container = await _pumpBrowse(tester, size: _desktop);
      expect(tester.takeException(), isNull);

      expect(find.text('Asura Scans'), findsOneWidget);
      expect(find.text('Flame Scans'), findsOneWidget);

      final field = tester.widget<TextField>(_topField());
      expect(field.decoration?.hintText, 'Search sources...');

      await tester.enterText(_topField(), 'asura');
      await tester.pump();
      expect(tester.takeException(), isNull);

      expect(container.read(sourceSearchQueryProvider), 'asura');
      expect(find.text('Asura Scans'), findsOneWidget);
      expect(find.text('Flame Scans'), findsNothing);

      await _unmount(tester);
    });

    testWidgets('switching tabs shows that tab filter; top box filters '
        'the Extensions list', (tester) async {
      final container = await _pumpBrowse(tester, size: _desktop);

      await tester.enterText(_topField(), 'asura');
      await tester.pump();

      // The open dropdown overlaps the tab bar; Esc closes it and keeps
      // the text so the tap below lands on the tab, not a result row.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      await tester.tap(find.text('Extensions'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      var field = tester.widget<TextField>(_topField());
      expect(field.decoration?.hintText, 'Search extensions...');
      expect(field.controller?.text, isEmpty);

      expect(find.text('Alpha Extension'), findsOneWidget);
      expect(find.text('Beta Extension'), findsOneWidget);

      await tester.enterText(_topField(), 'beta');
      await tester.pump();

      expect(container.read(extensionQueryProvider), 'beta');
      expect(find.text('Beta Extension'), findsOneWidget);
      expect(find.text('Alpha Extension'), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      await tester.tap(find.text('Sources'));
      await tester.pumpAndSettle();

      field = tester.widget<TextField>(_topField());
      expect(field.decoration?.hintText, 'Search sources...');
      expect(field.controller?.text, 'asura');
      expect(find.text('Asura Scans'), findsOneWidget);
      expect(find.text('Flame Scans'), findsNothing);

      await _unmount(tester);
    });

    testWidgets('inner boxes are absent on desktop', (tester) async {
      await _pumpBrowse(tester, size: _desktop);
      expect(tester.takeException(), isNull);
      expect(find.byType(DesktopSearchField), findsOneWidget);
      // Sources tab is active: its inner box is gone.
      expect(find.text('Asura Scans'), findsOneWidget);
      expect(find.byType(SearchField), findsNothing);

      // Tabs build lazily, so visit each one and assert while active.
      await tester.tap(find.text('Extensions'));
      await tester.pumpAndSettle();
      expect(find.text('Beta Extension'), findsOneWidget);
      expect(find.byType(SearchField), findsNothing);

      await tester.tap(find.text('Migrate'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(SearchField), findsNothing);

      await _unmount(tester);
    });

    testWidgets('inner boxes stay on phone', (tester) async {
      await _pumpBrowse(tester, size: _phone);
      expect(tester.takeException(), isNull);
      expect(find.byType(DesktopSearchField), findsNothing);
      // Sources searches from the app-bar entry.
      expect(find.byType(PhoneSearchEntry), findsOneWidget);

      await tester.tap(find.text('Extensions'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // The Extensions tab keeps its live box.
      expect(find.byType(SearchField), findsWidgets);

      await _unmount(tester);
    });

    testWidgets(
      'in-between layout keeps the global search button; phone/desktop hide it',
      (tester) async {
        await _pumpBrowse(tester, size: const Size(915, 412));
        expect(tester.takeException(), isNull);
        expect(
          find.widgetWithIcon(IconButton, Icons.travel_explore_rounded),
          findsOneWidget,
        );
        await _unmount(tester);

        await _pumpBrowse(tester, size: _phone);
        expect(tester.takeException(), isNull);
        expect(
          find.widgetWithIcon(IconButton, Icons.travel_explore_rounded),
          findsNothing,
        );
        await _unmount(tester);

        await _pumpBrowse(tester, size: _desktop);
        expect(tester.takeException(), isNull);
        expect(
          find.widgetWithIcon(IconButton, Icons.travel_explore_rounded),
          findsNothing,
        );
        await _unmount(tester);
      },
    );

    testWidgets('tapping the in-between-layout button opens Global Search', (
      tester,
    ) async {
      await _pumpBrowseInRouter(tester, size: const Size(915, 412));
      expect(tester.takeException(), isNull);
      expect(
        find.widgetWithIcon(IconButton, Icons.travel_explore_rounded),
        findsOneWidget,
      );

      await tester.tap(
        find.widgetWithIcon(IconButton, Icons.travel_explore_rounded),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('GLOBAL SEARCH'), findsOneWidget);

      await _unmount(tester);
    });
  });
}

/// Same providers as [_pumpBrowse], but inside a router so the tablet
/// Global Search button's [openGlobalSearch] push lands on a real route.
Future<void> _pumpBrowseInRouter(
  WidgetTester tester, {
  required Size size,
}) async {
  final container = await _pumpBrowse(tester, size: size);
  final router = GoRouter(
    initialLocation: '/browse',
    routes: [
      GoRoute(
        path: '/browse',
        builder: (context, state) => BrowseScreen(
          currentIndex: 0,
          onDestinationSelected: (_) {},
          children: const [
            SourceScreen(),
            ExtensionScreen(),
            MigrationSourcePickerBody(hideInnerSearchOnDesktop: true),
          ],
        ),
      ),
      GoRoute(
        path: '/global-search',
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('GLOBAL SEARCH'))),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}
