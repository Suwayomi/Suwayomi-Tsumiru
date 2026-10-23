// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Mount tests: pump each migration screen and assert it builds without throwing.
// These exist because a mount-time crash (containerOf called inside a useEffect)
// shipped past a full suite of fake-based unit tests that never mounted a screen.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/app_sizes.dart';
import 'package:tsumiru/src/constants/db_keys.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/account/domain/account_binding.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/browse_center/data/source_repository/source_repository.dart';
import 'package:tsumiru/src/features/browse_center/domain/manga_page/manga_page.dart';
import 'package:tsumiru/src/features/browse_center/domain/source/source_model.dart';
import 'package:tsumiru/src/features/browse_center/presentation/source/controller/source_controller.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_manga_list.dart';
import 'package:tsumiru/src/features/manga_book/data/manga_book/manga_book_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/migration/controller/migration_controller.dart';
import 'package:tsumiru/src/features/migration/data/migration_repository.dart';
import 'package:tsumiru/src/features/migration/domain/migration_models.dart';
import 'package:tsumiru/src/features/migration/presentation/screens/migration_bulk_run_screen.dart';
import 'package:tsumiru/src/features/migration/presentation/screens/migration_global_search_screen.dart';
import 'package:tsumiru/src/features/offline/data/background/catchup_work_spec.dart';
import 'package:tsumiru/src/features/offline/data/offline_server_identity_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/widgets/server_image.dart';

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

class _HangingSource extends Fake implements SourceRepository {
  final pending = Completer<MangaPage?>();
  int calls = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #fetchSourceManga) {
      calls++;
      return pending.future;
    }
    return super.noSuchMethod(invocation);
  }
}

class _HangingMigration extends Fake implements MigrationRepository {
  final pending = Completer<List<MangaDto>?>();
  int calls = 0;

  @override
  Future<List<MangaDto>?> searchMangaInSource(
    String sourceId,
    String query, [
    BuildContext? context,
  ]) {
    calls++;
    return pending.future;
  }
}

final _source = SourceDto.fromJson({
  'displayName': 'Hanging source',
  'iconUrl': '',
  'id': 'target',
  'isConfigurable': false,
  'contentWarning': 'SAFE',
  'lang': 'en',
  'name': 'Hanging source',
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

Future<ProviderContainer> _runContainer({
  _HangingSource? source,
  _HangingMigration? migration,
}) async {
  SharedPreferences.setMockInitialValues({
    CatchupStateStore.identityAuthorizedKey: true,
    DBKeys.serverRequestTimeout.name: 1000,
  });
  final prefs = await SharedPreferences.getInstance();
  final client = GraphQLClient(
    link: HttpLink('http://localhost:0'),
    cache: GraphQLCache(),
  );
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      graphQlClientProvider.overrideWithValue(client),
      authCredentialsStoreProvider.overrideWith(_MigrationSession.new),
      authTypeKeyProvider.overrideWithValue(AuthType.uiLogin),
      mangaBookRepositoryProvider.overrideWith(
        (ref) => _DeadSourceChapters(client, storedFails: false),
      ),
      libraryMangaListProvider.overrideWith((ref) async => [testManga()]),
      searchableSourcesProvider.overrideWithValue(AsyncValue.data([_source])),
      if (source != null)
        sourceRepositoryProvider.overrideWith((ref) => source),
      if (migration != null)
        migrationRepositoryProvider.overrideWith((ref) => migration),
    ],
  );
  await container.read(authCredentialsStoreProvider.future);
  return container;
}

Widget _app(ProviderContainer container, Widget screen) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: screen,
      ),
    );

const _runScreen = MigrationBulkRunScreen(
  data: MigrationBulkRunData(
    mangaIds: [1],
    targetSourceIds: ['target'],
    options: MigrationOption(),
  ),
);

void main() {
  testWidgets('desktop migration covers keep the normal search card width', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 1000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final migration = _HangingMigration();
    final container = await _runContainer(migration: migration);
    addTearDown(container.dispose);
    await tester.pumpWidget(_app(container, _runScreen));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byType(ServerImage), findsOneWidget);
    expect(
      tester.getSize(find.byType(ServerImage)).width,
      lessThanOrEqualTo(kShortSearchCoverWidth),
    );
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('hanging migration searches time out into actionable failures', (
    tester,
  ) async {
    final source = _HangingSource();
    final migration = _HangingMigration();
    final container = await _runContainer(source: source, migration: migration);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      _app(container, MigrationGlobalSearchScreen(sourceManga: testManga())),
    );
    await tester.pump();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(MigrationGlobalSearchScreen)),
    )!;
    expect(source.calls, 1);
    expect(find.text(l10n.retry), findsNothing);
    await tester.pump(const Duration(milliseconds: 999));
    expect(find.text(l10n.retry), findsNothing);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(
      find.text(l10n.couldntReachSource(_source.displayName)),
      findsOneWidget,
    );
    expect(find.text(l10n.retry), findsOneWidget);
    expect(
      container
          .read(
            migrationSourceQuickSearchMangaListProvider(
              _source.id,
              query: testManga().title,
            ),
          )
          .hasError,
      isTrue,
    );
    await tester.tap(find.text(l10n.retry));
    await tester.pump(const Duration(milliseconds: 500));
    expect(source.calls, 2);
    source.pending.complete(null);
    await tester.pumpAndSettle();
    expect(find.text(l10n.noResultFound), findsOneWidget);

    await tester.pumpWidget(_app(container, _runScreen));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(migration.calls, 1);
    expect(find.text(l10n.migrationListNoMatch), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text(l10n.migrationListNoMatch), findsOneWidget);
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text(l10n.migrationSearchManually), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('non-login migration waits for server identity and retries', (
    tester,
  ) async {
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
    final chapters = _DeadSourceChapters(client, storedFails: false);
    final firstResolution = Completer<String>();
    final retryResolution = Completer<String>();
    var attempts = 0;
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        graphQlClientProvider.overrideWithValue(client),
        authCredentialsStoreProvider.overrideWith(_MigrationSession.new),
        authTypeKeyProvider.overrideWithValue(AuthType.none),
        serverInstanceIdProvider.overrideWith((ref) {
          attempts++;
          return attempts == 1
              ? firstResolution.future
              : retryResolution.future;
        }),
        mangaBookRepositoryProvider.overrideWith((ref) => chapters),
        libraryMangaListProvider.overrideWith((ref) async => [testManga()]),
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
              mangaIds: [1],
              targetSourceIds: [],
              options: MigrationOption(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(MigrationBulkRunScreen)),
    )!;
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text(l10n.migrationIdentityUnavailable), findsNothing);
    expect(chapters.storedCalls, isEmpty);

    firstResolution.completeError(StateError('Identity unavailable'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text(l10n.migrationIdentityUnavailable), findsOneWidget);
    expect(find.text(l10n.retry), findsOneWidget);
    expect(chapters.storedCalls, isEmpty);

    await tester.tap(find.text(l10n.retry));
    await tester.pump();
    expect(attempts, 2);
    retryResolution.complete('server-id');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text(l10n.migrationIdentityUnavailable), findsNothing);
    expect(chapters.storedCalls, [1]);
    expect(find.text(l10n.migrationListNoMatch), findsOneWidget);

    container.invalidate(libraryMangaListProvider);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(chapters.storedCalls, [1]);
    expect(find.text(l10n.migrationListNoMatch), findsOneWidget);
  });
}
