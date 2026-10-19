// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Resizing across the 600 px breakpoint must update every route in place,
// never replace it: the detail pages (and the outer shells) share one page
// identity on both sides so no exiting copy stacks up. Flipping the page
// type with the width replaced all routes on every crossing, and flipping
// back inside the exit transition wedged the Navigator update — a slow drag
// through 600 px froze release builds at 100% main-thread CPU.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/about/data/about_repository.dart';
import 'package:tsumiru/src/features/about/presentation/about/controllers/about_controller.dart';
import 'package:tsumiru/src/features/browse_center/presentation/extension/controller/extension_update_badge.dart';
import 'package:tsumiru/src/features/library/domain/category/category_model.dart';
import 'package:tsumiru/src/features/library/domain/category/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/library/presentation/category/controller/edit_category_controller.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_manga_list.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/offline/data/offline_nav_status.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/routes/router_config.dart';
import 'package:tsumiru/src/utils/misc/toast/toast.dart';
import 'package:tsumiru/src/utils/motion/reduce_motion.dart';
import 'package:tsumiru/src/widgets/shell/navigation_shell_screen.dart';

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

Fragment$CategoryDto _cat(int id, String name) => Fragment$CategoryDto(
  id: id,
  name: name,
  order: id,
  defaultCategory: false,
  includeInDownload: Enum$IncludeOrExclude.UNSET,
  includeInUpdate: Enum$IncludeOrExclude.UNSET,
  mangas: Fragment$CategoryDto$mangas(totalCount: 1),
  meta: const [],
);

class _CategoryList extends CategoryController {
  _CategoryList(this.categories);
  final List<CategoryDto> categories;
  @override
  Future<List<CategoryDto>?> build() async => categories;
}

/// Pumps the real [$appRoutes] router on Library at 1400x900, with the same
/// provider stubs the route audit uses so screens build without a server.
/// Bounded pumps only (never pumpAndSettle) so pending requests cannot hang
/// the test.
Future<GoRouter> _pumpRouter(WidgetTester tester) async {
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
  SharedPreferences.setMockInitialValues(const {});
  final prefs = await SharedPreferences.getInstance();
  final router = GoRouter(
    initialLocation: const LibraryRoute(categoryId: 0).location,
    navigatorKey: rootNavigatorKey,
    routes: $appRoutes,
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        toastProvider.overrideWithValue(null),
        startupWebRevisionProvider.overrideWith(
          (ref) => Completer<String?>().future,
        ),
        sharedPreferencesProvider.overrideWithValue(prefs),
        packageInfoProvider.overrideWithValue(
          PackageInfo(
            appName: 'Tsumiru',
            packageName: 'test',
            version: '1',
            buildNumber: '1',
          ),
        ),
        offlineEnabledProvider.overrideWithValue(false),
        downloadsPausedBadgeProvider.overrideWith((ref) => false),
        extensionUpdateBadgeCountProvider.overrideWith((ref) async => 0),
        categoryControllerProvider.overrideWith(
          () => _CategoryList([_cat(1, 'A'), _cat(2, 'B')]),
        ),
        libraryMangaListProvider.overrideWith(
          (ref) async => <Fragment$MangaDto>[_manga(1, 'Alpha 1')],
        ),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => ReduceMotionScope(child: child!),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return router;
}

Future<void> _resize(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 900);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  testWidgets('resizing across 600 px replaces no routes', (tester) async {
    await _pumpRouter(tester);
    expect(tester.takeException(), isNull);

    final shell = find.byType(NavigationShellScreen).evaluate().single;
    final route = ModalRoute.of(shell);

    // Down through the breakpoint: phone layout, same shell and route.
    await _resize(tester, 599);
    expect(
      tester.takeException(),
      isNull,
      reason: 'crossing below 600 must not throw',
    );
    final below = find.byType(NavigationShellScreen).evaluate();
    expect(below, hasLength(1), reason: 'no exiting shell copy may stack up');
    expect(identical(below.single, shell), isTrue);
    expect(ModalRoute.of(below.single), same(route));

    // Back up: desktop layout, still the same shell and route.
    await _resize(tester, 600);
    expect(
      tester.takeException(),
      isNull,
      reason: 'crossing back to 600 must not throw',
    );
    final above = find.byType(NavigationShellScreen).evaluate();
    expect(above, hasLength(1));
    expect(identical(above.single, shell), isTrue);
    expect(ModalRoute.of(above.single), same(route));
  });

  testWidgets('rapid flips across 600 px settle without stacking shells', (
    tester,
  ) async {
    await _pumpRouter(tester);
    expect(tester.takeException(), isNull);

    // Pointer jitter around the breakpoint during a slow drag: every flip
    // lands inside the previous transition. Each step is one frame, so a
    // wedged Navigator update hangs here instead of passing.
    for (final w in [599.0, 600.0, 599.0, 600.0, 599.0, 600.0]) {
      tester.view.physicalSize = Size(w, 900);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        tester.takeException(),
        isNull,
        reason: 'flip to $w must not throw',
      );
    }
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    expect(find.byType(NavigationShellScreen), findsOneWidget);
  });

  testWidgets('resizing across 1200 px keeps the single shell', (
    tester,
  ) async {
    await _pumpRouter(tester);
    expect(tester.takeException(), isNull);

    final shell = find.byType(NavigationShellScreen).evaluate().single;
    for (final w in [1199.0, 1200.0, 1400.0]) {
      await _resize(tester, w);
      expect(tester.takeException(), isNull, reason: 'at width $w');
      final shells = find.byType(NavigationShellScreen).evaluate();
      expect(shells, hasLength(1), reason: 'at width $w');
      expect(identical(shells.single, shell), isTrue);
    }
  });
}
