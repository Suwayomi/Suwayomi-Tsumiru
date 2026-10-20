import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/account/data/account_providers.dart';
import 'package:tsumiru/src/features/account/domain/account_access.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/offline/data/background/background_download_lock.dart';
import 'package:tsumiru/src/features/offline/data/background/catchup_work_spec.dart';
import 'package:tsumiru/src/features/offline/data/offline_chapter_catchup.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_paths.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

import '../../../../helpers/offline_test_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late OfflineDatabase db;
  late CatchupStateStore state;
  late ProviderContainer container;
  late Directory tmp;
  var allowed = true;
  var publishEnabled = true;

  setUp(() async {
    resetChapterCatchUpStateForTest();
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({
      'offlineCatalogServerId': 'catalog',
    });
    final prefs = await SharedPreferences.getInstance();
    state = await CatchupStateStore.open();
    tmp = await Directory.systemTemp.createTemp('worker-obligations-');
    db = testOfflineDatabase();
    allowed = true;
    publishEnabled = true;
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        offlineDatabaseProvider.overrideWithValue(db),
        offlineEnabledProvider.overrideWith((ref) => true),
        offlineActiveProvider.overrideWith((ref) => publishEnabled),
        offlinePathsProvider.overrideWithValue(OfflinePaths(tmp.path)),
        settledAccountAccessProvider.overrideWith(
          (ref) => AccountAccess(
            capability: allowed
                ? AccountCapability.unsupported
                : AccountCapability.unknown,
          ),
        ),
      ],
    );
    await container.read(authCredentialsStoreProvider.future);
    await state.writeSpec(
      const CatchupWorkSpec(
        serverId: 'catalog',
        wifiOnly: false,
        storageCapEnabled: false,
        storageCapBytes: 0,
        manga: [
          CatchupMangaSpec(
            mangaId: 1,
            keepRule: OfflineKeepRule.all,
            keepUnreadCount: 3,
            onDeviceChapterIds: {},
            pinnedChapterIds: {},
          ),
        ],
      ),
    );
    await state.writeLedger(
      'catalog',
      const CatchupLedger(
        pendingServerFetch: {5: 1},
        serverFetchRetries: {5: 5},
      ),
    );
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> seed() => db.upsertChapterMetadata(
    id: 5,
    mangaId: 1,
    name: 'C',
    chapterIndex: 0,
    isRead: false,
    lastPageRead: 0,
    isBookmarked: false,
    serverIsDownloaded: false,
    pageCount: 1,
    updatedAt: DateTime(2026),
  );

  test(
    'spent attempts transfer to matching metadata and clear the obligation',
    () async {
      await seed();
      await db.incrementServerFetchAttempts(5);
      expect(await adoptWorkerObligations(container.read), isTrue);
      expect((await db.chapterById(5))!.serverFetchAttempts, 5);
      expect(state.readLedger('catalog').pendingServerFetch, isEmpty);
      expect(state.readLedger('catalog').serverFetchRetries, isEmpty);
    },
  );

  test('missing metadata retains the obligation until it arrives', () async {
    expect(await adoptWorkerObligations(container.read), isTrue);
    expect(state.readLedger('catalog').serverFetchRetries, {5: 5});
    await seed();
    expect(await adoptWorkerObligations(container.read), isTrue);
    expect((await db.chapterById(5))!.serverFetchAttempts, 5);
    expect(state.readLedger('catalog').pendingServerFetch, isEmpty);
  });

  test('an old worker generation cannot overwrite a newer chapter', () async {
    await seed();
    await db.bumpChapterGeneration(5);
    await db.incrementServerFetchAttempts(5);
    expect(await adoptWorkerObligations(container.read), isTrue);
    expect((await db.chapterById(5))!.serverFetchAttempts, 1);
    expect((await db.chapterById(5))!.downloadGeneration, 1);
  });

  for (final deny in [true, false]) {
    test(
      deny
          ? 'permission hold retains worker attempts'
          : 'an active worker lock retains attempts',
      () async {
        await seed();
        BackgroundDownloadLock? lock;
        if (deny) {
          allowed = false;
          container.invalidate(settledAccountAccessProvider);
        } else {
          lock = BackgroundDownloadLock(File('${tmp.path}/.bg_lock'));
          expect(await lock.acquire('test'), isTrue);
        }
        try {
          expect(await adoptWorkerObligations(container.read), isFalse);
          expect(state.readLedger('catalog').serverFetchRetries, {5: 5});
          expect((await db.chapterById(5))!.serverFetchAttempts, 0);
        } finally {
          await lock?.release();
        }
      },
    );
  }
}
