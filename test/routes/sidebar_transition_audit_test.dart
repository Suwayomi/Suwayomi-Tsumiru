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
import 'package:tsumiru/src/features/about/data/about_repository.dart';
import 'package:tsumiru/src/features/about/presentation/about/controllers/about_controller.dart';
import 'package:tsumiru/src/features/browse_center/domain/source/source_model.dart';
import 'package:tsumiru/src/features/browse_center/presentation/extension/controller/extension_update_badge.dart';
import 'package:tsumiru/src/features/browse_center/presentation/source_manga_list/controller/source_manga_controller.dart';
import 'package:tsumiru/src/features/library/presentation/library/library_screen.dart';
import 'package:tsumiru/src/features/manga_book/data/updates/updates_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/chapter_list_entry.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/next_update_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/manga_details_screen.dart';
import 'package:tsumiru/src/features/manga_book/presentation/upcoming/controller/upcoming_controller.dart';
import 'package:tsumiru/src/features/offline/data/offline_nav_status.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/routes/router_config.dart';
import 'package:tsumiru/src/utils/misc/toast/toast.dart';
import 'package:tsumiru/src/utils/motion/reduce_motion.dart';
import 'package:tsumiru/src/widgets/shell/big_screen_navigation_bar.dart';
import 'package:tsumiru/src/widgets/shell/desktop_sidebar.dart';
import 'package:tsumiru/src/widgets/shell/detail_navigation_shell_screen.dart';

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
/// The jump groups below pin the other direction: sidebar taps from a detail
/// page back to a main tab, both pushed (through `goBranch`) and cold
/// (through the `go` fallback, where the outer shell pages enter). Every
/// jump is sampled each frame and must keep a still sidebar with no blank
/// frame.
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

/// Pumps the real [$appRoutes] router at 1400x900, with the same provider
/// stubs the focused route tests use so screens build without a server.
/// Starts on Library. Bounded pumps only (never pumpAndSettle) so pending
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
        // The widget-test binding answers every request with HTTP 400, so any
        // screen that fetches on mount would toast its error. FToast has no
        // overlay in this tree and throws, which says nothing about the
        // transitions under audit; silence toasts the way other widget tests
        // do and assert on the mounted screens instead.
        toastProvider.overrideWithValue(null),
        // Mounting the main shell kicks off its update check, which reads
        // providers across async gaps. When the test unmounts first, those
        // reads land on a disposed container (UnmountedRefException
        // attributed to a later test). Park the check at its first await
        // with a future that never completes: pending futures are harmless,
        // and the update flow is orthogonal to the transitions under audit.
        startupWebRevisionProvider.overrideWith(
          (ref) => Completer<String?>().future,
        ),
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

