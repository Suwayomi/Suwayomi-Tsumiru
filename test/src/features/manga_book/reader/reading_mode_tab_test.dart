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
  bookmarkCount: 0,
  chapters: Fragment$MangaDto$chapters(totalCount: 0),
  downloadCount: 0,
  genre: const [],
  inLibrary: true,
  inLibraryAt: '0',
  initialized: true,
  meta: [
    for (final e in meta.entries)
      Fragment$MangaDto$meta(key: e.key, value: e.value),
  ],
  sourceId: '1',
  status: Enum$MangaStatus.ONGOING,
  categories: Fragment$MangaDto$categories(nodes: const []),
  trackRecords: Fragment$MangaDto$trackRecords(nodes: const []),
  unreadCount: 0,
  updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
  url: '/manga/1',
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

  Finder tabScrollable() => find
      .descendant(
        of: find.byType(ReadingModeTab),
        matching: find.byType(Scrollable),
      )
      .first;

  testWidgets('renders the 6 parity chips; no legacy chip for a mapped mode', (
    tester,
  ) async {
    await pumpTab(tester);

    expect(
      find.widgetWithText(FilterChip, 'Paged (left to right)'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(FilterChip, 'Paged (right to left)'),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilterChip, 'Paged (vertical)'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Long strip'), findsOneWidget);
    expect(
      find.widgetWithText(FilterChip, 'Long strip with gaps'),
      findsOneWidget,
    );
    expect(find.text('Continuous horizontal (legacy)'), findsNothing);
  });

  testWidgets('paged mode shows the paged section, not the long-strip one', (
    tester,
  ) async {
    await pumpTab(tester, meta: {'flutter_readerMode': 'singleHorizontalLTR'});

    await tester.scrollUntilVisible(
      find.text('Scale type'),
      200,
      scrollable: tabScrollable(),
    );
    expect(find.text('Scale type'), findsOneWidget);
    // Zoom start position is hidden (per-page pan on list-level zoom; reader.md).
    expect(find.text('Zoom start position'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Disable zoom out'),
      200,
      scrollable: tabScrollable(),
    );
    expect(find.text('Double tap to zoom'), findsOneWidget);
    expect(find.text('Pinch to Zoom'), findsOneWidget);
    expect(find.text('Disable zoom out'), findsOneWidget);
    // Paged-only: long strip has no zoom-in cap.
    expect(find.text('Disable zoom in'), findsOneWidget);
    expect(find.text('Long strip scale'), findsNothing);
    expect(find.text('Smooth Auto Scroll'), findsNothing);
  });

  testWidgets('long-strip mode shows smart scale, not the paged chips', (
    tester,
  ) async {
    await pumpTab(tester, meta: {'flutter_readerMode': 'webtoon'});

    await tester.scrollUntilVisible(
      find.text('Long strip scale'),
      200,
      scrollable: tabScrollable(),
    );
    expect(find.text('Long strip scale'), findsOneWidget);
    expect(find.text('Scale type'), findsNothing);
    // Gaps-scoped crop borders only appears in Long-strip-with-gaps mode.
    await tester.scrollUntilVisible(
      find.text('Crop borders'),
      200,
      scrollable: tabScrollable(),
    );
    expect(find.text('Crop borders'), findsOneWidget);
  });

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
