// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Arrow-key navigation in the desktop search dropdown: Up/Down move a
// highlight across every section in visual order, Enter opens the
// highlighted row exactly as a tap would, and typing resets the highlight.

import 'dart:ui' show Tristate;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/library/domain/category/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/library/presentation/category/controller/edit_category_controller.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_manga_list.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/quick_open/presentation/unified_search/desktop_search_field.dart';
import 'package:tsumiru/src/features/quick_open/presentation/unified_search/unified_search_providers.dart';
import 'package:tsumiru/src/features/quick_open/presentation/unified_search/unified_search_results.dart';
import 'package:tsumiru/src/features/quick_open/presentation/unified_search/unified_search_screen.dart';
import 'package:tsumiru/src/features/settings/controller/server_controller.dart';
import 'package:tsumiru/src/features/settings/domain/settings/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/settings/domain/settings/settings.dart';
import 'package:tsumiru/src/features/settings/presentation/koreader_sync/data/koreader_sync_repository.dart';
import 'package:tsumiru/src/features/settings/presentation/koreader_sync/domain/koreader_sync_domain.dart';
import 'package:tsumiru/src/features/settings/presentation/server/data/web_interface_repository.dart';
import 'package:tsumiru/src/features/settings/presentation/syncyomi/data/syncyomi_settings_provider.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

import '../../../helpers/unreachable_server_stubs.dart';

const _desktop = Size(1400, 980);

void _setSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Fragment$MangaDto _manga(int id, String title) => Fragment$MangaDto(
  id: id,
  title: title,
  thumbnailUrl: null,
  bookmarkCount: 0,
  chapters: Fragment$MangaDto$chapters(totalCount: 4),
  downloadCount: 1,
  genre: const [],
  inLibrary: true,
  inLibraryAt: '0',
  initialized: true,
  meta: const [],
  sourceId: '1',
  status: Enum$MangaStatus.ONGOING,
  categories: Fragment$MangaDto$categories(nodes: const []),
  trackRecords: Fragment$MangaDto$trackRecords(nodes: const []),
  unreadCount: 2,
  updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
  url: '/manga/$id',
);

const _emptyCategories = AsyncData(<Fragment$CategoryDto>[]);

// Reachable server, so the server-gated Settings rows render like on their
// pages (same overrides as the settings-search tests).
SettingsDto _loadedSettings() => Fragment$SettingsDto(
  backupInterval: 0,
  backupPath: '',
  backupTTL: 0,
  backupTime: '',
  ip: '0.0.0.0',
  port: 4567,
  socksProxyEnabled: false,
  socksProxyHost: '',
  socksProxyPassword: '',
  socksProxyPort: '',
  socksProxyUsername: '',
  socksProxyVersion: 5,
  flareSolverrEnabled: false,
  flareSolverrSessionName: '',
  flareSolverrSessionTtl: 0,
  flareSolverrTimeout: 0,
  flareSolverrUrl: '',
  debugLogsEnabled: false,
  systemTrayEnabled: false,
  extensionRepos: const [],
  maxSourcesInParallel: 0,
  localSourcePath: '',
  globalUpdateInterval: 12,
  updateMangas: false,
  excludeCompleted: false,
  excludeNotStarted: false,
  excludeUnreadChapters: false,
  downloadAsCbz: false,
  downloadsPath: '',
  autoDownloadNewChapters: false,
  autoDownloadNewChaptersLimit: 0,
  excludeEntryWithUnreadChapters: false,
);

class _LoadedSettings extends Settings {
  @override
  Future<SettingsDto?> build() async => _loadedSettings();
}