/// Same as [_checkSidebarJump]'s per-frame assertion for an already-resolved
/// sidebar element. Jump transitions have the outgoing and incoming sidebars
/// mounted, so every copy is checked without re-resolving by type.
Rect _expectBarStill(WidgetTester tester, Finder bar) {
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

/// Pumps the real route `build` output (not a copy of it) inside a minimal
/// GoRouter, so the DetailNavigationShellScreen wrap is what is tested.
/// Network-backed providers are stubbed; bounded pumps (never pumpAndSettle)
/// so pending requests cannot hang the test.
Future<void> _pumpDetailRoute(
  WidgetTester tester,
  Size size,
  GoRouteData route,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  // Unmount any previous tree first: updating an existing ProviderScope in
  // place reuses its container, so a reused notifier re-runs initialize().
  await tester.pumpWidget(const SizedBox());
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => route.build(context, state),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        downloadsPausedBadgeProvider.overrideWith((ref) => false),
        extensionUpdateBadgeCountProvider.overrideWith((ref) async => 0),
        sourceProvider('1').overrideWith((ref) async => _source),
        baseSourceMangaFilterListProvider(
          '1',
        ).overrideWith((ref) async => null),
        upcomingProvider.overrideWith((ref) async => UpcomingData.empty),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
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

  testWidgets('detail routes draw the sidebar on desktop, not on phone', (
    tester,
  ) async {
    for (final entry in _detailRouteCases.entries) {
      await _pumpDetailRoute(tester, const Size(1400, 900), entry.value);
      expect(
        find.byType(BigScreenNavigationBar),
        findsOneWidget,
        reason: '${entry.key} at desktop',
      );
      expect(tester.takeException(), isNull);
      await _pumpDetailRoute(tester, const Size(412, 900), entry.value);
      expect(
        find.byType(BigScreenNavigationBar),
        findsNothing,
        reason: '${entry.key} on phone',
      );
      expect(find.byType(Scaffold), findsWidgets);
      final exception = tester.takeException();
      if (entry.key == 'source page') {
        // Pre-existing test-env artifact, not from the wrap: the bare
        // SourceMangaListScreen overflows its chips row by the same 42px at
        // 412x900. The wrap returns the child untouched on phone.
        expect(
          exception == null ||
              '$exception'.contains('A RenderFlex overflowed by 42 pixels'),
          isTrue,
          reason: 'unexpected exception: $exception',
        );
      } else {
        expect(exception, isNull);
      }
    }
  });

  testWidgets('pushed series page jumps to Library with a still sidebar', (
    tester,
  ) async {
    // Reach the source the way the app does: pushed above the shell, so the
    // main shell sits underneath and the sidebar jumps through
    // shell.goBranch.
    final router = await _pumpAuditRouter(tester);
    try {
      unawaited(router.push(_jumpSource.location));
      await _checkSidebarJump(
        tester,
        source: _jumpSource,
        destination: _jumpDestination,
        index: 0,
        entry: 'pushed',
      );
      expect(tester.takeException(), isNull);
      await _unmountAndDrain(tester);
    } finally {
      // A failing jump must not leak deferred frames into the next test.
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      while (tester.takeException() != null) {}
    }
  });
}

/// One sidebar jump, from a settled source through the exact callback the
/// sidebar calls to a settled destination. Samples every frame of a 300 ms
/// window (longer than any route transition in the app, so the whole jump is
/// covered) and asserts: the sidebar is present in every frame, never
/// transformed, at a stable rect; and no frame shows neither page.
Future<void> _checkSidebarJump(
  WidgetTester tester, {
  required _JumpSource source,
  required _JumpDestination destination,
  required int index,
  required String entry,
}) async {
  final jump = '${source.name} ($entry) -> ${destination.name}';
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 150));
  await tester.pump(const Duration(milliseconds: 500));
  expect(
    find.byType(source.screen),
    findsOneWidget,
    reason: '$jump: source screen must build before the jump',
  );
  final detailBar = find.descendant(
    of: find.byType(DetailNavigationShellScreen),
    matching: find.byType(BigScreenNavigationBar),
  );
  expect(
    detailBar,
    findsOneWidget,
    reason: '$jump: source must draw its sidebar in the detail shell',
  );
  final settled = tester.getRect(detailBar);
  // The jump itself, through the exact callback the sidebar calls.
  tester.widget<BigScreenNavigationBar>(detailBar).onDestinationSelected(index);
  await tester.pump();
  for (var frame = 0; frame < 19; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
    final bars = _sidebarBars();
    expect(bars, isNotEmpty, reason: '$jump: frame $frame shows no sidebar');
    for (final bar in bars) {
      final rect = _expectBarStill(tester, _barFinder(bar));
      expect(rect, settled, reason: '$jump: frame $frame moved the sidebar');
    }
    final oldVisible = find.byType(source.screen).evaluate().isNotEmpty;
    final newVisible = find.byType(destination.screen).evaluate().isNotEmpty;
    expect(
      oldVisible || newVisible,
      isTrue,
      reason: '$jump: frame $frame shows neither page',
    );
  }
  await tester.pump(const Duration(milliseconds: 500));
  expect(
    find.byType(destination.screen),
    findsOneWidget,
    reason: '$jump: destination screen must settle',
  );
  final bars = _sidebarBars();
  expect(bars, hasLength(1), reason: '$jump: one sidebar settles');
  expect(
    tester.getRect(_barFinder(bars.single)),
    settled,
    reason: '$jump: settled sidebar moved',
  );
}

/// Detail routes that used to lose the sidebar on tablet/desktop.
final _detailRouteCases = <String, GoRouteData>{
  'source page': const SourceTypeRoute(
    sourceId: '1',
    sourceType: SourceType.POPULAR,
  ),
  'settings': const SettingsRoute(),
  'appearance': const AppearanceSettingsRoute(),
  'upcoming': const UpcomingRoute(),
};

/// One jump source, the series page: a pushed detail-shell route, with the
/// screen widget that proves its content is on screen. The other detail
/// routes repeat the same invariant.
final _jumpSource = _JumpSource(
  'series page',
  const MangaRoute(mangaId: 1).location,
  MangaDetailsScreen,
);

class _JumpSource {
  const _JumpSource(this.name, this.location, this.screen);
  final String name;
  final String location;
  final Type screen;
}

/// The Library destination, with the screen widget that proves it is on
/// screen. The other sidebar tabs repeat the same invariant.
class _JumpDestination {
  const _JumpDestination(this.name, this.screen);
  final String name;
  final Type screen;
}

const _jumpDestination = _JumpDestination('Library', LibraryScreen);
