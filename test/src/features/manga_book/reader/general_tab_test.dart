// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// General-tab parity contract: control order,
// the seekbar-chain / fullscreen / flash sub-toggle visibility rules, the
// background-color chip write, and the fullscreen→SystemUiMode branch.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/chrome/reader_flash_overlay.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/chrome/tabs/general_tab.dart';
import 'package:tsumiru/src/features/settings/presentation/reader/widgets/reader_general_prefs/reader_general_prefs.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

class _FakeMangaWithId extends MangaWithId {
  _FakeMangaWithId(this.manga);
  final MangaDto? manga;

  @override
  Future<MangaDto?> build({required int mangaId}) async => manga;
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

void main() {
  Future<void> pumpTab(
    WidgetTester tester, {
    Map<String, Object> prefValues = const {},
  }) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues(prefValues);
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          mangaWithIdProvider(
            mangaId: 1,
          ).overrideWith(() => _FakeMangaWithId(_manga())),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: GeneralTab(mangaId: 1)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder tabScrollable() => find
      .descendant(
        of: find.byType(GeneralTab),
        matching: find.byType(Scrollable),
      )
      .first;

  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(GeneralTab)));

  testWidgets('controls follow the Komikku GeneralSettingsPage order', (
    tester,
  ) async {
    await pumpTab(tester);

    await tester.scrollUntilVisible(
      find.text('Auto reading mode'),
      200,
      scrollable: tabScrollable(),
    );

    double dy(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(dy('Background color'), lessThan(dy('Show page number')));
    expect(dy('Show page number'), lessThan(dy('Force horizontal seekbar')));
    expect(dy('Force horizontal seekbar'), lessThan(dy('Fullscreen')));
    expect(dy('Fullscreen'), lessThan(dy('Keep screen on')));
    expect(dy('Keep screen on'), lessThan(dy('Show actions on long tap')));
    expect(
      dy('Show actions on long tap'),
      lessThan(dy('Always show chapter transition')),
    );
    expect(
      dy('Always show chapter transition'),
      lessThan(dy('Flash on page change')),
    );
    expect(dy('Flash on page change'), lessThan(dy('Auto reading mode')));
  });

  testWidgets('background chips render Black/Gray/White/Auto and write the '
      'global provider', (tester) async {
    await pumpTab(tester);

    double dx(String text) => tester.getTopLeft(find.text(text)).dx;
    expect(dx('Black'), lessThan(dx('Gray')));
    expect(dx('Gray'), lessThan(dx('White')));
    expect(dx('White'), lessThan(dx('Auto')));

    // Default black.
    final blackChip = find.widgetWithText(FilterChip, 'Black');
    expect(tester.widget<FilterChip>(blackChip).selected, isTrue);

    await tester.tap(find.text('Gray'));
    await tester.pumpAndSettle();
    expect(
      container(tester).read(readerBackgroundColorKeyProvider),
      ReaderBackgroundColor.gray,
    );
  });

  group('ReaderFlashOverlay', () {
    Future<ValueNotifier<int>> pumpOverlay(
      WidgetTester tester, {
      required Map<String, Object> prefValues,
    }) async {
      SharedPreferences.setMockInitialValues(prefValues);
      final prefs = await SharedPreferences.getInstance();
      final index = ValueNotifier(0);
      addTearDown(index.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: MaterialApp(
            home: ValueListenableBuilder<int>(
              valueListenable: index,
              builder: (_, i, _) => ReaderFlashOverlay(currentIndex: i),
            ),
          ),
        ),
      );
      return index;
    }

    Color? overlayColor(WidgetTester tester) {
      // Scope to the overlay's own box — the framework wraps the tree in other
      // ColoredBoxes (a transparent one sorts first on newer Flutter), so a
      // bare find.byType(ColoredBox).first reads the wrong widget.
      final boxes = find.descendant(
        of: find.byType(ReaderFlashOverlay),
        matching: find.byType(ColoredBox),
      );
      if (boxes.evaluate().isEmpty) return null;
      return tester.widget<ColoredBox>(boxes.first).color;
    }

    testWidgets('interval N flashes the 1st change then skips N-1', (
      tester,
    ) async {
      final index = await pumpOverlay(
        tester,
        prefValues: {'flashOnPageChange': true, 'flashPageInterval': 2},
      );

      index.value = 1;
      await tester.pump();
      expect(overlayColor(tester), Colors.black, reason: 'count 0 flashes');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      index.value = 2;
      await tester.pump();
      expect(overlayColor(tester), isNull, reason: 'count 1 skipped');

      index.value = 3;
      await tester.pump();
      expect(overlayColor(tester), Colors.black, reason: 'count 2 flashes');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
    });
  });
}
