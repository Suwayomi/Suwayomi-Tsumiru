// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/about/presentation/about/controllers/about_controller.dart';
import 'package:tsumiru/src/features/browse_center/domain/source/source_model.dart';
import 'package:tsumiru/src/features/browse_center/presentation/extension/controller/extension_update_badge.dart';
import 'package:tsumiru/src/features/browse_center/presentation/source_manga_list/controller/source_manga_controller.dart';
import 'package:tsumiru/src/features/manga_book/data/updates/updates_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/chapter_list_entry.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/next_update_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/upcoming/controller/upcoming_controller.dart';
import 'package:tsumiru/src/features/migration/domain/migration_models.dart';
import 'package:tsumiru/src/features/offline/data/offline_nav_status.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/routes/router_config.dart';
import 'package:tsumiru/src/utils/motion/reduce_motion.dart';
import 'package:tsumiru/src/widgets/shell/big_screen_navigation_bar.dart';
import 'package:tsumiru/src/widgets/shell/desktop_sidebar.dart';

/// Exhaustive sidebar-transition audit: every route the app's router defines
/// is walked from the real [$appRoutes] tree (never hand-listed), navigated
/// to the way the app navigates to it, and checked mid-transition at
/// 1400x900: wherever the destination keeps the sidebar, the sidebar must not
/// scale or slide and must already sit at its final rect.
///
/// Background: pushed routes that draw their own sidebar copy inside
/// [DetailNavigationShellScreen] used the default zoom transition, so the
/// sidebar visibly jumped with the page. The fix is the shared fade helper
/// ([detailNavigationPage]) for pushed detail routes and instant pages for
/// main-shell branch switches. This test pins that for every route, so the
/// bug cannot come back anywhere else.
///
/// Excluded, one line each:
/// - ReaderRoute (/manga/:mangaId/chapter/:chapterId): full-screen reader by
///   design, no sidebar on either side.
/// - OnboardingRoute (/onboarding): full-screen first-run wizard by design.
class _AuditedRoute {
  const _AuditedRoute({required this.pattern, required this.push});
  final String pattern;
  // True when the app reaches the route with push (detail/more/settings
  // pages above the main shell); false for main-shell branch tabs reached
  // with go.
  final bool push;
}

bool _isExcluded(String pattern) =>
    pattern == '/onboarding' || pattern.contains('/chapter/');

/// Recursively walks [$appRoutes] through shell routes and sub-routes.
/// A route reached through a [StatefulShellBranch] on its branch navigator
/// (no parent navigator key) is a tab the app switches to with go;
/// everything else is pushed above the shell.
List<_AuditedRoute> _walkAppRoutes() {
  final out = <_AuditedRoute>[];
  void visit(List<RouteBase> routes, String parent, bool inBranch) {
    for (final route in routes) {
      if (route is GoRoute) {
        final full = route.path.startsWith('/')
            ? route.path
            : '$parent/${route.path}';
        final pattern = full.replaceAll(RegExp('/+'), '/');
        out.add(
          _AuditedRoute(
            pattern: pattern,
            push: route.parentNavigatorKey != null || !inBranch,
          ),
        );
        visit(route.routes, pattern, inBranch);
      } else if (route is ShellRoute) {
        visit(route.routes, parent, false);
      } else if (route is StatefulShellRoute) {
        for (final branch in route.branches) {
          visit(branch.routes, parent, true);
        }
      }
    }
  }
  visit($appRoutes, '', false);
  return out;
}

/// Fills required path params with plausible values. All query params in the
/// tree are optional, so none are needed.
String _concreteLocation(String pattern) => pattern
    .replaceAll(':categoryId', '0')
    .replaceAll(':chapterId', '2')
    .replaceAll(':mangaId', '1')
    .replaceAll(':providerName', 'test')
    .replaceAll(':sourceType', 'p-o-p-u-l-a-r')
    .replaceAll(':sourceId', '1');

