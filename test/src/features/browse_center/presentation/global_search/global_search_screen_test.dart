// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:queue/queue.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/browse_center/data/source_repository/source_repository.dart';
import 'package:tsumiru/src/features/browse_center/domain/source/source_model.dart';
import 'package:tsumiru/src/features/browse_center/presentation/global_search/controller/source_quick_search_controller.dart';
import 'package:tsumiru/src/features/browse_center/presentation/global_search/global_search_screen.dart';
import 'package:tsumiru/src/features/browse_center/presentation/source/controller/source_controller.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/routes/navigation.dart';
import 'package:tsumiru/src/widgets/desktop/desktop_top_bar.dart';
import 'package:tsumiru/src/widgets/search_field.dart';

SourceDto _source({required String id, required String name}) =>
    SourceDto.fromJson({
      'displayName': name,
      'iconUrl': '',
      'id': id,
      'isConfigurable': false,
      'contentWarning': 'SAFE',
      'lang': 'en',
      'name': name,
      'supportsLatest': true,
      '__typename': 'SourceType',
      'meta': [],
      'extension': {
        'pkgName': 'pkg',
        'repo': 'repo',
        'isObsolete': false,
        '__typename': 'ExtensionType',
      },
    });

MangaDto _manga(int id, String title) => MangaDto.fromJson({
  '__typename': 'MangaType',
  'id': id,
  'title': title,
  'author': '',
  'bookmarkCount': 0,
  'chapters': {'totalCount': 0, '__typename': 'ChapterNodeList'},
  'downloadCount': 0,
  'genre': [],
  'inLibrary': false,
  'inLibraryAt': '0',
  'initialized': true,
  'meta': [],
  'sourceId': '1',
  'status': 'ONGOING',
  'categories': {'nodes': [], '__typename': 'CategoryNodeList'},
  'trackRecords': {'nodes': [], '__typename': 'TrackRecordNodeList'},
  'unreadCount': 0,
  'updateStrategy': 'ALWAYS_UPDATE',
  'url': '',
});

class _AllScope extends GlobalSearchScope {
  @override
  GlobalSearchSourceFilter? build() => GlobalSearchSourceFilter.all;
}

typedef _SourceResult = ({
  SourceDto source,
  Future<List<MangaDto>> Function() search,
});

const _query = 'Solo Leveling';

