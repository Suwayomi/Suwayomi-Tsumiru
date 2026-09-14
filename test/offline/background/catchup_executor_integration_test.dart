import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/account/data/account_providers.dart';
import 'package:tsumiru/src/features/account/domain/account_access.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/notifications/data/background/notification_background_client.dart';
import 'package:tsumiru/src/features/notifications/data/notification_state_store.dart';
import 'package:tsumiru/src/features/offline/data/background/background_completion_log.dart';
import 'package:tsumiru/src/features/offline/data/background/background_download_lock.dart';
import 'package:tsumiru/src/features/offline/data/background/background_token_record.dart';
import 'package:tsumiru/src/features/offline/data/background/catchup_download_executor.dart';
import 'package:tsumiru/src/features/offline/data/background/catchup_work_spec.dart';
import 'package:tsumiru/src/features/offline/data/chapter_manifest.dart';

import 'package:tsumiru/src/features/offline/data/offline_chapter_catchup.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_page_store_io.dart';
import 'package:tsumiru/src/features/offline/data/offline_paths.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/features/offline/data/offline_server_identity.dart';
import 'package:tsumiru/src/features/offline/data/offline_types.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:workmanager_android/workmanager_android.dart';

import '../../helpers/offline_test_db.dart';

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late HttpServer server;
  late CatchupStateStore state;
  late NotificationWorkerConfig config;
  late BackgroundCompletionLog log;
  late List<int> pages;
  late int requests;
  late bool holdPage;
  late bool failPage;
  late bool denyPage;
  late int pageStatus;
  late List<int> resolvedPages;
  late int serverChapterCount;
  late bool serverDownloaded;
  late List<int> enqueued;
  late bool revokeIdentityAfterEnqueue;
  late Set<int> serverMissing;
  late String serverIdentity;
  late Map<int, List<String>> pageUrls;
  late Completer<void> pageRequested;
  late Completer<void> releasePage;
  const token = BackgroundTokenRecord(gen: 0, authType: 'none');
  final broker = TokenBroker(
    read: () async => token,
    write: (_) async {},
    refreshFn: (_) async => (tokens: null, transient: false),
  );

  Future<bool> run() => HttpOverrides.runZoned(
    () => runCatchupDownloads(
      catchupStore: state,
      config: config,
      record: () => token,
      broker: broker,
    ),
    createHttpClient: _RealHttpOverrides().createHttpClient,
  );

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('catchup-integration-');
    pages = [];
    requests = 0;
    holdPage = false;
    failPage = false;
    denyPage = false;
    pageStatus = 200;
    resolvedPages = [];
    serverChapterCount = 30;
    serverDownloaded = true;
    enqueued = [];
    revokeIdentityAfterEnqueue = false;
    serverMissing = {};
    serverIdentity = 'catalog-uuid';
    pageUrls = {};
    pageRequested = Completer<void>();
    releasePage = Completer<void>();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests++;
      if (request.method == 'GET') {
        final id = int.parse(request.uri.pathSegments.last.split('.').first);
        pages.add(id);
        if (!pageRequested.isCompleted) pageRequested.complete();
        if (holdPage) await releasePage.future;
        request.response.statusCode = pageStatus;
        if (failPage) request.response.statusCode = 500;
        if (denyPage) request.response.statusCode = 403;
        request.response.headers.contentType = ContentType('image', 'jpeg');
        request.response.add([1, 2, 3]);
      } else {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        final query = body['query'] as String;
        final Object data;
        if (query.contains('OfflineServerIdentity')) {
          data = {
            'metas': {
              'nodes': [
                {'value': serverIdentity},
              ],
            },
          };
        } else if (query.contains('EnqueueDownloads')) {
          enqueued.addAll(
            ((body['variables'] as Map)['input']['ids'] as List).cast<int>(),
          );
          if (revokeIdentityAfterEnqueue) {
            await state.setIdentityAuthorized(false);
          }
          data = {
            'enqueueChapterDownloads': {
              '__typename': 'EnqueueChapterDownloadsPayload',
            },
          };
        } else if (query.contains('MangaChapters')) {
          data = {
            'chapters': {
              'nodes': List.generate(
                serverChapterCount,
                (index) => {
                  'id': index + 1,
                  'name': 'Chapter ${index + 1}',
                  'sourceOrder': index,
                  'chapterNumber': index + 1,
                  'isRead': false,
                  'isBookmarked': false,
                  'isDownloaded':
                      serverDownloaded && !serverMissing.contains(index + 1),
                  'pageCount': 1,
                },
              ),
            },
          };
        } else {
          expect(query, contains('GetChapterPages'));
          final id = (body['variables'] as Map)['input']['chapterId'];
          resolvedPages.add(id as int);
          data = {
            'fetchChapterPages': {
              'pages': pageUrls[id] ?? ['/page/$id.jpg'],
            },
          };
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'data': data}));
      }
      await request.response.close();
    });
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        expect(call.method, 'getApplicationSupportDirectory');
        return tmp.path;
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async {
        expect(call.method, 'check');
        return ['wifi'];
      },
    );
    WorkmanagerAndroid.registerWith();
    for (final method in ['registerPeriodicTask', 'cancelByUniqueName']) {
      messenger.setMockMessageHandler(
        'dev.flutter.pigeon.workmanager_platform_interface.WorkmanagerHostApi.$method',
        (_) async => const StandardMessageCodec().encodeMessage([null]),
      );
    }
    final base = 'http://127.0.0.1:${server.port}';
    final address = serverAddress(baseUrl: base, port: null, addPort: false);
    SharedPreferences.setMockInitialValues({
      'offlineCatalogServerId': 'catalog-uuid',
      'offlineLastServerId': 'catalog-uuid',
      'offlineLastServerAddress': address,
    });
    state = await CatchupStateStore.open();
    await state.setEnabled(false);
    await state.setDownloadEnabled(false);
    config = NotificationWorkerConfig(
      serverId: base,
      endpoint: NotificationEndpoint(baseUrl: base, addPort: false),
      newChaptersEnabled: false,
      includedCategoryIds: const {},
      excludedCategoryIds: const {},
      hideContent: false,
      catalogServerId: 'catalog-uuid',
      verifiedAddress: address,
    );
    await (await NotificationStateStore.open()).writeConfig(config);
    await state.writeSpec(
      CatchupWorkSpec(
        serverId: 'catalog-uuid',
        wifiOnly: true,
        storageCapEnabled: false,
        storageCapBytes: 0,
        manga: const [],
        queuedChapters: List.generate(
          30,
          (index) => QueuedChapterSpec(
            chapterId: index + 1,
            mangaId: 1,
            generation: 0,
          ),
        ),
      ),
    );
    log = BackgroundCompletionLog(
      File('${tmp.path}/offline/.bg_completion.log'),
    );
  });

  tearDown(() async {
    if (!releasePage.isCompleted) releasePage.complete();
    await server.close(force: true);
    try {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    } catch (_) {}
  });

  Future<void> enableOverlap({
    int queuedCount = 1,
    Map<int, int> chapterGenerations = const {},
    Map<int, int> serverFetchAttempts = const {},
    Set<int> failedChapterIds = const {},
    OfflineKeepRule keepRule = OfflineKeepRule.all,
  }) async {
    await state.setEnabled(true);
    await state.setDownloadEnabled(true);
    await state.writeSpec(
      CatchupWorkSpec(
        serverId: 'catalog-uuid',
        wifiOnly: true,
        storageCapEnabled: false,
        storageCapBytes: 0,
        manga: [
          CatchupMangaSpec(
            mangaId: 1,
            keepRule: keepRule,
            keepUnreadCount: 3,
            onDeviceChapterIds: {},
            pinnedChapterIds: {},
            failedChapterIds: failedChapterIds,
            chapterGenerations: chapterGenerations,
            serverFetchAttempts: serverFetchAttempts,
          ),
        ],
        queuedChapters: List.generate(
          queuedCount,
          (index) => QueuedChapterSpec(
            chapterId: index + 1,
            mangaId: 1,
            generation: 0,
          ),
        ),
      ),
    );
  }

  test(
    'late denial after account switch leaves old catalog state untouched',
    () async {
      serverChapterCount = 1;
      holdPage = true;
      denyPage = true;
      await enableOverlap(queuedCount: 0);
      final before = state.readLedger('catalog-uuid').toJson();
      final running = run();
      await pageRequested.future.timeout(const Duration(seconds: 5));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('offlineCatalogServerId', 'catalog-B');
      await prefs.setString('offlineLastServerId', 'catalog-B');
      releasePage.complete();
      expect(await running.timeout(const Duration(seconds: 5)), isTrue);
      await state.reload();
      expect(await log.parse(), isEmpty);
      expect(state.readLedger('catalog-uuid').toJson(), before);
      expect(state.downloadPermissionPaused('catalog-uuid'), isFalse);
      expect(state.downloadPermissionPaused('catalog-B'), isFalse);
    },
  );

  test(
    'exhausted keep-rule budget publishes a failed metadata chapter once',
    () async {
      serverChapterCount = 1;
      await enableOverlap(queuedCount: 0);
      await state.writeLedger(
        'catalog-uuid',
        const CatchupLedger(downloadRetries: {1: 5}, pendingDownloads: {1: 1}),
      );
      expect(await run(), isTrue);
      expect(await run(), isTrue);
      final entries = await log.parse();
      expect(entries.whereType<AdoptChapterEntry>(), hasLength(1));
      expect(entries.whereType<ChapterEntry>().single.status, 'error');
      expect(pages, isEmpty);
      final db = testOfflineDatabase();
      addTearDown(db.close);
      await db.upsertMangaMetadata(
        id: 1,
        title: 'M',
        updatedAt: DateTime(2026),
      );
      await db.setKeepRule(1, OfflineKeepRule.all, 3);
      await db.upsertChapterMetadata(
        id: 1,
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
      await replayCompletionLog(
        db: db,
        store: IoOfflinePageStore(OfflinePaths('${tmp.path}/offline')),
        log: log,
        catalogServerId: 'catalog-uuid',
      );
      expect((await db.chapterById(1))!.deviceState, OfflineDeviceState.error);
    },
  );

  for (final status in [401, 503]) {
    test(
      'backfill retains interrupted download obligation for status $status',
      () async {
        serverChapterCount = 1;
        pageStatus = status;
        await enableOverlap(queuedCount: 0);
        expect(await run(), isTrue);
        expect(state.readLedger('catalog-uuid').pendingDownloads, {1: 1});
        expect(state.readLedger('catalog-uuid').downloadRetries, isEmpty);
        pageStatus = 200;
        expect(await run(), isTrue);
        expect(
          (await log.parse()).whereType<AdoptChapterEntry>().single.status,
          isNull,
        );
        expect(state.readLedger('catalog-uuid').pendingDownloads, isEmpty);
      },
    );
  }

  test('backfill retains chapters beyond one run allowance', () async {
    await enableOverlap(queuedCount: 0);
    for (var wake = 1; wake <= 3; wake++) {
      expect(await run(), isTrue);
      expect(pages.length, wake * 10);
      expect(
        state.readLedger('catalog-uuid').pendingDownloads.length,
        30 - wake * 10,
      );
    }
  });

  test(
    'resumed bytes count once and crossing cap blocks the next fresh chapter',
    () async {
      final store = IoOfflinePageStore(OfflinePaths('${tmp.path}/offline'));
      await store.beginChapter(
        1,
        1,
        const ChapterManifest(generation: 0, indices: [0, 1]),
      );
      await store.writePage(1, 1, 0, List.filled(100, 1), 'jpg');
      pageUrls[1] = ['/page/1.jpg', '/page/1.jpg'];
      var initialBytes = 0;
      await for (final entry in Directory(
        '${tmp.path}/offline/1',
      ).list(recursive: true)) {
        if (entry is File) initialBytes += await entry.length();
      }
      await state.writeSpec(
        CatchupWorkSpec(
          serverId: 'catalog-uuid',
          wifiOnly: true,
          storageCapEnabled: true,
          storageCapBytes: initialBytes + 10,
          manga: const [],
          queuedChapters: List.generate(
            3,
            (index) => QueuedChapterSpec(
              chapterId: index + 1,
              mangaId: 1,
              generation: 0,
            ),
          ),
        ),
      );
      expect(await run(), isTrue);
      expect(pages, [1, 2]);
      expect(
        (await log.parse()).whereType<ChapterEntry>().map(
          (entry) => entry.chapterId,
        ),
        [1, 2],
      );
      expect(await store.readManifest(1, 3), isNull);
    },
  );

  test(
    'keep three skips a failed chapter when selecting its unread window',
    () async {
      serverChapterCount = 5;
      await enableOverlap(
        queuedCount: 0,
        failedChapterIds: {1},
        keepRule: OfflineKeepRule.nUnread,
      );
      expect(await run(), isTrue);
      expect(pages, [2, 3, 4]);
      expect(resolvedPages, [2, 3, 4]);
    },
  );

  test(
    'a new keep generation starts with a fresh device retry budget',
    () async {
      serverChapterCount = 1;
      failPage = true;
      await enableOverlap(queuedCount: 0, chapterGenerations: {1: 1});
      await state.writeLedger(
        'catalog-uuid',
        const CatchupLedger(
          pendingDownloads: {1: 1},
          pendingServerFetch: {1: 1},
          serverFetchRetries: {1: 5},
          downloadRetries: {1: 5},
        ),
      );
      expect(await run(), isTrue);
      expect(resolvedPages, [1]);
      expect(state.readLedger('catalog-uuid').downloadRetries, {1: 1});
      expect(state.readLedger('catalog-uuid').chapterGenerations, {1: 1});
      expect(state.readLedger('catalog-uuid').serverFetchRetries, isEmpty);
    },
  );

  test(
    'a new keep generation starts with a fresh server retry budget',
    () async {
      serverChapterCount = 1;
      serverDownloaded = false;
      await enableOverlap(queuedCount: 0, chapterGenerations: {1: 2});
      await state.writeLedger(
        'catalog-uuid',
        const CatchupLedger(
          pendingServerFetch: {1: 1},
          serverFetchRetries: {1: 5},
          chapterGenerations: {1: 1},
        ),
      );
      expect(await run(), isTrue);
      expect(enqueued, [1]);
      final ledger = state.readLedger('catalog-uuid');
      expect(ledger.serverFetchRetries, {1: 1});
      expect(ledger.chapterGenerations, {1: 2});
      serverDownloaded = true;
      expect(await run(), isTrue);
      expect(state.readLedger('catalog-uuid').chapterGenerations, isEmpty);
    },
  );

  test('a different live server identity prevents chapter requests', () async {
    serverIdentity = 'other-catalog';
    await run();
    expect(requests, 1);
    expect(resolvedPages, isEmpty);
    expect(pages, isEmpty);
  });

  test(
    'published failed chapters stay excluded after terminal log replay',
    () async {
      serverChapterCount = 3;
      await enableOverlap(queuedCount: 0, failedChapterIds: {1});
      expect(await log.parse(), isEmpty);
      expect(await run(), isTrue);
      expect(pages, [2, 3]);
      expect(resolvedPages, [2, 3]);
      expect(
        (await log.parse()).whereType<AdoptChapterEntry>().map(
          (entry) => entry.chapterId,
        ),
        [2, 3],
      );
    },
  );

  test(
    'same endpoint reauthorization rejects the captured old identity epoch',
    () async {
      await state.setIdentityAuthorized(false);
      await state.setIdentityAuthorized(true);
      expect(state.identityAuthorized, isTrue);
      expect(state.identityEpoch, greaterThan(config.identityEpoch));
      expect(await run(), isTrue);
      expect(requests, 0);
    },
  );

  test(
    'queued hard failure is not attempted again through the keep rule',
    () async {
      serverChapterCount = 1;
      failPage = true;
      await enableOverlap();
      expect(await run(), isTrue);
      expect(resolvedPages, [1]);
      expect(state.readLedger('catalog-uuid').queuedDownloadRetries, {
        '1:0': 1,
      });
      expect(state.readLedger('catalog-uuid').downloadRetries, isEmpty);
      expect((await log.parse()).whereType<AdoptChapterEntry>(), isEmpty);
    },
  );

  test(
    'exhausted queued generation cannot retry through the keep rule',
    () async {
      serverChapterCount = 1;
      await enableOverlap();
      await state.writeLedger(
        'catalog-uuid',
        const CatchupLedger(queuedDownloadRetries: {'1:0': 5}),
      );
      for (var wake = 0; wake < 2; wake++) {
        expect(await run(), isTrue);
      }
      expect(resolvedPages, isEmpty);
      expect(pages, isEmpty);
      final errors = (await log.parse()).whereType<ChapterEntry>().toList();
      expect(errors.length, 1);
      expect(errors.single.status, 'error');
      expect(errors.single.generation, 0);
      expect(state.readLedger('catalog-uuid').downloadRetries, isEmpty);
    },
  );

  test(
    'queued and keep-rule downloads share the ten-chapter allowance',
    () async {
      await enableOverlap(queuedCount: 4);
      expect(await run(), isTrue);
      expect(pages.length, 10);
      expect(pages.toSet().length, 10);
      final entries = await log.parse();
      expect(entries.whereType<ChapterEntry>().length, 4);
      expect(entries.whereType<AdoptChapterEntry>().length, 6);
    },
  );

  test(
    'three real executor wakes finish thirty queued chapters with catchup disabled',
    () async {
      for (var wake = 1; wake <= 3; wake++) {
        expect(await run(), isTrue);
        expect(pages.length, wake * 10);
        expect(pages.toSet().length, wake * 10);
      }
      final successes = (await log.parse()).whereType<ChapterEntry>().toList();
      expect(successes.length, 30);
      expect(
        successes.every(
          (entry) => entry.status == 'downloaded' && entry.generation == 0,
        ),
        isTrue,
      );
    },
  );

  test(
    'live pause blocks a previously published queue before network work',
    () async {
      await (await SharedPreferences.getInstance()).setBool(
        'offlineDownloadsPaused',
        true,
      );
      expect(await run(), isTrue);
      expect(requests, 0);
    },
  );

  test(
    'revoked identity blocks the published queue before network work',
    () async {
      await state.setIdentityAuthorized(false);
      expect(await run(), isTrue);
      expect(requests, 0);
    },
  );

  for (final source in ['snapshot', 'queued', 'both']) {
    test('keep worker carries four server attempts from $source', () async {
      serverChapterCount = 1;
      serverDownloaded = false;
      await enableOverlap(
        queuedCount: 0,
        serverFetchAttempts: source == 'queued' ? const {} : const {1: 4},
      );
      await state.writeLedger(
        'catalog-uuid',
        CatchupLedger(
          pendingServerFetch: const {1: 1},
          serverFetchRetries: const {1: 2},
          queuedServerRetries: source == 'snapshot'
              ? const {}
              : const {'1:0': 4},
        ),
      );
      expect(await run(), isTrue);
      expect(enqueued, [1]);
      expect(state.readLedger('catalog-uuid').serverFetchRetries[1], 5);
      expect(await run(), isTrue);
      expect(enqueued, [1]);
    });
  }

  for (final queued in [true, false]) {
    test(
      'accepted fifth ${queued ? 'queued' : 'keep-rule'} server attempt survives identity revocation',
      () async {
        serverChapterCount = 2;
        serverDownloaded = false;
        revokeIdentityAfterEnqueue = true;
        await enableOverlap(queuedCount: queued ? 2 : 0);
        await state.writeLedger(
          'catalog-uuid',
          CatchupLedger(
            pendingServerFetch: queued ? const {} : const {1: 1},
            serverFetchRetries: queued ? const {} : const {1: 4},
            queuedServerRetries: queued ? const {'1:0': 4} : const {},
          ),
        );
        expect(await run(), isTrue);
        await state.reload();
        expect(state.identityAuthorized, isFalse);
        expect(enqueued, [1]);
        expect(resolvedPages, isEmpty);
        expect(pages, isEmpty);
        final ledger = state.readLedger('catalog-uuid');
        expect(
          queued
              ? ledger.queuedServerRetries['1:0']
              : ledger.serverFetchRetries[1],
          5,
        );
        final firstRequests = requests;
        expect(await run(), isTrue);
        expect(requests, firstRequests);
        expect(enqueued, [1]);
      },
    );
  }

  test(
    'adoption publishes exhausted work before an immediate scheduled wake',
    () async {
      serverChapterCount = 1;
      serverDownloaded = false;
      await enableOverlap();
      final db = testOfflineDatabase();
      await db.upsertMangaMetadata(
        id: 1,
        title: 'M',
        updatedAt: DateTime(2026),
      );
      await db.setKeepRule(1, OfflineKeepRule.all, 3);
      await db.upsertChapterMetadata(
        id: 1,
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
      await db.setChapterDeviceState(1, OfflineDeviceState.queued);
      await state.writeLedger(
        'catalog-uuid',
        const CatchupLedger(
          queuedServerRetries: {'1:0': 5},
          queuedDownloadRetries: {'1:0': 5},
        ),
      );
      FlutterSecureStorage.setMockInitialValues({});
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
          offlineDatabaseProvider.overrideWithValue(db),
          offlinePathsProvider.overrideWithValue(
            OfflinePaths('${tmp.path}/offline'),
          ),
          offlineEnabledProvider.overrideWith((ref) => true),
          offlineActiveProvider.overrideWith((ref) => true),
          settledAccountAccessProvider.overrideWith(
            (ref) => AccountAccess(capability: AccountCapability.unsupported),
          ),
        ],
      );
      try {
        await container.read(authCredentialsStoreProvider.future);
        expect(await adoptWorkerObligations(container.read), isTrue);
        final snapshot = state.readSpec()!;
        expect(snapshot.queuedChapters, isEmpty);
        expect(snapshot.manga.single.serverFetchAttempts, {1: 5});
        expect(snapshot.manga.single.failedChapterIds, {1});
        expect(state.readLedger('catalog-uuid').queuedServerRetries, isEmpty);
        expect(state.readLedger('catalog-uuid').queuedDownloadRetries, isEmpty);
        expect(await run(), isTrue);
        expect(enqueued, isEmpty);
        expect(pages, isEmpty);
      } finally {
        container.dispose();
        await db.close();
      }
    },
  );

  test(
    'successful fifth server request leaves the device budget available',
    () async {
      serverChapterCount = 1;
      await enableOverlap(queuedCount: 0, serverFetchAttempts: {1: 5});
      expect(await run(), isTrue);
      expect(pages, [1]);
      expect(enqueued, isEmpty);
    },
  );

  test(
    'keep worker ignores queued attempts from an older generation',
    () async {
      serverChapterCount = 1;
      serverDownloaded = false;
      await enableOverlap(queuedCount: 0, chapterGenerations: {1: 1});
      await state.writeLedger(
        'catalog-uuid',
        const CatchupLedger(
          queuedServerRetries: {'1:0': 5},
          queuedDownloadRetries: {'1:0': 5},
        ),
      );
      expect(await run(), isTrue);
      expect(enqueued, [1]);
      expect(state.readLedger('catalog-uuid').serverFetchRetries[1], 1);
      expect(state.readLedger('catalog-uuid').chapterGenerations[1], 1);
    },
  );

  test(
    'keep worker retains queued device attempts for the same generation',
    () async {
      serverChapterCount = 1;
      pageUrls[1] = [];
      await enableOverlap(queuedCount: 0);
      await state.writeLedger(
        'catalog-uuid',
        const CatchupLedger(
          downloadRetries: {1: 2},
          pendingDownloads: {1: 1},
          queuedDownloadRetries: {'1:0': 4},
        ),
      );
      expect(await run(), isTrue);
      expect(state.readLedger('catalog-uuid').downloadRetries[1], 5);
      final firstRequests = resolvedPages.length;
      expect(await run(), isTrue);
      expect(resolvedPages.length, firstRequests);
    },
  );

  test(
    'accepted fifth server attempt survives yield during the next chapter',
    () async {
      serverChapterCount = 2;
      serverMissing = {1};
      holdPage = true;
      await enableOverlap(queuedCount: 0);
      await state.writeLedger(
        'catalog-uuid',
        const CatchupLedger(
          pendingServerFetch: {1: 1},
          serverFetchRetries: {1: 4},
        ),
      );
      final running = run();
      await pageRequested.future.timeout(const Duration(seconds: 5));
      expect(enqueued, [1]);
      final contender = BackgroundDownloadLock(
        File('${tmp.path}/offline/.bg_lock'),
      );
      await contender.requestYield();
      expect(await running.timeout(const Duration(seconds: 5)), isTrue);
      expect(state.readLedger('catalog-uuid').serverFetchRetries, {1: 5});
      expect(state.readLedger('catalog-uuid').chapterGenerations[1], 0);
    },
  );

  test(
    'yield aborts a slow page and releases ownership without spending retries',
    () async {
      holdPage = true;
      final running = run();
      await pageRequested.future.timeout(const Duration(seconds: 5));
      final contender = BackgroundDownloadLock(
        File('${tmp.path}/offline/.bg_lock'),
      );
      expect(await contender.acquire('test'), isFalse);
      await contender.requestYield();
      expect(await running.timeout(const Duration(seconds: 5)), isTrue);
      expect(await contender.acquire('test'), isTrue);
      await contender.release();
      expect(state.readLedger('catalog-uuid').queuedDownloadRetries, isEmpty);
      expect((await log.parse()).whereType<ChapterEntry>(), isEmpty);
      releasePage.complete();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      final files = await Directory('${tmp.path}/offline')
          .list(recursive: true)
          .where((entry) => entry.path.endsWith('.jpg'))
          .toList();
      expect(files, isEmpty);
      expect(pages, [1]);
    },
  );
}
