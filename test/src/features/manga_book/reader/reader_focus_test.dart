// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter_page/chapter_page_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/reader_wrapper.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

import 'reader_test_fixtures.dart';

void main() {
  testWidgets(
      'arrow key scrolls webtoon after arriving via a slide-transition route push',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();

    var count = 0;
    final navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          getNextAndPreviousChaptersProvider(mangaId: 1, chapterId: 1)
              .overrideWithValue(null),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      ),
    );
    await tester.pump();

    // Mirrors ReaderRoute's real transition (common_routes.dart) so the
    // focus loss it causes (Focus autofocus loses primaryFocus mid-slide)
    // has a chance to reproduce in the widget test harness.
    navigatorKey.currentState!.push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, animation, secondaryAnimation) =>
            ReaderWrapper(
          manga: testManga(),
          chapter: testChapter(),
          chapterPages: ChapterPagesDto(
            chapter: ChapterPagesChapterDto(id: 1, pageCount: 3),
            pages: const ['a', 'b', 'c'],
          ),
          currentIndex: 0,
          onChanged: (_) {},
          onNext: () => count++,
          onPrevious: () {},
          scrollDirection: Axis.vertical,
          effectiveReaderMode: ReaderMode.webtoon,
          child: const SizedBox.shrink(),
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    // No tap / no manual focus — just press the key.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    expect(count, 1);
  });
}
