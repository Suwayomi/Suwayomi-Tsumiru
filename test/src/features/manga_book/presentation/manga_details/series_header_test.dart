import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/next_update_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/manga_details_screen.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/widgets/big_screen_manga_details.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/widgets/manga_description.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/widgets/series_header.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/utils/theme/brand.dart';

final _manga = MangaDto.fromJson({
  '__typename': 'MangaType',
  'id': 1,
  'title': 'A series with a very long title ' * 12,
  'author': 'An author with a very long name ' * 12,
  'bookmarkCount': 0,
  'chapters': {'totalCount': 0, '__typename': 'ChapterNodeList'},
  'downloadCount': 0,
  'genre': ['Action', 'Adventure', 'Fantasy', 'Drama'],
  'inLibrary': true,
  'inLibraryAt': '0',
  'initialized': true,
  'meta': [],
  'sourceId': '0',
  'status': 'ONGOING',
  'categories': {'nodes': [], '__typename': 'CategoryNodeList'},
  'trackRecords': {'nodes': [], '__typename': 'TrackRecordNodeList'},
  'unreadCount': 0,
  'updateStrategy': 'ALWAYS_UPDATE',
  'url': '',
  'lastReadChapter': {
    '__typename': 'ChapterType',
    'id': 2,
    'isRead': false,
    'lastPageRead': 3,
    'lastReadAt': '1',
  },
});
final _chapter = ChapterDto(
  chapterNumber: 1,
  fetchedAt: '0',
  id: 2,
  isBookmarked: false,
  isDownloaded: false,
  isRead: false,
  lastPageRead: 3,
  lastReadAt: '1',
  mangaId: 1,
  name: 'Chapter 1',
  pageCount: 20,
  sourceOrder: 1,
  uploadDate: '0',
  url: '',
  meta: [],
);

class _Manga extends MangaWithId {
  _Manga([this.value]);

  final MangaDto? value;
  @override
  Future<MangaDto?> build({required int mangaId}) async => value ?? _manga;
  @override
  Future<void> refresh([bool onlineFetch = false]) async {}
}

class _Chapters extends MangaChapterList {
  @override
  Future<List<ChapterDto>?> build({required int mangaId}) async => [];
  @override
  Future<void> refresh([bool onlineFetch = false]) async {}
}

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  late SharedPreferences preferences;
  setUp(() async {
    SharedPreferences.setMockInitialValues({'showRecommendations': false});
    preferences = await SharedPreferences.getInstance();
  });

  testWidgets('series page keeps the big-screen layout at 900x900', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          offlineEnabledProvider.overrideWithValue(false),
          mangaWithIdProvider(mangaId: 1).overrideWith(_Manga.new),
          mangaChapterListProvider(mangaId: 1).overrideWith(_Chapters.new),
          mangaChapterListWithFilterProvider(
            mangaId: 1,
          ).overrideWith((ref) => const AsyncData([])),
          mangaChapterListEntriesProvider(
            mangaId: 1,
          ).overrideWith((ref) => const AsyncData([])),
          firstUnreadInFilteredChapterListProvider(
            mangaId: 1,
          ).overrideWith((ref) => _chapter),
          mangaNextUpdateProvider(mangaId: 1).overrideWith((ref) => null),
        ],
        child: _app(const MangaDetailsScreen(mangaId: 1)),
      ),
    );
    await tester.pumpAndSettle();
    // Still the two-pane big-screen layout, but without the >= 1200
    // desktop extras: no header pills, floating Resume instead.
    expect(find.byType(BigScreenMangaDetails), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SeriesHeader),
        matching: find.byType(SeriesHeaderPill),
      ),
      findsNothing,
    );
    expect(find.byType(BrandFab), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('manual collapse sticks after resizing to a tall window', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_descriptionApp(preferences));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byIcon(Icons.keyboard_arrow_down_rounded));
    await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byIcon(Icons.keyboard_arrow_up_rounded));
    await tester.tap(find.byIcon(Icons.keyboard_arrow_up_rounded));
    await tester.pumpAndSettle();

    tester.view.physicalSize = const Size(412, 1100);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<MangaDescriptionBody>(find.byType(MangaDescriptionBody))
          .isExpanded,
      isFalse,
    );
    tester.view.physicalSize = const Size(1400, 1100);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<MangaDescriptionBody>(find.byType(MangaDescriptionBody))
          .isExpanded,
      isFalse,
    );
    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
    expect(find.textContaining(RegExp(r'^\d+ more$')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _descriptionApp(SharedPreferences preferences) {
  final manga = MangaDto.fromJson({
    ..._manga.toJson(),
    'title': 'A short title',
    'author': 'An author',
    'description': 'A short description with a [link](https://example.com).',
    'genre': [for (var i = 0; i < 12; i++) 'Genre number $i'],
  });
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      offlineEnabledProvider.overrideWithValue(false),
      mangaWithIdProvider(mangaId: 1).overrideWith(() => _Manga(manga)),
      mangaChapterListProvider(mangaId: 1).overrideWith(_Chapters.new),
      mangaChapterListWithFilterProvider(
        mangaId: 1,
      ).overrideWith((ref) => const AsyncData([])),
      mangaChapterListEntriesProvider(
        mangaId: 1,
      ).overrideWith((ref) => const AsyncData([])),
      firstUnreadInFilteredChapterListProvider(
        mangaId: 1,
      ).overrideWith((ref) => _chapter),
      mangaNextUpdateProvider(mangaId: 1).overrideWith((ref) => null),
    ],
    child: _app(const MangaDetailsScreen(mangaId: 1)),
  );
}