GoRouter _router({required bool fromSuggestion}) => GoRouter(
  initialLocation: '/home',
  routes: [
    GoRoute(
      path: '/home',
      builder: (context, state) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => openGlobalSearch(
              context,
              query: _query,
              fromSuggestion: fromSuggestion,
            ),
            child: const Text('open search'),
          ),
        ),
      ),
    ),
    GoRoute(
      path: '/global-search',
      // Native desktop draws the search box in the shell bar above the
      // page. The body is keyed like the shells' so a breakpoint toggle
      // moves the page instead of remounting it.
      builder: (context, state) => Scaffold(
        body: Builder(
          builder: (context) => Column(
            children: [
              if (showsMergedTopBar(context)) const DesktopTopBar(),
              Expanded(
                key: const ValueKey('searchPage'),
                child: GlobalSearchScreen(
                  initialQuery: state.uri.queryParameters['query'],
                  fromSuggestion:
                      state.uri.queryParameters['from-suggestion'] == 'true',
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    GoRoute(
      path: '/manga/:mangaId',
      builder: (context, state) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('MANGA ${state.pathParameters['mangaId']}')),
      ),
    ),
  ],
);

Future<void> _pumpSearch(
  WidgetTester tester, {
  required bool fromSuggestion,
  required List<_SourceResult> sources,
  Duration? Function(int, Object)? retry,
  SourceRepository? repository,
  Queue? queue,
  bool overrideSourceSearches = true,
  Size? size,
  bool settle = true,
  Future<List<SourceDto>?> Function(Ref ref)? sourceList,
  AsyncValue<List<SourceDto>> Function(Ref ref)? searchableSources,
}) async {
  if (size != null) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
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
    ProviderScope(
      retry: retry,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        globalSearchScopeProvider.overrideWith(_AllScope.new),
        sourceListProvider.overrideWith(
          sourceList ?? (ref) async => [for (final s in sources) s.source],
        ),
        searchableSourcesProvider.overrideWith(
          searchableSources ??
              (ref) => AsyncData([for (final s in sources) s.source]),
        ),
        pinnedSourcesProvider.overrideWithValue(const []),
        if (repository != null)
          sourceRepositoryProvider.overrideWithValue(repository),
        if (queue != null)
          rateLimitQueueProvider(_query).overrideWithValue(queue),
        if (overrideSourceSearches)
          for (final s in sources)
            sourceQuickSearchMangaListProvider(
              s.source.id,
              query: _query,
            ).overrideWith((ref) => s.search()),
      ],
      child: MaterialApp.router(
        routerConfig: _router(fromSuggestion: fromSuggestion),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open search'));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }
}

void main() {
  testWidgets('a failed source shows an inline error and Retry re-fetches '
      'only that source', (tester) async {
    final alpha = _source(id: '1', name: 'Alpha');
    final comix = _source(id: '2', name: 'Comix (EN)');
    final beta = _source(id: '3', name: 'Beta');
    var comixCalls = 0;
    var alphaCalls = 0;
    var betaCalls = 0;

    await _pumpSearch(
      tester,
      fromSuggestion: false,
      sources: [
        (
          source: alpha,
          search: () async {
            alphaCalls++;
            return <MangaDto>[];
          },
        ),
        (
          source: comix,
          search: () async {
            comixCalls++;
            if (comixCalls == 1) throw TimeoutException('timed out');
            return <MangaDto>[];
          },
        ),
        (
          source: beta,
          search: () async {
            betaCalls++;
            throw Exception('boom');
          },
        ),
      ],
    );

    expect(find.text("Couldn't reach Comix (EN)"), findsOneWidget);
    expect(find.text("Couldn't reach Beta"), findsOneWidget);
    expect(find.text("can't reach the server"), findsNothing);
    expect(alphaCalls, 1);

    final comixRow = find
        .ancestor(
          of: find.text("Couldn't reach Comix (EN)"),
          matching: find.byType(Row),
        )
        .first;
    await tester.tap(
      find.descendant(of: comixRow, matching: find.text('Retry')),
    );
    await tester.pumpAndSettle();

    expect(comixCalls, 2);
    expect(alphaCalls, 1);
    expect(betaCalls, 1);
    expect(find.text("Couldn't reach Comix (EN)"), findsNothing);
    expect(find.text("Couldn't reach Beta"), findsOneWidget);
  });

  testWidgets('phone keeps the title and puts the chips below the field', (
    tester,
  ) async {
    await _pumpSearch(
      tester,
      fromSuggestion: false,
      sources: [
        (
          source: _source(id: '1', name: 'Alpha'),
          search: () async => <MangaDto>[],
        ),
      ],
      size: const Size(412, 900),
    );

    expect(find.widgetWithText(AppBar, 'Global Search'), findsOneWidget);

    final field = find.byType(SearchField);
    final allChip = find.widgetWithText(FilterChip, 'All');
    expect(field, findsOneWidget);
    expect(allChip, findsOneWidget);
    expect(
      tester.getTopLeft(allChip).dy,
      greaterThan(tester.getBottomLeft(field).dy),
    );
  });

  testWidgets('a lone exact match from a suggestion opens the series and '
      'replaces the search route', (tester) async {
    await _pumpSearch(
      tester,
      fromSuggestion: true,
      sources: [
        (
          source: _source(id: '1', name: 'Alpha'),
          search: () async => [_manga(7, '  solo   leveling ')],
        ),
        (
          source: _source(id: '2', name: 'Beta'),
          search: () async => [_manga(8, 'Something else')],
        ),
      ],
    );

    expect(find.text('MANGA 7'), findsOneWidget);
    expect(find.text('open search'), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('MANGA 7'), findsNothing);
    expect(find.text('open search'), findsOneWidget);
  });

  testWidgets('desktop draws the field in the shell bar, the chips below '
      'it, and names the route for assistive tech', (tester) async {
    final semantics = tester.ensureSemantics();

    await _pumpSearch(
      tester,
      fromSuggestion: false,
      sources: [
        (
          source: _source(id: '1', name: 'Alpha'),
          search: () async => <MangaDto>[],
        ),
      ],
      size: const Size(1400, 980),
    );

    expect(find.text('Global Search'), findsNothing);
    expect(find.byType(AppBar), findsNothing);

    // The search box moved to the shell bar; the chips stay in the body.
    final barRect = tester.getRect(find.byType(DesktopTopBar));
    final field = find.descendant(
      of: find.byType(DesktopTopBar),
      matching: find.byType(SearchField),
    );
    expect(field, findsOneWidget);
    expect(barRect.contains(tester.getCenter(field)), isTrue);
    final allChip = find.widgetWithText(FilterChip, 'All');
    expect(allChip, findsOneWidget);
    expect(
      tester.getTopLeft(allChip).dy,
      greaterThanOrEqualTo(barRect.bottom - 1),
    );

    final header = tester.getSemantics(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Global Search' &&
            widget.properties.namesRoute == true,
      ),
    );
    expect(header.flagsCollection.isHeader, isTrue);

    semantics.dispose();
  });

  testWidgets('typing a different query without submitting cancels the '
      'auto-open', (tester) async {
    final exact = Completer<List<MangaDto>>();

    await _pumpSearch(
      tester,
      fromSuggestion: true,
      settle: false,
      sources: [
        (source: _source(id: '1', name: 'Alpha'), search: () => exact.future),
      ],
    );

    await tester.enterText(find.byType(TextField), 'Something else');
    await tester.pump();

    exact.complete([_manga(7, _query)]);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('MANGA 7'), findsNothing);
    expect(find.text('Alpha'), findsOneWidget);
  });

  testWidgets('crossing the desktop breakpoint keeps search focus', (
    tester,
  ) async {
    await _pumpSearch(
      tester,
      fromSuggestion: false,
      sources: [
        (
          source: _source(id: '1', name: 'Alpha'),
          search: () async => <MangaDto>[],
        ),
      ],
      size: const Size(915, 412),
    );

    final focusNode = tester
        .widget<TextField>(find.byType(TextField))
        .focusNode!;
    expect(focusNode.hasFocus, isTrue);

    tester.view.physicalSize = const Size(900, 900);
    await tester.pumpAndSettle();

    expect(find.byType(AppBar), findsNothing);
    expect(focusNode.hasFocus, isTrue);
  });
}
