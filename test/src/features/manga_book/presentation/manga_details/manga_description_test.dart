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
