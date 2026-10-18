// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/legacy.dart';
import 'package:queue/queue.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/app_sizes.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/browse_center/data/source_repository/source_repository.dart';
import 'package:tsumiru/src/features/browse_center/domain/filter/filter_model.dart';
import 'package:tsumiru/src/features/browse_center/domain/manga_page/manga_page.dart';
import 'package:tsumiru/src/features/browse_center/domain/source/source_model.dart';
import 'package:tsumiru/src/features/browse_center/presentation/global_search/controller/source_quick_search_controller.dart';
import 'package:tsumiru/src/features/browse_center/presentation/global_search/global_search_screen.dart';
import 'package:tsumiru/src/features/browse_center/presentation/source/controller/source_controller.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/routes/navigation.dart';
import 'package:tsumiru/src/utils/network/graphql_errors.dart';
import 'package:tsumiru/src/widgets/custom_circular_progress_indicator.dart';
import 'package:tsumiru/src/widgets/manga_cover/grid/manga_cover_grid_tile.dart';
import 'package:tsumiru/src/widgets/search_field.dart';

import '../../../../../helpers/fake_extension_repository.dart';
import '../../../../../helpers/legacy_account_access.dart';

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

class _FailingSourceRepository extends SourceRepository {
  _FailingSourceRepository()
    : super(dummyGraphQLClient(), permissions: legacyAccountPermissions);

  int searchCalls = 0;

