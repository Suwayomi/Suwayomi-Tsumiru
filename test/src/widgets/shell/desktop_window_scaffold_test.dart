// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// P2: the 40 px app-level title strip must only be suppressed when the
// displayed route actually provides the merged top bar. The navigation
// shells register while they show it; routes outside the shells (reader,
// onboarding) keep the strip with its window controls and drag area.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/browse_center/presentation/extension/controller/extension_update_badge.dart';
import 'package:tsumiru/src/features/manga_book/data/manga_book/manga_book_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter_batch/chapter_batch_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter_page/chapter_page_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/controller/reader_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/reader_screen.dart';
import 'package:tsumiru/src/features/offline/data/offline_nav_status.dart';
import 'package:tsumiru/src/features/onboarding/presentation/onboarding_screen.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/utils/platform/platform_runtime.dart';
import 'package:tsumiru/src/widgets/desktop/desktop_title_bar.dart';
import 'package:tsumiru/src/widgets/desktop/desktop_top_bar.dart';
import 'package:tsumiru/src/widgets/desktop/desktop_window_scaffold.dart';
import 'package:window_manager/window_manager.dart';

const _png1x1 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=';

class _FakeMangaWithId extends MangaWithId {
  _FakeMangaWithId(this.manga);
  final MangaDto? manga;

  @override
  Future<MangaDto?> build({required int mangaId}) async => manga;
}

class _RecordingRepo extends Fake implements MangaBookRepository {
  @override
  Future<void> putChapter({
    required int chapterId,
    required ChapterChange patch,
  }) async {}
}

List<String> _localPages(int count) {
  final dir = Directory.systemTemp.createTempSync('tsumiru-scaffold-strip-');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  final bytes = base64Decode(_png1x1);
  return [
    for (var i = 0; i < count; i++)
      (File('${dir.path}/$i.png')..writeAsBytesSync(bytes)).uri.toString(),
  ];
}

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
  trackRecords: Fragment$MangaDto$trackRecords(nodes: const []),
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

ChapterPagesDto _chapterPages() => ChapterPagesDto(
  chapter: ChapterPagesChapterDto(id: 1, pageCount: 3),
  pages: _localPages(3),
);

Future<ProviderContainer> _container() async {
  SharedPreferences.setMockInitialValues(const {});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      downloadsPausedBadgeProvider.overrideWith((ref) => false),
      extensionUpdateBadgeCountProvider.overrideWith((ref) async => 0),
      mangaBookRepositoryProvider.overrideWithValue(_RecordingRepo()),
      mangaWithIdProvider(
        mangaId: 1,
      ).overrideWith(() => _FakeMangaWithId(_manga())),
      chapterProvider(chapterId: 1).overrideWithBuild((ref, _) => _chapter()),
      chapterPagesProvider(chapterId: 1).overrideWith((ref) => _chapterPages()),
      getNextAndPreviousChaptersProvider(
        mangaId: 1,
        chapterId: 1,
      ).overrideWithValue(null),
    ],
  );
  return container;
}

Future<void> _pump(
  WidgetTester tester,
  ProviderContainer container,
  Widget child, {
  Size size = const Size(1400, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
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
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: DesktopWindowScaffold(child: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _inStrip(Finder finder) =>
    find.descendant(of: find.byType(DesktopTitleBar), matching: finder);

void main() {
  setUp(() => debugDesktopPlatformOverride = true);
  tearDown(() => debugDesktopPlatformOverride = null);

  testWidgets('routes outside the shells keep the strip', (tester) async {
    // A plain route keeps the strip with its window controls and drag area.
    var container = await _container();
    addTearDown(container.dispose);
    await _pump(tester, container, const Text('plain page'));
    expect(find.byType(DesktopTitleBar), findsOneWidget);
    expect(find.byType(DesktopTopBar), findsNothing);
    expect(_inStrip(find.byType(DragToMoveArea)), findsOneWidget);
    expect(_inStrip(find.byType(WindowCaptionButton)), findsNWidgets(3));
    expect(tester.takeException(), isNull);

    // A narrow window keeps it too.
    await tester.pumpWidget(const SizedBox.shrink());
    container = await _container();
    addTearDown(container.dispose);
    await _pump(
      tester,
      container,
      const Text('plain page'),
      size: const Size(412, 900),
    );
    expect(find.byType(DesktopTitleBar), findsOneWidget);
    expect(find.text('plain page'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // So does onboarding.
    await tester.pumpWidget(const SizedBox.shrink());
    FlutterSecureStorage.setMockInitialValues({});
    container = await _container();
    addTearDown(container.dispose);
    await _pump(tester, container, const OnboardingScreen());
    expect(find.text('Next'), findsOneWidget);
    expect(find.byType(DesktopTitleBar), findsOneWidget);
    expect(_inStrip(find.byType(WindowCaptionButton)), findsNWidgets(3));
    expect(find.byType(DesktopTopBar), findsNothing);
    expect(tester.takeException(), isNull);

    // And the reader.
    await tester.pumpWidget(const SizedBox.shrink());
    container = await _container();
    addTearDown(container.dispose);
    await _pump(tester, container, ReaderScreen(mangaId: 1, chapterId: 1));
    // Wide window -> spread view on the first spread: indicator reads 2 / 3.
    expect(find.text('2 / 3'), findsOneWidget);
    expect(find.byType(DesktopTitleBar), findsOneWidget);
    expect(_inStrip(find.byType(DragToMoveArea)), findsOneWidget);
    expect(_inStrip(find.byType(WindowCaptionButton)), findsNWidgets(3));
    expect(find.byType(DesktopTopBar), findsNothing);
    // Flush the reader's debounced progress timer before teardown.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });
}
