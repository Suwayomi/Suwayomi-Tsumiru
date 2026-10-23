import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/notifications/data/background/notification_background_client.dart';
import 'package:tsumiru/src/features/notifications/data/notification_state_store.dart';
import 'package:tsumiru/src/features/offline/data/background/background_completion_log.dart';
import 'package:tsumiru/src/features/offline/data/background/background_token_record.dart';
import 'package:tsumiru/src/features/offline/data/background/catchup_download_executor.dart';
import 'package:tsumiru/src/features/offline/data/background/catchup_work_spec.dart';

import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_page_store_io.dart';
import 'package:tsumiru/src/features/offline/data/offline_paths.dart';
import 'package:tsumiru/src/features/offline/data/offline_server_identity.dart';
import 'package:tsumiru/src/features/offline/data/offline_types.dart';
import 'package:workmanager_android/workmanager_android.dart';

import '../../helpers/modern_user_fields_probe.dart';
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
        final probeData = modernUserFieldsProbeData(query);
        if (probeData != null) {
          data = probeData;
        } else if (query.contains('OfflineServerIdentity')) {
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
                  'user': {
                    'isRead': false,
                    'isBookmarked': false,
                    'isDownloaded':
                        serverDownloaded && !serverMissing.contains(index + 1),
                  },
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
    for (final method in [
      'registerPeriodicTask',
      'registerOneOffTask',
      'cancelByUniqueName',
    ]) {
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

  test('a different live server identity prevents chapter requests', () async {
    serverIdentity = 'other-catalog';
    await run();
    expect(requests, 1);
    expect(resolvedPages, isEmpty);
    expect(pages, isEmpty);
  });

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
}
