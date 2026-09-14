import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/account/domain/account_binding.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/manga_book/data/downloads/downloads_repository.dart';
import 'package:tsumiru/src/features/manga_book/data/manga_book/manga_book_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/migration/controller/bulk_migration_providers.dart';
import 'package:tsumiru/src/features/migration/data/migration_journal.dart';
import 'package:tsumiru/src/features/migration/domain/migration_models.dart';
import 'package:tsumiru/src/features/offline/data/background/catchup_work_spec.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/features/offline/data/offline_runtime_storage.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

import '../manga_book/manga_details/chapter_test_helpers.dart';

class _Session extends AuthCredentialsStore {
  int epoch = 0;
  @override
  int get sessionEpoch => epoch;
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

class _Chapters extends MangaBookRepository {
  _Chapters()
    : super(
        GraphQLClient(
          link: HttpLink('http://localhost:0'),
          cache: GraphQLCache(),
        ),
      );
  final entered = Completer<void>();
  final response = Completer<List<ChapterDto>?>();
  final calls = <int>[];
  @override
  Future<List<ChapterDto>?> getChapterList(int mangaId) {
    calls.add(mangaId);
    entered.complete();
    return response.future;
  }
}

class _Downloads extends Fake implements DownloadsRepository {
  final queued = <int>[];
  @override
  Future<void> addChaptersBatchToDownloadQueue(List<int> chapterIds) async {
    queued.addAll(chapterIds);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'account replacement stops download migration and runtime drain waits',
    () async {
      SharedPreferences.setMockInitialValues({
        CatchupStateStore.identityAuthorizedKey: true,
      });
      final prefs = await SharedPreferences.getInstance();
      final auth = _Session();
      final chapters = _Chapters();
      final downloads = _Downloads();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          authCredentialsStoreProvider.overrideWith(() => auth),
          authTypeKeyProvider.overrideWith(_UiLogin.new),
          mangaBookRepositoryProvider.overrideWithValue(chapters),
          downloadsRepositoryProvider.overrideWithValue(downloads),
          offlineActiveProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);
      await container.read(authCredentialsStoreProvider.future);
      final pending = migrateOfflineLocalState(
        container,
        1,
        2,
        const MigrationOption(migrateDownloads: true),
      );
      await chapters.entered.future;
      var drained = false;
      final drain = container
          .read(offlineRuntimeStorageProvider.notifier)
          .drain()
          .then((_) {
            drained = true;
          });
      await Future<void>.delayed(Duration.zero);
      expect(drained, isFalse);
      auth.epoch++;
      chapters.response.complete([ch(id: 10, number: 1, isDownloaded: true)]);
      await pending;
      await drain;
      expect(chapters.calls, [1]);
      expect(downloads.queued, isEmpty);
    },
  );

  test('unverified startup leaves legacy recovery bytes untouched', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final legacy = MigrationJournal(prefs);
    await legacy.put(
      const MigrationJournalEntry(
        fromMangaId: 1,
        toMangaId: 2,
        state: MigrationPairState.copying,
        options: MigrationOption(deleteSource: true),
      ),
    );
    final bytes = prefs.getString(MigrationJournal.prefsKey);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authCredentialsStoreProvider.overrideWith(_Session.new),
      ],
    );
    addTearDown(container.dispose);
    await recoverBulkMigrationsAtLaunch(container);
    expect(prefs.getString(MigrationJournal.prefsKey), bytes);
  });
}
