// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Mount tests: pump each migration screen and assert it builds without throwing.
// These exist because a mount-time crash (containerOf called inside a useEffect)
// shipped past a full suite of fake-based unit tests that never mounted a screen.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/browse_center/domain/source/source_model.dart';
import 'package:tsumiru/src/features/browse_center/presentation/source/controller/source_controller.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_manga_list.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/migration/domain/migration_models.dart';
import 'package:tsumiru/src/features/migration/presentation/screens/migration_bulk_config_screen.dart';
import 'package:tsumiru/src/features/migration/presentation/screens/migration_bulk_run_screen.dart';
import 'package:tsumiru/src/features/migration/presentation/screens/migration_source_picker_screen.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final client = GraphQLClient(link: HttpLink('http://localhost'), cache: GraphQLCache());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        graphQlClientProvider.overrideWithValue(client),
        libraryMangaListProvider.overrideWith((ref) async => <MangaDto>[]),
        searchableSourcesProvider
            .overrideWithValue(const AsyncValue.data(<SourceDto>[])),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: screen,
      ),
    ),
  );
  // Drain the mount-time async (search/chapter fetch kicked off in useEffect)
  // so no timer is left pending at test end.
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Select-sources screen mounts without crashing', (tester) async {
    await pumpScreen(tester, const MigrationBulkConfigScreen(mangaIds: [1]));
    expect(tester.takeException(), isNull);
  });

  testWidgets('migration list screen mounts without crashing', (tester) async {
    await pumpScreen(
      tester,
      const MigrationBulkRunScreen(
        data: MigrationBulkRunData(
          mangaIds: [],
          targetSourceIds: [],
          options: MigrationOption(),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('source picker screen mounts without crashing', (tester) async {
    await pumpScreen(tester, const MigrationSourcePickerScreen());
    expect(tester.takeException(), isNull);
  });
}
