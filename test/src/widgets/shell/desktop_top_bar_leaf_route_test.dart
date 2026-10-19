// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// P1: pushing a page inside the detail shell (series -> Suggestions) must
// move the desktop top bar to the pushed page's toolbar, and popping must
// restore the series toolbar. The host bar sits in the shell above its
// Navigator, so keying the slot by the shell's matchedLocation keeps showing
// the previous page after a push.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/browse_center/presentation/extension/controller/extension_update_badge.dart';
import 'package:tsumiru/src/features/manga_book/data/recommendations/recommendation_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/next_update_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/manga_details_screen.dart';
import 'package:tsumiru/src/features/manga_book/presentation/recommends/recommends_screen.dart';
import 'package:tsumiru/src/features/offline/data/offline_nav_status.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/widgets/desktop/desktop_top_bar.dart';

final _manga = Fragment$MangaDto(
  id: 1,
  title: 'Leaf route series title',
  thumbnailUrl: null,
  bookmarkCount: 0,
  chapters: Fragment$MangaDto$chapters(totalCount: 0),
  downloadCount: 0,
  genre: const [],
  inLibrary: true,
  inLibraryAt: '0',
  initialized: true,
  meta: const [],
  sourceId: '0',
  status: Enum$MangaStatus.ONGOING,
  categories: Fragment$MangaDto$categories(nodes: const []),
  trackRecords: Fragment$MangaDto$trackRecords(nodes: const []),
  unreadCount: 0,
  updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
  url: '',
);

class _Manga extends MangaWithId {
  @override
  Future<MangaDto?> build({required int mangaId}) async => _manga;
  @override
  Future<void> refresh([bool onlineFetch = false]) async {}
}

class _Chapters extends MangaChapterList {
  @override
  Future<List<ChapterDto>?> build({required int mangaId}) async =>
      const <ChapterDto>[];
  @override
  Future<void> refresh([bool onlineFetch = false]) async {}
}

Finder _inBar(Finder finder) => find.descendant(
  of: find.byType(DesktopTopBar),
  matching: finder,
);

void main() {
  testWidgets(
    'push inside the detail shell moves the bar to the leaf, pop restores',
    (tester) async {
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
        () => TestDefaultBinaryMessengerBinding
            .instance
            .defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('window_manager'),
              null,
            ),
      );
      SharedPreferences.setMockInitialValues({'showRecommendations': false});
      final prefs = await SharedPreferences.getInstance();
      final router = GoRouter(
        initialLocation: '/manga/1',
        routes: [
          ShellRoute(
            builder: (context, state, child) => Scaffold(
              body: Column(
                children: [
                  if (useDesktopTopBar(context)) const DesktopTopBar(),
                  Expanded(child: child),
                ],
              ),
            ),
            routes: [
              GoRoute(
                path: '/manga/:mangaId',
                builder: (_, _) => const MangaDetailsScreen(mangaId: 1),
              ),
              GoRoute(
                path: '/recommends/:mangaId',
                builder: (_, _) =>
                    const RecommendsScreen(mangaId: 1, mangaTitle: 'Alpha'),
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            downloadsPausedBadgeProvider.overrideWith((ref) => false),
            extensionUpdateBadgeCountProvider.overrideWith((ref) async => 0),
            offlineEnabledProvider.overrideWithValue(false),
            mangaWithIdProvider(mangaId: 1).overrideWith(_Manga.new),
            mangaChapterListProvider(mangaId: 1).overrideWith(_Chapters.new),
            mangaChapterListWithFilterProvider(
              mangaId: 1,
            ).overrideWith((ref) => const AsyncData([])),
            mangaChapterListEntriesProvider(
              mangaId: 1,
            ).overrideWith((ref) => const AsyncData([])),
            firstUnreadInFilteredChapterListProvider(
              mangaId: 1,
            ).overrideWith((ref) => null),
            mangaNextUpdateProvider(mangaId: 1).overrideWith((ref) => null),
            recommendationSetupProvider(
              1,
            ).overrideWith((ref) async => null),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DesktopTopBar), findsOneWidget);
      expect(_inBar(find.text(_manga.title)), findsOneWidget);

      router.push('/recommends/1');
      await tester.pumpAndSettle();

      expect(_inBar(find.text('Similar to Alpha')), findsOneWidget);
      expect(_inBar(find.text(_manga.title)), findsNothing);

      router.pop();
      await tester.pumpAndSettle();

      expect(_inBar(find.text(_manga.title)), findsOneWidget);
      expect(_inBar(find.text('Similar to Alpha')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
