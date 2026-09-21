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
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/account/domain/account_binding.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/browse_center/domain/source/source_model.dart';
import 'package:tsumiru/src/features/browse_center/presentation/source/controller/source_controller.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_manga_list.dart';
import 'package:tsumiru/src/features/manga_book/data/manga_book/manga_book_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/migration/domain/migration_models.dart';
import 'package:tsumiru/src/features/migration/presentation/screens/migration_bulk_config_screen.dart';
import 'package:tsumiru/src/features/migration/presentation/screens/migration_bulk_run_screen.dart';
import 'package:tsumiru/src/features/migration/presentation/screens/migration_source_picker_screen.dart';
import 'package:tsumiru/src/features/offline/data/background/catchup_work_spec.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

import '../manga_book/reader/reader_test_fixtures.dart';

class _DeadSourceChapters extends MangaBookRepository {
  _DeadSourceChapters(super.client, {required this.storedFails});
  final bool storedFails;
  final storedCalls = <int>[];
  @override
  Future<List<ChapterDto>?> getChapterList(int mangaId) async {
    throw StateError('Missing source 2528986671771677900');
  }

  @override
  Future<List<ChapterDto>?> getStoredChapterList(int mangaId) async {
    storedCalls.add(mangaId);
    if (storedFails && mangaId == 1) {
      throw StateError('Stored chapters unavailable');
    }
    return [testChapter()];
  }
}

class _MigrationSession extends AuthCredentialsStore {
  @override
  Future<AuthCredentialsState> build() async => const AuthCredentialsState(
    accountBinding: AccountBinding(
      address: 'http://server',
      username: 'a',
      userId: 1,
      catalogId: 'a',
    ),
  );
}

class _UiLogin extends AuthTypeKey {
  @override
  AuthType? build() => AuthType.uiLogin;
}

Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final client = GraphQLClient(
    link: HttpLink('http://localhost'),
    cache: GraphQLCache(),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        graphQlClientProvider.overrideWithValue(client),
        libraryMangaListProvider.overrideWith((ref) async => <MangaDto>[]),
        searchableSourcesProvider.overrideWithValue(
          const AsyncValue.data(<SourceDto>[]),
        ),
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
  for (final scenario in [0, 1, 2]) {
    final storedFails = scenario == 1;
    testWidgets('dead source preparation scenario $scenario', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SharedPreferences.setMockInitialValues({
        CatchupStateStore.identityAuthorizedKey: true,
      });
      final prefs = await SharedPreferences.getInstance();
      final client = GraphQLClient(
        link: HttpLink('http://localhost:0'),
        cache: GraphQLCache(),
      );
      final chapters = _DeadSourceChapters(client, storedFails: storedFails);
      var failRepository = scenario == 2;
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          graphQlClientProvider.overrideWithValue(client),
          authCredentialsStoreProvider.overrideWith(_MigrationSession.new),
          authTypeKeyProvider.overrideWith(_UiLogin.new),
          mangaBookRepositoryProvider.overrideWith((ref) {
            if (failRepository) throw StateError('Preparation unavailable');
            return chapters;
          }),
          libraryMangaListProvider.overrideWith(
            (ref) async => [testManga(), testManga().copyWith(id: 2)],
          ),
          searchableSourcesProvider.overrideWithValue(
            const AsyncValue.data(<SourceDto>[]),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(authCredentialsStoreProvider.future);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: MigrationBulkRunScreen(
              data: MigrationBulkRunData(
                mangaIds: [1, 2],
                targetSourceIds: [],
                options: MigrationOption(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (scenario == 2) {
        expect(find.textContaining('Preparation unavailable'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text('Retry'), findsOneWidget);
        failRepository = false;
        container.invalidate(mangaBookRepositoryProvider);
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      expect(chapters.storedCalls, [1, 2]);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      final l10n = AppLocalizations.of(
        tester.element(find.byType(MigrationBulkRunScreen)),
      )!;
      expect(find.text(l10n.migrationListNoMatch), findsNWidgets(2));
    });
  }

  testWidgets('Select-sources screen mounts without crashing', (tester) async {
    await pumpScreen(tester, const MigrationBulkConfigScreen(mangaIds: [1]));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'unverified migration list offers retry without migration actions',
    (tester) async {
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
      final context = tester.element(find.byType(MigrationBulkRunScreen));
      final l10n = AppLocalizations.of(context)!;
      expect(find.text(l10n.migrationIdentityUnavailable), findsOneWidget);
      expect(find.text(l10n.retry), findsOneWidget);
      expect(find.byTooltip(l10n.migrationActionCopy), findsNothing);
      expect(find.byTooltip(l10n.migrationActionMigrate), findsNothing);
    },
  );

  testWidgets('source picker screen mounts without crashing', (tester) async {
    await pumpScreen(tester, const MigrationSourcePickerScreen());
    expect(tester.takeException(), isNull);
  });
}
