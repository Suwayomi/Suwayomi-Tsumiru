// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/widgets/big_screen_manga_details.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/widgets/chapter_list_tile.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/widgets/small_screen_manga_details.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/utils/misc/toast/toast.dart';
import 'package:tsumiru/src/utils/theme/brand.dart';
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
  // Reading progress, so the header offers Resume rather than Start.
  'lastReadChapter': {
    'id': 2,
    'isRead': false,
    'lastPageRead': 4,
    'lastReadAt': '1',
    '__typename': 'ChapterType',
  },
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

/// Mirrors the desktop shell: the sidebar takes layout width from the page
/// (60 px collapsed, 208 px expanded) without changing the window size class.
class _ShellInset extends StatelessWidget {
  const _ShellInset({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final inset = width >= 1200 ? 208.0 : (width >= 840 ? 60.0 : 0.0);
    return Padding(
      padding: EdgeInsets.only(left: inset),
      child: child,
    );
  }
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
              const Expanded(
                child: _ShellInset(child: MangaDetailsScreen(mangaId: 1)),
              ),
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

bool _oneLineRows(WidgetTester tester) =>
    tester.widget<ChapterListTile>(find.byType(ChapterListTile).first).desktop;

/// A present label can still be ellipsised, so check the laid-out text.
void _expectFullLabel(WidgetTester tester, String label) {
  final finder = find.text(label);
  expect(finder, findsOneWidget);
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  expect(
    paragraph.didExceedMaxLines,
    isFalse,
    reason: '"$label" is ellipsised',
  );
  final painter = TextPainter(
    text: TextSpan(text: label, style: (paragraph.text as TextSpan).style),
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(tester.element(finder)),
    maxLines: 1,
  )..layout();
  expect(paragraph.size.width, greaterThanOrEqualTo(painter.width));
  painter.dispose();
}

Future<void> _selectRange(WidgetTester tester, String from, String to) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.tap(find.text(from));
  await tester.tap(find.text(to));
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Series page follows the window size classes', (tester) async {
    await _pumpDesktop(tester, size: const Size(839, 900));
    expect(find.byType(SmallScreenMangaDetails), findsOneWidget);
    expect(find.byType(BigScreenMangaDetails), findsNothing);
    expect(find.byType(BrandFab), findsOneWidget);

    // The phone body has no bar of its own at this width, so the merged bar
    // carries the page's toolbar: filter and the overflow menu (Migrate).
    final topBar = find.byType(DesktopTopBar);
    expect(topBar, findsOneWidget);
    expect(
      find.descendant(
        of: topBar,
        matching: find.byIcon(Icons.filter_list_rounded),
      ),
      findsOneWidget,
    );
    final overflow = find.descendant(
      of: topBar,
      matching: find.byIcon(Icons.more_vert_rounded),
    );
    expect(overflow, findsOneWidget);
    await tester.tap(overflow);
    await tester.pumpAndSettle();
    expect(find.text('Migrate'), findsOneWidget);
    await tester.tapAt(const Offset(1, 1));
    await tester.pumpAndSettle();

    // Long-press starts a selection; the bar swaps to the selection toolbar.
    await tester.scrollUntilVisible(
      find.text('Chapter 2'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(SmallScreenMangaDetails),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.longPress(find.text('Chapter 2'));
    await tester.pumpAndSettle();
    final selectAll = find.descendant(
      of: topBar,
      matching: find.byIcon(Icons.select_all_rounded),
    );
    expect(selectAll, findsOneWidget);
    await tester.tap(selectAll);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: topBar, matching: find.text('6 Selected')),
      findsOneWidget,
    );
    // Close the selection so the two-column checks below start clean.
    await tester.tap(
      find.descendant(of: topBar, matching: find.byIcon(Icons.close_rounded)),
    );
    await tester.pumpAndSettle();
    expect(selectAll, findsNothing);

    tester.view.physicalSize = const Size(840, 900);
    await tester.pumpAndSettle();
    expect(find.byType(BigScreenMangaDetails), findsOneWidget);
    expect(find.byType(SmallScreenMangaDetails), findsNothing);
    expect(find.byType(BrandFab), findsNothing);
    // The info column beside the cover is too narrow for both pills, so they
    // move to their own full-width row and keep their labels.
    expect(
      find.byKey(const ValueKey('series-header-stacked-controls')),
      findsOneWidget,
    );
    _expectFullLabel(tester, 'Resume');
    _expectFullLabel(tester, 'In library');

    tester.view.physicalSize = const Size(1199, 900);
    await tester.pumpAndSettle();
    expect(_oneLineRows(tester), isFalse);
    expect(
      find.byKey(const ValueKey('series-header-stacked-controls')),
      findsNothing,
    );
    _expectFullLabel(tester, 'Resume');
    _expectFullLabel(tester, 'In library');

    tester.view.physicalSize = const Size(1200, 900);
    await tester.pumpAndSettle();
    expect(_oneLineRows(tester), isTrue);
    expect(
      find.byKey(const ValueKey('series-header-stacked-controls')),
      findsOneWidget,
    );
    _expectFullLabel(tester, 'Resume');
    _expectFullLabel(tester, 'In library');
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
}
