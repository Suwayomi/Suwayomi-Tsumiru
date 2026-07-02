// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// "Always show chapter transition": ON renders the full prev/next
// transition (label + chapter name); OFF collapses to a slim label only.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/chapter_separator.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

MangaDto _manga() => Fragment$MangaDto(
      id: 1,
      title: 'Test Manga',
      bookmarkCount: 0,
      chapters: Fragment$MangaDto$chapters(totalCount: 0),
      downloadCount: 0,
      genre: const [],
      inLibrary: true,
      inLibraryAt: '0',
      initialized: true,
      meta: const [],
      sourceId: '1',
      status: Enum$MangaStatus.ONGOING,
      categories: Fragment$MangaDto$categories(nodes: const []),
      trackRecords:
          Fragment$MangaDto$trackRecords(totalCount: 0, nodes: const []),
      unreadCount: 0,
      updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
      url: '/manga/1',
    );

ChapterDto _chapter() => Fragment$ChapterDto(
      chapterNumber: 1,
      fetchedAt: '0',
      id: 1,
      isBookmarked: false,
      isDownloaded: false,
      isRead: false,
      lastPageRead: 0,
      lastReadAt: '0',
      mangaId: 1,
      name: 'Chapter 1',
      pageCount: 3,
      sourceOrder: 1,
      uploadDate: '0',
      url: '/chapter/1',
      meta: const [],
    );

Future<void> _pump(WidgetTester tester, {required bool alwaysShow}) async {
  SharedPreferences.setMockInitialValues(const {});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        // Neighbour lookup null → no nav buttons; isolates the label/name test.
        getNextAndPreviousChaptersProvider(mangaId: 1, chapterId: 1)
            .overrideWithValue(null),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ChapterSeparator(
            manga: _manga(),
            chapter: _chapter(),
            isPreviousChapterSeparator: true,
            alwaysShow: alwaysShow,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('chapter transition separator', () {
    testWidgets('ON (default) shows the full transition with chapter name',
        (tester) async {
      await _pump(tester, alwaysShow: true);
      expect(find.text('Chapter 1'), findsOneWidget);
    });

    testWidgets('OFF minimizes: slim label only, no chapter name',
        (tester) async {
      await _pump(tester, alwaysShow: false);
      expect(find.text('Chapter 1'), findsNothing);
      // Collapsed form renders exactly one Text (the start/finished label).
      expect(find.byType(Text), findsOneWidget);
    });
  });
}