/// Extra payloads for routes that pop themselves without one.
Object? _extraFor(String location) {
  if (location == '/migration/global-search') {
    return MigrationRouteData(
      sourceManga: Fragment$MangaDto(
        bookmarkCount: 0,
        chapters: Fragment$MangaDto$chapters(totalCount: 0),
        downloadCount: 0,
        genre: const ['Action'],
        id: 1,
        inLibrary: true,
        inLibraryAt: '0',
        initialized: true,
        meta: const [],
        sourceId: '0',
        status: Enum$MangaStatus.ONGOING,
        title: 'A series',
        categories: Fragment$MangaDto$categories(nodes: const []),
        trackRecords: Fragment$MangaDto$trackRecords(nodes: const []),
        unreadCount: 0,
        updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
        url: '',
      ),
    );
  }
  if (location == '/migration/bulk-config') {
    return MigrationBulkConfigData(mangaIds: const [1]);
  }
  if (location == '/migration/bulk-run') {
    return MigrationBulkRunData(
      mangaIds: const [1],
      targetSourceIds: const ['1'],
      options: const MigrationOption(),
    );
  }
  if (location == '/migration/source-manga') {
    return const MigrationSourceMangaData(
      sourceId: '1',
      sourceName: 'Test',
    );
  }
  return null;
}

final _source = SourceDto.fromJson({
  'displayName': 'Weeb Central (EN)',
  'iconUrl': '',
  'id': '1',
  'isConfigurable': false,
  'contentWarning': 'SAFE',
  'lang': 'en',
  'name': 'Weeb Central (EN)',
  'supportsLatest': true,
  '__typename': 'SourceType',
  'meta': [],
  'extension': {
    'pkgName': 'pkg',
    'repo': 'repo',
    'isObsolete': false,
    '__typename': 'ExtensionType',
  },
});

final _manga = MangaDto.fromJson({
  '__typename': 'MangaType',
  'id': 1,
  'title': 'A series',
  'author': 'An author',
  'bookmarkCount': 0,
  'chapters': {'totalCount': 0, '__typename': 'ChapterNodeList'},
  'downloadCount': 0,
  'genre': ['Action'],
  'inLibrary': true,
  'inLibraryAt': '0',
  'initialized': true,
  'meta': [],
  'sourceId': '0',
  'status': 'ONGOING',
  'categories': {'nodes': [], '__typename': 'CategoryNodeList'},
  'trackRecords': {'nodes': [], '__typename': 'TrackRecordNodeList'},
  'unreadCount': 0,
  'updateStrategy': 'ALWAYS_UPDATE',
  'url': '',
  'lastReadChapter': {
    '__typename': 'ChapterType',
    'id': 2,
    'isRead': false,
    'lastPageRead': 3,
    'lastReadAt': '1',
  },
});

final _chapter = ChapterDto(
  chapterNumber: 1,
  fetchedAt: '0',
  id: 2,
  isBookmarked: false,
  isDownloaded: false,
  isRead: false,
  lastPageRead: 3,
  lastReadAt: '1',
  mangaId: 1,
  name: 'Chapter 1',
  pageCount: 20,
  sourceOrder: 1,
  uploadDate: '0',
  url: '',
  meta: [],
);

class _Manga extends MangaWithId {
  @override
  Future<MangaDto?> build({required int mangaId}) async => _manga;
  @override
  Future<void> refresh([bool onlineFetch = false]) async {}
}

class _Chapters extends MangaChapterList {
  @override
  Future<List<ChapterDto>?> build({required int mangaId}) async => [_chapter];
  @override
  Future<void> refresh([bool onlineFetch = false]) async {}
}

