// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/manga_book/data/manga_book/manga_book_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter_batch/chapter_batch_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/chapter_list_entry.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/next_update_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/manga_details_screen.dart';
import 'package:tsumiru/src/features/manga_book/widgets/chapter_actions/multi_chapters_actions_bottom_app_bar.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/utils/misc/toast/toast.dart';
import 'package:tsumiru/src/widgets/desktop/desktop_top_bar.dart';

ChapterDto _chapter({
  required int id,
  bool read = false,
  bool bookmarked = false,
  bool downloaded = false,
  String? scanlator = 'Group A',
  int lastPageRead = 0,
  int pageCount = 20,
  String? realUrl,
}) => ChapterDto(
  chapterNumber: id.toDouble(),
  fetchedAt: '0',
  id: id,
  isBookmarked: bookmarked,
  isDownloaded: downloaded,
  isRead: read,
  lastPageRead: lastPageRead,
  lastReadAt: read ? '1' : '0',
  mangaId: 1,
  name: 'Chapter $id',
  pageCount: pageCount,
  realUrl: realUrl,
  scanlator: scanlator,
  sourceOrder: id,
  uploadDate: '0',
  url: '',
  meta: const [],
);

final _chapters = [
  _chapter(id: 1, read: true),
  // Current chapter: first unread, with reading progress.
  _chapter(id: 2, lastPageRead: 4, realUrl: 'https://example.com/c2'),
  // Downloaded + bookmarked + unknown scanlator.
  _chapter(
    id: 3,
    bookmarked: true,
    downloaded: true,
    scanlator: null,
    lastPageRead: 5,
    pageCount: 30,
    realUrl: 'https://example.com/c3',
  ),
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
  _Chapters(this.chapters);
  final List<ChapterDto> chapters;
  @override
  Future<List<ChapterDto>?> build({required int mangaId}) async => chapters;
  @override
  Future<void> refresh([bool onlineFetch = false]) async {}
}

class _RecordingBook extends MangaBookRepository {
  _RecordingBook()
    : super(
        GraphQLClient(
          link: HttpLink('http://localhost:0'),
          cache: GraphQLCache(),
        ),
      );

  final batches = <ChapterBatch>[];
  final putCalls = <({int id, ChapterChange patch})>[];

  @override
  Future<void> modifyBulkChapters(ChapterBatch batch) async =>
      batches.add(batch);

  @override
  Future<void> putChapter({
    required int chapterId,
    required ChapterChange patch,
  }) async => putCalls.add((id: chapterId, patch: patch));
}

class _Session extends AuthCredentialsStore {
  @override
  Future<AuthCredentialsState> build() async =>
      const AuthCredentialsState.empty();
}

class _FakeToast implements Toast {
  String? undoLabel;
  VoidCallback? undo;

  @override
  void showWithAction(
    String msg, {
    required String actionLabel,
    required VoidCallback onAction,
    Duration duration = const Duration(seconds: 5),
  }) {
    undoLabel = actionLabel;
    undo = onAction;
  }

  @override
  void show(
    String msg, {
    bool withMicrotask = false,
    bool instantShow = false,
  }) {}

  @override
  void showError(
    String error, {
    bool withMicrotask = false,
    bool instantShow = false,
  }) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(
  SharedPreferences preferences, {
  List<Override> overrides = const [],
  List<ChapterDto>? chapters,
}) {
  final list = chapters ?? _chapters;
  return ProviderScope(
    overrides: [
      ...overrides,
      sharedPreferencesProvider.overrideWithValue(preferences),
      offlineEnabledProvider.overrideWithValue(false),
      mangaWithIdProvider(mangaId: 1).overrideWith(_Manga.new),
      mangaChapterListProvider(mangaId: 1).overrideWith(() => _Chapters(list)),
      mangaChapterListWithFilterProvider(
        mangaId: 1,
      ).overrideWith((ref) => AsyncData(list)),
      mangaChapterListEntriesProvider(mangaId: 1).overrideWith(
        (ref) => AsyncData([for (final c in list) MangaChapterEntry(c)]),
      ),
      firstUnreadInFilteredChapterListProvider(
        mangaId: 1,
      ).overrideWith((ref) => list[list.length > 1 ? 1 : 0]),
      mangaNextUpdateProvider(mangaId: 1).overrideWith((ref) => null),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // Native desktop draws the back button and title in the shell bar
      // above the page.
      home: Scaffold(
        body: Builder(
          builder: (context) => Column(
            children: [
              if (showsMergedTopBar(context)) const DesktopTopBar(),
              const Expanded(child: MangaDetailsScreen(mangaId: 1)),
            ],
          ),
        ),
      ),
    ),
  );
}

void _mockWindowManager() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('window_manager'), (
        call,
      ) async {
        if (call.method == 'isMaximized') return false;
        return null;
      });
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), null),
  );
}

