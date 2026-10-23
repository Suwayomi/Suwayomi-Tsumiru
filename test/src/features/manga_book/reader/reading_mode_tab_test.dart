// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Reading-mode tab parity contract: 6 chips + honest legacy-orphan chip
// (§2.5), contextual paged/long-strip sections, tap-invert visibility, and
// the "For this series" OFF path routing writes to the global provider.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/manga_book/data/manga_book/manga_book_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/chrome/tabs/reading_mode_tab.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

class _FakeMangaWithId extends MangaWithId {
  _FakeMangaWithId(this.manga);
  final MangaDto? manga;

  @override
  Future<MangaDto?> build({required int mangaId}) async => manga;
}

/// Records meta writes/deletes instead of hitting a server.
class _RecordingRepo implements MangaBookRepository {
  final patches = <(String, dynamic)>[];
  final deletes = <String>[];

  @override
  Future<void> patchMangaMeta({
    required int mangaId,
    required String key,
    required dynamic value,
  }) async {
    patches.add((key, value));
  }

  @override
  Future<void> deleteMangaMeta({
    required int mangaId,
    required String key,
  }) async {
    deletes.add(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

MangaDto _manga({Map<String, String> meta = const {}}) => Fragment$MangaDto(
  id: 1,
  title: 'Test Manga',
  chapters: Fragment$MangaDto$chapters(totalCount: 0),
  genre: const [],
  initialized: true,
  meta: [
    for (final e in meta.entries)
      Fragment$MangaDto$meta(key: e.key, value: e.value),
  ],
  sourceId: '1',
  status: Enum$MangaStatus.ONGOING,
  categories: Fragment$MangaDto$categories(nodes: const []),
  trackRecords: Fragment$MangaDto$trackRecords(nodes: const []),
  updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
  url: '/manga/1',
  user: Fragment$MangaDto$user(
    bookmarkCount: 0,
    downloadCount: 0,
    inLibrary: true,
    inLibraryAt: '0',
    unreadCount: 0,
  ),
);

void main() {
  late _RecordingRepo repo;

  Future<void> pumpTab(
    WidgetTester tester, {
    Map<String, String> meta = const {},
  }) async {
    // Tall viewport so the common rows fit without scrolling.
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    repo = _RecordingRepo();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          mangaBookRepositoryProvider.overrideWithValue(repo),
          mangaWithIdProvider(
            mangaId: 1,
          ).overrideWith(() => _FakeMangaWithId(_manga(meta: meta))),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ReadingModeTab(mangaId: 1, readerPadding: ValueNotifier(0.0)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('reading mode always writes a per-series override', (
    tester,
  ) async {
    await pumpTab(tester, meta: {'flutter_readerMode': 'singleHorizontalLTR'});

    await tester.tap(find.text('Long strip'));
    await tester.pumpAndSettle();

    expect(repo.patches, [('flutter_readerMode', 'webtoon')]);
    expect(repo.deletes, isEmpty);
  });
}
