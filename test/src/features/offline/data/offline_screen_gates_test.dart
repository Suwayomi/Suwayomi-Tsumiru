// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/library/data/category_repository.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_controller.dart';
import 'package:tsumiru/src/features/manga_book/data/manga_book/manga_book_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/controller/reader_controller.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_paths.dart';
import 'package:tsumiru/src/features/offline/data/offline_read_fallback.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';

import '../../../../helpers/offline_test_db.dart';

class _ThrowingCategoryRepo implements CategoryRepository {
  @override
  dynamic noSuchMethod(Invocation i) => throw const SocketException('offline');
}

class _ThrowingMangaBookRepo implements MangaBookRepository {
  @override
  dynamic noSuchMethod(Invocation i) => throw const SocketException('offline');
}

/// A server that accepts the request and never answers — the slow-connection
/// shape the reader used to sit on for the full 15 s fallback cap.
class _HangingMangaBookRepo extends Fake implements MangaBookRepository {
  final mangaAnswer = Completer<MangaDto?>();
  final chapterAnswer = Completer<ChapterDto?>();
  int mangaCalls = 0;
  int chapterCalls = 0;

  @override
  Future<MangaDto?> getManga({required int mangaId}) {
    mangaCalls++;
    return mangaAnswer.future;
  }

  @override
  Future<ChapterDto?> getChapter({required int chapterId}) {
    chapterCalls++;
    return chapterAnswer.future;
  }
}

class _Session extends AuthCredentialsStore {
  @override
  Future<AuthCredentialsState> build() async =>
      const AuthCredentialsState.empty();
}

MangaDto _serverManga() => Fragment$MangaDto(
  id: 1,
  title: 'FreshManga',
  chapters: Fragment$MangaDto$chapters(totalCount: 1),
  genre: const [],
  initialized: true,
  sourceId: '1',
  status: Enum$MangaStatus.ONGOING,
  categories: Fragment$MangaDto$categories(nodes: const []),
  trackRecords: Fragment$MangaDto$trackRecords(nodes: const []),
  updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
  meta: const [],
  url: '/manga/1',
  user: Fragment$MangaDto$user(
    bookmarkCount: 0,
    downloadCount: 1,
    inLibrary: true,
    inLibraryAt: '0',
    unreadCount: 0,
  ),
);

ChapterDto _serverChapter() => Fragment$ChapterDto(
  chapterNumber: 5,
  fetchedAt: '0',
  id: 99,
  mangaId: 1,
  name: 'Fresh Chapter',
  pageCount: 1,
  sourceOrder: 5,
  uploadDate: '0',
  url: '/chapter/99',
  meta: const [],
  user: Fragment$ChapterDto$user(
    isBookmarked: false,
    isDownloaded: true,
    isRead: false,
    lastPageRead: 0,
    lastReadAt: '0',
  ),
);

