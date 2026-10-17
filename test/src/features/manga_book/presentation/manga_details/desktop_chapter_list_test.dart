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
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
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
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/widgets/chapter_list_tile.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/widgets/series_header.dart';
import 'package:tsumiru/src/features/manga_book/widgets/chapter_actions/multi_chapters_actions_bottom_app_bar.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/utils/misc/toast/toast.dart';
import 'package:tsumiru/src/utils/theme/brand.dart';

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
      home: const Scaffold(body: MangaDetailsScreen(mangaId: 1)),
    ),
  );
}

Future<void> _pumpTile(
  WidgetTester tester, {
  String? scanlator = 'Group A',
  int lastPageRead = 0,
  bool isCurrent = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        offlineEnabledProvider.overrideWithValue(false),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ChapterListTile(
            manga: _manga,
            chapter: _chapter(
              id: 99,
              scanlator: scanlator,
              lastPageRead: lastPageRead,
            ),
            updateData: () async {},
            toggleSelect: (_) {},
            desktop: true,
            isCurrent: isCurrent,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
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
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    _app(preferences, overrides: overrides, chapters: chapters),
  );
  await tester.pumpAndSettle();
}

Future<void> _resizeWindow(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 900);
  await tester.pumpAndSettle();
}

bool _wideRows(WidgetTester tester) => _topChapter(tester)!.desktop;

/// The topmost chapter row that is at least partly inside the list viewport.
ChapterListTile? _topChapter(WidgetTester tester) {
  final list = find.byType(ScrollablePositionedList);
  final top = tester.getTopLeft(list).dy;
  final bottom = tester.getBottomLeft(list).dy;
  ChapterListTile? first;
  var firstTop = double.infinity;
  for (final element in find.byType(ChapterListTile).evaluate()) {
    final box = element.renderObject! as RenderBox;
    final rowTop = box.localToGlobal(Offset.zero).dy;
    if (rowTop + box.size.height <= top + 0.5 || rowTop >= bottom) continue;
    if (rowTop < firstTop) {
      first = element.widget as ChapterListTile;
      firstTop = rowTop;
    }
  }
  return first;
}

/// Drags the one-line list until [id] is the first visible chapter.
Future<void> _scrollToChapter(WidgetTester tester, int id) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    final first = _topChapter(tester);
    if (first == null) break;
    final delta = first.chapter.id - id;
    if (delta == 0) return;
    // Dragging down reveals earlier chapters; 46 is the one-line row height.
    final rows = delta.clamp(-4, 4);
    await tester.drag(
      find.byType(ScrollablePositionedList),
      Offset(0, rows * 46.0),
    );
    await tester.pumpAndSettle();
  }
  fail('Chapter $id never reached the top of the list');
}

