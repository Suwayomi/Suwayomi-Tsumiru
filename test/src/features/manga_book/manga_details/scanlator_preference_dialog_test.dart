// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/manga_book/data/manga_book/manga_book_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/widgets/scanlator_preference_dialog.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

import 'chapter_test_helpers.dart';

GraphQLClient _dummyClient() => GraphQLClient(
      link: HttpLink('http://localhost:0'),
      cache: GraphQLCache(),
    );

class _RecordingRepo extends MangaBookRepository {
  _RecordingRepo() : super(_dummyClient());
  final List<(int, String, dynamic)> patched = [];
  @override
  Future<void> patchMangaMeta({
    required int mangaId,
    required String key,
    required dynamic value,
  }) async {
    patched.add((mangaId, key, value));
  }
}

class _FailingRepo extends MangaBookRepository {
  _FailingRepo() : super(_dummyClient());
  @override
  Future<void> patchMangaMeta({
    required int mangaId,
    required String key,
    required dynamic value,
  }) async {
    throw Exception('server write failed');
  }
}

/// A manga seeded with the given meta entries. keepAlive matches the real
/// provider — without it the fake disposes between pre-warm and dialog open.
class _FakeMangaWithId extends MangaWithId {
  _FakeMangaWithId(this.meta);
  final Map<String, String> meta;
  @override
  Future<MangaDto?> build({required int mangaId}) async {
    ref.keepAlive();
    return _manga(mangaId);
  }

  Fragment$MangaDto _manga(int mangaId) => Fragment$MangaDto(
        id: mangaId,
        title: 'M',
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
        trackRecords:
            Fragment$MangaDto$trackRecords(totalCount: 0, nodes: const []),
        unreadCount: 0,
        updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
        url: '/manga/$mangaId',
      );
}

class _FixedChapterList extends MangaChapterList {
  _FixedChapterList(this.chapters);
  final List<ChapterDto> chapters;
  @override
  Future<List<ChapterDto>?> build({required int mangaId}) async {
    ref.keepAlive();
    return chapters;
  }
}

class _DialogHost extends ConsumerWidget {
  const _DialogHost();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => const ScanlatorPreferenceDialog(mangaId: 1),
          ),
          child: const Text('open'),
        ),
      ),
    );
  }
}

void main() {
  // number 1: A copy, B copy; number 2: no scanlator (Unknown group).
  final chapters = [
    ch(id: 1, number: 1, scanlator: 'A'),
    ch(id: 2, number: 1, scanlator: 'B'),
    ch(id: 3, number: 2, scanlator: null),
  ];

  Future<T> pumpDialog<T extends MangaBookRepository>(
    WidgetTester tester, {
    required T repo,
    List<String> preference = const ['B'],
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          mangaBookRepositoryProvider.overrideWithValue(repo),
          offlineActiveProvider.overrideWithValue(false),
          mangaChapterListProvider(mangaId: 1)
              .overrideWith(() => _FixedChapterList(chapters)),
          mangaWithIdProvider(mangaId: 1).overrideWith(
            () => _FakeMangaWithId({
              'flutter_preferredScanlators': jsonEncode(preference),
            }),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const _DialogHost(),
        ),
      ),
    );

    // Resolve the manga before opening: in the app the details screen has
    // long since loaded it (keepAlive), so the dialog never sees a loading
    // preference. Without this the draft rank list seeds from [].
    final container =
        ProviderScope.containerOf(tester.element(find.byType(_DialogHost)));
    await container.read(mangaWithIdProvider(mangaId: 1).future);
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(ScanlatorPreferenceDialog), findsOneWidget);
    return repo;
  }

  testWidgets('renders all three groups; B ranked, blank shown as Unknown',
      (tester) async {
    await pumpDialog(tester, repo: _RecordingRepo());

    expect(find.byType(CheckboxListTile), findsNWidgets(3));
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    expect(find.text('Unknown'), findsOneWidget);

    final rankedTile = tester
        .widget<CheckboxListTile>(find.byKey(const ValueKey('ranked-B')));
    expect(rankedTile.value, isTrue);
  });

  testWidgets('checking A then saving persists the new rank order',
      (tester) async {
    final repo = await pumpDialog(tester, repo: _RecordingRepo());

    await tester.tap(find.byKey(const ValueKey('unranked-A')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(
      repo.patched,
      contains((1, 'flutter_preferredScanlators', '["B","A"]')),
    );
    expect(find.byType(ScanlatorPreferenceDialog), findsNothing);
  });

  testWidgets('a failed server write keeps the dialog open',
      (tester) async {
    await pumpDialog(tester, repo: _FailingRepo());

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.byType(ScanlatorPreferenceDialog), findsOneWidget);
  });
}