Future<ProviderContainer> _container({
  List<Fragment$MangaDto> library = const [],
}) async {
  SharedPreferences.setMockInitialValues({});
  final sp = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(sp),
      libraryMangaListProvider.overrideWith((ref) async => library),
      visibleCategoryListProvider.overrideWithValue(_emptyCategories),
      settingsProvider.overrideWith(_LoadedSettings.new),
      webInterfaceSettingsProvider.overrideWith((ref) async => null),
      syncYomiSettingsProvider.overrideWith((ref) async => null),
      koreaderSyncSettingsProvider.overrideWith((ref) async => null),
      koSyncStatusProvider.overrideWith(
        (ref) async => const KoSyncStatus(isLoggedIn: false),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

GoRouter _router() => GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => Scaffold(
        body: Center(
          child: SizedBox(
            width: 500,
            child: Consumer(
              builder: (context, ref, _) => DesktopSearchField(
                query: ref.watch(unifiedSearchQueryProvider),
                onChanged: (value) =>
                    ref.read(unifiedSearchQueryProvider.notifier).state = value,
                onNavigate: () =>
                    ref.read(unifiedSearchQueryProvider.notifier).state = '',
              ),
            ),
          ),
        ),
      ),
    ),
    GoRoute(
      path: '/updates',
      builder: (_, _) =>
          const Scaffold(body: Center(child: Text('UPDATES PAGE'))),
    ),
    GoRoute(
      path: '/manga/:mangaId',
      builder: (_, state) => Scaffold(
        body: Center(
          child: Text('MANGA ${state.pathParameters['mangaId']}'),
        ),
      ),
    ),
    GoRoute(
      path: '/global-search',
      builder: (_, _) =>
          const Scaffold(body: Center(child: Text('GLOBAL SEARCH PAGE'))),
    ),
    GoRoute(
      path: '/more/settings/library',
      builder: (_, state) => Scaffold(
        body: Center(
          child: Text(
            'SETTINGS library highlight=${state.uri.queryParameters['highlight']}',
          ),
        ),
      ),
    ),
  ],
);

