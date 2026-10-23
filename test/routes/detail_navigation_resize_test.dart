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
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/about/data/about_repository.dart';
import 'package:tsumiru/src/features/about/presentation/about/controllers/about_controller.dart';
import 'package:tsumiru/src/features/account/domain/account_binding.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/browse_center/presentation/extension/controller/extension_update_badge.dart';
import 'package:tsumiru/src/features/browse_center/presentation/source/controller/source_controller.dart';
import 'package:tsumiru/src/features/library/domain/category/category_model.dart';
import 'package:tsumiru/src/features/library/domain/category/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/library/presentation/category/controller/edit_category_controller.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_manga_list.dart';
import 'package:tsumiru/src/features/manga_book/data/manga_book/manga_book_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/migration/domain/migration_models.dart';
import 'package:tsumiru/src/features/migration/presentation/screens/migration_bulk_run_screen.dart';
import 'package:tsumiru/src/features/offline/data/background/catchup_work_spec.dart';
import 'package:tsumiru/src/features/offline/data/offline_nav_status.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/features/offline/data/offline_server_identity_repository.dart';
import 'package:tsumiru/src/features/settings/presentation/settings/settings_window.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/routes/router_config.dart';
import 'package:tsumiru/src/utils/misc/toast/toast.dart';
import 'package:tsumiru/src/utils/motion/reduce_motion.dart';
import 'package:tsumiru/src/utils/platform/platform_runtime.dart';
import 'package:tsumiru/src/widgets/desktop/desktop_window_scaffold.dart';
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

class _MigrationSession extends AuthCredentialsStore {
  @override
  Future<AuthCredentialsState> build() async => const AuthCredentialsState(
    accountBinding: AccountBinding(
      address: 'http://server',
      username: 'a',
      userId: 1,
      catalogId: 'a',
    ),
  );
}

/// No chapters, so the migration runner's per-target fetch has nothing to do.
class _EmptyChapters extends MangaBookRepository {
  _EmptyChapters(super.client);
  @override
  Future<List<ChapterDto>?> getChapterList(int mangaId) async => [];
  @override
  Future<List<ChapterDto>?> getStoredChapterList(int mangaId) async => [];
}

/// Pumps the real [$appRoutes] router on Library at 1400x900, with the same
/// provider stubs the route audit uses so screens build without a server.
/// Bounded pumps only (never pumpAndSettle) so pending requests cannot hang
/// the test.
Future<GoRouter> _pumpRouter(
  WidgetTester tester, {
  bool withDesktopScaffold = false,
}) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  debugDesktopPlatformOverride = true;
  addTearDown(() => debugDesktopPlatformOverride = null);
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
  SharedPreferences.setMockInitialValues({
    CatchupStateStore.identityAuthorizedKey: true,
  });
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
        authCredentialsStoreProvider.overrideWith(_MigrationSession.new),
        authTypeKeyProvider.overrideWithValue(AuthType.none),
        serverInstanceIdProvider.overrideWith((ref) async => 'server-id'),
        mangaBookRepositoryProvider.overrideWith(
          (ref) => _EmptyChapters(
            GraphQLClient(
              link: HttpLink('http://localhost:0'),
              cache: GraphQLCache(),
            ),
          ),
        ),
        searchableSourcesProvider.overrideWithValue(const AsyncValue.data([])),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => ReduceMotionScope(
          child: withDesktopScaffold
              ? DesktopWindowScaffold(child: child!)
              : child!,
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return router;
}

