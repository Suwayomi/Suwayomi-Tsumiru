// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Reading-mode tab parity contract: 6 chips + honest legacy-orphan chip
// (§2.5), contextual paged/long-strip sections, tap-invert visibility, and
// the "For this series" OFF path routing writes to the global provider.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/manga_book/data/manga_book/manga_book_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/chrome/tabs/reading_mode_tab.dart';
import 'package:tsumiru/src/features/settings/presentation/reader/widgets/reader_paged_prefs/reader_paged_prefs.dart';
import 'package:tsumiru/src/features/settings/presentation/reader/widgets/reader_webtoon_prefs/reader_webtoon_prefs.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

class _FakeMangaWithId extends MangaWithId {
  _FakeMangaWithId(this.manga);
  final MangaDto? manga;

  @override
  Future<MangaDto?> build({required int mangaId}) async => manga;
}

/// Records meta writes/deletes instead of hitting a server.
class _RecordingRepo implements MangaBookRepository {
  final patches = <(String, dynamic)>[];
  final deletes = <String>[];

  @override
  Future<void> patchMangaMeta({
    required int mangaId,
    required String key,
    required dynamic value,
  }) async {
    patches.add((key, value));
  }

  @override
  Future<void> deleteMangaMeta({
    required int mangaId,
    required String key,
  }) async {
    deletes.add(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
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

void main() {
  late _RecordingRepo repo;

  Future<void> pumpTab(
    WidgetTester tester, {
    Map<String, String> meta = const {},
  }) async {
    // Tall viewport so the common rows fit without scrolling.
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    repo = _RecordingRepo();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          mangaBookRepositoryProvider.overrideWithValue(repo),
          mangaWithIdProvider(mangaId: 1)
              .overrideWith(() => _FakeMangaWithId(_manga(meta: meta))),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ReadingModeTab(
              mangaId: 1,
              readerPadding: ValueNotifier(0.0),
              magnifierSize: ValueNotifier(1.0),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder tabScrollable() => find
      .descendant(
        of: find.byType(ReadingModeTab),
        matching: find.byType(Scrollable),
      )
      .first;

  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(ReadingModeTab)));

  testWidgets('renders the 6 parity chips; no legacy chip for a mapped mode',
      (tester) async {
    await pumpTab(tester);

    expect(find.widgetWithText(FilterChip, 'Paged (left to right)'),
        findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Paged (right to left)'),
        findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Paged (vertical)'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Long strip'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Long strip with gaps'),
        findsOneWidget);
    expect(find.text('Continuous horizontal (legacy)'), findsNothing);
  });

  testWidgets(
      'legacy orphan: extra active chip shown; rotation write preserves the '
      'stored mode (§2.5)', (tester) async {
    await pumpTab(
      tester,
      meta: {'flutter_readerMode': 'continuousHorizontalRTL'},
    );

    final legacyChip = find.widgetWithText(
      FilterChip,
      'Continuous horizontal (legacy)',
    );
    expect(legacyChip, findsOneWidget);
    expect(tester.widget<FilterChip>(legacyChip).selected, isTrue);

    await tester.tap(find.text('Portrait'));
    await tester.pumpAndSettle();

    expect(repo.patches, [('flutter_readerOrientation', 'portrait')]);
    expect(repo.deletes, isEmpty);
  });

  testWidgets('tap-invert row hidden when tap zones are Disabled',
      (tester) async {
    await pumpTab(
      tester,
      meta: {'flutter_readerNavigationLayout': 'disabled'},
    );
    expect(find.text('Invert tap zones'), findsNothing);
  });

  testWidgets('tap-invert row shown for an enabled tap-zone layout',
      (tester) async {
    await pumpTab(
      tester,
      meta: {'flutter_readerNavigationLayout': 'lShaped'},
    );
    await tester.scrollUntilVisible(
      find.text('Invert tap zones'),
      100,
      scrollable: tabScrollable(),
    );
    expect(find.text('Invert tap zones'), findsOneWidget);
    expect(find.text('Horizontal'), findsOneWidget);
  });

  testWidgets('paged mode shows the paged section, not the long-strip one',
      (tester) async {
    await pumpTab(tester, meta: {'flutter_readerMode': 'singleHorizontalLTR'});

    await tester.scrollUntilVisible(
      find.text('Scale type'),
      200,
      scrollable: tabScrollable(),
    );
    expect(find.text('Scale type'), findsOneWidget);
    // Zoom start position is hidden (per-page pan on list-level zoom; reader.md).
    expect(find.text('Zoom start position'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Disable zoom out'),
      200,
      scrollable: tabScrollable(),
    );
    expect(find.text('Double tap to zoom'), findsOneWidget);
    expect(find.text('Pinch to Zoom'), findsOneWidget);
    expect(find.text('Disable zoom out'), findsOneWidget);
    expect(find.text('Disable zoom in'), findsNothing);
    expect(find.text('Smart scale on wide screen'), findsNothing);
    expect(find.text('Smooth Auto Scroll'), findsNothing);
  });

  testWidgets('long-strip mode shows smart scale, not the paged chips',
      (tester) async {
    await pumpTab(tester, meta: {'flutter_readerMode': 'webtoon'});

    await tester.scrollUntilVisible(
      find.text('Smart scale on wide screen'),
      200,
      scrollable: tabScrollable(),
    );
    expect(find.text('Smart scale on wide screen'), findsOneWidget);
    expect(find.text('Scale type'), findsNothing);
    // Gaps-scoped crop borders only appears in Long-strip-with-gaps mode.
    await tester.scrollUntilVisible(
      find.text('Crop borders'),
      200,
      scrollable: tabScrollable(),
    );
    expect(find.text('Crop borders'), findsOneWidget);
  });

  testWidgets(
      'long strip auto-scroll tiles: toggle, interval slider, and scroll '
      'amount chips all write their providers', (tester) async {
    await pumpTab(tester, meta: {'flutter_readerMode': 'webtoon'});

    await tester.scrollUntilVisible(
      find.text('Smooth Auto Scroll'),
      200,
      scrollable: tabScrollable(),
    );
    expect(find.text('Smooth Auto Scroll'), findsOneWidget);
    // Defaults ON (DBKeys.smoothAutoScroll(true)), so a tap flips it OFF.
    await tester.tap(find.text('Smooth Auto Scroll'));
    await tester.pumpAndSettle();
    expect(container(tester).read(smoothAutoScrollProvider), isFalse);

    await tester.scrollUntilVisible(
      find.text('Auto scroll interval'),
      200,
      scrollable: tabScrollable(),
    );
    expect(find.text('Auto scroll interval'), findsOneWidget);
    final slider = find.descendant(
      of: find.widgetWithText(ListTile, 'Auto scroll interval'),
      matching: find.byType(Slider),
    );
    tester.widget<Slider>(slider).onChanged!(20);
    await tester.pumpAndSettle();
    expect(container(tester).read(autoScrollIntervalSecondsProvider), 20);

    await tester.scrollUntilVisible(
      find.text('Keyboard scroll distance'),
      200,
      scrollable: tabScrollable(),
    );
    expect(find.text('Keyboard scroll distance'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Large'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilterChip, 'Tiny'));
    await tester.pumpAndSettle();
    expect(
      container(tester).read(readerScrollAmountKeyProvider),
      ReaderScrollAmount.tiny,
    );
  });

  testWidgets('long strip with gaps adds the gaps-scoped crop borders',
      (tester) async {
    await pumpTab(tester, meta: {'flutter_readerMode': 'continuousVertical'});

    await tester.scrollUntilVisible(
      find.text('Disable zoom out'),
      200,
      scrollable: tabScrollable(),
    );
    await tester.pumpAndSettle();
    expect(find.text('Crop borders'), findsNWidgets(2));
  });

  testWidgets(
      'pure Komikku: "For this series" is a heading, not a scope switch',
      (tester) async {
    await pumpTab(tester, meta: {'flutter_readerMode': 'singleHorizontalLTR'});
    // The group heading is present...
    expect(find.text('For this series'), findsOneWidget);
    // ...and it is a plain heading, not a scope toggle (no switch on that row).
    expect(
      find.ancestor(
        of: find.text('For this series'),
        matching: find.byType(SwitchListTile),
      ),
      findsNothing,
    );
  });

  testWidgets('reading mode always writes a per-series override',
      (tester) async {
    await pumpTab(tester, meta: {'flutter_readerMode': 'singleHorizontalLTR'});

    await tester.tap(find.text('Long strip'));
    await tester.pumpAndSettle();

    expect(repo.patches, [('flutter_readerMode', 'webtoon')]);
    expect(repo.deletes, isEmpty);
  });

  testWidgets(
      'paged wide-page toggles ordered before Animate page transitions; '
      'invert sub-toggles hidden while OFF; Pan wide images visible',
      (tester) async {
    await pumpTab(tester, meta: {'flutter_readerMode': 'singleHorizontalLTR'});

    await tester.scrollUntilVisible(
      find.text('Animate page transitions'),
      200,
      scrollable: tabScrollable(),
    );

    expect(find.text('Pan wide images'), findsOneWidget);
    double dy(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(dy('Split wide pages'), lessThan(dy('Rotate wide pages to fit')));
    expect(
      dy('Rotate wide pages to fit'),
      lessThan(dy('Animate page transitions')),
    );
    expect(find.text('Invert split pages placement'), findsNothing);
    expect(find.text('Invert rotation of wide pages'), findsNothing);
    // KEEP extra lives in the paged section too.
    expect(find.text('Dual page spread in landscape'), findsOneWidget);
  });

  testWidgets(
      'paged split ON reveals its invert sub-toggle and writes the global '
      'providers', (tester) async {
    await pumpTab(tester, meta: {'flutter_readerMode': 'singleHorizontalLTR'});

    await tester.scrollUntilVisible(
      find.text('Split wide pages'),
      200,
      scrollable: tabScrollable(),
    );
    await tester.tap(find.text('Split wide pages'));
    await tester.pumpAndSettle();

    expect(container(tester).read(dualPageSplitPagedProvider), isTrue);
    expect(find.text('Invert split pages placement'), findsOneWidget);

    await tester.tap(find.text('Invert split pages placement'));
    await tester.pumpAndSettle();
    expect(container(tester).read(dualPageInvertPagedProvider), isTrue);
    expect(repo.patches, isEmpty, reason: 'global prefs never touch meta');
  });

  testWidgets(
      'rotate-wide ON reveals its invert sub-toggle and writes the global '
      'providers', (tester) async {
    await pumpTab(tester, meta: {'flutter_readerMode': 'singleHorizontalLTR'});

    await tester.scrollUntilVisible(
      find.text('Rotate wide pages to fit'),
      200,
      scrollable: tabScrollable(),
    );
    await tester.tap(find.text('Rotate wide pages to fit'));
    await tester.pumpAndSettle();

    expect(container(tester).read(rotateWidePagesProvider), isTrue);
    expect(find.text('Invert rotation of wide pages'), findsOneWidget);

    await tester.tap(find.text('Invert rotation of wide pages'));
    await tester.pumpAndSettle();
    expect(container(tester).read(rotateWideInvertProvider), isTrue);
  });

  testWidgets('dual page spread toggle writes its global provider',
      (tester) async {
    await pumpTab(tester, meta: {'flutter_readerMode': 'singleHorizontalLTR'});

    await tester.scrollUntilVisible(
      find.text('Dual page spread in landscape'),
      200,
      scrollable: tabScrollable(),
    );
    await tester.ensureVisible(find.text('Dual page spread in landscape'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dual page spread in landscape'));
    await tester.pumpAndSettle();

    expect(container(tester).read(trueDualPageSpreadProvider), isTrue);
  });

  testWidgets(
      'webtoon split-wide is hidden (frozen page-list remap); no paged-only '
      'rows leak into the long-strip section', (tester) async {
    await pumpTab(tester, meta: {'flutter_readerMode': 'webtoon'});

    await tester.scrollUntilVisible(
      find.text('Disable zoom out'),
      200,
      scrollable: tabScrollable(),
    );
    // Webtoon dual-split (+invert) is hidden — a 1→2 page-list remap would
    // breach the frozen webtoon scroll math (see reader.md).
    expect(find.text('Split wide pages'), findsNothing);
    expect(find.text('Invert split pages placement'), findsNothing);
    // Paged-only rows must not leak into the long-strip section either.
    expect(find.text('Rotate wide pages to fit'), findsNothing);
    expect(find.text('Dual page spread in landscape'), findsNothing);
  });
}
