// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// I7 gate + C2/C3 contract for the 3-tab reader settings sheet: tab switches
// and per-tab scrolling never crash (no shared scroll controller), the modal
// barrier stays real on every tab, and every dismiss path restores chrome.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/chrome/reader_settings_dialog.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/chrome/tabs/reading_mode_tab.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

class _FakeMangaWithId extends MangaWithId {
  _FakeMangaWithId(this.manga);
  final MangaDto? manga;

  @override
  Future<MangaDto?> build({required int mangaId}) async => manga;
}

MangaDto _manga({Map<String, String> meta = const {}}) => Fragment$MangaDto(
      id: 1,
      title: 'Test Manga',
      bookmarkCount: 0,
      chapters: Fragment$MangaDto$chapters(totalCount: 0),
      downloadCount: 0,
      genre: const [],
      inLibrary: true,
      inLibraryAt: '0',
      initialized: true,
      meta: [
        for (final e in meta.entries)
          Fragment$MangaDto$meta(key: e.key, value: e.value),
      ],
      sourceId: '1',
      status: Enum$MangaStatus.ONGOING,
      categories: Fragment$MangaDto$categories(nodes: const []),
      trackRecords:
          Fragment$MangaDto$trackRecords(totalCount: 0, nodes: const []),
      unreadCount: 0,
      updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
      url: '/manga/1',
    );

/// Mimics ReaderWrapper's gear tap: owns the visibility/padding/magnifier
/// notifiers and opens the sheet through the real helper.
class _SheetHost extends ConsumerWidget {
  const _SheetHost({
    required this.visibility,
    required this.padding,
    required this.magnifier,
  });

  final ValueNotifier<bool> visibility;
  final ValueNotifier<double> padding;
  final ValueNotifier<double> magnifier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () => showReaderSettingsSheet(
            context: context,
            ref: ref,
            mangaId: 1,
            visibility: visibility,
            readerPadding: padding,
            magnifierSize: magnifier,
          ),
          child: const Text('open'),
        ),
      ),
    );
  }
}

void main() {
  late ValueNotifier<bool> visibility;

  Future<void> pumpHost(
    WidgetTester tester, {
    Map<String, String> meta = const {},
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    visibility = ValueNotifier(true);
    addTearDown(visibility.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          mangaWithIdProvider(mangaId: 1)
              .overrideWith(() => _FakeMangaWithId(_manga(meta: meta))),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: _SheetHost(
            visibility: visibility,
            padding: ValueNotifier(0.0),
            magnifier: ValueNotifier(1.0),
          ),
        ),
      ),
    );
  }

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderSettingsDialog), findsOneWidget);
  }

  Finder tabScrollable() => find
      .descendant(
        of: find.byType(ReadingModeTab),
        matching: find.byType(Scrollable),
      )
      .first;

  testWidgets('Reading-mode tab renders the parity chip rows', (tester) async {
    await pumpHost(tester);
    await openSheet(tester);

    expect(find.text('For this series'), findsOneWidget);
    expect(find.text('Paged (left to right)'), findsOneWidget);
    expect(find.text('Rotation'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Tap zones'),
      100,
      scrollable: tabScrollable(),
    );
    expect(find.text('Tap zones'), findsOneWidget);
  });

  testWidgets(
      'zoom toggles: webtoon-resolved mode shows the 3 long-strip switches',
      (tester) async {
    // No meta: stored mode is Default, which dereferences to webtoon.
    await pumpHost(tester);
    await openSheet(tester);

    await tester.scrollUntilVisible(
      find.text('Disable zoom out'),
      200,
      scrollable: tabScrollable(),
    );

    expect(find.text('Double tap to zoom'), findsOneWidget);
    expect(find.text('Pinch to Zoom'), findsOneWidget);
    expect(find.text('Disable zoom out'), findsOneWidget);
    expect(find.text('Disable zoom in'), findsNothing);
  });

  testWidgets('zoom toggles: paged mode shows the same zoom trio',
      (tester) async {
    await pumpHost(tester, meta: {'flutter_readerMode': 'singleHorizontalRTL'});
    await openSheet(tester);

    await tester.scrollUntilVisible(
      find.text('Disable zoom out'),
      200,
      scrollable: tabScrollable(),
    );

    expect(find.text('Double tap to zoom'), findsOneWidget);
    expect(find.text('Pinch to Zoom'), findsOneWidget);
    expect(find.text('Disable zoom out'), findsOneWidget);
    expect(find.text('Disable zoom in'), findsNothing);
  });

  testWidgets(
      'I7 gate: switch all 3 tabs, scroll each, drag sheet — no exceptions',
      (tester) async {
    await pumpHost(tester);
    await openSheet(tester);

    // Scroll inside the Reading-mode tab (drag from a label, not a slider).
    await tester.drag(find.text('Rotation'), const Offset(0, -60));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('General'));
    await tester.pumpAndSettle();
    await tester.drag(
        find.byType(ListView).hitTestable().first, const Offset(0, -60));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Custom filter'));
    await tester.pumpAndSettle();
    await tester.drag(
        find.byType(ListView).hitTestable().first, const Offset(0, -60));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Drag the sheet itself from the tab bar (non-scrolled region).
    await tester.drag(find.byType(TabBar), const Offset(0, 60));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'C2: barrier dims on Reading-mode/General, clears + hides chrome on '
      'Custom filter — and stays a real barrier', (tester) async {
    await pumpHost(tester);
    await openSheet(tester);

    // Dimmed tabs use the color-animated barrier.
    expect(find.byType(AnimatedModalBarrier), findsOneWidget);
    expect(visibility.value, true);

    await tester.tap(find.text('Custom filter'));
    await tester.pumpAndSettle();
    // Transparent barrierColor drops the animated variant, but a plain
    // ModalBarrier remains above the reader route — gestures still blocked.
    expect(find.byType(AnimatedModalBarrier), findsNothing);
    expect(find.byType(ModalBarrier), findsWidgets);
    expect(visibility.value, false, reason: 'chrome hidden = page visible');

    await tester.tap(find.text('General'));
    await tester.pumpAndSettle();
    expect(find.byType(AnimatedModalBarrier), findsOneWidget);
    expect(visibility.value, true, reason: 'leaving Custom filter restores');
  });

  testWidgets('C3: barrier tap dismisses and restores chrome', (tester) async {
    await pumpHost(tester);
    await openSheet(tester);

    await tester.tap(find.text('Custom filter'));
    await tester.pumpAndSettle();
    expect(visibility.value, false);

    await tester.tapAt(const Offset(400, 40));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderSettingsDialog), findsNothing);
    expect(visibility.value, true);
  });

  testWidgets('C3: system back closes the SHEET and restores chrome',
      (tester) async {
    await pumpHost(tester);
    await openSheet(tester);

    await tester.tap(find.text('Custom filter'));
    await tester.pumpAndSettle();
    expect(visibility.value, false);

    final widgetsAppState = tester.state<State<WidgetsApp>>(
      find.byType(WidgetsApp),
    ) as WidgetsBindingObserver;
    await widgetsAppState.didPopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(ReaderSettingsDialog), findsNothing);
    expect(find.text('open'), findsOneWidget, reason: 'host route survives');
    expect(visibility.value, true);
  });
}