Future<void> _selectRange(WidgetTester tester, String from, String to) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.tap(find.text(from));
  await tester.tap(find.text(to));
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('header shows count, subline and labelled buttons', (
    tester,
  ) async {
    await _pumpDesktop(tester);
    expect(find.text('6 Chapters'), findsOneWidget);
    expect(find.text('5 unread'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Refresh'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Filter'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unknown scanlator shows nothing', (tester) async {
    await _pumpDesktop(tester);
    final tile = tester.widget<ChapterListTile>(
      find.byKey(const ValueKey('3')),
    );
    expect(tile.chapter.scanlator, isNull);
    // No "Unknown" text anywhere in the chapter column rows.
    expect(find.textContaining('nknown'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('whitespace-only scanlator shows nothing', (tester) async {
    await _pumpTile(tester, scanlator: '   ');
    expect(find.text('   '), findsNothing);
    expect(find.textContaining('nknown'), findsNothing);
    expect(
      find.byWidgetPredicate((w) => w is SizedBox && w.width == 96),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('current chapter without progress shows no progress line', (
    tester,
  ) async {
    await _pumpTile(tester, isCurrent: true);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('progress line only on the current chapter', (tester) async {
    await _pumpDesktop(tester);
    Finder progressIn(int id) => find.descendant(
      of: find.byKey(ValueKey('$id')),
      matching: find.byType(LinearProgressIndicator),
    );
    expect(progressIn(2), findsOneWidget);
    for (final id in [1, 3, 4, 5, 6]) {
      expect(progressIn(id), findsNothing);
    }
    expect(find.byTooltip('Page 5 of 20'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('current chapter accent bar does not shift its title', (
    tester,
  ) async {
    await _pumpDesktop(tester, size: const Size(1400, 900));
    final current = tester.getTopLeft(find.text('Chapter 2')).dx;
    final normal = tester.getTopLeft(find.text('Chapter 4')).dx;
    expect(current, normal);
    expect(tester.takeException(), isNull);
  });

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

  testWidgets('menu offers server delete for a downloaded chapter', (
    tester,
  ) async {
    await _pumpDesktop(tester);
    await tester.tap(find.text('Chapter 3'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    // Offline storage is off in tests, so the device row hides (same as the
    // row's own save button); the server row still offers the delete.
    expect(find.text('Remove from device'), findsNothing);
    expect(find.text('Delete from server…'), findsOneWidget);
    expect(find.text('Keep offline'), findsNothing);
    expect(find.text('Download'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('menu shows download actions otherwise', (tester) async {
    await _pumpDesktop(tester);
    await tester.tap(find.text('Chapter 1'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.text('Keep offline'), findsNothing);
    expect(find.text('Download'), findsOneWidget);
    expect(find.text('Remove from device'), findsNothing);
    expect(find.text('Delete from server…'), findsNothing);
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

  testWidgets('esc with menu open closes only the menu', (tester) async {
    await _pumpDesktop(tester);
    await tester.tap(find.text('Chapter 1'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.text('Bookmark'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Bookmark'), findsNothing);
    expect(find.byType(Checkbox), findsNothing);
    // Still on the series page with its chapter list.
    expect(find.text('6 Chapters'), findsOneWidget);
    expect(find.text('Chapter 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('esc in selection mode clears the selection', (tester) async {
    await _pumpDesktop(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(find.text('Chapter 2'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(find.byType(Checkbox), findsWidgets);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(Checkbox), findsNothing);
    expect(find.text('6 Chapters'), findsOneWidget);
    expect(find.text('Chapter 2'), findsOneWidget);
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

  testWidgets('select in between only appears with a selection', (
    tester,
  ) async {
    await _pumpDesktop(tester);
    await tester.tap(find.text('Chapter 1'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.text('Select in between'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(find.text('Chapter 2'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chapter 4'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.text('Select in between'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('right-click on a selected row acts on the selection', (
    tester,
  ) async {
    await _pumpDesktop(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(find.text('Chapter 2'));
    await tester.tap(find.text('Chapter 3'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chapter 2'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    // Once in the chapter-column header, once as the menu header.
    expect(find.text('2 Selected'), findsNWidgets(2));
    expect(find.text('Select'), findsNothing);
    expect(find.text('Delete from server…'), findsOneWidget);
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

  testWidgets('desktop selection header fits at 1200 wide', (tester) async {
    await _pumpDesktop(tester, size: const Size(1200, 900));
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
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing the selection header restores the chapter header', (
    tester,
  ) async {
    await _pumpDesktop(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(find.text('Chapter 2'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(find.text('1 Selected'), findsOneWidget);
    await tester.tap(find.widgetWithIcon(IconButton, Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.text('1 Selected'), findsNothing);
    expect(find.text('6 Chapters'), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('header More menu holds overflow and select actions', (
    tester,
  ) async {
    await _pumpDesktop(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(find.text('Chapter 2'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('chapterSelectionHeader')),
        matching: find.widgetWithText(TextButton, 'More'),
      ),
    );
    await tester.pumpAndSettle();
    for (final label in [
      'Mark as read',
      'Bookmark',
      'Keep offline',
      'Download',
    ]) {
      expect(find.text(label), findsNothing);
    }
    for (final label in [
      'Mark previous as read',
      'Select next 10',
      'Select below',
      'Select Unread',
      'Select in between',
      'Open in browser',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('tablet selection header is icon-only with no bottom bar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(_app(preferences));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Chapter 2'));
    await tester.pumpAndSettle();
    expect(find.text('1 Selected'), findsOneWidget);
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
    expect(find.widgetWithText(TextButton, 'Mark as read'), findsNothing);
    expect(find.byTooltip('Delete'), findsOneWidget);
    expect(
      find.descendant(of: header, matching: find.byTooltip('More')),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextButton, 'Delete…'), findsNothing);
    expect(
      find.descendant(
        of: header,
        matching: find.widgetWithText(TextButton, 'More'),
      ),
      findsNothing,
    );
    expect(find.byType(MultiChaptersActionsBottomAppBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone selection bar gains bookmark and previous', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(_app(preferences));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Chapter 2'));
    await tester.pumpAndSettle();
    expect(find.byType(MultiChaptersActionsBottomAppBar), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_rounded), findsWidgets);
    expect(find.byIcon(Icons.history_rounded), findsOneWidget);
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

  testWidgets('Undo of Mark previous as read keeps already-read progress', (
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
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(find.text('Chapter 4'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(find.text('1 Selected'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('chapterSelectionHeader')),
        matching: find.widgetWithText(TextButton, 'More'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark previous as read'));
    await tester.pumpAndSettle();
    expect(book.batches, hasLength(1));
    expect(book.batches.single.ids, containsAll([1, 2, 3]));

    toast.undo!();
    await tester.pumpAndSettle();

    final restored = {for (final c in book.putCalls) c.id: c.patch};
    // Chapter 1 was already read with no progress, so nothing to restore.
    expect(restored.containsKey(1), isFalse);
    expect(restored[2]!.isRead, isFalse);
    expect(restored[2]!.lastPageRead, 4);
    expect(restored[3]!.isRead, isFalse);
    expect(restored[3]!.lastPageRead, 5);
    expect(
      book.putCalls.where((c) => c.patch.isRead == true),
      isEmpty,
      reason: 'no previously-read chapter is left read by undo',
    );
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

  testWidgets('tablet 1190 gives the chapter column one-line rows', (
    tester,
  ) async {
    await _pumpDesktop(tester, size: const Size(1190, 900));
    final tile = tester.widget<ChapterListTile>(
      find.byKey(const ValueKey('2')),
    );
    expect(tile.desktop, isTrue);
    // One-line rows draw the scanlator as its own column, not the phone
    // subtitle's bulleted run.
    expect(find.text('Group A'), findsWidgets);
    expect(find.text(' • Group A'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('2')),
        matching: find.byType(LinearProgressIndicator),
      ),
      findsOneWidget,
    );
    // Title once, beside the cover; no app bar title on tablets.
    expect(find.byType(SeriesAppBarTitle), findsNothing);
    expect(
      find.descendant(
        of: find.byType(SeriesHeader),
        matching: find.text('Test series'),
      ),
      findsOneWidget,
    );
    expect(find.text('Test series'), findsOneWidget);
    // The selection header uses the same rule: labelled actions at this width.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(find.text('Chapter 2'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('chapterSelectionHeader')),
        matching: find.widgetWithText(TextButton, 'More'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('tablet 800 keeps the narrow two-line rows', (tester) async {
    await _pumpDesktop(tester, size: const Size(800, 900));
    final tile = tester.widget<ChapterListTile>(
      find.byKey(const ValueKey('2')),
    );
    expect(tile.desktop, isFalse);
    expect(find.text(' • Group A'), findsWidgets);
    expect(find.text('Group A'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('2')),
        matching: find.byType(LinearProgressIndicator),
      ),
      findsNothing,
    );
    expect(find.byType(SeriesAppBarTitle), findsNothing);
    expect(
      find.descendant(
        of: find.byType(SeriesHeader),
        matching: find.text('Test series'),
      ),
      findsOneWidget,
    );
    expect(find.text('Test series'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop 1400 keeps one-line rows and the bar title', (
    tester,
  ) async {
    await _pumpDesktop(tester, size: const Size(1400, 900));
    final tile = tester.widget<ChapterListTile>(
      find.byKey(const ValueKey('2')),
    );
    expect(tile.desktop, isTrue);
    expect(find.text('Group A'), findsWidgets);
    expect(find.text(' • Group A'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(SeriesAppBarTitle),
        matching: find.text('Test series'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(SeriesHeader),
        matching: find.text('Test series'),
      ),
      findsNothing,
    );
    expect(find.text('Test series'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone 412 keeps the phone rows and bar title', (tester) async {
    await _pumpDesktop(tester, size: const Size(412, 915));
    final tile = tester.widget<ChapterListTile>(
      find.byKey(const ValueKey('2')),
    );
    expect(tile.desktop, isFalse);
    expect(find.text(' • Group A'), findsWidgets);
    expect(find.text('Group A'), findsNothing);
    // Phone app bar still carries the faded title and the Resume button.
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Test series'),
      ),
      findsOneWidget,
    );
    expect(find.byType(BrandFab), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('row style stays put while resizing inside the band', (
    tester,
  ) async {
    // Below 1200 the chapter column takes half the window: 495, 475, 480.
    // The band is 472..487, so none of these flips the rows.
    await _pumpDesktop(tester, size: const Size(990, 900));
    expect(_wideRows(tester), isTrue);

    await _resizeWindow(tester, 950);
    expect(_wideRows(tester), isTrue, reason: '475 stays one-line');

    await _resizeWindow(tester, 990);
    expect(_wideRows(tester), isTrue);

    await _resizeWindow(tester, 960);
    expect(_wideRows(tester), isTrue, reason: '480 stays one-line');

    await _resizeWindow(tester, 940);
    expect(_wideRows(tester), isFalse, reason: '470 leaves the band');

    await _resizeWindow(tester, 990);
    expect(_wideRows(tester), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('row style switch keeps the chapter at the top', (tester) async {
    final chapters = [
      for (var id = 1; id <= 120; id++) _chapter(id: id, read: true),
    ];
    await _pumpDesktop(tester, size: const Size(990, 900), chapters: chapters);
    await _scrollToChapter(tester, 60);
    expect(_topChapter(tester)?.chapter.id, 60);

    await _resizeWindow(tester, 940);
    expect(_wideRows(tester), isFalse);
    expect(_topChapter(tester)?.chapter.id, inInclusiveRange(59, 61));

    await _resizeWindow(tester, 990);
    expect(_wideRows(tester), isTrue);
    expect(_topChapter(tester)?.chapter.id, inInclusiveRange(59, 61));
    expect(tester.takeException(), isNull);
  });
}