  @override
  Future<MangaPage?> fetchSourceManga({
    required String sourceId,
    required SourceType sourceType,
    required int page,
    String? query,
    List<FilterChange>? filters,
  }) async {
    searchCalls++;
    throw Exception('HTTP 522');
  }
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
      builder: (context, state) => GlobalSearchScreen(
        initialQuery: state.uri.queryParameters['query'],
        fromSuggestion: state.uri.queryParameters['from-suggestion'] == 'true',
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

  testWidgets('a loading source reserves the cover row height with a small '
      'indicator', (tester) async {
    final pending = Completer<List<MangaDto>>();

    await _pumpSearch(
      tester,
      fromSuggestion: false,
      settle: false,
      sources: [
        (source: _source(id: '1', name: 'Alpha'), search: () => pending.future),
      ],
    );

    expect(find.byType(CenterSorayomiShimmerIndicator), findsNothing);

    final indicator = find.byType(SorayomiShimmerIndicator);
    expect(indicator, findsOneWidget);

    final boxes = find.ancestor(
      of: indicator,
      matching: find.byType(SizedBox),
    );
    expect(tester.getSize(boxes.first), const Size.square(48));
    expect(
      tester.getSize(boxes.at(1)).height,
      mangaCoverBoxHeight(kShortSearchCoverWidth),
    );

    pending.complete(<MangaDto>[]);
    await tester.pumpAndSettle();
  });

  testWidgets('a failed source is not retried automatically under the app '
      'retry policy', (tester) async {
    final comix = _source(id: '2', name: 'Comix (EN)');
    final repository = _FailingSourceRepository();

    await _pumpSearch(
      tester,
      fromSuggestion: false,
      sources: [(source: comix, search: () async => <MangaDto>[])],
      overrideSourceSearches: false,
      retry: (retryCount, error) => isConnectionError(error)
          ? null
          : ProviderContainer.defaultRetry(retryCount, error),
      repository: repository,
      queue: Queue(),
    );

    expect(find.text("Couldn't reach Comix (EN)"), findsOneWidget);
    expect(repository.searchCalls, 1);

    await tester.pump(const Duration(seconds: 45));

    expect(repository.searchCalls, 1);
    expect(find.text("Couldn't reach Comix (EN)"), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(repository.searchCalls, 2);
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

  testWidgets('two exact matches stay on the results list', (tester) async {
    await _pumpSearch(
      tester,
      fromSuggestion: true,
      sources: [
        (
          source: _source(id: '1', name: 'Alpha'),
          search: () async => [_manga(7, _query)],
        ),
        (
          source: _source(id: '2', name: 'Beta'),
          search: () async => [_manga(8, _query)],
        ),
      ],
    );

    expect(find.text('MANGA 7'), findsNothing);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
  });

  testWidgets('without the suggestion flag a lone exact match stays', (
    tester,
  ) async {
    await _pumpSearch(
      tester,
      fromSuggestion: false,
      sources: [
        (
          source: _source(id: '1', name: 'Alpha'),
          search: () async => [_manga(7, _query)],
        ),
      ],
    );

    expect(find.text('MANGA 7'), findsNothing);
    expect(find.text('Alpha'), findsOneWidget);
  });

  testWidgets('desktop puts the field and chips on one row and names the '
      'route for assistive tech', (tester) async {
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

    final field = find.byType(SearchField);
    final allChip = find.widgetWithText(FilterChip, 'All');
    expect(field, findsOneWidget);
    expect(allChip, findsOneWidget);
    expect(
      (tester.getCenter(field).dy - tester.getCenter(allChip).dy).abs(),
      lessThanOrEqualTo(2),
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

  testWidgets('one source erroring does not block an exact match elsewhere', (
    tester,
  ) async {
    await _pumpSearch(
      tester,
      fromSuggestion: true,
      sources: [
        (
          source: _source(id: '1', name: 'Alpha'),
          search: () async => throw TimeoutException('timed out'),
        ),
        (
          source: _source(id: '2', name: 'Beta'),
          search: () async => [_manga(9, _query)],
        ),
      ],
    );

    expect(find.text('MANGA 9'), findsOneWidget);
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

  testWidgets('scrolling cancels the auto-open', (tester) async {
    final exact = Completer<List<MangaDto>>();

    await _pumpSearch(
      tester,
      fromSuggestion: true,
      settle: false,
      sources: [
        (source: _source(id: '1', name: 'Alpha'), search: () => exact.future),
      ],
    );

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(const Offset(300, 400)));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));
    await tester.pump();

    exact.complete([_manga(7, _query)]);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('MANGA 7'), findsNothing);
    expect(find.text('Alpha'), findsOneWidget);
  });

  testWidgets('pressing a key cancels the auto-open', (tester) async {
    final exact = Completer<List<MangaDto>>();

    await _pumpSearch(
      tester,
      fromSuggestion: true,
      settle: false,
      sources: [
        (source: _source(id: '1', name: 'Alpha'), search: () => exact.future),
      ],
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pump();

    exact.complete([_manga(7, _query)]);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('MANGA 7'), findsNothing);
    expect(find.text('Alpha'), findsOneWidget);
  });

  testWidgets('a result opened before the sources settle is not replaced', (
    tester,
  ) async {
    final exact = Completer<List<MangaDto>>();

    await _pumpSearch(
      tester,
      fromSuggestion: true,
      settle: false,
      sources: [
        (
          source: _source(id: '1', name: 'Alpha'),
          search: () async => [_manga(8, 'Not it')],
        ),
        (source: _source(id: '2', name: 'Beta'), search: () => exact.future),
      ],
    );

    await tester.tap(find.byType(MangaCoverGridTile));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('MANGA 8'), findsOneWidget);

    exact.complete([_manga(9, _query)]);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('MANGA 8'), findsOneWidget);
    expect(find.text('MANGA 9'), findsNothing);
  });

  testWidgets('a refreshing source list is not treated as settled', (
    tester,
  ) async {
    final alpha = _source(id: '1', name: 'Alpha');
    final beta = _source(id: '2', name: 'Beta');
    final gamma = _source(id: '3', name: 'Gamma');
    final alphaSearch = Completer<List<MangaDto>>();
    final secondLoad = Completer<List<SourceDto>?>();
    final sourcesState = StateProvider<AsyncValue<List<SourceDto>>>(
      (ref) => AsyncData([alpha, beta]),
    );
    var sourceListCalls = 0;

    await _pumpSearch(
      tester,
      fromSuggestion: true,
      settle: false,
      sources: [
        (source: alpha, search: () => alphaSearch.future),
        (source: beta, search: () async => [_manga(8, 'Something else')]),
        (source: gamma, search: () async => [_manga(9, _query)]),
      ],
      sourceList: (ref) {
        sourceListCalls++;
        return sourceListCalls == 1
            ? Future.value([alpha, beta])
            : secondLoad.future;
      },
      searchableSources: (ref) => ref.watch(sourcesState),
    );

    final container = ProviderScope.containerOf(
      tester.element(find.byType(GlobalSearchScreen)),
      listen: false,
    );
    container.invalidate(sourceListProvider);
    await tester.pump();

    alphaSearch.complete([_manga(7, _query)]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('MANGA 7'), findsNothing);

    container.read(sourcesState.notifier).state = AsyncData([
      alpha,
      beta,
      gamma,
    ]);
    await tester.pump();
    secondLoad.complete([alpha, beta, gamma]);
    await tester.pumpAndSettle();

    expect(find.text('MANGA 7'), findsNothing);
    expect(find.text('MANGA 9'), findsNothing);
    expect(find.text('Gamma', skipOffstage: false), findsOneWidget);
  });

  for (final (name, size) in [
    ('desktop', const Size(1400, 980)),
    ('phone', const Size(412, 900)),
  ]) {
    testWidgets('the search field is focused on arrival on $name', (
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
        size: size,
      );

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.focusNode?.hasFocus, isTrue);
    });
  }

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

  testWidgets('crossing the desktop breakpoint does not take focus back', (
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
    focusNode.unfocus();
    await tester.pumpAndSettle();
    expect(focusNode.hasFocus, isFalse);

    tester.view.physicalSize = const Size(900, 900);
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.focusNode?.hasFocus, isFalse);
  });

  testWidgets('crossing the desktop breakpoint keeps the typed draft', (
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

    await tester.enterText(find.byType(TextField), 'draft query');
    await tester.pump();

    tester.view.physicalSize = const Size(900, 900);
    await tester.pumpAndSettle();

    expect(find.byType(AppBar), findsNothing);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, 'draft query');
  });
}
