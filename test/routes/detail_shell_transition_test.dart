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
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/browse_center/presentation/extension/controller/extension_update_badge.dart';
import 'package:tsumiru/src/features/manga_book/data/updates/updates_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/chapter_list_entry.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/next_update_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/upcoming/controller/upcoming_controller.dart';
import 'package:tsumiru/src/features/offline/data/offline_nav_status.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/routes/router_config.dart';
import 'package:tsumiru/src/utils/motion/reduce_motion.dart';
import 'package:tsumiru/src/widgets/shell/big_screen_navigation_bar.dart';

class _ReduceMotionOn extends AppReduceMotion {
  @override
  bool build() => true;
}

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

/// Minimal router around the real [DetailNavigationShellRoute.pageBuilder]
/// and the real detail route builds, so the pages (and their transitions)
/// under test are the ones the app uses. Bounded pumps only
/// (never pumpAndSettle) so pending requests cannot hang the test.
Future<GoRouter> _pumpRouter(
  WidgetTester tester, {
  required Size size,
  bool reduceMotion = false,
  String initialLocation = '/',
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({'showRecommendations': false});
  final preferences = await SharedPreferences.getInstance();
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('home'))),
      ),
      ShellRoute(
        pageBuilder: (context, state, navigator) =>
            const DetailNavigationShellRoute().pageBuilder(
              context,
              state,
              navigator,
            ),
        routes: [
          GoRoute(
            path: '/manga/:mangaId',
            builder: (context, state) =>
                const MangaRoute(mangaId: 1).build(context, state),
          ),
          GoRoute(
            path: '/library-update-errors',
            builder: (context, state) =>
                const LibraryUpdateErrorsRoute().build(context, state),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (reduceMotion)
          appReduceMotionProvider.overrideWith(_ReduceMotionOn.new),
        sharedPreferencesProvider.overrideWithValue(preferences),
        offlineEnabledProvider.overrideWithValue(false),
        downloadsPausedBadgeProvider.overrideWith((ref) => false),
        extensionUpdateBadgeCountProvider.overrideWith((ref) async => 0),
        upcomingProvider.overrideWith((ref) async => UpcomingData.empty),
        failedUpdatesProvider.overrideWith((ref) async => <MangaDto>[]),
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

void _expectSidebarStill(WidgetTester tester) {
  final navBar = find.byType(BigScreenNavigationBar);
  expect(navBar, findsOneWidget);
  expect(
    find.ancestor(of: navBar, matching: find.byType(ScaleTransition)),
    findsNothing,
  );
  for (final transform in tester.widgetList<Transform>(
    find.ancestor(of: navBar, matching: find.byType(Transform)),
  )) {
    expect(transform.transform.getMaxScaleOnAxis(), 1.0);
  }
}

void main() {
  testWidgets(
    'series page fades without scaling the sidebar at 1400x900',
    (tester) async {
      final router = await _pumpRouter(
        tester,
        size: const Size(1400, 900),
      );
      unawaited(router.push(const MangaRoute(mangaId: 1).location));
      await tester.pump();
      // Half-way through the 150 ms transition.
      await tester.pump(const Duration(milliseconds: 75));

      _expectSidebarStill(tester);

      final fades = tester.widgetList<FadeTransition>(
        find.ancestor(
          of: find.byType(BigScreenNavigationBar),
          matching: find.byType(FadeTransition),
        ),
      );
      expect(fades, isNotEmpty);
      // Mid-transition: the fade is actually in flight, not instant.
      expect(
        fades.any((f) => f.opacity.value > 0.0 && f.opacity.value < 1.0),
        isTrue,
      );

      // The sidebar never moves: same rect mid-transition and after.
      final during = tester.getRect(find.byType(BigScreenNavigationBar));
      await tester.pump(const Duration(milliseconds: 75));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.getRect(find.byType(BigScreenNavigationBar)), during);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'moving within the detail shell does not zoom the sidebar at 1400x900',
    (tester) async {
      final router = await _pumpRouter(
        tester,
        size: const Size(1400, 900),
        initialLocation: const MangaRoute(mangaId: 1).location,
      );
      await tester.pump(const Duration(milliseconds: 500));
      final before = tester.getRect(find.byType(BigScreenNavigationBar));

      unawaited(router.push(const LibraryUpdateErrorsRoute().location));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 75));

      _expectSidebarStill(tester);
      expect(tester.getRect(find.byType(BigScreenNavigationBar)), before);
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'series page keeps the default MaterialPage transition at 412x900',
    (tester) async {
      final router = await _pumpRouter(tester, size: const Size(412, 900));
      unawaited(router.push(const MangaRoute(mangaId: 1).location));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(BigScreenNavigationBar), findsNothing);
      final route = ModalRoute.of(
        tester.element(find.textContaining('Chapter 1')),
      );
      expect(route, isA<PageRoute>());
      expect(route!.settings, isA<MaterialPage>());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'series page shows instantly with reduced motion at 1400x900',
    (tester) async {
      final router = await _pumpRouter(
        tester,
        size: const Size(1400, 900),
        reduceMotion: true,
      );
      unawaited(router.push(const MangaRoute(mangaId: 1).location));
      // The pushed route is built on the frame after insertion; with a
      // zero-length transition it is already settled then.
      await tester.pump();
      await tester.pump();

      final navBar = find.byType(BigScreenNavigationBar);
      expect(navBar, findsOneWidget);
      // No fade in flight: the zero-length transition settles at once. (The
      // series screen itself may keep content animations running; only the
      // route transition must be still.)
      expect(
        find.ancestor(of: navBar, matching: find.byType(FadeTransition)),
        findsNothing,
      );
      final firstFrame = tester.getRect(navBar);
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.getRect(navBar), firstFrame);
      expect(tester.takeException(), isNull);
    },
  );
}
