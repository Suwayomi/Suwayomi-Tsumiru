import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/account/data/account_providers.dart';
import 'package:tsumiru/src/features/account/domain/account_access.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/offline/data/background/background_download_controller_shim.dart';
import 'package:tsumiru/src/features/offline/data/background/background_download_lock.dart';
import 'package:tsumiru/src/features/offline/data/background/catchup_work_spec.dart';
import 'package:tsumiru/src/features/offline/data/offline_chapter_catchup.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_providers.dart';
import 'package:tsumiru/src/features/offline/data/offline_paths.dart';
import 'package:tsumiru/src/features/offline/data/offline_reconciler.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/features/offline/data/reconcile_types.dart';
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

  test('a refreshed spec does not relabel old worker attempts', () async {
    await seed();
    await db.bumpChapterGeneration(5);
    final spec = state.readSpec()!;
    await state.writeSpec(
      CatchupWorkSpec(
        serverId: spec.serverId,
        wifiOnly: spec.wifiOnly,
        storageCapEnabled: spec.storageCapEnabled,
        storageCapBytes: spec.storageCapBytes,
        manga: const [
          CatchupMangaSpec(
            mangaId: 1,
            keepRule: OfflineKeepRule.all,
            keepUnreadCount: 3,
            onDeviceChapterIds: {},
            pinnedChapterIds: {},
            chapterGenerations: {5: 1},
          ),
        ],
      ),
    );
    expect(await adoptWorkerObligations(container.read), isTrue);
    expect((await db.chapterById(5))!.serverFetchAttempts, 0);
    expect(state.readLedger('catalog').pendingServerFetch, isEmpty);
  });

  for (final keepDevice in [false, true]) {
    test(
      'handoff retains generation only with remaining device state: $keepDevice',
      () async {
        await seed();
        await db.bumpChapterGeneration(5);
        await state.writeLedger(
          'catalog',
          CatchupLedger(
            pendingServerFetch: const {5: 1},
            serverFetchRetries: const {5: 2},
            chapterGenerations: const {5: 1},
            pendingDownloads: keepDevice ? const {5: 1} : const {},
            downloadRetries: keepDevice ? const {5: 3} : const {},
          ),
        );
        expect(await adoptWorkerObligations(container.read), isTrue);
        expect((await db.chapterById(5))!.serverFetchAttempts, 2);
        final ledger = state.readLedger('catalog');
        expect(ledger.pendingServerFetch, isEmpty);
        expect(ledger.chapterGenerations, keepDevice ? {5: 1} : isEmpty);
        expect(ledger.downloadRetries, keepDevice ? {5: 3} : isEmpty);
      },
    );
  }

  for (final status in ['matching', 'newer', 'downloaded', 'missing']) {
    test('exhausted device obligation handoff: $status', () async {
      if (status != 'missing') await seed();
      if (status == 'newer') await db.bumpChapterGeneration(5);
      if (status == 'downloaded') {
        await db.setChapterDeviceState(5, OfflineDeviceState.downloaded);
      }
      await state.writeLedger(
        'catalog',
        const CatchupLedger(
          pendingDownloads: {5: 1},
          downloadRetries: {5: 5},
          chapterGenerations: {5: 0},
        ),
      );
      expect(await adoptWorkerObligations(container.read), isTrue);
      final chapter = await db.chapterById(5);
      if (status == 'matching') {
        expect(chapter!.deviceState, OfflineDeviceState.error);
      } else if (status == 'downloaded') {
        expect(chapter!.deviceState, OfflineDeviceState.downloaded);
      } else if (status == 'newer') {
        expect(chapter!.deviceState, isNot(OfflineDeviceState.error));
      }
      final ledger = state.readLedger('catalog');
      expect(ledger.downloadRetries, status == 'missing' ? {5: 5} : isEmpty);
      expect(ledger.pendingDownloads, status == 'missing' ? {5: 1} : isEmpty);
      expect(ledger.chapterGenerations, status == 'missing' ? {5: 0} : isEmpty);
    });
  }

  for (final keepSpent in [0, 2, 5]) {
    test(
      'queued server attempts merge with keep attempts by maximum: $keepSpent',
      () async {
        await seed();
        await state.writeLedger(
          'catalog',
          CatchupLedger(
            pendingServerFetch: keepSpent == 0 ? const {} : const {5: 1},
            serverFetchRetries: keepSpent == 0 ? const {} : {5: keepSpent},
            queuedServerRetries: const {'5:0': 4},
          ),
        );
        expect(await adoptWorkerObligations(container.read), isTrue);
        expect(
          (await db.chapterById(5))!.serverFetchAttempts,
          keepSpent == 5 ? 5 : 4,
        );
        final ledger = state.readLedger('catalog');
        expect(ledger.serverFetchRetries, isEmpty);
        expect(ledger.queuedServerRetries, isEmpty);
        await db.resetServerFetchAttempts(5);
        expect(await adoptWorkerObligations(container.read), isTrue);
        expect((await db.chapterById(5))!.serverFetchAttempts, 0);
      },
    );
  }

  for (final status in ['matching', 'newer', 'downloaded', 'missing']) {
    test('queued exhausted device handoff: $status', () async {
      if (status != 'missing') await seed();
      if (status == 'newer') await db.bumpChapterGeneration(5);
      if (status == 'downloaded') {
        await db.setChapterDeviceState(5, OfflineDeviceState.downloaded);
      }
      await state.writeLedger(
        'catalog',
        const CatchupLedger(
          queuedServerRetries: {'5:0': 4},
          queuedDownloadRetries: {'5:0': 5},
        ),
      );
      expect(await adoptWorkerObligations(container.read), isTrue);
      final chapter = await db.chapterById(5);
      if (status == 'matching') {
        expect(chapter!.deviceState, OfflineDeviceState.error);
        expect(chapter.serverFetchAttempts, 4);
      } else if (status == 'downloaded') {
        expect(chapter!.deviceState, OfflineDeviceState.downloaded);
        expect(chapter.serverFetchAttempts, 0);
      } else if (status == 'newer') {
        expect(chapter!.deviceState, isNot(OfflineDeviceState.error));
        expect(chapter.serverFetchAttempts, 0);
      }
      final ledger = state.readLedger('catalog');
      expect(
        ledger.queuedServerRetries,
        status == 'missing' ? {'5:0': 4} : isEmpty,
      );
      expect(
        ledger.queuedDownloadRetries,
        status == 'missing' ? {'5:0': 5} : isEmpty,
      );
    });
  }

  test(
    'four queued attempts leave foreground reconciliation one request',
    () async {
      await seed();
      await db.upsertMangaMetadata(
        id: 1,
        title: 'M',
        updatedAt: DateTime(2026),
      );
      await db.setKeepRule(1, OfflineKeepRule.all, 3);
      await state.writeLedger(
        'catalog',
        const CatchupLedger(queuedServerRetries: {'5:0': 4}),
      );
      expect(await adoptWorkerObligations(container.read), isTrue);
      final requested = <int>[];
      final reconciler = OfflineReconciler(
        db: db,
        nets: SafetyNetConfig.off,
        onDownload: (_) async {},
        onEvict: (_) async {},
        now: DateTime(2026),
        onServerDownload: (ids) async => requested.addAll(ids),
      );
      await reconciler.reconcileManga(1);
      expect(requested, [5]);
      expect((await db.chapterById(5))!.serverFetchAttempts, 5);
      await reconciler.reconcileManga(1);
      expect(requested, [5]);
      expect((await db.chapterById(5))!.deviceState, OfflineDeviceState.error);
    },
  );

  test('adoption reuses ownership held by the foreground controller', () async {
    await seed();
    final controller = container.read(backgroundDownloadControllerProvider);
    final adopted = await controller.withOwnership(() async {
      expect(controller.ownedStorageRoot, tmp.path);
      return adoptWorkerObligations(container.read);
    });
    expect(adopted, isTrue);
    expect((await db.chapterById(5))!.serverFetchAttempts, 5);
    expect(state.readLedger('catalog').serverFetchRetries, isEmpty);
  });

  test(
    'failed snapshot retains worker counters after database adoption',
    () async {
      await seed();
      expect(
        await adoptWorkerObligations(<T>(ProviderListenable<T> provider) {
          if (identical(provider, safetyNetConfigProvider)) {
            throw StateError('Snapshot unavailable');
          }
          return container.read(provider);
        }),
        isFalse,
      );
      expect((await db.chapterById(5))!.serverFetchAttempts, 5);
      expect(state.readLedger('catalog').serverFetchRetries, {5: 5});
    },
  );

  test(
    'skipped snapshot keeps adopted ledger attempts for the next handoff',
    () async {
      await seed();
      publishEnabled = false;
      container.invalidate(offlineActiveProvider);
      expect(await adoptWorkerObligations(container.read), isFalse);
      expect((await db.chapterById(5))!.serverFetchAttempts, 5);
      expect(state.readLedger('catalog').serverFetchRetries, {5: 5});
      publishEnabled = true;
      container.invalidate(offlineActiveProvider);
      expect(await adoptWorkerObligations(container.read), isTrue);
      expect((await db.chapterById(5))!.serverFetchAttempts, 5);
      expect(state.readLedger('catalog').serverFetchRetries, isEmpty);
    },
  );

  test('below-cap queued device attempts stay with the worker', () async {
    await seed();
    await state.writeLedger(
      'catalog',
      const CatchupLedger(queuedDownloadRetries: {'5:0': 4}),
    );
    expect(await adoptWorkerObligations(container.read), isTrue);
    expect(state.readLedger('catalog').queuedDownloadRetries, {'5:0': 4});
    expect((await db.chapterById(5))!.deviceState, OfflineDeviceState.none);
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