/// Pumps the real [$appRoutes] router at 1400x900 starting on Library, with
/// the same provider stubs the focused route tests use so screens build
/// without a server. Bounded pumps only (never pumpAndSettle) so pending
/// requests cannot hang the test.
Future<GoRouter> _pumpAuditRouter(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final router = GoRouter(
    initialLocation: const LibraryRoute(categoryId: 0).location,
    navigatorKey: rootNavigatorKey,
    routes: $appRoutes,
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
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
        upcomingProvider.overrideWith((ref) async => UpcomingData.empty),
        failedUpdatesProvider.overrideWith((ref) async => <MangaDto>[]),
        sourceProvider('1').overrideWith((ref) async => _source),
        baseSourceMangaFilterListProvider(
          '1',
        ).overrideWith((ref) async => null),
        mangaWithIdProvider(mangaId: 1).overrideWith(_Manga.new),
        mangaChapterListProvider(mangaId: 1).overrideWith(_Chapters.new),
        mangaChapterListWithFilterProvider(
          mangaId: 1,
        ).overrideWith((ref) => AsyncData([_chapter])),
        mangaChapterListEntriesProvider(
          mangaId: 1,
        ).overrideWith((ref) => AsyncData([MangaChapterEntry(_chapter)])),
        firstUnreadInFilteredChapterListProvider(
          mangaId: 1,
        ).overrideWith((ref) => _chapter),
        mangaNextUpdateProvider(mangaId: 1).overrideWith((ref) => null),
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
  await tester.pump(const Duration(milliseconds: 100));
  return router;
}

/// All sidebar widgets currently mounted. At 1400x900 the wide layout wraps
/// the [DesktopSidebar] in a [BigScreenNavigationBar]; a bare
/// [DesktopSidebar] only counts when it has no such ancestor.
List<Element> _sidebarBars() {
  final bars = [...find.byType(BigScreenNavigationBar).evaluate()];
  for (final bar in find.byType(DesktopSidebar).evaluate()) {
    final insideRail = find
        .ancestor(
          of: find.byWidget(bar.widget),
          matching: find.byType(BigScreenNavigationBar),
        )
        .evaluate()
        .isNotEmpty;
    if (!insideRail) bars.add(bar);
  }
  return bars;
}

/// Finder for exactly one sidebar [Element]. Element identity is used
/// throughout: a push rebuilds the covered page (new widget instances, same
/// elements), and [ModalRoute.isCurrent] is true for the top route of every
/// nested [Navigator], so neither widgets nor current flags can tell the
/// incoming page from the covered one.
Finder _barFinder(Element bar) =>
    find.byElementPredicate((candidate) => identical(candidate, bar));

/// The pushed destination sidebar: the bar element that was not mounted
/// before the push.
Element _pushedDestination(Set<Element> home) {
  final fresh = _sidebarBars().where((bar) => !home.contains(bar)).toList();
  expect(
    fresh,
    hasLength(1),
    reason: 'pushed destination must add exactly one sidebar copy',
  );
  return fresh.single;
}

/// Asserts [bar] is untransformed mid-transition and returns its rect so
/// callers can compare against the settled rect. Settled transition
/// scaffolding above the sidebar (offset zero, scale one) is inert and
/// allowed; anything actually displacing the sidebar fails.
Rect _expectSidebarStill(WidgetTester tester, Finder bar) {
  expect(bar, findsOneWidget);
  for (final scale in tester.widgetList<ScaleTransition>(
    find.ancestor(of: bar, matching: find.byType(ScaleTransition)),
  )) {
    expect(
      scale.scale.value,
      1.0,
      reason: 'sidebar must not scale during the transition',
    );
  }
  for (final slide in tester.widgetList<SlideTransition>(
    find.ancestor(of: bar, matching: find.byType(SlideTransition)),
  )) {
    expect(
      slide.position.value,
      Offset.zero,
      reason: 'sidebar must not slide during the transition',
    );
  }
  for (final transform in tester.widgetList<Transform>(
    find.ancestor(of: bar, matching: find.byType(Transform)),
  )) {
    expect(
      transform.transform.getMaxScaleOnAxis(),
      1.0,
      reason: 'sidebar must not scale during the transition',
    );
  }
  return tester.getRect(bar);
}

Future<void> _expectSettledAt(
  WidgetTester tester,
  Finder resolve,
  Rect during,
) async {
  await tester.pump(const Duration(milliseconds: 75));
  await tester.pump(const Duration(milliseconds: 500));
  expect(tester.getRect(resolve), during);
}

/// Unmounts the test tree and flushes deferred callbacks before the test
/// ends. DesktopSearchField unregisters its focus node in a post-frame
/// callback; at teardown that frame can land after the provider container is
/// disposed, which throws a StateError with no bearing on the transitions
/// already asserted above. Drain exactly that artifact, nothing else.
Future<void> _unmountAndDrain(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  Object? exception = tester.takeException();
  while (exception != null) {
    expect(
      '$exception'.contains('after `dispose` was called') &&
          '$exception'.contains('StateController'),
      isTrue,
      reason: 'unexpected exception during teardown: $exception',
    );
    exception = tester.takeException();
  }
}

void main() {
  test('audit walks every route the router defines', () {
    final routes = _walkAppRoutes();
    final patterns = routes.map((r) => r.pattern).toList();
    // Spot-check the walk itself so a silently empty tree cannot pass.
    for (final expected in [
      '/library/:categoryId',
      '/updates',
      '/history',
      '/source',
      '/extension',
      '/migrate',
      '/downloads',
      '/more',
      '/more/settings',
      '/more/settings/library/edit-categories',
      '/more/account/users',
      '/source/:sourceId/preference',
      '/source/:sourceId/:sourceType',
      '/manga/:mangaId',
      '/upcoming',
      '/global-search',
      '/migration/bulk-run',
    ]) {
      expect(patterns, contains(expected), reason: 'walk missed $expected');
    }
    final checked = routes.where((r) => !_isExcluded(r.pattern)).toList();
    debugPrint(
      'sidebar audit: ${routes.length} routes walked, '
      '${checked.length} checked, '
      '${routes.length - checked.length} excluded by design',
    );
  });

  final routes = _walkAppRoutes()
      .where((r) => !_isExcluded(r.pattern))
      .toList();

  group('every route keeps the sidebar still at 1400x900', () {
    for (final route in routes) {
      final location = _concreteLocation(route.pattern);
      // Starting point is Library itself; pushing it onto itself tests no
      // transition, so it is covered by the branch-switch test below.
      if (location == const LibraryRoute(categoryId: 0).location) continue;
      testWidgets('${route.pattern} (${route.push ? 'push' : 'go'})', (
        tester,
      ) async {
        final router = await _pumpAuditRouter(tester);
        // The Library sidebar mounted at start; a push must add exactly one
        // copy of it, and a pop must reveal this same one again.
        final home = _sidebarBars().toSet();
        expect(home, hasLength(1));
        try {
          if (route.push) {
            unawaited(router.push(location, extra: _extraFor(location)));
          } else {
            router.go(location);
          }
          await tester.pump();
          // Half-way through the 150 ms fade.
          await tester.pump(const Duration(milliseconds: 75));

          final Element destination;
          if (route.push) {
            destination = _pushedDestination(home);
          } else {
            final bars = _sidebarBars();
            expect(bars, hasLength(1));
            destination = bars.single;
          }
          final Finder bar = _barFinder(destination);
          final during = _expectSidebarStill(tester, bar);
          // Pushed detail pages fade instead of zooming: the sidebar's page
          // is the shared fade, never the default zoom.
          if (route.push) {
            final modal = ModalRoute.of(tester.element(bar));
            expect(modal, isA<PageRoute>());
            expect(
              modal!.settings,
              isA<CustomTransitionPage>(),
              reason: 'pushed route must use the shared fade page',
            );
          }
          await _expectSettledAt(tester, _barFinder(destination), during);

          if (route.push) {
            router.pop();
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 75));
            final revealed = _barFinder(home.single);
            final back = _expectSidebarStill(tester, revealed);
            await _expectSettledAt(tester, revealed, back);
          }
          expect(tester.takeException(), isNull);
          await _unmountAndDrain(tester);
        } finally {
          // A failing route must not leak deferred frames into the next test.
          await tester.pumpWidget(const SizedBox());
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          while (tester.takeException() != null) {}
        }
      });
    }
  });

  testWidgets('main sidebar destinations never transform the sidebar', (
    tester,
  ) async {
    final router = await _pumpAuditRouter(tester);
    const destinations = [
      LibraryRoute(categoryId: 0),
      UpdatesRoute(),
      HistoryTabRoute(),
      BrowseSourceRoute(),
      DownloadsRoute(),
      MoreRoute(),
    ];
    for (final destination in destinations) {
      router.go(destination.location);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 75));
      final bars = _sidebarBars();
      expect(bars, hasLength(1));
      final bar = _barFinder(bars.single);
      final during = _expectSidebarStill(tester, bar);
      // Re-resolve by type: switching tabs rebuilds the shell around a new
      // sidebar instance, but there is always exactly one of it.
      await _expectSettledAt(
        tester,
        find.byType(BigScreenNavigationBar),
        during,
      );
    }
    expect(tester.takeException(), isNull);
    await _unmountAndDrain(tester);
  });
}