Future<ProviderContainer> _container(
  OfflineDatabase db,
  List<Override> extra,
) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      offlineDatabaseProvider.overrideWithValue(db),
      offlineEnabledProvider.overrideWithValue(true),
      offlineActiveProvider.overrideWithValue(true),
      ...extra,
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  late OfflineDatabase db;
  setUp(() => db = testOfflineDatabase());
  tearDown(() => db.close());

  group('offlineDefaultCategoryDto', () {});

  group('chapterMetaWithOfflineFallback', () {});

  // The bugs Aaron actually hit: the real gating providers must render offline,
  // not just the helpers in isolation.
  test('real gating providers render offline', () async {
    await db.upsertMangaMetadata(
      id: 1,
      title: 'Saved',
      updatedAt: DateTime(2026),
    );
    await db.upsertChapterMetadata(
      id: 99,
      mangaId: 1,
      name: 'Ch99',
      chapterIndex: 5,
      isRead: false,
      lastPageRead: 0,
      isBookmarked: false,
      serverIsDownloaded: true,
      pageCount: 10,
      updatedAt: DateTime(2026),
    );
    await db.setChapterDeviceState(99, OfflineDeviceState.downloaded, bytes: 1);

    final reader = await _container(db, [
      mangaBookRepositoryProvider.overrideWithValue(_ThrowingMangaBookRepo()),
    ]);
    final ch = await reader.read(chapterProvider(chapterId: 99).future);
    expect(ch!.id, 99);
    expect(ch.name, 'Ch99');

    final list = await _container(db, [
      categoryRepositoryProvider.overrideWithValue(_ThrowingCategoryRepo()),
    ]);
    final mangas = await list.read(categoryMangaListProvider(0).future);
    expect(mangas!.map((m) => m.id), [1]);
  });

  // A rating edit with offline viewing on must be what the series screen
  // shows afterwards: the server write mirrors into the offline catalog.
  test('rating edit with offline viewing on is served from the mirror', () async {
    await db.upsertMangaMetadata(
      id: 1,
      title: 'Saved',
      updatedAt: DateTime(2026),
    );
    final client = GraphQLClient(
      link: Link.function((request, [forward]) {
        return Stream.value(
          Response(
            data: const {'__typename': 'Mutation', 'setMangaMeta': null},
            response: const {},
          ),
        );
      }),
      cache: GraphQLCache(),
    );
    final repo = MangaBookRepository(client, readOfflineDb: () => db);
    await repo.patchMangaMeta(
      mangaId: 1,
      key: 'flutter_rating',
      value: '4',
    );
    final served = await mangaWithOfflineFallback(
      fetch: () => throw const SocketException('offline'),
      db: db,
      offlineEnabled: true,
      mangaId: 1,
      offlineFirst: true,
    );
    expect(served?.metaData.rating, 4);
  });

  // A slow connection used to park the reader on its shimmer for the full 15 s
  // fallback cap even though the chapter was complete on the device. The three
  // providers the reader gates on must resolve from the catalog at once, then
  // take the server's answer when it lands.
  test('reader providers open a downloaded chapter from the device, then '
      'refresh from the server', () async {
    await db.upsertMangaMetadata(
      id: 1,
      title: 'Saved',
      updatedAt: DateTime(2026),
    );
    await db.upsertChapterMetadata(
      id: 99,
      mangaId: 1,
      name: 'Ch99',
      chapterIndex: 5,
      isRead: false,
      lastPageRead: 0,
      isBookmarked: false,
      serverIsDownloaded: true,
      pageCount: 1,
      updatedAt: DateTime(2026),
    );
    await db.setChapterDeviceState(99, OfflineDeviceState.downloaded, bytes: 1);
    await db
        .into(db.offlinePages)
        .insert(
          OfflinePagesCompanion.insert(
            chapterId: 99,
            pageIndex: 0,
            relativePath: '1/99/000.jpg',
          ),
        );

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    fakeAsync((async) {
      var repo = _HangingMangaBookRepo();
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          offlineDatabaseProvider.overrideWithValue(db),
          offlinePathsProvider.overrideWithValue(
            const OfflinePaths('/offline'),
          ),
          offlineEnabledProvider.overrideWithValue(true),
          offlineActiveProvider.overrideWithValue(true),
          offlineSyncProvider.overrideWithValue(null),
          authCredentialsStoreProvider.overrideWith(_Session.new),
          mangaBookRepositoryProvider.overrideWith((ref) => repo),
        ],
      );
      addTearDown(c.dispose);
      final subs = [
        c.listen(mangaWithIdProvider(mangaId: 1), (_, _) {}),
        c.listen(chapterProvider(chapterId: 99), (_, _) {}),
        c.listen(chapterPagesProvider(chapterId: 99), (_, _) {}),
      ];
      addTearDown(() {
        for (final sub in subs) {
          sub.close();
        }
      });

      async.flushMicrotasks();

      expect(async.elapsed, lessThan(const Duration(seconds: 15)));
      expect(c.read(mangaWithIdProvider(mangaId: 1)).value?.title, 'Saved');
      expect(c.read(chapterProvider(chapterId: 99)).value?.name, 'Ch99');
      expect(
        c.read(chapterPagesProvider(chapterId: 99)).value?.pages,
        hasLength(1),
      );

      repo.chapterAnswer.complete(_serverChapter());
      repo.mangaAnswer.complete(_serverManga());
      async.flushMicrotasks();

      expect(
        c.read(chapterProvider(chapterId: 99)).value?.name,
        'Fresh Chapter',
      );
      expect(
        c.read(mangaWithIdProvider(mangaId: 1)).value?.title,
        'FreshManga',
      );

      // A new endpoint or custom header rebuilds the repository. The reader's
      // providers must refetch through the new one rather than hold the old
      // answer (and its connection errors) until something else changes.
      repo = _HangingMangaBookRepo();
      c.invalidate(mangaBookRepositoryProvider);
      // The scheduled rebuild and the catalog reads land well inside the 15 s
      // fallback cap.
      async.elapse(const Duration(seconds: 1));

      expect(repo.chapterCalls, 1);
      expect(repo.mangaCalls, 1);
    });
  });
}
