import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/next_update_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/widgets/manga_description.dart';

import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/sorayomi.dart';

import '../../reader/reader_test_fixtures.dart';

class _LibraryManga extends MangaWithId {
  @override
  Future<MangaDto?> build({required int mangaId}) async => testManga();
}

void main() {
  testWidgets(
    'automatic scrollbars exclude horizontal and disabled scrolling',
    (tester) async {
      late BuildContext context;
      tester.view.physicalSize = const Size(1400, 980);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (value) {
              context = value;
              return const SizedBox();
            },
          ),
        ),
      );
      const behavior = AppScrollBehavior();
      const child = SizedBox();
      for (final details in [
        const ScrollableDetails.horizontal(),
        const ScrollableDetails.vertical(
          physics: NeverScrollableScrollPhysics(),
        ),
        const ScrollableDetails.vertical(
          physics: ClampingScrollPhysics(
            parent: NeverScrollableScrollPhysics(),
          ),
        ),
      ]) {
        expect(behavior.buildScrollbar(context, child, details), same(child));
      }
      expect(
        behavior.buildScrollbar(
          context,
          child,
          const ScrollableDetails.vertical(),
        ),
        isA<Scrollbar>(),
      );
    },
  );

  test('expected chapter uses natural plural wording', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(l10n.seriesNextChapterExpected(0), 'Next chapter expected soon');
    expect(l10n.seriesNextChapterExpected(1), 'Next chapter expected in 1 day');
    expect(
      l10n.seriesNextChapterExpected(3),
      'Next chapter expected in 3 days',
    );
  });

  for (final width in [1400.0, 412.0]) {
    testWidgets('description arrow sits below the clipped preview at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 980);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var expanded = false;
      await tester.pumpWidget(
        _app(
          MangaDescriptionBody(
            description: 'A long description. ' * 100,
            isExpanded: false,
            onToggleExpanded: () => expanded = true,
          ),
        ),
      );
      final preview = tester.getRect(find.byType(SingleChildScrollView));
      final arrow = tester.getRect(
        find.byIcon(Icons.keyboard_arrow_down_rounded),
      );
      expect(arrow.top, greaterThanOrEqualTo(preview.bottom));
      expect(find.byType(Scrollbar), findsNothing);
      await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
      expect(expanded, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('collapsed markdown preview does not overflow', (tester) async {
    await tester.pumpWidget(
      _app(
        MangaDescriptionBody(
          description: [
            '# Heading',
            '',
            for (var i = 0; i < 12; i++)
              'Paragraph $i with enough text to wrap across the preview width.',
          ].join('\n\n'),
          isExpanded: false,
          onToggleExpanded: () {},
        ),
      ),
    );

    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('In library asks before removal and Cancel keeps the series', (
    tester,
  ) async {
    var inLibrary = true;
    var refreshes = 0;
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          mangaNextUpdateProvider(mangaId: 1).overrideWith((ref) => null),
          mangaWithIdProvider(mangaId: 1).overrideWith(_LibraryManga.new),
          offlineEnabledProvider.overrideWithValue(false),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: MangaDescription(
                manga: testManga(),
                removeMangaFromLibrary: () async {
                  inLibrary = false;
                },
                addMangaToLibrary: () async {},
                refresh: () async {
                  refreshes++;
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('In library'));
    await tester.pumpAndSettle();

    expect(find.text('Remove from Library?'), findsOneWidget);
    expect(find.text('Remove'), findsOneWidget);
    expect(
      find.text(
        'Remove 1 entry from your library? This also deletes downloaded chapters on this device.',
      ),
      findsOneWidget,
    );
    expect(inLibrary, isTrue);
    expect(refreshes, 0);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('In library'), findsOneWidget);
    expect(inLibrary, isTrue);
    expect(refreshes, 0);
  });

  testWidgets('opens markdown links with the supplied callback', (
    tester,
  ) async {
    String? openedUrl;

    await tester.pumpWidget(
      _app(
        MangaDescriptionBody(
          description: '[Source](https://example.com/title)',
          isExpanded: true,
          onToggleExpanded: () {},
          onOpenLink: (url) => openedUrl = url,
        ),
      ),
    );

    await tester.tap(find.text('Source', findRichText: true));
    await tester.pump();

    expect(openedUrl, 'https://example.com/title');
  });
}

Widget _app(Widget child) => MaterialApp(
  scrollBehavior: const AppScrollBehavior(),
  home: Scaffold(
    body: Padding(padding: const EdgeInsets.all(16), child: child),
  ),
);