void main() {
  testWidgets('rapid flips across 600 px settle without stacking shells', (
    tester,
  ) async {
    await _pumpRouter(tester);
    expect(tester.takeException(), isNull);

    final shell = find.byType(NavigationShellScreen).evaluate().single;
    final route = ModalRoute.of(shell);

    // Pointer jitter around the breakpoint during a slow drag: every flip
    // lands inside the previous transition. Each step is one frame, so a
    // wedged Navigator update hangs here instead of passing. Both crossings
    // (down and back up) must keep the same shell and route.
    for (final w in [599.0, 600.0, 599.0, 600.0, 599.0, 600.0]) {
      tester.view.physicalSize = Size(w, 900);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        tester.takeException(),
        isNull,
        reason: 'flip to $w must not throw',
      );
      final shells = find.byType(NavigationShellScreen).evaluate();
      expect(shells, hasLength(1), reason: 'at width $w');
      expect(identical(shells.single, shell), isTrue);
      expect(ModalRoute.of(shells.single), same(route));
    }
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    expect(find.byType(NavigationShellScreen), findsOneWidget);
  });

  testWidgets('resizing keeps the migration route and its extra', (
    tester,
  ) async {
    final router = await _pumpRouter(tester, withDesktopScaffold: true);
    final data = MigrationBulkRunData(
      mangaIds: [1],
      targetSourceIds: const [],
      options: MigrationOption(),
    );
    router.push(MigrationBulkRunRoute($extra: data).location, extra: data);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(MigrationBulkRunScreen), findsOneWidget);
    final l10n = AppLocalizations.of(
      tester.element(find.byType(MigrationBulkRunScreen)),
    )!;

    // The desktop window scaffold used to move the Router in the tree on
    // resize; the router then re-parsed its serialized route info, dropped
    // the non-JSON extra, and the migration screen popped to the page below.
    for (final size in [
      const Size(599, 900),
      const Size(601, 900),
      const Size(1199, 900),
      const Size(1400, 900),
      const Size(1400, 599),
      const Size(1400, 900),
    ]) {
      tester.view.physicalSize = size;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull, reason: 'at $size');
      expect(
        router.state.matchedLocation,
        Routes.migrationBulkRun,
        reason: 'at $size',
      );
      expect(
        find.byType(MigrationBulkRunScreen),
        findsOneWidget,
        reason: 'at $size',
      );
      expect(
        find.text(l10n.migrationDataUnavailable),
        findsNothing,
        reason: 'at $size',
      );
    }

    // Let the runner wind down with the screen before the tree is disposed.
    router.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('settings page list fits at 1000 by 720 without scrolling', (
    tester,
  ) async {
    final router = await _pumpRouter(tester, withDesktopScaffold: true);
    tester.view.physicalSize = const Size(1000, 720);
    router.push(const SettingsRoute().location);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byKey(const ValueKey('settingsWindow'))),
      const Size(936, 672),
    );
    final list = find.byKey(const ValueKey('settingsWindowPageList'));
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: list, matching: find.byType(Scrollable)).first,
    );
    expect(scrollable.position.maxScrollExtent, 0);
    expect(scrollable.position.viewportDimension, 616);
    final viewport = tester.renderObject<RenderViewport>(
      find.descendant(of: list, matching: find.byType(Viewport)),
    );
    final contentHeight = viewport.firstChild!.geometry!.scrollExtent;
    expect(contentHeight, 576);
    debugPrint(
      'Settings list: content $contentHeight, viewport ${scrollable.position.viewportDimension}, maxScrollExtent ${scrollable.position.maxScrollExtent}',
    );
    expect(find.byType(SettingsWindowPageList), findsOneWidget);
  });

  testWidgets(
    'settings Esc and close restore the previous route after nested navigation',
    (tester) async {
      final router = await _pumpRouter(tester);
      final previous = tester.element(find.byType(NavigationShellScreen));
      final previousRoute = ModalRoute.of(previous);
      final previousLocation = router.state.uri;
      for (final escape in [false, true]) {
        router.push(const LibrarySettingsRoute().location);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        router.push(const EditCategoriesRoute().location);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(SettingsWindowPageList), findsOneWidget);
        expect(find.byType(BackButton), findsWidgets);
        if (escape) {
          await tester.tap(find.byType(TextField).first);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        } else {
          await tester.tap(find.byType(CloseButton));
        }
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        expect(router.state.uri, previousLocation);
        expect(find.byType(SettingsWindowPageList), findsNothing);
        expect(
          tester.element(find.byType(NavigationShellScreen)),
          same(previous),
        );
        expect(ModalRoute.of(previous), same(previousRoute));
      }
    },
  );
}
