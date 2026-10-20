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
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/browse_center/domain/source/source_model.dart';
import 'package:tsumiru/src/features/browse_center/presentation/global_search/controller/source_quick_search_controller.dart';
import 'package:tsumiru/src/features/browse_center/presentation/global_search/global_search_screen.dart';
import 'package:tsumiru/src/features/browse_center/presentation/source/controller/source_controller.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/routes/navigation.dart';
import 'package:tsumiru/src/widgets/desktop/desktop_top_bar.dart';

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
  required List<_SourceResult> sources,
}) async {
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
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        globalSearchScopeProvider.overrideWith(_AllScope.new),
        sourceListProvider.overrideWith(
          (ref) async => [for (final s in sources) s.source],
        ),
        searchableSourcesProvider.overrideWith(
          (ref) => AsyncData([for (final s in sources) s.source]),
        ),
        pinnedSourcesProvider.overrideWithValue(const []),
        for (final s in sources)
          sourceQuickSearchMangaListProvider(
            s.source.id,
            query: _query,
          ).overrideWith((ref) => s.search()),
      ],
      child: MaterialApp.router(
        routerConfig: _router(fromSuggestion: false),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open search'));
  await tester.pumpAndSettle();
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

}
