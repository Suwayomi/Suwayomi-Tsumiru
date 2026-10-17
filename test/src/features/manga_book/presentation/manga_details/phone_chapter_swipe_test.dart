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
import 'package:tsumiru/src/features/manga_book/data/downloads/downloads_repository.dart';
import 'package:tsumiru/src/features/manga_book/data/manga_book/manga_book_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter_batch/chapter_batch_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/downloads/downloads_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/downloads/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/downloads/controller/downloads_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/chapter_list_entry.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/next_update_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/manga_details_screen.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/utils/theme/brand.dart';

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

class _RecordingDownloads extends DownloadsRepository {
  _RecordingDownloads()
    : super(
        _dummyClient(),
        _dummyClient(),
        permissions: legacyAccountPermissions,
      );

  final queued = <int>[];
  final removed = <int>[];

  @override
  Future<void> addChaptersBatchToDownloadQueue(List<int> chapterIds) async {
    queued.addAll(chapterIds);
  }

  @override
  Future<void> removeChapterFromDownloadQueue(int chapterId) async {
    removed.add(chapterId);
  }
}

class _Session extends AuthCredentialsStore {
  @override
  Future<AuthCredentialsState> build() async =>
      const AuthCredentialsState.empty();
}

DownloadDto _queuedEntry(int id) => Fragment$DownloadDto(
  chapter: Fragment$DownloadDto$chapter(
    id: id,
    name: 'c$id',
    sourceOrder: id,
    isDownloaded: false,
    pageCount: 20,
  ),
  manga: Fragment$DownloadDto$manga(id: 1, title: 'M', downloadCount: 0),
  progress: 0,
  state: DownloadState.QUEUED,
  tries: 0,
  position: 0,
);

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
  _RecordingDownloads? downloads,
  Map<int, DownloadDto> queue = const {},
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
        if (downloads != null)
          downloadsRepositoryProvider.overrideWith((ref) => downloads),
        for (final entry in queue.entries)
          downloadsFromIdProvider(entry.key).overrideWithValue(entry.value),
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
  testWidgets('swipe right past 56px marks an unread chapter read', (
    tester,
  ) async {
    final book = _RecordingBook();
    await _pumpPhone(tester, book: book);
    await _swipe(tester, 'Chapter 4', const Offset(200, 0));
    expect(book.batches, hasLength(1));
    expect(book.batches.single.ids, contains(4));
    expect(book.batches.single.patch.isRead, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('swipe right on a read chapter marks it unread', (tester) async {
    final book = _RecordingBook();
    await _pumpPhone(tester, book: book);
    await _swipe(tester, 'Chapter 1', const Offset(200, 0));
    expect(book.batches, hasLength(1));
    expect(book.batches.single.ids, contains(1));
    expect(book.batches.single.patch.isRead, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('swipe left toggles the bookmark both ways', (tester) async {
    final book = _RecordingBook();
    await _pumpPhone(tester, book: book);
    await _swipe(tester, 'Chapter 4', const Offset(-200, 0));
    expect(book.putCalls, hasLength(1));
    expect(book.putCalls.single.id, 4);
    expect(book.putCalls.single.patch.isBookmarked, isTrue);
    await _swipe(tester, 'Chapter 3', const Offset(-200, 0));
    expect(book.putCalls, hasLength(2));
    expect(book.putCalls.last.id, 3);
    expect(book.putCalls.last.patch.isBookmarked, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('short swipe does nothing', (tester) async {
    final book = _RecordingBook();
    final downloads = _RecordingDownloads();
    await _pumpPhone(tester, book: book, downloads: downloads);
    await _swipe(tester, 'Chapter 4', const Offset(30, 0));
    await _swipe(tester, 'Chapter 4', const Offset(-30, 0));
    expect(book.batches, isEmpty);
    expect(book.putCalls, isEmpty);
    expect(book.deleted, isEmpty);
    expect(downloads.queued, isEmpty);
    expect(downloads.removed, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('swipe is disabled in selection mode', (tester) async {
    final book = _RecordingBook();
    await _pumpPhone(tester, book: book);
    await tester.longPress(find.text('Chapter 2'));
    await tester.pumpAndSettle();
    await _swipe(tester, 'Chapter 4', const Offset(200, 0));
    await _swipe(tester, 'Chapter 4', const Offset(-200, 0));
    expect(book.batches, isEmpty);
    expect(book.putCalls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('prefs change the actions', (tester) async {
    final book = _RecordingBook();
    await _pumpPhone(
      tester,
      book: book,
      prefs: const {'chapterSwipeToLeft': 0},
    );
    await _swipe(tester, 'Chapter 5', const Offset(-200, 0));
    expect(book.batches, hasLength(1));
    expect(book.batches.single.ids, contains(5));
    expect(book.batches.single.patch.isRead, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabled makes that direction inert', (tester) async {
    final book = _RecordingBook();
    await _pumpPhone(
      tester,
      book: book,
      prefs: const {'chapterSwipeToRight': 3, 'chapterSwipeToLeft': 3},
    );
    await _swipe(tester, 'Chapter 4', const Offset(200, 0));
    await _swipe(tester, 'Chapter 4', const Offset(-200, 0));
    expect(book.batches, isEmpty);
    expect(book.putCalls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('download action queues a missing chapter', (tester) async {
    final downloads = _RecordingDownloads();
    await _pumpPhone(
      tester,
      downloads: downloads,
      prefs: const {'chapterSwipeToLeft': 2},
    );
    await _swipe(tester, 'Chapter 4', const Offset(-200, 0));
    expect(downloads.queued, [4]);
    expect(downloads.removed, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('download action cancels a queued chapter', (tester) async {
    final downloads = _RecordingDownloads();
    await _pumpPhone(
      tester,
      downloads: downloads,
      prefs: const {'chapterSwipeToLeft': 2},
      queue: {4: _queuedEntry(4)},
    );
    await _swipe(tester, 'Chapter 4', const Offset(-200, 0));
    expect(downloads.removed, [4]);
    expect(downloads.queued, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('download swipe asks before deleting a downloaded chapter', (
    tester,
  ) async {
    final book = _RecordingBook();
    await _pumpPhone(
      tester,
      book: book,
      prefs: const {'chapterSwipeToLeft': 2},
    );
    await _swipe(tester, 'Chapter 3', const Offset(-200, 0));
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      find.text('Are you sure you want to delete the selected chapters?'),
      findsOneWidget,
    );
    expect(book.deleted, isEmpty);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(book.deleted, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('download swipe deletes once the confirmation is accepted', (
    tester,
  ) async {
    final book = _RecordingBook();
    await _pumpPhone(
      tester,
      book: book,
      prefs: const {'chapterSwipeToLeft': 2},
    );
    await _swipe(tester, 'Chapter 3', const Offset(-200, 0));
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(book.deleted, hasLength(1));
    expect(book.deleted.single, contains(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('bookmarked chapters show a bookmark before the title', (
    tester,
  ) async {
    await _pumpPhone(tester);
    final row = find.byKey(const ValueKey('3'));
    final icon = find.descendant(
      of: row,
      matching: find.byIcon(Icons.bookmark_rounded),
    );
    expect(icon, findsOneWidget);
    expect(
      tester.getCenter(icon).dx,
      lessThan(tester.getTopLeft(find.text('Chapter 3')).dx),
    );
    final plainRow = find.byKey(const ValueKey('4'));
    expect(
      find.descendant(
        of: plainRow,
        matching: find.byIcon(Icons.bookmark_rounded),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('resume never covers the header or the last row', (tester) async {
    await _pumpPhone(tester);
    final fab = tester.getRect(find.byType(BrandFab));
    expect(tester.getRect(find.text('6 Chapters')).overlaps(fab), isFalse);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('6')),
      100,
      scrollable: find.ancestor(
        of: find.byKey(const ValueKey('6')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    final lastRow = tester.getRect(find.byKey(const ValueKey('6')));
    expect(lastRow.bottom, lessThanOrEqualTo(fab.top));
    expect(tester.takeException(), isNull);
  });
}
