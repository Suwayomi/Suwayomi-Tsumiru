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
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/account/domain/account_binding.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/browse_center/domain/source/source_model.dart';
import 'package:tsumiru/src/features/browse_center/presentation/source/controller/source_controller.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_manga_list.dart';
import 'package:tsumiru/src/features/manga_book/data/manga_book/manga_book_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/migration/domain/migration_models.dart';
import 'package:tsumiru/src/features/migration/presentation/screens/migration_bulk_run_screen.dart';
import 'package:tsumiru/src/features/offline/data/background/catchup_work_spec.dart';
import 'package:tsumiru/src/features/offline/data/offline_server_identity_repository.dart';
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

void main() {
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
