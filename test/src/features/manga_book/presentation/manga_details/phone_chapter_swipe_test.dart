// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/account/data/account_providers.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/manga_book/data/manga_book/manga_book_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter_batch/chapter_batch_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/downloads/controller/downloads_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/chapter_list_entry.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/next_update_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/manga_details_screen.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

import '../../../../../helpers/legacy_account_access.dart';

GraphQLClient _dummyClient() =>
    GraphQLClient(link: HttpLink('http://localhost:0'), cache: GraphQLCache());

class _RecordingBook extends MangaBookRepository {
  _RecordingBook() : super(_dummyClient());

  final batches = <ChapterBatch>[];
  final putCalls = <({int id, ChapterChange patch})>[];
  final deleted = <List<int>>[];

  @override
  Future<void> modifyBulkChapters(ChapterBatch batch) async {
    batches.add(batch);
  }

  @override
  Future<void> putChapter({
    required int chapterId,
    required ChapterChange patch,
  }) async {
    putCalls.add((id: chapterId, patch: patch));
  }

  @override
  Future<void> deleteChapters(List<int> chapterIds) async {
    deleted.add(chapterIds);
  }
}

class _Session extends AuthCredentialsStore {
  @override
  Future<AuthCredentialsState> build() async =>
      const AuthCredentialsState.empty();
}

ChapterDto _chapter({
  required int id,
  bool read = false,
  bool bookmarked = false,
  bool downloaded = false,
}) => ChapterDto(
  chapterNumber: id.toDouble(),
  fetchedAt: '0',
  id: id,
  isBookmarked: bookmarked,
  isDownloaded: downloaded,
  isRead: read,
  lastPageRead: 0,
  lastReadAt: read ? '1' : '0',
  mangaId: 1,
  name: 'Chapter $id',
  pageCount: 20,
  realUrl: null,
  scanlator: 'Group A',
  sourceOrder: id,
  uploadDate: '0',
  url: '',
  meta: const [],
);

final _chapters = [
  _chapter(id: 1, read: true),
  _chapter(id: 2),
  _chapter(id: 3, bookmarked: true, downloaded: true),
  _chapter(id: 4),
  _chapter(id: 5),
  _chapter(id: 6),
];

final _manga = MangaDto.fromJson({
  '__typename': 'MangaType',
  'id': 1,
  'title': 'Test series',
  'author': 'An author',
  'bookmarkCount': 0,
  'chapters': {'totalCount': 6, '__typename': 'ChapterNodeList'},
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
  'unreadCount': 5,
  'updateStrategy': 'ALWAYS_UPDATE',
  'url': '',
});

class _Manga extends MangaWithId {
  @override
  Future<MangaDto?> build({required int mangaId}) async => _manga;
  @override
  Future<void> refresh([bool onlineFetch = false]) async {}
}

class _Chapters extends MangaChapterList {
  @override
  Future<List<ChapterDto>?> build({required int mangaId}) async => _chapters;
  @override
  Future<void> refresh([bool onlineFetch = false]) async {}
}

Future<void> _pumpPhone(
  WidgetTester tester, {
  Map<String, Object> prefs = const {},
  _RecordingBook? book,
}) async {
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues(prefs);
  final preferences = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        offlineEnabledProvider.overrideWithValue(false),
        settledAccountAccessProvider.overrideWithValue(legacyAccountAccess),
        authCredentialsStoreProvider.overrideWith(_Session.new),
        downloadUpdatesProvider.overrideWith((ref) => const Stream.empty()),
        downloadStatusProvider.overrideWith((ref) async => null),
        if (book != null)
          mangaBookRepositoryProvider.overrideWith((ref) => book),
        mangaWithIdProvider(mangaId: 1).overrideWith(_Manga.new),
        mangaChapterListProvider(mangaId: 1).overrideWith(_Chapters.new),
        mangaChapterListWithFilterProvider(
          mangaId: 1,
        ).overrideWith((ref) => AsyncData(_chapters)),
        mangaChapterListEntriesProvider(mangaId: 1).overrideWith(
          (ref) => AsyncData([for (final c in _chapters) MangaChapterEntry(c)]),
        ),
        firstUnreadInFilteredChapterListProvider(
          mangaId: 1,
        ).overrideWith((ref) => _chapters[1]),
        mangaNextUpdateProvider(mangaId: 1).overrideWith((ref) => null),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: MangaDetailsScreen(mangaId: 1)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _swipe(WidgetTester tester, String label, Offset delta) async {
  await tester.drag(find.text(label), delta);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('swipe right marks an unread chapter read and a read one unread', (
    tester,
  ) async {
    final book = _RecordingBook();
    await _pumpPhone(tester, book: book);
    await _swipe(tester, 'Chapter 4', const Offset(200, 0));
    expect(book.batches, hasLength(1));
    expect(book.batches.single.ids, contains(4));
    expect(book.batches.single.patch.isRead, isTrue);

    await _swipe(tester, 'Chapter 1', const Offset(200, 0));
    expect(book.batches, hasLength(2));
    expect(book.batches.last.ids, contains(1));
    expect(book.batches.last.patch.isRead, isFalse);
    expect(tester.takeException(), isNull);
  });
}