Future<void> _pumpWithRouter(
  WidgetTester tester,
  ProviderContainer container, {
  Size size = _desktop,
}) async {
  _setSize(tester, size);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: _router(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _field() => find.descendant(
  of: find.byType(DesktopSearchField),
  matching: find.byType(TextField),
);

Future<void> _down(WidgetTester tester, [int n = 1]) async {
  for (var i = 0; i < n; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
  }
}

Future<void> _up(WidgetTester tester, [int n = 1]) async {
  for (var i = 0; i < n; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
  }
}

Future<void> _submit(WidgetTester tester) async {
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

// "upd" hits Library, Go to, Settings, and Search all sources with few rows.
Future<void> _typeUpd(WidgetTester tester) async {
  await tester.enterText(_field(), 'upd');
  await tester.pump();
  await tester.pump();
}

// The highlight paints the row's hover colour, so the highlighted row is the
// ancestor Material wearing it. (Semantics flags live on ancestor nodes and
// don't merge down into the row's Text, so colour is the row-identity check;
// the selected flag itself is covered by [_treeHasSelected].)
bool _isHighlighted(WidgetTester tester, Finder text) {
  final hover = Theme.of(tester.element(text)).hoverColor;
  return tester
      .widgetList<Material>(
        find.ancestor(of: text, matching: find.byType(Material)),
      )
      .any((m) => m.color == hover);
}

// Whether any node in the semantics tree carries the selected flag — the
// screen-reader announcement for the highlight.
bool _treeHasSelected(WidgetTester tester) {
  var found = false;
  void visit(SemanticsNode node) {
    if (found) return;
    if (node.getSemanticsData().flagsCollection.isSelected ==
        Tristate.isTrue) {
      found = true;
      return;
    }
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  // The test tree renders under the per-view owner, not the root one.
  // ignore: deprecated_member_use
  final root = tester.binding.pipelineOwner.semanticsOwner?.rootSemanticsNode;
  if (root != null) visit(root);
  return found;
}

void main() {
  group('desktop search arrow-key navigation', () {
    testWidgets('Down, Down, Enter opens the second row', (tester) async {
      final container = await _container(
        library: [_manga(2, 'Update Notes')],
      );
      await _pumpWithRouter(tester, container);

      await _typeUpd(tester);
      expect(find.text('Updates'), findsOneWidget);

      await _down(tester, 2);
      expect(_isHighlighted(tester, find.text('Updates')), isTrue);
      await _submit(tester);

      expect(find.text('UPDATES PAGE'), findsOneWidget);
      expect(
        container.read(unifiedSearchQueryProvider),
        isEmpty,
        reason: 'leaving through a result clears the query',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('Up returns to the first row', (tester) async {
      await _pumpWithRouter(
        tester,
        await _container(library: [_manga(2, 'Update Notes')]),
      );

      await _typeUpd(tester);
      await _down(tester, 2);
      await _up(tester);
      await _submit(tester);

      expect(find.text('MANGA 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Up from the first row clears the highlight', (tester) async {
      final sem = tester.ensureSemantics();
      await _pumpWithRouter(
        tester,
        await _container(library: [_manga(2, 'Update Notes')]),
      );

      await _typeUpd(tester);
      expect(_treeHasSelected(tester), isFalse);

      await _down(tester);
      expect(_isHighlighted(tester, find.text('Update Notes')), isTrue);
      expect(_treeHasSelected(tester), isTrue);

      // Up from the first row goes back to none, so Enter keeps the
      // top-result rule instead of opening the first row as highlighted.
      await _up(tester);
      expect(_treeHasSelected(tester), isFalse);
      // The handle must go before the end of the test, not in a tearDown.
      sem.dispose();
      await _submit(tester);

      expect(find.text('MANGA 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('highlight resets when the text changes', (tester) async {
      final sem = tester.ensureSemantics();
      await _pumpWithRouter(
        tester,
        await _container(library: [_manga(2, 'Update Notes')]),
      );

      await _typeUpd(tester);
      await _down(tester);
      expect(_isHighlighted(tester, find.text('Update Notes')), isTrue);
      expect(_treeHasSelected(tester), isTrue);

      // Typing keeps working with focus in the field, and clears the
      // highlight: only "Search all sources" matches, so Enter hands off.
      await tester.enterText(_field(), 'upd x');
      await tester.pump();
      await tester.pump();
      expect(_treeHasSelected(tester), isFalse);
      expect(
        tester.widget<TextField>(_field()).focusNode?.hasFocus,
        isTrue,
        reason: 'focus stays in the field while moving',
      );
      // The handle must go before the end of the test, not in a tearDown.
      sem.dispose();
      await _submit(tester);

      expect(find.text('GLOBAL SEARCH PAGE'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Enter with no highlight keeps the top-result behaviour', (
      tester,
    ) async {
      await _pumpWithRouter(
        tester,
        await _container(library: [_manga(2, 'Update Notes')]),
      );

      await _typeUpd(tester);
      await _submit(tester);

      expect(find.text('MANGA 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('rows across sections are reachable in visual order', (
      tester,
    ) async {
      await _pumpWithRouter(
        tester,
        await _container(library: [_manga(2, 'Update Notes')]),
      );

      // Go to sits right after the Library row: two Downs reach it, so the
      // Library and Go to headers are not stops.
      await _typeUpd(tester);
      await _down(tester, 2);
      await _submit(tester);
      expect(find.text('UPDATES PAGE'), findsOneWidget);
    });

    testWidgets('a Settings row opens its page with the highlight id', (
      tester,
    ) async {
      await _pumpWithRouter(
        tester,
        await _container(library: [_manga(2, 'Update Notes')]),
      );

      // Three Downs reach the first Settings row, past both headers, so the
      // Settings header is not a stop either.
      await _typeUpd(tester);
      await _down(tester, 3);
      expect(_isHighlighted(tester, find.text('Automatic Update')), isTrue);
      await _submit(tester);

      expect(
        find.text('SETTINGS library highlight=automaticUpdate'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('Search all sources is reachable after every row', (
      tester,
    ) async {
      await _pumpWithRouter(
        tester,
        await _container(library: [_manga(2, 'Update Notes')]),
      );

      // Walk down until the handoff row highlights, however many Settings
      // rows sit above it, then Enter hands off to global search.
      await _typeUpd(tester);
      final handoff = find.text(
        'Search all sources for "upd"',
        skipOffstage: false,
      );
      var reached = false;
      for (var i = 0; i < 40 && !reached; i++) {
        await _down(tester);
        await tester.pump();
        reached =
            tester.any(handoff) && _isHighlighted(tester, handoff);
      }
      expect(reached, isTrue);
      await _submit(tester);

      expect(find.text('GLOBAL SEARCH PAGE'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a field suggestion takes part in the order', (tester) async {
      await _pumpWithRouter(tester, await _container());

      // 'unread:' offers value completions at the top of the order, so the
      // first Down reaches the suggestion row.
      await tester.enterText(_field(), 'unread:');
      await tester.pump();
      await tester.pump();
      expect(find.text('unread:true'), findsOneWidget);

      await _down(tester);
      expect(_isHighlighted(tester, find.text('unread:true')), isTrue);
      await _submit(tester);
      await tester.pump();

      // Enter spliced the suggestion over the active token, trailing space
      // included, exactly as tapping the row would.
      expect(
        tester.widget<TextField>(_field()).controller?.text,
        'unread:true ',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('hover moves the highlight', (tester) async {
      final sem = tester.ensureSemantics();
      await _pumpWithRouter(
        tester,
        await _container(library: [_manga(2, 'Update Notes')]),
      );

      await _typeUpd(tester);
      expect(_treeHasSelected(tester), isFalse);

      final mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.text('Updates')));
      await tester.pump();

      // No arrow key was pressed: hover alone highlighted the row, so Enter
      // opens it.
      expect(_isHighlighted(tester, find.text('Updates')), isTrue);
      expect(_treeHasSelected(tester), isTrue);
      // The handle must go before the end of the test, not in a tearDown.
      sem.dispose();
      await _submit(tester);

      expect(find.text('UPDATES PAGE'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a tall highlight scrolls into view', (tester) async {
      await _pumpWithRouter(
        tester,
        await _container(
          library: [
            _manga(1, 'Alpha One'),
            _manga(2, 'Beta Tales'),
            _manga(3, 'Gamma Saga'),
            _manga(4, 'Delta Notes'),
            _manga(5, 'Zeta Pages'),
            _manga(6, 'Eta Stories'),
            _manga(7, 'Theta Lines'),
          ],
        ),
        size: const Size(1400, 400),
      );

      // "a" matches capped Library hits plus long Go to and Settings runs,
      // overflowing the 280 px dropdown; the handoff row is always last.
      await tester.enterText(_field(), 'a');
      await tester.pump();
      await tester.pump();
      final scroller = find.descendant(
        of: find.byType(UnifiedSearchResults),
        matching: find.byType(Scrollable),
      );
      final listRect = tester.getRect(scroller);
      expect(
        tester.state<ScrollableState>(scroller).position.maxScrollExtent,
        greaterThan(0),
        reason: 'the dropdown actually scrolls',
      );

      final handoff = find.text(
        'Search all sources for "a"',
        skipOffstage: false,
      );
      var reached = false;
      for (var i = 0; i < 40 && !reached; i++) {
        await _down(tester);
        await tester.pump();
        reached = tester.any(handoff) && _isHighlighted(tester, handoff);
      }
      expect(reached, isTrue, reason: 'every row stays reachable');
      await tester.pumpAndSettle();

      expect(
        tester.state<ScrollableState>(scroller).position.pixels,
        greaterThan(0),
        reason: 'the list scrolled',
      );
      expect(
        listRect.contains(tester.getCenter(handoff)),
        isTrue,
        reason: 'the highlighted row scrolled into view',
      );
      await _submit(tester);

      expect(find.text('GLOBAL SEARCH PAGE'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('quick-open overlay arrow-key navigation', () {
    Future<ProviderContainer> pumpOverlay(WidgetTester tester) async {
      _setSize(tester, _desktop);
      SharedPreferences.setMockInitialValues({});
      final sp = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sp),
          libraryMangaListProvider.overrideWith(
            (ref) async => [_manga(1, 'Sword A'), _manga(2, 'Sword B')],
          ),
          visibleCategoryListProvider.overrideWithValue(_emptyCategories),
          ...unreachableServerStubs,
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: GoRouter(
              initialLocation: '/',
              routes: [
                GoRoute(
                  path: '/',
                  builder: (_, _) => Scaffold(
                    body: UnifiedSearchScreen(afterClick: () {}),
                  ),
                ),
                GoRoute(
                  path: '/manga/:mangaId',
                  builder: (_, state) => Scaffold(
                    body: Center(
                      child: Text(
                        'MANGA ${state.pathParameters['mangaId']}',
                      ),
                    ),
                  ),
                ),
                GoRoute(
                  path: '/global-search',
                  builder: (_, _) => const Scaffold(
                    body: Center(child: Text('GLOBAL SEARCH PAGE')),
                  ),
                ),
              ],
            ),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('Down, Down, Enter opens the second library row', (
      tester,
    ) async {
      await pumpOverlay(tester);

      await tester.enterText(find.byType(TextField), 'sword');
      await tester.pump();
      await tester.pump();
      expect(find.text('Sword A'), findsOneWidget);
      expect(find.text('Sword B'), findsOneWidget);

      await _down(tester, 2);
      await _submit(tester);

      expect(find.text('MANGA 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Enter with no highlight opens the top result', (
      tester,
    ) async {
      await pumpOverlay(tester);

      await tester.enterText(find.byType(TextField), 'sword');
      await tester.pump();
      await tester.pump();
      await _submit(tester);

      expect(find.text('MANGA 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
