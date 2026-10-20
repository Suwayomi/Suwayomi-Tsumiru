// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Arrow-key navigation over the History page's desktop search dropdown: the
// leading History rows are keyboard-reachable in visual order before the
// unified rows, and Enter opens the highlighted row exactly as a tap would.

import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/history/data/graphql/__generated__/query.graphql.dart';
import 'package:tsumiru/src/features/history/domain/history_item.dart';
import 'package:tsumiru/src/features/history/presentation/history_controller.dart';
import 'package:tsumiru/src/features/history/presentation/history_screen.dart';
import 'package:tsumiru/src/features/library/presentation/category/controller/edit_category_controller.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_manga_list.dart';
import 'package:tsumiru/src/features/quick_open/presentation/unified_search/desktop_search_field.dart';
import 'package:tsumiru/src/features/quick_open/presentation/unified_search/unified_search_results.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/widgets/desktop/desktop_top_bar.dart';

import '../../../helpers/unreachable_server_stubs.dart';

const _desktop = Size(1400, 980);

void _setSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

HistoryItemDto _historyItem({
  required int id,
  required int mangaId,
  required String seriesTitle,
  required String chapter,
}) => Fragment$HistoryChapterDto(
  id: id,
  chapterNumber: 1,
  fetchedAt: '0',
  isBookmarked: false,
  isDownloaded: false,
  isRead: false,
  lastPageRead: 4,
  lastReadAt: '1700000000',
  mangaId: mangaId,
  name: chapter,
  pageCount: 10,
  sourceOrder: 1,
  uploadDate: '0',
  url: '/c/$id',
  meta: const [],
  manga: Fragment$HistoryChapterDto$manga(
    id: mangaId,
    inLibrary: true,
    title: seriesTitle,
    unreadCount: 3,
  ),
);

class _StubReadingHistory extends ReadingHistory {
  _StubReadingHistory(this.items);

  final List<HistoryItemDto> items;

  @override
  Future<List<HistoryItemDto>?> build() async => items;
}

Future<ProviderContainer> _container(List<HistoryItemDto> items) async {
  SharedPreferences.setMockInitialValues({});
  final sp = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(sp),
      readingHistoryProvider.overrideWith(() => _StubReadingHistory(items)),
      libraryMangaListProvider.overrideWith((ref) async => []),
      visibleCategoryListProvider.overrideWithValue(const AsyncData([])),
      ...unreachableServerStubs,
    ],
  );
  addTearDown(container.dispose);
  return container;
}

GoRouter _router() => GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      // Native desktop draws the toolbar in the shell bar above the page.
      path: '/',
      builder: (_, _) => Scaffold(
        body: Builder(
          builder: (context) => Column(
            children: [
              if (showsMergedTopBar(context)) const DesktopTopBar(),
              const Expanded(child: HistoryScreen()),
            ],
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
        body: Center(child: Text('MANGA ${state.pathParameters['mangaId']}')),
      ),
    ),
  ],
);

Future<void> _pumpHistory(
  WidgetTester tester,
  ProviderContainer container,
) async {
  _setSize(tester, _desktop);
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

// Dropdown rows only — the page list behind the dropdown shows the same
// series titles.
Finder _dropRow(String text) => find.descendant(
  of: find.byType(UnifiedSearchResults),
  matching: find.text(text),
);

Future<void> _down(WidgetTester tester, [int n = 1]) async {
  for (var i = 0; i < n; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
  }
}

Future<void> _submit(WidgetTester tester) async {
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

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
    if (node.getSemanticsData().flagsCollection.isSelected == Tristate.isTrue) {
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
  group('history dropdown arrow-key navigation', () {
    testWidgets('Down walks History rows then unified rows, Enter opens', (
      tester,
    ) async {
      final sem = tester.ensureSemantics();
      final container = await _container([
        _historyItem(
          id: 1,
          mangaId: 7,
          seriesTitle: 'Upd One',
          chapter: 'Chapter 1',
        ),
        _historyItem(
          id: 2,
          mangaId: 8,
          seriesTitle: 'Upd Two',
          chapter: 'Chapter 2',
        ),
      ]);
      await _pumpHistory(tester, container);

      await _typeUpd(tester);
      expect(_dropRow('Upd One'), findsOneWidget);
      expect(_dropRow('Upd Two'), findsOneWidget);
      expect(_treeHasSelected(tester), isFalse);

      // The first Down lands on the first History row.
      await _down(tester);
      expect(_isHighlighted(tester, _dropRow('Upd One')), isTrue);
      expect(_treeHasSelected(tester), isTrue);

      // The second lands on the second History row.
      await _down(tester);
      expect(_isHighlighted(tester, _dropRow('Upd Two')), isTrue);

      // The third reaches the unified rows; the History header is not a stop.
      await _down(tester);
      expect(_isHighlighted(tester, find.text('Updates')), isTrue);
      // The handle must go before the end of the test, not in a tearDown.
      sem.dispose();
      await _submit(tester);

      expect(find.text('UPDATES PAGE'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
