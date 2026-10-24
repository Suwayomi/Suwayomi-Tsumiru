import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/next_update_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/widgets/manga_description.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/utils/webui_meta/webui_meta_codec.dart';

import '../../reader/reader_test_fixtures.dart';

class _LibraryManga extends MangaWithId {
  @override
  Future<MangaDto?> build({required int mangaId}) async => testManga();
}

Future<void> _pumpDescription(WidgetTester tester, MangaDto manga) async {
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
              manga: manga,
              removeMangaFromLibrary: () async {},
              addMangaToLibrary: () async {},
              refresh: () async {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<String> _descriptionMarkdownData(WidgetTester tester) => tester
    .widgetList<MarkdownBody>(
      find.descendant(
        of: find.byType(MangaDescriptionBody),
        matching: find.byType(MarkdownBody),
      ),
    )
    .map((body) => body.data)
    .toList();

void main() {
  testWidgets('expanded phone library notes offer Edit notes', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final manga = testManga().copyWith.call(
      description: 'Description',
      meta: [Fragment$MangaDto$meta(key: 'webUI_notes', value: 'Draft notes')],
    );
    for (final width in [412.0, 1440.0]) {
      for (final inLibrary in [true, false]) {
        tester.view.physicalSize = Size(width, 1200);
        await tester.pumpWidget(const SizedBox());
        await _pumpDescription(
          tester,
          manga.copyWith.call(
            user: manga.user.copyWith.call(inLibrary: inLibrary),
          ),
        );
        expect(find.text('Edit notes'), findsNothing);
        await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
        await tester.pumpAndSettle();
        expect(
          find.widgetWithIcon(TextButton, Icons.edit_note),
          width == 412 && inLibrary ? findsOneWidget : findsNothing,
        );
      }
    }
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

    expect(find.text('Remove from library'), findsOneWidget);
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

  testWidgets('webUI notes render above the description with a divider', (
    tester,
  ) async {
    final manga = testManga().copyWith.call(
      description: 'A description',
      meta: [Fragment$MangaDto$meta(key: 'webUI_notes', value: 'Some notes')],
    );
    await _pumpDescription(tester, manga);

    expect(_descriptionMarkdownData(tester), ['Some notes', 'A description']);
    expect(
      find.descendant(
        of: find.byType(MangaDescriptionBody),
        matching: find.byType(Divider),
      ),
      findsOneWidget,
    );
  });

  testWidgets('chunked webUI notes render in full', (tester) async {
    final notes = 'n' * 4001;
    final plan = planWebUiWrite({}, 'notes', notes);
    final manga = testManga().copyWith.call(
      description: 'A description',
      meta: [
        for (final entry in plan.set.entries)
          Fragment$MangaDto$meta(key: entry.key, value: entry.value),
      ],
    );
    expect(manga.webUiNotes, notes);

    await _pumpDescription(tester, manga);

    expect(_descriptionMarkdownData(tester), [notes, 'A description']);
  });

  testWidgets('a series without notes shows only the description', (
    tester,
  ) async {
    final manga = testManga().copyWith.call(description: 'A description');
    await _pumpDescription(tester, manga);

    expect(_descriptionMarkdownData(tester), ['A description']);
    expect(
      find.descendant(
        of: find.byType(MangaDescriptionBody),
        matching: find.byType(Divider),
      ),
      findsNothing,
    );
  });
}
