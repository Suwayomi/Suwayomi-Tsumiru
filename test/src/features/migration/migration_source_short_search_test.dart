// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/browse_center/domain/source/source_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/migration/controller/migration_controller.dart';
import 'package:tsumiru/src/features/migration/presentation/widgets/migration_source_short_search.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/widgets/server_unreachable_view.dart';

const _query = 'Solo Leveling';

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

Future<void> _pump(
  WidgetTester tester, {
  required Object error,
  required VoidCallback onSearchBuild,
}) async {
  final source = _source(id: 'comix', name: 'Comix');
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        migrationSourceQuickSearchMangaListProvider(
          source.id,
          query: _query,
        ).overrideWith((ref) {
          onSearchBuild();
          return <MangaDto>[];
        }),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Consumer(
          builder: (context, ref, _) {
            ref.watch(
              migrationSourceQuickSearchMangaListProvider(
                source.id,
                query: _query,
              ),
            );
            return Scaffold(
              body: MigrationSourceShortSearch(
                source: source,
                mangaList: AsyncError(error, StackTrace.empty),
                query: _query,
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  for (final (label, error) in [
    ('a connection error', TimeoutException('timed out')),
    ('another error', Exception('bad response')),
  ]) {
    testWidgets('$label shows the inline row and Retry re-fetches', (
      tester,
    ) async {
      var searchBuilds = 0;
      await _pump(tester, error: error, onSearchBuild: () => searchBuilds++);

      expect(searchBuilds, 1);
      expect(find.text("Couldn't reach Comix"), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byType(ServerUnreachableView), findsNothing);

      await tester.tap(find.text('Retry'));
      await tester.pump();

      expect(searchBuilds, 2);
      expect(find.byType(ServerUnreachableView), findsNothing);
    });
  }
}
