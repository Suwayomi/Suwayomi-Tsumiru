import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/manga_book/data/recommendations/recommendation_provider.dart';
import 'package:tsumiru/src/features/manga_book/data/recommendations/recommendation_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/next_update_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/manga_details_screen.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/widgets/manga_description.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/widgets/recommends_row.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/widgets/series_header.dart';
import 'package:tsumiru/src/features/manga_book/presentation/recommends/recommendation_card.dart';
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

  testWidgets(
    'desktop title shrinks to 15 and ellipsizes on one line at 1400',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 980);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        _app(
          SizedBox(width: 540, child: SeriesAppBarTitle(title: _manga.title)),
        ),
      );
      final text = tester.widget<Text>(find.text(_manga.title));
      expect(text.style!.fontSize, 15);
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
      expect(find.byTooltip(_manga.title), findsOneWidget);
      await tester.pumpWidget(
        _app(
          const SizedBox(
            width: 540,
            child: SeriesAppBarTitle(title: 'Short title'),
          ),
        ),
      );
      expect(tester.widget<Text>(find.text('Short title')).style!.fontSize, 20);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [1400.0, 900.0, 412.0]) {
    testWidgets(
      'header and floating Resume use the correct placement at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 980);
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
        final headerPills = find.descendant(
          of: find.byType(SeriesHeader),
          matching: find.byType(SeriesHeaderPill),
        );
        expect(headerPills, width >= 1200 ? findsNWidgets(2) : findsNothing);
        expect(
          find.byType(BrandFab),
          width >= 1200 ? findsNothing : findsOneWidget,
        );
        if (width >= 1200) {
          final title = tester.widget<Text>(
            find.descendant(
              of: find.byType(SeriesAppBarTitle),
              matching: find.text(_manga.title),
            ),
          );
          expect(title.style!.fontSize, 15);
          expect(title.maxLines, 1);
          expect(title.overflow, TextOverflow.ellipsis);
          expect(
            find.descendant(
              of: find.byType(SeriesHeader),
              matching: find.text('Resume'),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: find.byType(SeriesHeader),
              matching: find.text('In library'),
            ),
            findsOneWidget,
          );
          final cover = tester.getRect(
            find.byKey(const ValueKey('series-header-cover')),
          );
          final controls = tester.getRect(
            find.byKey(const ValueKey('series-header-controls')),
          );
          expect(cover.width, 180);
          expect(controls.bottom, closeTo(cover.bottom, .01));
          final coverCard = tester.getRect(
            find
                .descendant(
                  of: find.byKey(const ValueKey('series-header-cover')),
                  matching: find.byType(Material),
                )
                .first,
          );
          final resume = tester.getRect(headerPills.first);
          expect(resume.bottom, closeTo(coverCard.bottom, .01));
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final width in [420.0, 610.0]) {
    testWidgets('suggestions end on exactly half a card at $width', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'showRecommendations': true});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            mangaRecommendationsProvider(1).overrideWith(
              (ref) async => [
                for (var i = 0; i < 12; i++)
                  Recommendation(title: 'Series $i', category: 'Test'),
              ],
            ),
          ],
          child: _app(
            SizedBox(width: width, child: const RecommendsRow(mangaId: 1)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final cards = tester
          .widgetList<RecommendationCard>(find.byType(RecommendationCard))
          .toList();
      final viewport = tester.getSize(find.byType(ListView)).width;
      final cardWidth = cards.first.width;
      final whole = (viewport / 106 - .5).floor().clamp(1, 100);
      expect(viewport - whole * (cardWidth + 10), closeTo(cardWidth / 2, .001));
      expect(
        tester.getSize(find.byType(RecommendationCard).first).width,
        closeTo(cardWidth, .001),
      );
      expect(find.text('See all'), findsOneWidget);
      expect(
        tester.widgetList<IconButton>(find.byType(IconButton)).first.onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [1400.0, 900.0]) {
    for (final height in [1100.0, 480.0]) {
      testWidgets('description fits the info column at $width x $height', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, height);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(_descriptionApp(preferences));
        await tester.pumpAndSettle();

        final body = tester.widget<MangaDescriptionBody>(
          find.byType(MangaDescriptionBody),
        );
        expect(body.isExpanded, height == 1100);
        expect(body.showToggle, height != 1100);
        expect(
          find.byIcon(Icons.keyboard_arrow_down_rounded),
          height == 1100 ? findsNothing : findsOneWidget,
        );
        expect(
          find.textContaining(RegExp(r'^\d+ more$')),
          height == 1100 ? findsNothing : findsOneWidget,
        );
        if (height == 1100) {
          final infoScroll = find.ancestor(
            of: find.byType(MangaDescription),
            matching: find.byType(SingleChildScrollView),
          );
          final scrollable = tester.state<ScrollableState>(
            find
                .descendant(of: infoScroll, matching: find.byType(Scrollable))
                .first,
          );
          expect(scrollable.position.maxScrollExtent, 0);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

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

  testWidgets('N more counts only whole tags hidden from the collapsed row', (
    tester,
  ) async {
    var expanded = false;
    await tester.pumpWidget(
      _app(
        SizedBox(
          width: 300,
          child: CollapsedSeriesTags(
            tags: const ['Action', 'Adventure', 'Fantasy', 'Drama'],
            leading: const SizedBox(width: 38, height: 30),
            onExpand: () => expanded = true,
            onTagTap: (_, _) {},
          ),
        ),
      ),
    );
    expect(find.text('Action'), findsOneWidget);
    expect(find.text('Adventure'), findsNothing);
    expect(find.text('3 more'), findsOneWidget);
    await tester.tap(find.text('3 more'));
    expect(expanded, isTrue);
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