Future<void> _pumpDesktop(
  WidgetTester tester, {
  Size size = const Size(1400, 980),
  List<Override> overrides = const [],
  List<ChapterDto>? chapters,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  _mockWindowManager();
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    _app(preferences, overrides: overrides, chapters: chapters),
  );
  await tester.pumpAndSettle();
}

Future<void> _selectRange(WidgetTester tester, String from, String to) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.tap(find.text(from));
  await tester.tap(find.text(to));
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('right-click opens the menu without selecting', (tester) async {
    await _pumpDesktop(tester);
    await tester.tap(find.text('Chapter 1'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.text('Bookmark'), findsOneWidget);
    // Chapter 1 is already read, so the toggle offers the reverse.
    expect(find.text('Mark as unread'), findsOneWidget);
    expect(find.text('Mark previous as read'), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
    expect(find.textContaining('Selected'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('delete from server shows a confirmation', (tester) async {
    await _pumpDesktop(tester);
    await tester.tap(find.text('Chapter 3'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete from server…'));
    await tester.pumpAndSettle();
    expect(
      find.text('Are you sure you want to delete the selected chapters?'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shift-click selects a range', (tester) async {
    await _pumpDesktop(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(find.text('Chapter 2'));
    await tester.tap(find.text('Chapter 5'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    Checkbox boxFor(int id) => tester.widget<Checkbox>(
      find.descendant(
        of: find.byKey(ValueKey('$id')),
        matching: find.byType(Checkbox),
      ),
    );
    for (final id in [2, 3, 4, 5]) {
      expect(boxFor(id).value, isTrue);
    }
    expect(boxFor(1).value, isFalse);
    expect(boxFor(6).value, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop selection swaps the chapter header in place', (
    tester,
  ) async {
    await _pumpDesktop(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(find.text('Chapter 2'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(find.text('1 Selected'), findsOneWidget);
    expect(find.text('6 Chapters'), findsNothing);
    expect(
      find.widgetWithIcon(IconButton, Icons.close_rounded),
      findsOneWidget,
    );
    final header = find.byKey(const ValueKey('chapterSelectionHeader'));
    for (final tooltip in [
      'Mark as read',
      'Bookmark',
      'Keep offline',
      'Download',
    ]) {
      expect(
        find.descendant(of: header, matching: find.byTooltip(tooltip)),
        findsOneWidget,
      );
    }
    expect(
      find.descendant(
        of: header,
        matching: find.widgetWithText(TextButton, 'More'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: header,
        matching: find.widgetWithText(TextButton, 'Delete…'),
      ),
      findsOneWidget,
    );
    expect(find.byTooltip('Delete'), findsNothing);
    expect(find.byType(MultiChaptersActionsBottomAppBar), findsNothing);
    await tester.tap(find.widgetWithText(TextButton, 'Delete…'));
    await tester.pumpAndSettle();
    expect(
      find.text('Are you sure you want to delete the selected chapters?'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Undo after bulk mark read restores once the bar is gone', (
    tester,
  ) async {
    final book = _RecordingBook();
    final toast = _FakeToast();
    await _pumpDesktop(
      tester,
      overrides: [
        mangaBookRepositoryProvider.overrideWith((ref) => book),
        toastProvider.overrideWith((ref) => toast),
        authCredentialsStoreProvider.overrideWith(_Session.new),
      ],
    );
    await _selectRange(tester, 'Chapter 2', 'Chapter 4');
    expect(find.byType(Checkbox), findsWidgets);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('chapterSelectionHeader')),
        matching: find.byTooltip('Mark as read'),
      ),
    );
    await tester.pumpAndSettle();
    // The action cleared the selection, disposing the header whose ref the
    // Undo callback used to capture.
    expect(find.byType(Checkbox), findsNothing);
    expect(book.batches, hasLength(1));
    expect(toast.undo, isNotNull);

    toast.undo!();
    await tester.pumpAndSettle();

    final restored = {for (final c in book.putCalls) c.id: c.patch};
    expect(restored.keys, containsAll([2, 3, 4]));
    expect(restored[2]!.isRead, isFalse);
    expect(restored[2]!.lastPageRead, 4);
    expect(restored[3]!.isRead, isFalse);
    expect(restored[3]!.lastPageRead, 5);
    expect(restored[4]!.isRead, isFalse);
    expect(restored[4]!.lastPageRead, 0);
    // A restore, not another inverted bulk write.
    expect(book.batches, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('filter panel opens with tabs and badges on use', (tester) async {
    await _pumpDesktop(tester);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Filter'));
    await tester.pumpAndSettle();
    expect(find.text('Sort'), findsOneWidget);
    expect(find.text('Display'), findsOneWidget);
    // No badge before any filter is active.
    expect(find.text('1'), findsNothing);
    await tester.tap(find.text('Unread'));
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget);
    expect(find.textContaining('filtered'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
